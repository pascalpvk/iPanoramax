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

        // C'est la configuration de l'instance qui dit ce qu'elle accepte, pas
        // nos suppositions. L'application devra faire exactement pareil.
        let configuration = try await client.configuration()
        let allowed = configuration.visibility?.possibleValues ?? []
        print("Licence des photos    \(configuration.license?.id ?? "non déclarée")")
        print("Visibilités acceptées \(allowed.isEmpty ? "non déclarées" : allowed.joined(separator: ", "))")

        let visibility = chooseVisibility(allowed: allowed, arguments: arguments)

        let title = arguments.options["title"] ?? "iPanoramax — essai \(Date().formatted(.iso8601))"
        let uploadSet = try await createUploadSet(client, title: title, visibility: visibility)
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

    // MARK: - Visibilité

    /// Un essai ne doit pas devenir de la donnée publique. Si l'instance ne
    /// sait pas masquer une séquence, on le dit et on s'arrête : mieux vaut
    /// refuser que tenir une promesse qu'on ne peut pas tenir.
    static func chooseVisibility(allowed: [String], arguments: Arguments) -> Visibility? {
        if allowed.contains(Visibility.ownerOnly.rawValue) {
            print("Envoi en owner-only — invisible des autres contributeurs.")
            return .ownerOnly
        }
        guard arguments.has("public") else {
            Probe.fail("""
                Cette instance ne déclare pas la visibilité « owner-only ».
                L'essai créerait donc une séquence PUBLIQUE.

                Relance avec --public si c'est bien ce que tu veux. Elle sera
                supprimée à la fin, sauf --keep.
                """)
        }
        print("--public : la séquence sera PUBLIQUE le temps de l'essai.")
        return nil
    }

    // MARK: - Création de l'upload set

    /// Crée l'upload set, en réduisant la requête tant qu'elle est refusée.
    ///
    /// Un 500 sur cette route rend une page d'erreur générique : elle ne dit pas
    /// quel champ pose problème. Plutôt que de deviner, on retire les champs un
    /// à un et on rapporte celui dont le retrait débloque la situation.
    static func createUploadSet(
        _ client: PanoramaxClient,
        title: String,
        visibility: Visibility?
    ) async throws -> UploadSet {
        var attempts: [(String, UploadSetRequest)] = [
            ("complet", UploadSetRequest(
                title: title,
                estimatedNbFiles: 1,
                sortMethod: .timeAscending,
                visibility: visibility,
                userAgent: Probe.userAgent
            ))
        ]
        if visibility != nil {
            attempts.append(("sans visibility", UploadSetRequest(
                title: title,
                estimatedNbFiles: 1,
                sortMethod: .timeAscending,
                userAgent: Probe.userAgent
            )))
        }
        attempts.append(("sans sort_method", UploadSetRequest(
            title: title,
            estimatedNbFiles: 1,
            sortMethod: nil,
            userAgent: Probe.userAgent
        )))
        attempts.append(("sans user_agent", UploadSetRequest(
            title: title,
            estimatedNbFiles: 1,
            sortMethod: nil
        )))
        attempts.append(("titre seul", UploadSetRequest(title: title, sortMethod: nil)))
        // Le titre était identique partout jusqu'ici : un accent ou un tiret
        // cadratin mal géré côté serveur resterait invisible à une bisection
        // qui ne fait varier que les autres champs.
        attempts.append(("titre ASCII", UploadSetRequest(title: "iPanoramax test", sortMethod: nil)))

        var lastError: Error?
        for (index, attempt) in attempts.enumerated() {
            let (label, request) = attempt
            print("\n  tentative « \(label) »")
            print("  corps  \(body(of: request))")
            do {
                let uploadSet = try await client.createUploadSet(request)
                print("  → acceptée.")
                if index > 0 {
                    let previous = attempts[index - 1].0
                    print("  Le champ absent ici et présent dans « \(previous) » est en cause.")
                }
                return uploadSet
            } catch {
                print("  → refusée : \(Probe.describe(error))")
                lastError = error
            }
        }
        await investigate(client)
        throw lastError ?? PanoramaxError.server(status: 500, message: nil)
    }

    /// Quand aucun corps ne passe, le problème n'est pas dans le corps.
    ///
    /// Trois questions, dans cet ordre : le compte a-t-il accepté les
    /// conditions d'utilisation de l'instance, que renvoie `/users/me` en
    /// entier, et l'ancienne route d'envoi répond-elle mieux ?
    static func investigate(_ client: PanoramaxClient) async {
        print("\n--- Aucun corps accepté : la cause est ailleurs ---")

        if let configuration = try? await client.configuration() {
            let tos = configuration.auth?.enforceTosAcceptance == true
            print("\nConditions d'utilisation à accepter : \(tos ? "OUI" : "non")")
            if tos {
                print("Si tu ne les as jamais acceptées sur le site, c'est la piste")
                print("la plus probable : connecte-toi sur le site de l'instance,")
                print("accepte les conditions, puis relance cet essai.")
            }
        }

        if let response = try? await client.raw(path: "users/me") {
            print("\nGET /api/users/me → HTTP \(response.statusCode)")
            print(String(response.body.prefix(800)))
        }

        print("\nEssai de l'ancienne route POST /api/collections :")
        do {
            let collection = try await client.createCollection(title: "iPanoramax test")
            print("  → acceptée, séquence \(collection.id)")
            print("  Les upload sets sont donc hors service sur cette instance,")
            print("  pas l'envoi en général. À signaler à l'équipe Panoramax.")
            try? await client.deleteCollection(id: UUID(uuidString: collection.id) ?? UUID())
        } catch {
            print("  → refusée : \(Probe.describe(error))")
            print("  Les deux routes échouent : le problème tient au compte ou")
            print("  à l'instance, pas à la requête.")
        }
    }

    /// Le corps réellement envoyé, pour qu'un refus soit lisible sans deviner.
    static func body(of request: UploadSetRequest) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(request),
              let text = String(data: data, encoding: .utf8)
        else { return "— illisible —" }
        return text
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
