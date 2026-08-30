// SPDX-License-Identifier: MIT

import Foundation

/// Configuration publique d'une instance Panoramax (`GET /api/configuration`).
///
/// À lire **avant** tout envoi : elle porte la licence des photos, la couverture
/// géographique acceptée, et les valeurs de découpage par défaut que l'app doit
/// utiliser plutôt que des constantes codées en dur.
public struct InstanceConfiguration: Codable, Sendable {

    /// Chaîne localisée : un libellé par défaut plus, éventuellement, une
    /// traduction par code de langue.
    public struct Localized: Codable, Sendable, Hashable {
        public let label: String?
        public let langs: [String: String]?

        /// Rend la variante correspondant à la langue préférée de l'appareil,
        /// avec repli sur `label`.
        public func text(preferring languages: [String] = Locale.preferredLanguages) -> String? {
            for identifier in languages {
                let code = String(identifier.prefix(2))
                if let value = langs?[code] { return value }
            }
            return label
        }
    }

    public struct Auth: Codable, Sendable {
        public let enabled: Bool
        public let registrationIsOpen: Bool?
        public let enforceTosAcceptance: Bool?

        enum CodingKeys: String, CodingKey {
            case enabled
            case registrationIsOpen = "registration_is_open"
            case enforceTosAcceptance = "enforce_tos_acceptance"
        }
    }

    /// Licence appliquée aux **photos** publiées sur cette instance.
    /// Sans rapport avec la licence du code de l'application.
    public struct License: Codable, Sendable, Hashable {
        public let id: String?
        public let url: URL?
    }

    /// Valeurs par défaut de découpage et de déduplication propres à l'instance.
    public struct Defaults: Codable, Sendable {
        public let splitDistance: Int?
        public let splitTime: Double?
        public let duplicateDistance: Double?
        public let duplicateRotation: Int?
        public let defaultVisibility: String?

        enum CodingKeys: String, CodingKey {
            case splitDistance = "split_distance"
            case splitTime = "split_time"
            case duplicateDistance = "duplicate_distance"
            case duplicateRotation = "duplicate_rotation"
            case defaultVisibility = "default_visibility"
        }
    }

    public struct VisibilityOptions: Codable, Sendable {
        public let possibleValues: [String]?

        enum CodingKeys: String, CodingKey {
            case possibleValues = "possible_values"
        }
    }

    public let name: Localized?
    public let description: Localized?
    public let geoCoverage: Localized?
    public let license: License?
    public let auth: Auth?
    public let defaults: Defaults?
    public let visibility: VisibilityOptions?
    public let color: String?
    public let logo: URL?
    public let email: String?
    public let version: String?
    public let pages: [String]?

    enum CodingKeys: String, CodingKey {
        case name, description, license, auth, defaults, visibility
        case color, logo, email, version, pages
        case geoCoverage = "geo_coverage"
    }
}

extension PanoramaxClient {

    public func configuration() async throws -> InstanceConfiguration {
        try await send(
            makeRequest("GET", path: "configuration", authenticated: false),
            as: InstanceConfiguration.self
        )
    }
}
