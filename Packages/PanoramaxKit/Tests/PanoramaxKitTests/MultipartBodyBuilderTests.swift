// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import PanoramaxKit

@Suite("Corps multipart")
struct MultipartBodyBuilderTests {

    /// Dossier temporaire propre à chaque test.
    private func makeScratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ipanoramax-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFile(_ bytes: Data, named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try bytes.write(to: url)
        return url
    }

    @Test("Le corps respecte le cadrage multipart et préserve le fichier octet pour octet")
    func framesBodyCorrectly() throws {
        let scratch = try makeScratchDirectory()
        let payload = Data("\u{FFFD}JPEG-CONTENU-BINAIRE\u{0}\u{1}\u{2}".utf8)
        let jpeg = try writeFile(payload, named: "IMG_0001.jpg", in: scratch)
        let destination = scratch.appendingPathComponent("body.multipart")

        let builder = MultipartBodyBuilder(boundary: "FRONTIERE")
        try builder.writeBody(
            fields: ["picture_id": "11111111-2222-3333-4444-555555555555", "isBlurred": "false"],
            fileURL: jpeg,
            fileName: "photo.jpg",
            to: destination
        )

        let body = try Data(contentsOf: destination)
        let text = try #require(String(data: body, encoding: .isoLatin1))

        #expect(builder.contentType == "multipart/form-data; boundary=FRONTIERE")

        // Champs textuels, triés par nom pour que le corps soit reproductible.
        let isBlurredIndex = try #require(text.range(of: "name=\"isBlurred\"")).lowerBound
        let pictureIDIndex = try #require(text.range(of: "name=\"picture_id\"")).lowerBound
        let fileIndex = try #require(text.range(of: "name=\"file\"")).lowerBound
        #expect(isBlurredIndex < pictureIDIndex)
        #expect(pictureIDIndex < fileIndex)

        #expect(text.contains("Content-Disposition: form-data; name=\"isBlurred\"\r\n\r\nfalse\r\n"))
        #expect(text.contains("filename=\"photo.jpg\""))
        #expect(text.contains("Content-Type: image/jpeg\r\n\r\n"))
        #expect(text.hasSuffix("\r\n--FRONTIERE--\r\n"))
        #expect(text.hasPrefix("--FRONTIERE\r\n"))

        // Le contenu du fichier traverse sans altération.
        #expect(body.range(of: payload) != nil)
    }

    @Test("Un gros fichier est recopié en flux, sans perte ni troncature")
    func streamsLargeFile() throws {
        let scratch = try makeScratchDirectory()
        // 2 Mo, soit quatre blocs de lecture complets plus un reliquat.
        var payload = Data(count: 2 * 1024 * 1024 + 137)
        payload[0] = 0xFF
        payload[payload.count - 1] = 0xD9
        let jpeg = try writeFile(payload, named: "grande.jpg", in: scratch)
        let destination = scratch.appendingPathComponent("body.multipart")

        let builder = MultipartBodyBuilder(boundary: "B")
        try builder.writeBody(fileURL: jpeg, to: destination)

        let body = try Data(contentsOf: destination)
        let header = "--B\r\nContent-Disposition: form-data; name=\"file\";"
            + " filename=\"grande.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n"
        let footer = "\r\n--B--\r\n"

        #expect(body.count == header.utf8.count + payload.count + footer.utf8.count)
        #expect(body.suffix(footer.utf8.count + 1).first == 0xD9)
    }

    @Test("Écrire deux fois au même endroit écrase proprement")
    func overwritesExistingBody() throws {
        let scratch = try makeScratchDirectory()
        let jpeg = try writeFile(Data("court".utf8), named: "a.jpg", in: scratch)
        let destination = scratch.appendingPathComponent("body.multipart")

        let builder = MultipartBodyBuilder(boundary: "B")
        try builder.writeBody(fields: ["n": "1"], fileURL: jpeg, to: destination)
        let first = try Data(contentsOf: destination)
        try builder.writeBody(fileURL: jpeg, to: destination)
        let second = try Data(contentsOf: destination)

        #expect(second.count < first.count)
        #expect(String(data: second, encoding: .utf8)?.contains("name=\"n\"") == false)
    }
}

@Suite("Préparation d'un envoi")
struct UploadRequestPreparationTests {

    @Test("La requête et le corps sur disque sont prêts pour une session background")
    func preparesRequestAndBodyFile() async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let jpeg = scratch.appendingPathComponent("IMG_0003.jpg")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try Data("contenu".utf8).write(to: jpeg)

        let client = MockNetwork().makeClient(token: "header.payload.signature")
        let uploadSetID = try #require(UUID(uuidString: "60d94628-8098-42cc-b684-ffb9aa9d35a7"))
        let pictureID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))

        let prepared = try await client.makeUploadRequest(
            uploadSetID: uploadSetID,
            pictureID: pictureID,
            jpegURL: jpeg,
            bodyDirectory: scratch
        )

        #expect(prepared.request.httpMethod == "POST")
        #expect(prepared.request.url?.path == "/api/upload_sets/\(uploadSetID.uuidString)/files")
        #expect(prepared.request.value(forHTTPHeaderField: "Authorization")
            == "Bearer header.payload.signature")
        #expect(prepared.request.value(forHTTPHeaderField: "Content-Type")?
            .hasPrefix("multipart/form-data; boundary=") == true)

        // Le corps est un fichier : c'est la seule forme qu'accepte une
        // URLSession en configuration .background.
        #expect(prepared.request.httpBody == nil)
        #expect(FileManager.default.fileExists(atPath: prepared.bodyFileURL.path))

        let body = try #require(String(data: Data(contentsOf: prepared.bodyFileURL), encoding: .utf8))
        #expect(body.contains(pictureID.uuidString))
        #expect(body.contains("name=\"isBlurred\"\r\n\r\nfalse"))
    }
}
