// SPDX-License-Identifier: MIT

import Foundation
import GeoKit
import ImageMetadataKit
import Testing
@testable import Persistence

@Suite("Bibliothèque — base et disque")
struct CaptureLibraryTests {

    private func makeSession(_ sandbox: Sandbox) async throws -> UUID {
        let id = UUID()
        try await sandbox.store.createSession(id: id, mode: .distance(metres: 5))
        return id
    }

    @Test("Un cliché enregistré laisse un fichier et une ligne")
    func recordWritesFileAndRow() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        let session = try await makeSession(sandbox)

        let jpeg = Sample.jpeg(padding: 120)
        let draft = Sample.draft(step: 0)
        let snapshot = try await sandbox.library.record(jpeg: jpeg, draft: draft, in: session)

        #expect(sandbox.files.exists(session: session, shot: draft.id))
        let readBack = try sandbox.library.jpeg(for: snapshot)
        #expect(readBack == jpeg)
        // Le poids inscrit vient du fichier, pas de ce que l'appelant annonce.
        #expect(snapshot.byteCount == jpeg.count)
        let total = try await sandbox.store.byteCount(in: session)
        #expect(total == jpeg.count)
    }

    @Test("Le fichier porte le nom du picture_id")
    func fileIsNamedAfterThePictureIdentifier() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        let session = try await makeSession(sandbox)

        let draft = Sample.draft(step: 0)
        let snapshot = try await sandbox.library.record(jpeg: Sample.jpeg(), draft: draft, in: session)

        #expect(sandbox.library.fileURL(for: snapshot).lastPathComponent == "\(draft.id.uuidString).jpg")
    }

    @Test("Supprimer un cliché efface les deux côtés")
    func deletingShotRemovesBothSides() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        let session = try await makeSession(sandbox)

        let draft = Sample.draft(step: 0)
        try await sandbox.library.record(jpeg: Sample.jpeg(), draft: draft, in: session)
        try await sandbox.library.deleteShot(id: draft.id, in: session)

        let row = try await sandbox.store.shot(id: draft.id)
        #expect(row == nil)
        #expect(!sandbox.files.exists(session: session, shot: draft.id))
    }

    @Test("Supprimer une session vide son dossier")
    func deletingSessionEmptiesTheFolder() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        let session = try await makeSession(sandbox)

        for step in 0..<3 {
            try await sandbox.library.record(jpeg: Sample.jpeg(), draft: Sample.draft(step: step), in: session)
        }
        try await sandbox.library.deleteSession(id: session)

        #expect(sandbox.files.shotIdentifiers(session: session).isEmpty)
        #expect(sandbox.files.byteCount(session: session) == 0)
        let remaining = try await sandbox.store.shotCount(in: session)
        #expect(remaining == 0)
    }

    @Test("Le balayage n'emporte que les fichiers sans ligne")
    func sweepRemovesOrphanFilesOnly() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        let session = try await makeSession(sandbox)

        let kept = Sample.draft(step: 0)
        try await sandbox.library.record(jpeg: Sample.jpeg(), draft: kept, in: session)

        // Un fichier écrit sans ligne : ce que laisse une coupure entre les
        // deux écritures, ou un cliché retiré d'une version antérieure.
        let orphan = UUID()
        try sandbox.files.write(Sample.jpeg(), session: session, shot: orphan)

        let swept = try await sandbox.library.sweepOrphanFiles(in: session)
        #expect(swept == 1)
        #expect(!sandbox.files.exists(session: session, shot: orphan))
        #expect(sandbox.files.exists(session: session, shot: kept.id))
    }

    @Test("Une inscription refusée ne laisse pas de fichier derrière elle")
    func failedRecordLeavesNoFile() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }

        let ghost = UUID()
        let draft = Sample.draft(step: 0)
        await #expect(throws: CaptureStoreError.sessionNotFound(ghost)) {
            try await sandbox.library.record(jpeg: Sample.jpeg(), draft: draft, in: ghost)
        }
        // Le fichier est écrit avant la ligne ; si la ligne échoue, il repart.
        #expect(!sandbox.files.exists(session: ghost, shot: draft.id))
    }
}
