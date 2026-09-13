// SPDX-License-Identifier: MIT

import Foundation
import ImageIO
import Testing
@testable import ImageMetadataKit

@Suite("Paquet XMP")
struct XMPPacketTests {

    static let attitude = CameraAttitude(yaw: 137.42, pitch: -3.5, roll: 0.75)

    @Test("Le paquet déclare l'espace de noms attendu par exiv2")
    func declaresPix4DNamespace() {
        let packet = XMPInjector.packet(for: Self.attitude, toolkit: "iPanoramax 0.1.0")
        #expect(packet.contains("xmlns:Camera=\"http://pix4d.com/camera/1.0/\""))
        #expect(packet.contains("x:xmptk=\"iPanoramax 0.1.0\""))
        #expect(packet.hasPrefix("<?xpacket begin="))
        #expect(packet.hasSuffix("<?xpacket end=\"w\"?>"))
    }

    @Test("Les angles s'écrivent avec un point décimal, pas une virgule")
    func alwaysUsesDecimalPoint() {
        let packet = XMPInjector.packet(for: Self.attitude, toolkit: "iPanoramax")
        #expect(packet.contains("Camera:Yaw=\"137.4200\""))
        #expect(packet.contains("Camera:Pitch=\"-3.5000\""))
        #expect(packet.contains("Camera:Roll=\"0.7500\""))
        #expect(!packet.contains(","))
    }

    @Test("Le nom de l'outil est échappé")
    func escapesToolkitName() {
        let packet = XMPInjector.packet(for: Self.attitude, toolkit: "a & b <c> \"d\"")
        #expect(packet.contains("x:xmptk=\"a &amp; b &lt;c&gt; &quot;d&quot;\""))
    }

    @Test("Sans attitude, aucun paquet — un segment vide n'apporte que du poids")
    func skipsPacketWithoutAttitude() throws {
        var metadata = try ExifMetadataBuilderTests.metadata()
        #expect(XMPInjector.packet(for: metadata) == nil)

        metadata.attitude = Self.attitude
        #expect(XMPInjector.packet(for: metadata) != nil)
    }
}

@Suite("Injection XMP dans le JPEG")
struct XMPInjectionTests {

    static func xmpSegments(in jpeg: Data) throws -> [JPEGSegment] {
        try JPEGScanner.segments(in: jpeg).filter { XMPInjector.isXMP($0, in: jpeg) }
    }

    @Test("Ce qui est injecté se relit à l'octet près")
    func roundTripsPacket() throws {
        let jpeg = try SampleJPEG.make()
        let packet = XMPInjector.packet(for: XMPPacketTests.attitude, toolkit: "iPanoramax")

        let written = try XMPInjector.injecting(packet, into: jpeg)
        let read = try #require(XMPInjector.extractingPacket(from: written))
        #expect(read == packet)
    }

    @Test("Une seconde injection remplace au lieu de dupliquer")
    func replacesInsteadOfDuplicating() throws {
        let jpeg = try SampleJPEG.make()
        let first = XMPInjector.packet(
            for: CameraAttitude(yaw: 10, pitch: 0, roll: 0),
            toolkit: "iPanoramax"
        )
        let second = XMPInjector.packet(
            for: CameraAttitude(yaw: 200, pitch: 0, roll: 0),
            toolkit: "iPanoramax"
        )

        let once = try XMPInjector.injecting(first, into: jpeg)
        let twice = try XMPInjector.injecting(second, into: once)

        let onceCount = try Self.xmpSegments(in: once).count
        let twiceCount = try Self.xmpSegments(in: twice).count
        #expect(onceCount == 1)
        #expect(twiceCount == 1)
        let read = try #require(XMPInjector.extractingPacket(from: twice))
        #expect(read.contains("Camera:Yaw=\"200.0000\""))
        #expect(!read.contains("Camera:Yaw=\"10.0000\""))
    }

    @Test("Le XMP se place après les segments applicatifs de tête, pas avant")
    func placesSegmentAfterLeadingAppMarkers() throws {
        let jpeg = try ImageMetadataWriter.writingMetadata(
            try ExifMetadataBuilderTests.metadata(),
            into: try SampleJPEG.make()
        )
        let packet = XMPInjector.packet(for: XMPPacketTests.attitude, toolkit: "iPanoramax")
        let written = try XMPInjector.injecting(packet, into: jpeg)

        let segments = try JPEGScanner.segments(in: written)
        let xmpIndex = try #require(segments.firstIndex { XMPInjector.isXMP($0, in: written) })

        // Tout ce qui précède le XMP est applicatif : l'APP1 Exif reste premier.
        #expect(segments[..<xmpIndex].allSatisfy { JPEGScanner.isApplicationMarker($0.marker) })
        // Et le XMP précède le premier segment non applicatif.
        let firstNonApp = segments.firstIndex { !JPEGScanner.isApplicationMarker($0.marker) }
        #expect(firstNonApp == nil || xmpIndex < (firstNonApp ?? 0))
    }

