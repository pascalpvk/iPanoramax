// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import PanoramaxKit

@Suite("Configuration d'instance")
struct InstanceConfigurationTests {

    /// Fixture capturée sur `https://panoramax.ign.fr/api/configuration`.
    /// Les fixtures sont versionnées : c'est le seul moyen de détecter une
    /// évolution du contrat d'API sans dépendre du réseau en CI.
    static func fixture(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            Issue.record("Fixture introuvable : \(name).json")
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    @Test("Décode la configuration de l'instance IGN")
    func decodesIGNConfiguration() throws {
        let data = try Self.fixture("configuration-ign")
        let config = try PanoramaxClient.makeDecoder()
            .decode(InstanceConfiguration.self, from: data)

        #expect(config.name?.label == "IGN")
        #expect(config.license?.id == "etalab-2.0")
        #expect(config.auth?.enabled == true)
        #expect(config.auth?.enforceTosAcceptance == true)
        #expect(config.defaults?.splitDistance == 100)
        #expect(config.defaults?.splitTime == 300.0)
        #expect(config.defaults?.duplicateDistance == 1.0)
        #expect(config.visibility?.possibleValues == ["anyone", "owner-only"])
    }

    @Test("Rend la couverture géographique dans la langue demandée")
    func localizesGeoCoverage() throws {
        let data = try Self.fixture("configuration-ign")
        let config = try PanoramaxClient.makeDecoder()
            .decode(InstanceConfiguration.self, from: data)

        let french = config.geoCoverage?.text(preferring: ["fr-FR"])
        #expect(french?.contains("territoire français") == true)
    }
}

@Suite("Résolution d'instance")
struct PanoramaxInstanceTests {

    @Test("Complète les URL saisies par l'utilisateur", arguments: [
        "panoramax.openstreetmap.fr",
        "https://panoramax.openstreetmap.fr",
        "https://panoramax.openstreetmap.fr/",
        "https://panoramax.openstreetmap.fr/api"
    ])
    func normalizesWebsiteURL(_ input: String) throws {
        let instance = try #require(PanoramaxInstance(websiteURL: input))
        #expect(instance.apiBaseURL.absoluteString == "https://panoramax.openstreetmap.fr/api")
    }

    @Test("Rejette une saisie vide")
    func rejectsEmptyInput() {
        #expect(PanoramaxInstance(websiteURL: "   ") == nil)
    }
}
