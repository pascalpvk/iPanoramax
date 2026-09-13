// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import PanoramaxKit

@Suite("Upload sets")
struct UploadSetsAPITests {

    private static let uploadSetJSON = """
    {
      "id": "60d94628-8098-42cc-b684-ffb9aa9d35a7",
      "title": "Chemin des Vignes",
      "created_at": "2026-08-30T12:00:00.123456Z",
      "completed": false,
      "dispatched": false,
      "ready": false,
      "items_status": {
        "prepared": 12,
        "preparing": 3,
        "broken": 0,
        "rejected": 1,
        "not_processed": 4
      },
      "associated_collections": [
        { "id": "8c1f0b02-0000-4000-8000-000000000001",
          "title": "Chemin des Vignes — 1", "nb_items": 12, "ready": false }
      ]
    }
    """

    @Test("Les champs partent en snake_case, les valeurs absentes sont omises")
    func encodesRequestInSnakeCase() async throws {
        let network = MockNetwork()
        network.stub { _ in .json(Self.uploadSetJSON, status: 201) }
        let client = network.makeClient(token: "header.payload.signature")

        _ = try await client.createUploadSet(
            UploadSetRequest(
                title: "Chemin des Vignes",
                estimatedNbFiles: 214,
                splitDistance: 100,
                sortMethod: .timeAscending,
                visibility: .anyone
            )
        )

        let sent = try #require(network.requests.first)
        let body = try #require(sent.recordedBody)
        let object = try JSONSerialization.jsonObject(with: body)
        let json = try #require(object as? [String: Any])

        #expect(json["title"] as? String == "Chemin des Vignes")
        #expect(json["estimated_nb_files"] as? Int == 214)
        #expect(json["split_distance"] as? Int == 100)
        #expect(json["sort_method"] as? String == "time-asc")
        #expect(json["visibility"] as? String == "anyone")

        // Laissés à nil : c'est l'instance qui décide, pas le client.
        // `Any?` ne se compare pas à nil — on interroge les clés présentes.
        #expect(!json.keys.contains("split_time"))
        #expect(!json.keys.contains("duplicate_distance"))
        #expect(!json.keys.contains("no_split"))

        // Rempli automatiquement à partir du client.
        #expect(json["user_agent"] as? String == "iPanoramax/tests")
    }

    @Test("L'état d'un upload set est décodé, fractions de seconde comprises")
    func decodesUploadSet() async throws {
        let network = MockNetwork()
        network.stub { _ in .json(Self.uploadSetJSON) }
        let client = network.makeClient(token: "header.payload.signature")

        let id = try #require(UUID(uuidString: "60d94628-8098-42cc-b684-ffb9aa9d35a7"))
        let uploadSet = try await client.uploadSet(id: id)

        #expect(uploadSet.title == "Chemin des Vignes")
        #expect(uploadSet.ready == false)
        #expect(uploadSet.createdAt != nil)
        #expect(uploadSet.itemsStatus?.prepared == 12)
        #expect(uploadSet.itemsStatus?.total == 20)
        #expect(uploadSet.associatedCollections?.count == 1)
        #expect(uploadSet.associatedCollections?.first?.nbItems == 12)
    }

    @Test("Le motif de refus d'un fichier est conservé")
    func decodesRejection() async throws {
        let network = MockNetwork()
        network.stub { _ in
            .json("""
            {
              "files": [
                { "file_name": "IMG_0001.jpg", "size": 3145728,
                  "picture_id": "11111111-2222-3333-4444-555555555555" },
                { "file_name": "IMG_0002.jpg", "size": 3145728,
                  "rejected": {
                    "reason": "invalid_metadata",
                    "severity": "error",
                    "message": "Position GPS absente"
                  }
                }
              ]
            }
            """)
        }
        let client = network.makeClient(token: "header.payload.signature")

        let id = try #require(UUID(uuidString: "60d94628-8098-42cc-b684-ffb9aa9d35a7"))
        let files = try await client.uploadSetFiles(id: id)

        #expect(files.count == 2)
        #expect(files[0].rejected == nil)
        #expect(files[1].rejected?.reason == "invalid_metadata")
        #expect(files[1].rejected?.message == "Position GPS absente")
    }

    @Test("La clôture vise bien /complete")
    func callsCompleteEndpoint() async throws {
        let network = MockNetwork()
        network.stub { _ in .json(Self.uploadSetJSON) }
        let client = network.makeClient(token: "header.payload.signature")
        let id = try #require(UUID(uuidString: "60d94628-8098-42cc-b684-ffb9aa9d35a7"))

        _ = try await client.completeUploadSet(id: id)

        let sent = try #require(network.requests.first)
        #expect(sent.httpMethod == "POST")
        #expect(sent.url?.path == "/api/upload_sets/\(id.uuidString)/complete")
    }
}
