// SPDX-License-Identifier: MIT

import Foundation
import GeoKit
import ImageMetadataKit
@testable import Persistence

/// Une bibliothèque jetable dans un dossier temporaire à elle.
///
/// Un dossier par test, jamais partagé : les suites de Swift Testing
/// s'exécutent en parallèle, et un magasin commun ferait lire à un test ce
/// qu'un autre vient d'écrire. La leçon a déjà été payée sur `PanoramaxKit`.
struct Sandbox: Sendable {

    let root: URL
    let library: CaptureLibrary

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("iPanoramax-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        library = try CaptureLibrary.inFolder(root)
    }

    var store: CaptureStore { library.store }
    var files: PhotoFileStore { library.files }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}

enum Sample {

    /// Un JPEG minuscule mais reconnaissable : l'en-tête SOI, un commentaire,
    /// le marqueur de fin. Les tests de persistance n'ont pas besoin d'image,
    /// seulement d'octets dont on sait qu'ils ressortent identiques.
    static func jpeg(byte: UInt8 = 0x42, padding: Int = 16) -> Data {
        var data = Data([0xFF, 0xD8])
        data.append(contentsOf: [UInt8](repeating: byte, count: padding))
        data.append(contentsOf: [0xFF, 0xD9])
        return data
    }

    static let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// Un cliché sur une ligne droite vers l'est, un point tous les dix mètres.
    static func draft(
        id: UUID = UUID(),
        step: Int,
        heading: Heading? = Heading(trueDegrees: 90, source: .gpsCourse)
    ) -> ShotDraft {
        ShotDraft(
            id: id,
            capturedAt: start.addingTimeInterval(Double(step) * 7),
            coordinate: Coordinate(
                latitude: 48.8566,
                longitude: 2.3522 + Double(step) * 0.000_136
            ),
            altitude: 35 + Double(step),
            horizontalAccuracy: 4.5,
            heading: heading
        )
    }
}
