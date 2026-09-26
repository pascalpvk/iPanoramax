// SPDX-License-Identifier: MIT

import Foundation
import GeoKit
import ImageMetadataKit
import Testing
@testable import Persistence

@Suite("Magasin — sessions")
struct CaptureSessionStoreTests {

    // Le premier test de la suite, et le plus bête en apparence : il vérifie
    // qu'un `#Predicate` sait comparer des UUID. Si le magasin sous-jacent ne
    // le sait pas, tout le reste échoue en cascade sans dire pourquoi ; ici
    // l'échec nomme la cause.
    @Test("Une session se retrouve par son identifiant")
    func createsAndFetchesSessionByIdentifier() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }

        let id = UUID()
        try await sandbox.store.createSession(id: id, title: "Berges", mode: .distance(metres: 5))

        let found = try await sandbox.store.session(id: id)
        #expect(found?.id == id)
        #expect(found?.title == "Berges")
        #expect(found?.state == .recording)
        #expect(found?.shotCount == 0)
        let missing = try await sandbox.store.session(id: UUID())
        #expect(missing == nil)
    }

    @Test("Recréer la même session ne la dédouble pas")
    func creatingTwiceWithSameIdentifierDoesNotDuplicate() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }

        let id = UUID()
        try await sandbox.store.createSession(id: id, title: "Premier", mode: .manual)
        try await sandbox.store.createSession(id: id, title: "Second", mode: .time(seconds: 3))

        let sessions = try await sandbox.store.sessions()
        #expect(sessions.count == 1)
        // Le titre d'origine est conservé : la seconde création est une reprise
        // après relance, pas une redéfinition.
        #expect(sessions.first?.title == "Premier")
    }

    @Test("Les sessions arrivent de la plus récente à la plus ancienne")
    func listsSessionsNewestFirst() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }

        let old = UUID()
        let recent = UUID()
        try await sandbox.store.createSession(id: old, mode: .manual, startedAt: Sample.start)
        try await sandbox.store.createSession(
            id: recent,
            mode: .manual,
            startedAt: Sample.start.addingTimeInterval(3_600)
        )

        let listed = try await sandbox.store.sessions()
        #expect(listed.map(\.id) == [recent, old])
    }

    @Test("Clore une session l'horodate et la déclare prête")
    func endingSessionStampsDateAndState() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }

        let id = UUID()
        try await sandbox.store.createSession(id: id, mode: .distance(metres: 10))
        let end = Sample.start.addingTimeInterval(600)
        let closed = try await sandbox.store.endSession(id: id, at: end)

        #expect(closed.endedAt == end)
        #expect(closed.state == .ready)
    }

    @Test("Rattacher un upload set fait passer la session en envoi")
    func attachingUploadSetSwitchesToSending() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }

        let id = UUID()
        let uploadSet = UUID()
        try await sandbox.store.createSession(id: id, mode: .manual)
        try await sandbox.store.attachUploadSet(
            uploadSet,
            to: id,
            instanceHost: "panoramax.openstreetmap.fr",
            visibility: "owner-only"
        )

        let session = try await sandbox.store.session(id: id)
        #expect(session?.uploadSetID == uploadSet)
        #expect(session?.instanceHost == "panoramax.openstreetmap.fr")
        #expect(session?.visibility == "owner-only")
        #expect(session?.state == .sending)
    }

    @Test("Les trois modes de déclenchement se relisent tels quels")
    func roundTripsCaptureMode() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }

        let modes: [CaptureMode] = [.distance(metres: 7.5), .time(seconds: 2.5), .manual]
        for mode in modes {
            let id = UUID()
            try await sandbox.store.createSession(id: id, mode: mode)
            let stored = try await sandbox.store.session(id: id)
            #expect(stored?.mode == mode)
        }
    }

    @Test("Supprimer une session rend les clichés à effacer")
    func deletingSessionReturnsItsShots() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }

        let id = UUID()
        try await sandbox.store.createSession(id: id, mode: .manual)
        let first = Sample.draft(step: 0)
        let second = Sample.draft(step: 1)
        try await sandbox.store.appendShot(first, to: id)
        try await sandbox.store.appendShot(second, to: id)

        let removed = try await sandbox.store.deleteSession(id: id)
        #expect(Set(removed) == Set([first.id, second.id]))
        let gone = try await sandbox.store.session(id: id)
        #expect(gone == nil)
        // La suppression en cascade doit avoir emporté les clichés.
        let remaining = try await sandbox.store.shotCount(in: id)
        #expect(remaining == 0)
    }
}
