// SPDX-License-Identifier: MIT

import Foundation

extension PanoramaxClient {

    /// Étape 1 — crée un upload set. Le serveur se chargera du découpage en
    /// séquences et de la déduplication.
    public func createUploadSet(_ body: UploadSetRequest) async throws -> UploadSet {
        var body = body
        if body.userAgent == nil { body.userAgent = userAgent }
        let request = makeRequest(
            "POST",
            path: "upload_sets",
            body: try encode(body),
            contentType: "application/json"
        )
        return try await send(request, as: UploadSet.self)
    }

    /// Étape 2 — envoie un fichier déjà préparé sous forme de corps multipart
    /// **écrit sur disque**.
    ///
    /// La séparation entre construction du corps et envoi n'est pas gratuite :
    /// une `URLSession` en configuration `.background` n'accepte que
    /// `uploadTask(with:fromFile:)`. C'est cette contrainte qui structure toute
    /// la file d'envoi de l'application.
    ///
    /// - Parameter bodyFileURL: fichier produit par ``MultipartBodyBuilder``.
    public func uploadPreparedFile(
        uploadSetID: UUID,
        bodyFileURL: URL,
        contentType: String
    ) async throws {
        var request = makeRequest(
            "POST",
            path: "upload_sets/\(uploadSetID.uuidString)/files",
            contentType: contentType
        )
        request.httpBody = try Data(contentsOf: bodyFileURL)
        try await send(request)
    }

    /// Construit la requête d'envoi sans l'exécuter, pour la confier à une
    /// `URLSession` en tâche de fond.
    ///
    /// ```swift
    /// let (request, bodyURL) = try await client.makeUploadRequest(…)
    /// backgroundSession.uploadTask(with: request, fromFile: bodyURL).resume()
    /// ```
    public func makeUploadRequest(
        uploadSetID: UUID,
        pictureID: UUID,
        jpegURL: URL,
        isBlurred: Bool = false,
        bodyDirectory: URL
    ) throws -> (request: URLRequest, bodyFileURL: URL) {
        let builder = MultipartBodyBuilder()
        let bodyURL = bodyDirectory.appendingPathComponent("\(pictureID.uuidString).multipart")
        try builder.writeBody(
            fields: [
                "picture_id": pictureID.uuidString,
                "isBlurred": isBlurred ? "true" : "false"
            ],
            fileURL: jpegURL,
            fileName: "\(pictureID.uuidString).jpg",
            to: bodyURL
        )
        let request = makeRequest(
            "POST",
            path: "upload_sets/\(uploadSetID.uuidString)/files",
            contentType: builder.contentType
        )
        return (request, bodyURL)
    }

    /// Étape 3 — clôt l'ensemble.
    ///
    /// Nécessaire dès que le nombre réel de fichiers diffère de
    /// `estimated_nb_files`, ce qui est le cas dès que l'utilisateur supprime un
    /// cliché avant envoi — donc presque toujours.
    @discardableResult
    public func completeUploadSet(id: UUID) async throws -> UploadSet {
        try await send(
            makeRequest("POST", path: "upload_sets/\(id.uuidString)/complete"),
            as: UploadSet.self
        )
    }

    /// Étape 4 — état du traitement serveur.
    public func uploadSet(id: UUID) async throws -> UploadSet {
        try await send(
            makeRequest("GET", path: "upload_sets/\(id.uuidString)"),
            as: UploadSet.self
        )
    }

    /// Étape 4 bis — détail par fichier, avec les motifs de refus.
    public func uploadSetFiles(id: UUID) async throws -> [UploadSetFile] {
        let response = try await send(
            makeRequest("GET", path: "upload_sets/\(id.uuidString)/files"),
            as: UploadSetFilesResponse.self
        )
        return response.files
    }
}
