// SPDX-License-Identifier: MIT

import Foundation

/// Une instance Panoramax, identifiée par l'URL de base de son API.
///
/// Panoramax est fédéré : une vingtaine d'instances publiques exposent la même
/// API STAC. L'app doit donc traiter l'instance comme une donnée, jamais comme
/// une constante compilée.
public struct PanoramaxInstance: Sendable, Hashable, Codable {

    /// URL de base de l'API, terminaison `/api` incluse.
    /// Exemple : `https://panoramax.openstreetmap.fr/api`
    public let apiBaseURL: URL

    public init(apiBaseURL: URL) {
        self.apiBaseURL = apiBaseURL
    }

    /// Construit une instance à partir de l'URL d'un site Panoramax,
    /// en ajoutant `/api` si l'utilisateur ne l'a pas saisi.
    public init?(websiteURL string: String) {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if !trimmed.hasSuffix("/api") { trimmed += "/api" }
        guard let url = URL(string: trimmed), url.host != nil else { return nil }
        self.apiBaseURL = url
    }

    public static let openStreetMapFrance = PanoramaxInstance(
        apiBaseURL: URL(string: "https://panoramax.openstreetmap.fr/api")!
    )

    public static let ign = PanoramaxInstance(
        apiBaseURL: URL(string: "https://panoramax.ign.fr/api")!
    )
}
