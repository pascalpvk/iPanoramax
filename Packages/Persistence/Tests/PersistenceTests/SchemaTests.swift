// SPDX-License-Identifier: MIT

import Foundation
import GeoKit
import ImageMetadataKit
import SwiftData
import Testing
@testable import Persistence

@Suite("Schéma")
struct SchemaTests {

    @Test("Le schéma est estampillé et porte les deux entités")
    func schemaIsVersionedAndComplete() {
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(SchemaV1.models.count == 2)
        #expect(CaptureMigrationPlan.schemas.count == 1)
        // Aucune étape tant qu'il n'y a qu'une version. La liste existe pour
        // que l'ajout d'`UploadTask` en phase 3 soit une migration, pas un
        // effacement de la base des premiers utilisateurs.
        #expect(CaptureMigrationPlan.stages.isEmpty)
    }

    @Test("Un conteneur en mémoire se crée sans toucher au disque")
    func buildsInMemoryContainer() throws {
        let container = try CaptureContainer.inMemory()
        #expect(container.configurations.contains(where: { $0.isStoredInMemoryOnly }))
    }

    @Test("Ce qui est écrit se relit après réouverture de la base")
    func dataSurvivesReopeningTheStore() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("iPanoramax-reopen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let session = UUID()
        let draft = Sample.draft(step: 1)
        do {
            let library = try CaptureLibrary.inFolder(root)
            try await library.store.createSession(
                id: session,
                title: "Canal Saint-Martin",
                mode: .distance(metres: 5),
                instanceHost: "panoramax.openstreetmap.fr"
            )
            try await library.record(jpeg: Sample.jpeg(padding: 64), draft: draft, in: session)
            try await library.store.endSession(id: session)
        }

        let reopened = try CaptureLibrary.inFolder(root)
        let stored = try await reopened.store.session(id: session)
        #expect(stored?.title == "Canal Saint-Martin")
        #expect(stored?.mode == .distance(metres: 5))
        #expect(stored?.instanceHost == "panoramax.openstreetmap.fr")
        #expect(stored?.state == .ready)
        #expect(stored?.shotCount == 1)

        let shots = try await reopened.store.shots(in: session)
        #expect(shots.first?.id == draft.id)
        #expect(shots.first?.coordinate == draft.coordinate)
        // Les octets aussi doivent avoir survécu : la base ne porte que le
        // chemin, c'est le dossier qui porte la photo.
        let jpeg = try reopened.files.read(session: session, shot: draft.id)
        #expect(jpeg == Sample.jpeg(padding: 64))
    }
}
