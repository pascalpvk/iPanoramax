// SPDX-License-Identifier: MIT

import Foundation

/// Lien STAC / HATEOAS. Panoramax s'en sert aussi pour exposer les permissions
/// de l'utilisateur sur une ressource (`rel: "edit"`, `"delete"`, `"claim"`…).
public struct STACLink: Codable, Sendable, Hashable {
    public let rel: String
    public let href: URL
    public let type: String?
    public let title: String?
    public let method: String?
}

/// Jeton d'API Panoramax.
///
/// Un jeton fraîchement généré n'est rattaché à aucun compte : il faut que
/// l'utilisateur ouvre ``claimURL`` dans un navigateur pour le revendiquer.
public struct PanoramaxToken: Codable, Sendable, Hashable {
    public let id: UUID
    public let jwtToken: String
    public let description: String?
    public let generatedAt: Date?
    public let links: [STACLink]?

    /// URL à ouvrir dans une `ASWebAuthenticationSession` pour rattacher le
    /// jeton au compte de l'utilisateur.
    public var claimURL: URL? {
        links?.first { $0.rel == "claim" }?.href
    }

    enum CodingKeys: String, CodingKey {
        case id
        case jwtToken = "jwt_token"
        case description
        case generatedAt = "generated_at"
        case links
    }
}

public struct PanoramaxUser: Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let links: [STACLink]?
}

extension PanoramaxClient {

    /// Étape 1 — génère un jeton non revendiqué. Aucune authentification requise.
    ///
    /// C'est ce flux, et non OAuth, qui permet à iPanoramax de fonctionner sur
    /// n'importe quelle instance : aucune inscription préalable de l'app côté
    /// serveur n'est nécessaire.
    public func generateToken(description: String? = nil) async throws -> PanoramaxToken {
        let payload = ["description": description ?? userAgent]
        let request = makeRequest(
            "POST",
            path: "auth/tokens/generate",
            body: try encode(payload),
            contentType: "application/json",
            authenticated: false
        )
        let token = try await send(request, as: PanoramaxToken.self)
        setToken(token.jwtToken)
        return token
    }

    /// Étape 3 — vérifie que le jeton courant est valide et revendiqué.
    public func currentUser() async throws -> PanoramaxUser {
        try await send(makeRequest("GET", path: "users/me"), as: PanoramaxUser.self)
    }

    /// Interroge `/users/me` jusqu'à ce que l'utilisateur ait revendiqué le
    /// jeton dans son navigateur, ou jusqu'à expiration du délai.
    ///
    /// - Parameters:
    ///   - interval: intervalle entre deux essais.
    ///   - timeout: délai au-delà duquel on abandonne.
    public func waitForTokenClaim(
        every interval: Duration = .seconds(2),
        timeout: Duration = .seconds(300)
    ) async throws -> PanoramaxUser {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            do {
                return try await currentUser()
            } catch PanoramaxError.unauthorized {
                try await Task.sleep(for: interval)
            }
        }
        throw PanoramaxError.tokenNotClaimed
    }

    public func revokeToken(id: UUID) async throws {
        try await send(makeRequest("DELETE", path: "users/me/tokens/\(id.uuidString)"))
    }
}
