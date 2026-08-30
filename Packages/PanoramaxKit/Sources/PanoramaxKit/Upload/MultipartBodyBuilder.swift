// SPDX-License-Identifier: MIT

import Foundation

/// Écrit un corps `multipart/form-data` **sur disque**, en flux.
///
/// Pourquoi sur disque plutôt qu'en mémoire : une `URLSession` en configuration
/// `.background` — la seule qui survive à la mise en arrière-plan de
/// l'application — n'accepte que `uploadTask(with:fromFile:)`. Construire le
/// corps en `Data` interdirait donc l'envoi en tâche de fond, et ferait monter
/// la mémoire proportionnellement à la taille des photos.
///
/// Le fichier source est copié par blocs de 512 Ko : l'empreinte mémoire reste
/// constante quelle que soit la taille du JPEG.
public struct MultipartBodyBuilder: Sendable {

    public let boundary: String

    public var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    public init(boundary: String? = nil) {
        self.boundary = boundary ?? "iPanoramax.\(UUID().uuidString)"
    }

    /// - Parameters:
    ///   - fields: champs textuels, sérialisés dans l'ordre alphabétique pour
    ///     que le corps soit reproductible (utile en test).
    ///   - fileField: nom du champ de fichier attendu par Panoramax.
    ///   - fileURL: le JPEG à envoyer.
    ///   - destination: le fichier de corps à produire. Écrasé s'il existe.
    public func writeBody(
        fields: [String: String] = [:],
        fileField: String = "file",
        fileURL: URL,
        fileName: String? = nil,
        mimeType: String = "image/jpeg",
        to destination: URL
    ) throws {
        let manager = FileManager.default
        try manager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        guard manager.createFile(atPath: destination.path, contents: nil),
              let output = FileHandle(forWritingAtPath: destination.path)
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? output.close() }

        var header = ""
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            header += "--\(boundary)\r\n"
            header += "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
            header += "\(value)\r\n"
        }
        header += "--\(boundary)\r\n"
        header += "Content-Disposition: form-data; name=\"\(fileField)\";"
        header += " filename=\"\(fileName ?? fileURL.lastPathComponent)\"\r\n"
        header += "Content-Type: \(mimeType)\r\n\r\n"
        try output.write(contentsOf: Data(header.utf8))

        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 512 * 1024), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }

        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    }
}
