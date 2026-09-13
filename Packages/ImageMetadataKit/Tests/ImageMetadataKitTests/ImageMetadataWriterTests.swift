// SPDX-License-Identifier: MIT

import Foundation
import ImageIO
import Testing
@testable import ImageMetadataKit

@Suite("Aller-retour dans un JPEG")
struct ImageMetadataWriterTests {

    /// Le seul test qui prouve quelque chose : écrire, relire avec ImageIO,
    /// comparer. Un dictionnaire bien formé ne garantit pas un fichier bien
    /// formé — c'est précisément là que Panoramax rejette une photo.
    @Test("Ce qui est écrit se relit")
    func roundTripsThroughImageIO() throws {
        let original = try SampleJPEG.make()
        let metadata = try ExifMetadataBuilderTests.metadata()

        let written = try ImageMetadataWriter.writingMetadata(metadata, into: original)
        let properties = try ImageMetadataWriter.readingProperties(from: written)

        let gps = try #require(properties[kCGImagePropertyGPSDictionary as String] as? [String: Any])
        let latitude = try #require(gps[kCGImagePropertyGPSLatitude as String] as? Double)
        let longitude = try #require(gps[kCGImagePropertyGPSLongitude as String] as? Double)

        // ImageIO repasse par des rationnels EXIF : on compare à la tolérance
        // d'un dix-millième de degré, soit une dizaine de centimètres.
        #expect(abs(latitude - 45.9237) < 0.0001)
        #expect(abs(longitude - 6.8694) < 0.0001)
        #expect(gps[kCGImagePropertyGPSLatitudeRef as String] as? String == "N")
        #expect(gps[kCGImagePropertyGPSLongitudeRef as String] as? String == "E")

        #expect(gps[kCGImagePropertyGPSDateStamp as String] as? String == "2026:08:30")
        let time = try #require(gps[kCGImagePropertyGPSTimeStamp as String] as? String)
        #expect(time.hasPrefix("14:05:09"))

        let direction = try #require(gps[kCGImagePropertyGPSImgDirection as String] as? Double)
        #expect(abs(direction - 137.4) < 0.01)
        #expect(gps[kCGImagePropertyGPSImgDirectionRef as String] as? String == "T")

        let exif = try #require(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])
        #expect(exif[kCGImagePropertyExifDateTimeOriginal as String] as? String == "2026:08:30 16:05:09")
        #expect(exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String == "+02:00")
        #expect(exif[kCGImagePropertyExifSubsecTimeOriginal as String] as? String == "250")

        let tiff = try #require(properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any])
        #expect(tiff[kCGImagePropertyTIFFMake as String] as? String == "Apple")
        #expect(tiff[kCGImagePropertyTIFFModel as String] as? String == "iPhone 15 Pro")
    }

    @Test("L'image n'est pas recompressée et garde ses dimensions")
    func preservesImagePayload() throws {
        let original = try SampleJPEG.make(width: 24, height: 18)
        let metadata = try ExifMetadataBuilderTests.metadata()
        let written = try ImageMetadataWriter.writingMetadata(metadata, into: original)

        let properties = try ImageMetadataWriter.readingProperties(from: written)
        #expect(properties[kCGImagePropertyPixelWidth as String] as? Int == 24)
        #expect(properties[kCGImagePropertyPixelHeight as String] as? Int == 18)

        // Métadonnées ajoutées, donc fichier plus gros — mais du même ordre :
        // une recompression changerait radicalement la taille utile.
        #expect(written.count > original.count)
        #expect(written.count < original.count + 8_192)
    }

    @Test("Les propriétés déjà présentes sont conservées")
    func mergesInsteadOfReplacing() throws {
        let base: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: [
                kCGImagePropertyGPSAltitude as String: 900.0,
                kCGImagePropertyGPSDOP as String: 1.5
            ],
            kCGImagePropertyOrientation as String: 6
        ]
        let additions: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: [
                kCGImagePropertyGPSAltitude as String: 1_042.5,
                kCGImagePropertyGPSLatitude as String: 45.9237
            ]
        ]

        let merged = ImageMetadataWriter.merging(base, with: additions)
        let gps = try #require(merged[kCGImagePropertyGPSDictionary as String] as? [String: Any])

        // Remplacé par la nouvelle valeur…
        #expect(gps[kCGImagePropertyGPSAltitude as String] as? Double == 1_042.5)
        // …ajouté…
        #expect(gps[kCGImagePropertyGPSLatitude as String] as? Double == 45.9237)
        // …et surtout : pas effacé par la fusion du bloc GPS.
        #expect(gps[kCGImagePropertyGPSDOP as String] as? Double == 1.5)
        #expect(merged[kCGImagePropertyOrientation as String] as? Int == 6)
    }

    @Test("Des octets qui ne sont pas une image sont refusés proprement")
    func rejectsNonImageData() throws {
        let garbage = Data("ceci n'est pas un JPEG".utf8)
        let metadata = try ExifMetadataBuilderTests.metadata()

        #expect(throws: ImageMetadataWriter.Failure.unreadableSource) {
            _ = try ImageMetadataWriter.writingMetadata(metadata, into: garbage)
        }
        #expect(throws: ImageMetadataWriter.Failure.unreadableSource) {
            _ = try ImageMetadataWriter.readingProperties(from: garbage)
        }
    }
}
