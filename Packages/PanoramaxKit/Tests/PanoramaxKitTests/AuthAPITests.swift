// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import PanoramaxKit

@Suite("Authentification")
struct AuthAPITests {

    private static let tokenJSON = """
    {
      "id": "3f0f1a5e-1b6f-4c2e-9a4b-000000000001",
      "jwt_token": "header.payload.signature",
      "generated_at": "2026-08-30T12:00:00Z",
      "description": "iPanoramax/tests",
      "links": [
        {
          "rel": "claim",
          "href": "https://panoramax.openstreetmap.fr/api/auth/tokens/3f0f1a5e/claim"
        }
      ]
    }
    """

    private static let userJSON = """
    { "id": "u-42", "name": "pascalpvk", "links": [] }
    """

    @Test("Le jeton est généré sans authentification, puis mémorisé")
    func generatesAndStoresToken() async throws {
        let network = MockNetwork()
        network.stub { _ in .json(Self.tokenJSON) }
        let client = network.makeClient()

        let token = try await client.generateToken()
        #expect(token.jwtToken == "header.payload.signature")
        #expect(token.claimURL?.absoluteString.hasSuffix("/claim") == true)

        let stored = await client.hasToken
        #expect(stored)

        let sent = try #require(network.requests.first)
        #expect(sent.httpMethod == "POST")
        #expect(sent.url?.path == "/api/auth/tokens/generate")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sent.value(forHTTPHeaderField: "User-Agent") == "iPanoramax/tests")
    }

    @Test("Une requête authentifiée porte le jeton en Bearer")
    func sendsBearerToken() async throws {
        let network = MockNetwork()
        network.stub { _ in .json(Self.userJSON) }
        let client = network.makeClient(token: "header.payload.signature")

        let user = try await client.currentUser()
        #expect(user.name == "pascalpvk")

        let sent = try #require(network.requests.first)
        #expect(sent.url?.path == "/api/users/me")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer header.payload.signature")
    }

    @Test("L'attente de revendication s'arrête dès que le serveur répond 200")
    func waitsUntilTokenIsClaimed() async throws {
        let network = MockNetwork()
        network.stub(sequence: [
            .status(401),
            .status(401),
            .json(Self.userJSON)
        ])
        let client = network.makeClient(token: "header.payload.signature")

        let user = try await client.waitForTokenClaim(
            every: .milliseconds(5),
            timeout: .seconds(5)
        )
        #expect(user.name == "pascalpvk")
        #expect(network.requests.count == 3)
    }

    @Test("Un jeton jamais revendiqué finit en tokenNotClaimed")
    func givesUpOnUnclaimedToken() async {
        let network = MockNetwork()
        network.stub { _ in .status(401) }
        let client = network.makeClient(token: "header.payload.signature")

        await #expect(throws: PanoramaxError.tokenNotClaimed) {
            _ = try await client.waitForTokenClaim(
                every: .milliseconds(5),
                timeout: .milliseconds(50)
            )
        }
    }

    @Test("Un 429 remonte le délai de réessai")
    func surfacesRetryAfter() async {
        let network = MockNetwork()
        network.stub { _ in .status(429, headers: ["Retry-After": "30"]) }
        let client = network.makeClient(token: "header.payload.signature")

        await #expect(throws: PanoramaxError.rateLimited(retryAfter: 30)) {
            _ = try await client.currentUser()
        }
    }

    @Test("Seules les erreurs transitoires sont rejouables")
    func classifiesRetryableErrors() {
        #expect(PanoramaxError.transport("réseau coupé").isRetryable)
        #expect(PanoramaxError.rateLimited(retryAfter: nil).isRetryable)
        #expect(PanoramaxError.server(status: 503, message: nil).isRetryable)

        #expect(!PanoramaxError.unauthorized.isRetryable)
        #expect(!PanoramaxError.forbidden.isRetryable)
        #expect(!PanoramaxError.server(status: 400, message: nil).isRetryable)
        #expect(!PanoramaxError.rejected(FileRejection(
            reason: "outside_coverage",
            severity: "error",
            message: "Hors zone"
        )).isRetryable)
    }
}
