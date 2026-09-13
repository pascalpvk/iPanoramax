// SPDX-License-Identifier: MIT

import Foundation
import PanoramaxKit

/// Réponse HTTP simulée.
struct MockResponse: Sendable {
    var statusCode: Int = 200
    var headers: [String: String] = ["Content-Type": "application/json"]
    var body: Data = Data()

    static func json(_ string: String, status: Int = 200) -> MockResponse {
        MockResponse(statusCode: status, body: Data(string.utf8))
    }

    static func status(_ code: Int, headers: [String: String] = [:]) -> MockResponse {
        MockResponse(statusCode: code, headers: headers, body: Data())
    }
}

enum MockError: Error, CustomStringConvertible {
    case noStub(host: String)
    case queueExhausted(host: String)

    var description: String {
        switch self {
        case .noStub(let host): "Aucune réponse préparée pour l'hôte \(host)"
        case .queueExhausted(let host): "File de réponses épuisée pour l'hôte \(host)"
        }
    }
}

/// Un réseau simulé, isolé des autres tests par un hôte unique.
///
/// L'isolation passe par l'hôte, pas par un verrou global : Swift Testing
/// exécute les suites en parallèle, et `.serialized` ne sérialise qu'*à
/// l'intérieur* d'une suite. Avec un registre partagé, un test lit donc les
/// requêtes d'un autre — le symptôme est déroutant, une assertion sur
/// `/api/users/me` qui voit passer `/api/upload_sets/…/complete`.
///
/// Chaque instance de `MockNetwork` parle à `https://<uuid>.test.invalid/api`
/// (`.invalid` est le TLD réservé à cet usage), et le registre range les stubs
/// et les requêtes par hôte.
struct MockNetwork {

    let instance: PanoramaxInstance
    let session: URLSession
    private let host: String

    init() {
        let host = "\(UUID().uuidString.lowercased()).test.invalid"
        guard let url = URL(string: "https://\(host)/api") else {
            preconditionFailure("URL d'hôte de test invalide")
        }
        self.host = host
        self.instance = PanoramaxInstance(apiBaseURL: url)
        self.session = MockURLProtocol.makeSession()
    }

    func makeClient(token: String? = nil, userAgent: String = "iPanoramax/tests") -> PanoramaxClient {
        PanoramaxClient(instance: instance, session: session, token: token, userAgent: userAgent)
    }

    func stub(_ handler: @escaping @Sendable (URLRequest) throws -> MockResponse) {
        MockURLProtocol.registry.stub(handler, for: host)
    }

    /// Rend les réponses dans l'ordre ; la dernière est répétée indéfiniment.
    func stub(sequence responses: [MockResponse]) {
        MockURLProtocol.registry.stub(sequence: responses, for: host)
    }

    var requests: [URLRequest] {
        MockURLProtocol.registry.requests(for: host)
    }
}

/// Intercepte les requêtes des sessions de test et rend des réponses préparées,
/// sans toucher au réseau. Passe par ``MockNetwork`` plutôt que directement.
///
/// Non marquée `final` : les points d'entrée d'`URLProtocol` se redéfinissent en
/// `override class func`, ce qu'une classe finale n'autorise pas.
class MockURLProtocol: URLProtocol {

    typealias Handler = @Sendable (URLRequest) throws -> MockResponse

    /// État partagé rangé par hôte, protégé par verrou : `URLProtocol` impose
    /// du statique, mais chaque test n'y voit que sa propre case.
    final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var handlers: [String: Handler] = [:]
        private var recorded: [String: [URLRequest]] = [:]

        func stub(_ handler: @escaping Handler, for host: String) {
            lock.lock()
            defer { lock.unlock() }
            handlers[host] = handler
            recorded[host] = []
        }

        func stub(sequence responses: [MockResponse], for host: String) {
            let queue = ResponseQueue(responses, host: host)
            stub({ _ in try queue.next() }, for: host)
        }

        func respond(to request: URLRequest) throws -> MockResponse {
            guard let host = request.url?.host else { throw MockError.noStub(host: "—") }
            lock.lock()
            let handler = handlers[host]
            recorded[host, default: []].append(request)
            lock.unlock()
            guard let handler else { throw MockError.noStub(host: host) }
            return try handler(request)
        }

        func requests(for host: String) -> [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return recorded[host] ?? []
        }
    }

    private final class ResponseQueue: @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [MockResponse]
        private let host: String

        init(_ responses: [MockResponse], host: String) {
            self.responses = responses
            self.host = host
        }

        func next() throws -> MockResponse {
            lock.lock()
            defer { lock.unlock() }
            guard let first = responses.first else { throw MockError.queueExhausted(host: host) }
            if responses.count > 1 { responses.removeFirst() }
            return first
        }
    }

    static let registry = Registry()

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let stub = try MockURLProtocol.registry.respond(to: request)
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: stub.statusCode,
                      httpVersion: "HTTP/1.1",
                      headerFields: stub.headers
                  )
            else {
                client?.urlProtocol(self, didFailWithError: MockError.noStub(host: "—"))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !stub.body.isEmpty {
                client?.urlProtocol(self, didLoad: stub.body)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLRequest {

    /// `URLProtocol` vide `httpBody` et ne laisse que `httpBodyStream` : sans ce
    /// détour, un test qui vérifie le corps d'une requête voit toujours `nil`.
    var recordedBody: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let size = 8192
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
