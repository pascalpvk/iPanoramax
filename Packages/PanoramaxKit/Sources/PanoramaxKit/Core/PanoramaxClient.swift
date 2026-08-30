// SPDX-License-Identifier: MIT

import Foundation

/// Client de l'API Panoramax (STAC API 1.0.0 + extensions Panoramax).
///
/// Aucune dépendance à UIKit ni à SwiftUI : le module se compile et se teste
/// sans simulateur, et reste réutilisable côté macOS ou en ligne de commande.
///
/// ```swift
/// let client = PanoramaxClient(instance: .openStreetMapFrance)
/// let config = try await client.configuration()
/// print(config.license?.id ?? "licence non déclarée")
/// ```
public actor PanoramaxClient {

    public let instance: PanoramaxInstance

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var token: String?

    /// Valeur envoyée en `User-Agent` et en `user_agent` sur les upload sets.
    public let userAgent: String

    public init(
        instance: PanoramaxInstance,
        session: URLSession = .shared,
        token: String? = nil,
        userAgent: String = "iPanoramax"
    ) {
        self.instance = instance
        self.session = session
        self.token = token
        self.userAgent = userAgent
        self.decoder = PanoramaxClient.makeDecoder()
        self.encoder = PanoramaxClient.makeEncoder()
    }

    // MARK: - Jeton

    public func setToken(_ token: String?) {
        self.token = token
    }

    public var hasToken: Bool { token != nil }

    // MARK: - Construction de requêtes

    func url(path: String, query: [URLQueryItem] = []) -> URL {
        var url = instance.apiBaseURL
        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        guard !query.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.queryItems = query
        return components.url ?? url
    }

    func makeRequest(
        _ method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil,
        authenticated: Bool = true
    ) -> URLRequest {
        var request = URLRequest(url: url(path: path, query: query))
        request.httpMethod = method
        request.httpBody = body
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if authenticated, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: - Exécution

    @discardableResult
    func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PanoramaxError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PanoramaxError.transport("Réponse non HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw PanoramaxClient.error(for: http, data: data)
        }
        return data
    }

    func send<T: Decodable & Sendable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data = try await send(request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw PanoramaxError.decoding(String(describing: error))
        }
    }

    func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw PanoramaxError.decoding("Encodage impossible : \(error)")
        }
    }

    // MARK: - Utilitaires

    static func error(for response: HTTPURLResponse, data: Data) -> PanoramaxError {
        let message = String(data: data, encoding: .utf8).flatMap { body -> String? in
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(400))
        }
        switch response.statusCode {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retryAfter)
        default:
            return .server(status: response.statusCode, message: message)
        }
    }

    /// Panoramax renvoie des dates ISO 8601 avec ou sans fraction de seconde
    /// selon les champs. On accepte les deux.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let styles = [
                Date.ISO8601FormatStyle(includingFractionalSeconds: true),
                Date.ISO8601FormatStyle(includingFractionalSeconds: false)
            ]
            for style in styles {
                if let date = try? style.parse(raw) { return date }
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Date ISO 8601 non reconnue : \(raw)"
            )
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(.iso8601))
        }
        return encoder
    }
}
