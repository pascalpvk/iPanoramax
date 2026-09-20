// SPDX-License-Identifier: MIT

import Foundation
import ImageIO
import ImageMetadataKit
import PanoramaxKit

/// L'épreuve du feu de la phase 1 : une photo dont les métadonnées sont écrites
/// par notre code est-elle acceptée par une vraie instance Panoramax ?
///
/// Aucun test sur fixture ne peut y répondre. C'est le serveur qui tranche.
enum UploadProbe {

    /// Position de repli, volontairement banale et publique. Toute vraie
    /// campagne passe par `--lat` et `--lon`.
    static let defaultLatitude = 48.8584
    static let defaultLongitude = 2.2945

    static func run(
        instance: PanoramaxInstance,
        host: String,
        arguments: Arguments
    ) async throws {
        guard let path = arguments.argument(at: 1) else {
            Probe.fail("Indique le JPEG à envoyer : panoramax-probe upload photo.jpg")
        }
        let source = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let original: Data
        do {
            original = try Data(contentsOf: source)
        } catch {
            Probe.fail("Lecture impossible de \(source.path) : \(error.localizedDescription)")
        }

        // --- 1. Écriture des métadonnées ---------------------------------

        let metadata = makeMetadata(from: arguments)
        let enriched = try ImageMetadataWriter.writingMetadata(metadata, into: original)

        let destination = source
            .deletingPathExtension()
            .appendingPathExtension("panoramax.jpg")
        try enriched.write(to: destination)

        print("Source    \(source.lastPathComponent) — \(octets(original.count))")
        print("Produit   \(destination.lastPathComponent) — \(octets(enriched.count))")
        print()

        // --- 2. Relecture : ce qui est écrit est-il lisible ? -------------

        try describe(enriched)

        guard arguments.has("send") else {
            print("\nEssai à blanc. Ajoute --send pour envoyer réellement sur \(host).")
            return
        }

        // --- 3. Envoi ----------------------------------------------------

        guard let entry = TokenStore().entry(for: host) else {
            Probe.fail("Aucun jeton pour \(host). Lance d'abord : panoramax-probe login \(host)")
        }
        let client = PanoramaxClient(instance: instance, token: entry.jwt, userAgent: Probe.userAgent)

        print("\n--- Envoi sur \(host) ---")
        print("Visibilité : owner-only — un essai n'a pas à devenir de la donnée publique.")

        let title = arguments.options["title"] ?? "iPanoramax — essai \(Date().formatted(.iso8601))"
        let uploadSet = try await client.createUploadSet(
            UploadSetRequest(title: title, estimatedNbFiles: 1, visibility: .ownerOnly)
        )
        print("Upload set \(uploadSet.id.uuidString)")

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("panoramax-probe/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let pictureID = UUID()
        let jpegURL = scratch.appendingPathComponent("\(pictureID.uuidString).jpg")
        try enriched.write(to: jpegURL)

        // Le même chemin que celui qu'empruntera l'application : corps
        // multipart écrit sur disque, prêt pour une session en tâche de fond.
        let prepared = try await client.makeUploadRequest(
            uploadSetID: uploadSet.id,
            pictureID: pictureID,
            jpegURL: jpegURL,
            bodyDirectory: scratch
        )
        let contentType = prepared.request.value(forHTTPHeaderField: "Content-Type") ?? ""
        try await client.uploadPreparedFile(
            uploadSetID: uploadSet.id,
            bodyFileURL: prepared.bodyFileURL,
            contentType: contentType
        )
        print("Fichier envoyé, picture_id \(pictureID.uuidString)")

        try await client.completeUploadSet(id: uploadSet.id)

        // --- 4. Verdict du serveur ---------------------------------------

        let final = try await waitForProcessing(client, id: uploadSet.id)
        try await report(client, uploadSet: final, host: host)

        // --- 5. Nettoyage -------------------------------------------------

        guard !arguments.has("keep") else {
            print("\n--keep : la séquence reste sur \(host). Pense à la supprimer.")
            return
        }
        await cleanUp(client, uploadSet: final, host: host)
    }

    // MARK: - Métadonnées

    static func makeMetadata(from arguments: Arguments) -> CaptureMetadata {
        CaptureMetadata(
            position: GeoPosition(
                latitude: arguments.double("lat") ?? defaultLatitude,
                longitude: arguments.double("lon") ?? defaultLongitude,
                altitude: arguments.double("alt") ?? 35,
                horizontalAccuracy: 4.5,
                speed: 1.2
            ),
            timestamp: Date(),
            timeZone: .current,
            heading: arguments.double("heading").map {
                Heading(trueDegrees: $0, source: .magneticCompass)
            },
            attitude: CameraAttitude(yaw: 0, pitch: 0, roll: 0),
            device: DeviceDescription(
                make: "Apple",
                model: "panoramax-probe",
                focalLength: 6.86,
                focalLengthIn35mm: 24
            ),
            software: "iPanoramax (panoramax-probe)"
        )
    }

    /// Relit le fichier produit et affiche ce que Panoramax y trouvera.
    static func describe(_ jpeg: Data) throws {
        let properties = try ImageMetadataWriter.readingProperties(from: jpeg)

        func show(_ label: String, _ value: Any?) {
            let rendered = value.map { "\($0)" } ?? "— absent —"
            print("  \(label.padding(toLength: 22, withPad: " ", startingAt: 0)) \(rendered)")
        }

        print("Métadonnées relues dans le fichier produit :")
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]
        show("GPSLatitude", gps[kCGImagePropertyGPSLatitude as String])
        show("GPSLatitudeRef", gps[kCGImagePropertyGPSLatitudeRef as String])
        show("GPSLongitude", gps[kCGImagePropertyGPSLongitude as String])
        show("GPSLongitudeRef", gps[kCGImagePropertyGPSLongitudeRef as String])
        show("GPSDateStamp", gps[kCGImagePropertyGPSDateStamp as String])
        show("GPSTimeStamp", gps[kCGImagePropertyGPSTimeStamp as String])
        show("GPSImgDirection", gps[kCGImagePropertyGPSImgDirection as String])
        show("GPSAltitude", gps[kCGImagePropertyGPSAltitude as String])

        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        show("DateTimeOriginal", exif[kCGImagePropertyExifDateTimeOriginal as String])
        show("OffsetTimeOriginal", exif[kCGImagePropertyExifOffsetTimeOriginal as String])

        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        show("Make", tiff[kCGImagePropertyTIFFMake as String])
        show("Model", tiff[kCGImagePropertyTIFFModel as String])

        if let packet = try XMPInjector.extractingPacket(from: jpeg) {
            let attitude = packet
                .split(separator: "\n")
                .filter { $0.contains("Camera:") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
            print("  XMP                    \(attitude.joined(separator: " "))")
        } else {
            print("  XMP                    — absent —")
        }
    }

    // MARK: - Suivi et verdict

    static func waitForProcessing(
        _ client: PanoramaxClient,
        id: UUID,
        attempts: Int = 40
    ) async throws -> UploadSet {
        var latest = try await client.uploadSet(id: id)
        for _ in 1...attempts {
            if latest.ready == true { return latest }
            let status = latest.itemsStatus
            print("  traitement… prêt \(status?.prepared ?? 0)"
                + ", en cours \(status?.preparing ?? 0)"
                + ", cassé \(status?.broken ?? 0)"
                + ", refusé \(status?.rejected ?? 0)")
            try await Task.sleep(for: .seconds(3))
            latest = try await client.uploadSet(id: id)
        }
        return latest
    }

    static func report(_ client: PanoramaxClient, uploadSet: UploadSet, host: String) async throws {
        let files = try await client.uploadSetFiles(id: uploadSet.id)

        print("\n--- Verdict ---")
        for file in files {
            let name = file.fileName ?? file.pictureId?.uuidString ?? "?"
            if let rejection = file.rejected {
                print("REFUSÉ  \(name)")
                print("        motif   \(rejection.reason ?? "—")")
                print("        gravité \(rejection.severity ?? "—")")
                print("        message \(rejection.message ?? "—")")
            } else {
                print("ACCEPTÉ \(name)")
            }
        }

        for collection in uploadSet.associatedCollections ?? [] {
            print("\nSéquence \(collection.id.uuidString)")
            print("  \(collection.nbItems ?? 0) photo(s), prête : \(collection.ready == true ? "oui" : "pas encore")")
            print("  https://\(host)/api/collections/\(collection.id.uuidString)")
        }
    }

    // MARK: - Nettoyage

    /// Un essai contre une instance publique se nettoie derrière lui : ce qu'on
    /// y dépose est de la donnée réelle dans un commun partagé.
    static func cleanUp(_ client: PanoramaxClient, uploadSet: UploadSet, host: String) async {
        let collections = uploadSet.associatedCollections ?? []
        guard !collections.isEmpty else {
            print("\nAucune séquence créée — rien à nettoyer.")
            return
        }
        print("\n--- Nettoyage ---")
        for collection in collections {
            do {
                try await client.deleteCollection(id: collection.id)
                print("Séquence \(collection.id.uuidString) supprimée.")
            } catch {
                print("Suppression impossible de \(collection.id.uuidString) : \(Probe.describe(error))")
                print("À supprimer à la main sur https://\(host)/")
            }
        }
    }

    static func octets(_ count: Int) -> String {
        count < 1024 ? "\(count) o" : String(format: "%.1f Ko", Double(count) / 1024)
    }
}
