// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// Tient la base et le disque d'accord.
///
/// Deux magasins, une seule règle d'ordre :
///
/// - à l'écriture, **le fichier d'abord, la ligne ensuite** ;
/// - à la suppression, **la ligne d'abord, le fichier ensuite**.
///
/// Les deux vont dans le même sens et donnent le même invariant : *toute ligne
/// a son fichier ; certains fichiers peuvent n'avoir aucune ligne*. Le
/// déséquilibre est volontaire. Un fichier orphelin ne coûte que des octets, et
/// ``sweepOrphanFiles(in:)`` les récupère ; une ligne orpheline, elle, désigne
/// une photo qui n'existe pas, que l'écran affiche en vignette cassée et que la
/// file d'envoi retente indéfiniment.
///
/// Une structure et non un acteur : ``CaptureStore`` sérialise déjà les accès à
/// la base, et ``PhotoFileStore`` est sans état. Un acteur de plus n'ajouterait
/// qu'un saut d'isolation — et pas la garantie qu'on pourrait croire, puisque
/// chaque `await` rendrait la main de toute façon.
public struct CaptureLibrary: Sendable {

    public let store: CaptureStore
    public let files: PhotoFileStore

    public init(container: ModelContainer, files: PhotoFileStore) {
        self.store = CaptureStore(modelContainer: container)
        self.files = files
    }

    /// Bibliothèque de l'application : base et photos aux emplacements par
    /// défaut.
    public static func onDisk() throws -> CaptureLibrary {
        CaptureLibrary(container: try CaptureContainer.onDisk(), files: try PhotoFileStore())
    }

    /// Bibliothèque entièrement contenue dans un dossier, base comprise. Pour
    /// les tests et les aperçus.
    public static func inFolder(_ root: URL) throws -> CaptureLibrary {
        let databaseURL = root.appendingPathComponent("captures.store")
        let photos = root.appendingPathComponent("photos", isDirectory: true)
        return CaptureLibrary(
            container: try CaptureContainer.at(databaseURL),
            files: try PhotoFileStore(root: photos)
        )
    }

    // MARK: - Capture

    /// Range un cliché : le JPEG sur le disque, puis la ligne dans la base.
    ///
    /// Si l'inscription échoue, le fichier est retiré — l'appelant retrouve
    /// l'état d'avant, pas un demi-cliché.
    @discardableResult
    public func record(
        jpeg: Data,
        draft: ShotDraft,
        in sessionID: UUID
    ) async throws -> ShotSnapshot {
        var draft = draft
        draft.byteCount = jpeg.count
        try files.write(jpeg, session: sessionID, shot: draft.id)
        do {
            return try await store.appendShot(draft, to: sessionID)
        } catch {
            try? files.remove(session: sessionID, shot: draft.id)
            throw error
        }
    }

    public func jpeg(for shot: ShotSnapshot) throws -> Data {
        try files.read(session: shot.sessionID, shot: shot.id)
    }

    public func fileURL(for shot: ShotSnapshot) -> URL {
        files.fileURL(session: shot.sessionID, shot: shot.id)
    }

    // MARK: - Suppression

    public func deleteShot(id: UUID, in sessionID: UUID) async throws {
        try await store.deleteShot(id: id)
        try files.remove(session: sessionID, shot: id)
    }

    public func deleteSession(id: UUID) async throws {
        try await store.deleteSession(id: id)
        try files.removeSession(id)
    }

    /// Efface les JPEG que plus aucune ligne ne réclame, et rend leur nombre.
    ///
    /// À ne pas lancer pendant une capture : un cliché dont le fichier est
    /// écrit mais dont la ligne n'est pas encore enregistrée passerait pour un
    /// orphelin. Après la clôture d'une session, en revanche, c'est sans
    /// risque.
    @discardableResult
    public func sweepOrphanFiles(in sessionID: UUID) async throws -> Int {
        let known = Set(try await store.shotIdentifiers(in: sessionID))
        let onDisk = files.shotIdentifiers(session: sessionID)
        let orphans = onDisk.subtracting(known)
        for orphan in orphans {
            try files.remove(session: sessionID, shot: orphan)
        }
        return orphans.count
    }
}
