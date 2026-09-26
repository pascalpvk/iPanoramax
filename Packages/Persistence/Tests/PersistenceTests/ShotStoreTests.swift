// SPDX-License-Identifier: MIT

import Foundation
import GeoKit
import ImageMetadataKit
import Testing
@testable import Persistence

@Suite("Magasin — clichés")
struct ShotStoreTests {

    private func makeSession(_ sandbox: Sandbox) async throws -> UUID {
        let id = UUID()
        try await sandbox.store.createSession(id: id, mode: .distance(metres: 10))
        return id
    }

    @Test("Les rangs se suivent dans l'ordre d'inscription")
    func appendsShotsWithIncreasingIndexes() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        let session = try await makeSession(sandbox)

        for step in 0..<4 {
            try await sandbox.store.appendShot(Sample.draft(step: step), to: session)
        }

        let shots = try await sandbox.store.shots(in: session)
        #expect(shots.map(\.index) == [0, 1, 2, 3])
        #expect(shots.map(\.state) == Array(repeating: ShotState.captured, count: 4))
    }

    @Test("Réinscrire le même cliché ne crée pas de doublon")
    func reappendingSameShotIsIdempotent() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        let session = try await makeSession(sandbox)

        let draft = Sample.draft(step: 0)
        let first = try await sandbox.store.appendShot(draft, to: session)
        let second = try await sandbox.store.appendShot(draft, to: session)

        #expect(first == second)
        let count = try await sandbox.store.shotCount(in: session)
        #expect(count == 1)
    }

    @Test("Un rang libéré par une suppression n'est pas réattribué")
    func indexIsNotReusedAfterDeletion() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        let session = try await makeSession(sandbox)

        let middle = Sample.draft(step: 1)
        try await sandbox.store.appendShot(Sample.draft(step: 0), to: session)
        try await sandbox.store.appendShot(middle, to: session)
        try await sandbox.store.appendShot(Sample.draft(step: 2), to: session)
        try await sandbox.store.deleteShot(id: middle.id)

        let added = try await sandbox.store.appendShot(Sample.draft(step: 3), to: session)
        // Trois rangs attribués, un cliché supprimé : le suivant est 3, pas 2.
        // Sans quoi deux clichés se disputeraient la même place dans la séquence.
        #expect(added.index == 3)
        let shots = try await sandbox.store.shots(in: session)
        #expect(shots.map(\.index) == [0, 2, 3])
    }

    @Test("La file d'envoi ignore ce qui est déjà parti")
    func pendingShotsIgnoreWhatIsAlreadySent() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        let session = try await makeSession(sandbox)

        let sent = Sample.draft(step: 0)
        let waiting = Sample.draft(step: 1)
        try await sandbox.store.appendShot(sent, to: session)
        try await sandbox.store.appendShot(waiting, to: session)
        try await sandbox.store.setShotState(.sent, for: sent.id)

        let pending = try await sandbox.store.pendingShots(in: session)
        #expect(pending.map(\.id) == [waiting.id])
    }

    @Test("Un motif de refus disparaît quand le cliché n'est plus refusé")
    func rejectionReasonIsClearedWhenStateChanges() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        let session = try await makeSession(sandbox)

        let draft = Sample.draft(step: 0)
        try await sandbox.store.appendShot(draft, to: session)
        try await sandbox.store.setShotState(.rejected, reason: "Invalid EXIF date", for: draft.id)

        let refused = try await sandbox.store.shot(id: draft.id)
        #expect(refused?.state == .rejected)
        #expect(refused?.rejectionReason == "Invalid EXIF date")

        try await sandbox.store.setShotState(.sent, for: draft.id)
        let accepted = try await sandbox.store.shot(id: draft.id)
        #expect(accepted?.state == .sent)
        // Garder le motif sous un cliché accepté serait un mensonge à l'écran.
        #expect(accepted?.rejectionReason == nil)
    }

    @Test("Position, altitude, précision et cap se relisent tels quels")
    func roundTripsGeometryAndHeading() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        let session = try await makeSession(sandbox)

        let draft = Sample.draft(step: 2, heading: Heading(trueDegrees: 187.5, source: .magneticCompass))
        try await sandbox.store.appendShot(draft, to: session)

        let stored = try await sandbox.store.shot(id: draft.id)
        #expect(stored?.coordinate == draft.coordinate)
        #expect(stored?.altitude == draft.altitude)
        #expect(stored?.horizontalAccuracy == draft.horizontalAccuracy)
        #expect(stored?.heading == Heading(trueDegrees: 187.5, source: .magneticCompass))
        #expect(stored?.capturedAt == draft.capturedAt)
    }

    @Test("Un cliché sans cap reste sans cap")
    func keepsMissingHeadingMissing() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        let session = try await makeSession(sandbox)

        let draft = Sample.draft(step: 0, heading: nil)
        try await sandbox.store.appendShot(draft, to: session)

        let stored = try await sandbox.store.shot(id: draft.id)
        #expect(stored?.heading == nil)
    }

    @Test("Inscrire dans une session inconnue échoue explicitement")
    func appendingToUnknownSessionThrows() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }

        let ghost = UUID()
        await #expect(throws: CaptureStoreError.sessionNotFound(ghost)) {
            try await sandbox.store.appendShot(Sample.draft(step: 0), to: ghost)
        }
    }
}
