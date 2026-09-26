// SPDX-License-Identifier: MIT

import Foundation

/// Range les JPEG sur le disque, à l'écart de la base.
///
/// La base ne contient que des chemins : une séquence de 500 clichés pèse
/// plusieurs gigaoctets, et un magasin SwiftData qui les porterait serait
/// illisible, insauvegardable et lent à migrer. Les fichiers vivent dans
/// `Application Support/captures/<session>/<cliché>.jpg`.
///
/// `Application Support` et non `Caches` : le système vide `Caches` sous
/// pression de stockage, et perdre une séquence pas encore envoyée n'est pas
/// une option.
public struct PhotoFileStore: Sendable {

    public enum Failure: Error, Sendable, Equatable {
        case rootUnavailable
    }

    public let root: URL

    /// - Parameter root: dossier racine. Par défaut
    ///   `Application Support/captures`. Un dossier temporaire en test.
    public init(root: URL? = nil) throws {
        if let root {
            self.root = root
        } else {
            guard let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw Failure.rootUnavailable
            }
            self.root = support.appendingPathComponent("captures", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    public func directory(for session: UUID) -> URL {
        root.appendingPathComponent(session.uuidString, isDirectory: true)
    }

    /// Nom de fichier d'un cliché. C'est aussi son `picture_id` côté Panoramax :
    /// un seul identifiant du déclenchement jusqu'à l'ingestion.
    public func fileName(for shot: UUID) -> String {
        "\(shot.uuidString).jpg"
    }

    public func fileURL(session: UUID, shot: UUID) -> URL {
        directory(for: session).appendingPathComponent(fileName(for: shot))
    }

    @discardableResult
    public func write(_ jpeg: Data, session: UUID, shot: UUID) throws -> URL {
        let directory = directory(for: session)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName(for: shot))
        try jpeg.write(to: url, options: .atomic)
        return url
    }

    public func read(session: UUID, shot: UUID) throws -> Data {
        try Data(contentsOf: fileURL(session: session, shot: shot))
    }

    public func exists(session: UUID, shot: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(session: session, shot: shot).path)
    }

    public func byteCount(session: UUID, shot: UUID) -> Int {
        let path = fileURL(session: session, shot: shot).path
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }

    public func remove(session: UUID, shot: UUID) throws {
        let url = fileURL(session: session, shot: shot)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func removeSession(_ session: UUID) throws {
        let url = directory(for: session)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Identifiants des clichés réellement présents sur le disque.
    ///
    /// Sert au balayage des orphelins : la base est la référence, le disque
    /// peut la dépasser mais jamais lui manquer.
    public func shotIdentifiers(session: UUID) -> Set<UUID> {
        let directory = directory(for: session)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            atPath: directory.path
        ) else { return [] }
        return Set(entries.compactMap { entry -> UUID? in
            guard entry.hasSuffix(".jpg") else { return nil }
            return UUID(uuidString: String(entry.dropLast(4)))
        })
    }

    /// Octets occupés par une session. Sert à dire à l'utilisateur ce que sa
    /// séquence pèse avant de la lui faire envoyer en 4G.
    public func byteCount(session: UUID) -> Int {
        let directory = directory(for: session)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return entries.reduce(0) { total, url in
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            return total + (size ?? 0)
        }
    }
}
