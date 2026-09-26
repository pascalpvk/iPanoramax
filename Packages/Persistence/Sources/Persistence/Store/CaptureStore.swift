// SPDX-License-Identifier: MIT

import Foundation
import GeoKit
import SwiftData

public enum CaptureStoreError: Error, Sendable, Equatable {
    case sessionNotFound(UUID)
    case shotNotFound(UUID)
}

/// Le magasin : sessions et clichés, rien d'autre.
///
/// Les octets des JPEG ne passent pas par ici — voir ``PhotoFileStore``, et
/// ``CaptureLibrary`` qui tient les deux d'accord.
///
/// `@ModelActor` parce qu'un `ModelContext` n'est pas `Sendable` : il reste
/// enfermé dans cet acteur, et rien n'en sort qui ne soit une valeur.
@ModelActor
public actor CaptureStore {

    // MARK: - Sessions

    /// Crée une session, ou rend celle qui porte déjà cet identifiant.
    ///
    /// Idempotent à dessein : une reprise après relance de l'app ne doit pas
    /// dédoubler la séquence en cours.
    @discardableResult
    public func createSession(
        id: UUID = UUID(),
        title: String? = nil,
        mode: CaptureMode,
        instanceHost: String? = nil,
        startedAt: Date = Date()
    ) throws -> SessionSnapshot {
        if let existing = try fetchSession(id) {
            return existing.snapshot(shotCount: try shotCount(in: id))
        }
        let session = CaptureSession(
            id: id,
            title: title,
            startedAt: startedAt,
            mode: mode,
            instanceHost: instanceHost
        )
        modelContext.insert(session)
        try modelContext.save()
        return session.snapshot(shotCount: 0)
    }

    public func session(id: UUID) throws -> SessionSnapshot? {
        guard let session = try fetchSession(id) else { return nil }
        return session.snapshot(shotCount: try shotCount(in: id))
    }

    /// Toutes les sessions, la plus récente en tête — l'ordre de l'écran
    /// « mes séquences ».
    public func sessions() throws -> [SessionSnapshot] {
        let descriptor = FetchDescriptor<CaptureSession>(
            sortBy: [SortDescriptor<CaptureSession>(\.startedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { session in
            session.snapshot(shotCount: (try? shotCount(in: session.id)) ?? 0)
        }
    }

    /// Clôt la capture. L'envoi, lui, n'a pas encore commencé.
    @discardableResult
    public func endSession(id: UUID, at date: Date = Date()) throws -> SessionSnapshot {
        let session = try requireSession(id)
        session.endedAt = date
        if session.state == .recording { session.state = .ready }
        try modelContext.save()
        return session.snapshot(shotCount: try shotCount(in: id))
    }

    public func setSessionState(_ state: SessionState, for id: UUID) throws {
        let session = try requireSession(id)
        session.state = state
        try modelContext.save()
    }

    public func setTitle(_ title: String?, for id: UUID) throws {
        let session = try requireSession(id)
        session.title = title
        try modelContext.save()
    }

    /// Rattache l'upload set créé côté serveur, et passe la session en envoi.
    public func attachUploadSet(
        _ uploadSetID: UUID,
        to id: UUID,
        instanceHost: String? = nil,
        visibility: String? = nil
    ) throws {
        let session = try requireSession(id)
        session.uploadSetID = uploadSetID
        if let instanceHost { session.instanceHost = instanceHost }
        if let visibility { session.visibility = visibility }
        session.state = .sending
        try modelContext.save()
    }

    /// Supprime la session et ses clichés, et rend les identifiants supprimés
    /// pour que l'appelant efface les fichiers correspondants.
    @discardableResult
    public func deleteSession(id: UUID) throws -> [UUID] {
        guard let session = try fetchSession(id) else { return [] }
        let removed = try shotIdentifiers(in: id)
        modelContext.delete(session)
        try modelContext.save()
        return removed
    }

    // MARK: - Accès internes

    func fetchSession(_ id: UUID) throws -> CaptureSession? {
        var descriptor = FetchDescriptor<CaptureSession>(
            predicate: #Predicate<CaptureSession> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func requireSession(_ id: UUID) throws -> CaptureSession {
        guard let session = try fetchSession(id) else {
            throw CaptureStoreError.sessionNotFound(id)
        }
        return session
    }
}