    @Test("L'injection ne casse ni l'image ni son EXIF")
    func preservesImageAndExif() throws {
        let metadata = try ExifMetadataBuilderTests.metadata()
        let base = try ImageMetadataWriter.writingMetadata(metadata, into: try SampleJPEG.make(width: 24, height: 18))
        let packet = XMPInjector.packet(for: XMPPacketTests.attitude, toolkit: "iPanoramax")
        let written = try XMPInjector.injecting(packet, into: base)

        let properties = try ImageMetadataWriter.readingProperties(from: written)
        #expect(properties[kCGImagePropertyPixelWidth as String] as? Int == 24)
        #expect(properties[kCGImagePropertyPixelHeight as String] as? Int == 18)

        let gps = try #require(properties[kCGImagePropertyGPSDictionary as String] as? [String: Any])
        #expect(gps[kCGImagePropertyGPSLatitudeRef as String] as? String == "N")
        let exif = try #require(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])
        #expect(exif[kCGImagePropertyExifDateTimeOriginal as String] as? String == "2026:08:30 16:05:09")
    }

    @Test("Le chemin complet écrit EXIF et XMP en une passe")
    func writesBothInOneCall() throws {
        var metadata = try ExifMetadataBuilderTests.metadata()
        metadata.attitude = XMPPacketTests.attitude

        let written = try ImageMetadataWriter.writingMetadata(metadata, into: try SampleJPEG.make())

        let packet = try #require(XMPInjector.extractingPacket(from: written))
        #expect(packet.contains("Camera:Yaw=\"137.4200\""))

        let properties = try ImageMetadataWriter.readingProperties(from: written)
        #expect(properties.keys.contains(kCGImagePropertyGPSDictionary as String))
    }

    @Test("Des octets qui ne sont pas un JPEG sont refusés")
    func rejectsNonJPEG() {
        let garbage = Data("ceci n'est pas un JPEG".utf8)
        #expect(throws: JPEGError.notAJPEG) {
            _ = try XMPInjector.injecting("<x/>", into: garbage)
        }
        #expect(throws: JPEGError.notAJPEG) {
            _ = try XMPInjector.extractingPacket(from: garbage)
        }
    }

    @Test("Un paquet trop gros pour un segment est refusé, pas tronqué")
    func rejectsOversizedPacket() throws {
        let jpeg = try SampleJPEG.make()
        let huge = String(repeating: "a", count: 70_000)
        #expect(throws: JPEGError.packetTooLarge(bytes: 70_000)) {
            _ = try XMPInjector.injecting(huge, into: jpeg)
        }
    }
}

@Suite("Analyse des segments JPEG")
struct JPEGScannerTests {

    @Test("Le parcours s'arrête au début des données compressées")
    func stopsAtStartOfScan() throws {
        let jpeg = try SampleJPEG.make()
        let segments = try JPEGScanner.segments(in: jpeg)

        let last = try #require(segments.last)
        #expect(last.marker == JPEGScanner.startOfScan)
        #expect(segments.filter { $0.marker == JPEGScanner.startOfScan }.count == 1)
    }

    @Test("Les étendues rendues restent valides sur une Data réindexée")
    func handlesNonZeroStartIndex() throws {
        let jpeg = try SampleJPEG.make()
        let padded = Data(repeating: 0, count: 7) + jpeg
        let slice = padded.dropFirst(7)

        #expect(slice.startIndex == 7)
        let direct = try JPEGScanner.segments(in: jpeg)
        let offsetted = try JPEGScanner.segments(in: slice)
        #expect(direct == offsetted)
    }

    @Test("Un fichier tronqué au milieu d'un segment est signalé")
    func reportsTruncatedSegment() throws {
        let jpeg = try SampleJPEG.make()
        let truncated = jpeg.prefix(6)
        #expect(throws: (any Error).self) {
            _ = try JPEGScanner.segments(in: Data(truncated))
        }
    }
}
