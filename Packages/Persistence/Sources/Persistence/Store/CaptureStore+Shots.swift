// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

extension CaptureStore {

    /// Inscrit un cliché dans une session.
    ///
    /// Idempotent sur ``ShotDraft/id`` : rejouer l'inscription après une
    /// interruption rend la ligne existante au lieu d'en créer une seconde.
    /// C'est la même garantie que côté serveur, où `picture_id` est fourni par
    /// le client — et pour la même raison.
    @discardableResult
    public func appendShot(_ draft: ShotDraft, to sessionID: UUID) throws -> ShotSnapshot {
        let session = try requireSession(sessionID)
        if let existing = try fetchShot(draft.id) { return existing.snapshot }
        let shot = Shot(draft: draft, sessionID: sessionID, index: try nextIndex(in: sessionID))
        modelContext.insert(shot)
        shot.session = session
        try modelContext.save()
        return shot.snapshot
    }

    /// Les clichés d'une session, dans l'ordre de prise de vue.
    public func shots(in sessionID: UUID) throws -> [ShotSnapshot] {
        try fetchShots(in: sessionID).map(\.snapshot)
    }

    public func shot(id: UUID) throws -> ShotSnapshot? {
        try fetchShot(id)?.snapshot
    }

    /// Ce qui reste à envoyer, dans l'ordre. C'est la file d'attente de la
    /// phase 3, rendue sous forme de valeurs.
    public func pendingShots(in sessionID: UUID) throws -> [ShotSnapshot] {
        let captured = ShotState.captured.rawValue
        let descriptor = FetchDescriptor<Shot>(
            predicate: #Predicate<Shot> { $0.sessionID == sessionID && $0.stateRaw == captured },
            sortBy: [SortDescriptor<Shot>(\.index)]
        )
        return try modelContext.fetch(descriptor).map(\.snapshot)
    }

    public func shotIdentifiers(in sessionID: UUID) throws -> [UUID] {
        try fetchShots(in: sessionID).map(\.id)
    }

    public func shotCount(in sessionID: UUID) throws -> Int {
        try modelContext.fetchCount(
            FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.sessionID == sessionID })
        )
    }

    /// Octets cumulés d'une session, d'après ce que la base a enregistré.
    public func byteCount(in sessionID: UUID) throws -> Int {
        try fetchShots(in: sessionID).reduce(0) { $0 + $1.byteCount }
    }

    /// - Parameter reason: motif rendu par le serveur. Effacé quand l'état
    ///   n'est plus `rejected` : garder un motif périmé sous un cliché accepté
    ///   serait un mensonge à l'écran.
    public func setShotState(_ state: ShotState, reason: String? = nil, for id: UUID) throws {
        guard let shot = try fetchShot(id) else { throw CaptureStoreError.shotNotFound(id) }
        shot.state = state
        shot.rejectionReason = state == .rejected ? reason : nil
        try modelContext.save()
    }

    public func deleteShot(id: UUID) throws {
        guard let shot = try fetchShot(id) else { return }
        modelContext.delete(shot)
        try modelContext.save()
    }

    // MARK: - Accès internes

    func fetchShot(_ id: UUID) throws -> Shot? {
        var descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchShots(in sessionID: UUID) throws -> [Shot] {
        let descriptor = FetchDescriptor<Shot>(
            predicate: #Predicate<Shot> { $0.sessionID == sessionID },
            sortBy: [SortDescriptor<Shot>(\.index)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Un rang au-dessus du plus haut déjà attribué.
    ///
    /// Pas le nombre de clichés : après une suppression au milieu, le compte
    /// retomberait sur un rang déjà pris.
    func nextIndex(in sessionID: UUID) throws -> Int {
        var descriptor = FetchDescriptor<Shot>(
            predicate: #Predicate<Shot> { $0.sessionID == sessionID },
            sortBy: [SortDescriptor<Shot>(\.index, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try modelContext.fetch(descriptor).first?.index ?? -1) + 1
    }
}
