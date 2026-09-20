// SPDX-License-Identifier: MIT

import Foundation
import ImageIO
import Testing
@testable import ImageMetadataKit

@Suite("Dictionnaire EXIF")
struct ExifMetadataBuilderTests {

    /// 30 août 2026, 14:05:09,250 UTC.
    static let instant = Date(timeIntervalSince1970: 1_788_098_709.25)

    static func metadata(
        latitude: Double = 45.9237,
        longitude: Double = 6.8694,
        altitude: Double? = 1_042.5,
        heading: Heading? = Heading(trueDegrees: 137.4, source: .magneticCompass)
    ) throws -> CaptureMetadata {
        CaptureMetadata(
            position: GeoPosition(
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                horizontalAccuracy: 4.5,
                speed: 1.4
            ),
            timestamp: instant,
            timeZone: try #require(TimeZone(identifier: "Europe/Paris")),
            heading: heading,
            device: DeviceDescription(
                make: "Apple",
                model: "iPhone 15 Pro",
                lensModel: "iPhone 15 Pro back camera 6.86mm f/1.78",
                focalLength: 6.86,
                focalLengthIn35mm: 24
            ),
            software: "iPanoramax 0.1.0"
        )
    }

    /// Méthode d'instance : Swift Testing crée une instance par test, et un
    /// membre statique ne s'appelle pas sans qualification depuis celle-ci.
    /// `metadata` reste statique, `ImageMetadataWriterTests` s'en sert.
    func gps(_ metadata: CaptureMetadata) -> [String: Any] {
        ExifMetadataBuilder.gps(for: metadata)
    }

    @Test("La position part en valeur absolue, le signe dans la référence")
    func splitsSignIntoReference() throws {
        let north = gps(try Self.metadata())
        #expect(north[kCGImagePropertyGPSLatitude as String] as? Double == 45.9237)
        #expect(north[kCGImagePropertyGPSLatitudeRef as String] as? String == "N")
        #expect(north[kCGImagePropertyGPSLongitude as String] as? Double == 6.8694)
        #expect(north[kCGImagePropertyGPSLongitudeRef as String] as? String == "E")

        let south = gps(try Self.metadata(latitude: -22.9068, longitude: -43.1729))
        #expect(south[kCGImagePropertyGPSLatitude as String] as? Double == 22.9068)
        #expect(south[kCGImagePropertyGPSLatitudeRef as String] as? String == "S")
        #expect(south[kCGImagePropertyGPSLongitude as String] as? Double == 43.1729)
        #expect(south[kCGImagePropertyGPSLongitudeRef as String] as? String == "W")
    }

    @Test("L'altitude sous le niveau de la mer passe par la référence 1")
    func encodesNegativeAltitude() throws {
        let below = gps(try Self.metadata(altitude: -12.0))
        #expect(below[kCGImagePropertyGPSAltitude as String] as? Double == 12.0)
        #expect(below[kCGImagePropertyGPSAltitudeRef as String] as? Int == 1)

        let above = gps(try Self.metadata())
        #expect(above[kCGImagePropertyGPSAltitudeRef as String] as? Int == 0)
    }

    @Test("Un cap absent n'écrit aucune direction — mieux vaut rien qu'un cap faux")
    func omitsAbsentHeading() throws {
        let without = gps(try Self.metadata(heading: nil))
        #expect(!without.keys.contains(kCGImagePropertyGPSImgDirection as String))
        #expect(!without.keys.contains(kCGImagePropertyGPSImgDirectionRef as String))
        #expect(!without.keys.contains(kCGImagePropertyGPSTrack as String))
    }

    @Test("GPSTrack n'est rempli que si le cap vient du déplacement")
    func writesTrackOnlyForGPSCourse() throws {
        let compass = gps(try Self.metadata(heading: Heading(trueDegrees: 137.4, source: .magneticCompass)))
        #expect(compass[kCGImagePropertyGPSImgDirection as String] as? Double == 137.4)
        #expect(compass[kCGImagePropertyGPSImgDirectionRef as String] as? String == "T")
        #expect(!compass.keys.contains(kCGImagePropertyGPSTrack as String))

        let course = gps(try Self.metadata(heading: Heading(trueDegrees: 137.4, source: .gpsCourse)))
        #expect(course[kCGImagePropertyGPSTrack as String] as? Double == 137.4)
        #expect(course[kCGImagePropertyGPSTrackRef as String] as? String == "T")
    }

    @Test("Un cap est ramené dans 0..<360")
    func normalizesHeading() {
        #expect(Heading(trueDegrees: 370, source: .gpsCourse).trueDegrees == 10)
        #expect(Heading(trueDegrees: -90, source: .gpsCourse).trueDegrees == 270)
        #expect(Heading(trueDegrees: 359.9, source: .gpsCourse).trueDegrees == 359.9)
    }

    @Test("La vitesse est convertie en km/h")
    func convertsSpeedToKilometresPerHour() throws {
        let values = gps(try Self.metadata())
        let speed = try #require(values[kCGImagePropertyGPSSpeed as String] as? Double)
        #expect(abs(speed - 5.04) < 0.001)
        #expect(values[kCGImagePropertyGPSSpeedRef as String] as? String == "K")
    }

    @Test("La précision horizontale est reportée telle quelle")
    func reportsHorizontalAccuracy() throws {
        let values = gps(try Self.metadata())
        #expect(values[kCGImagePropertyGPSHPositioningError as String] as? Double == 4.5)
    }

    @Test("L'appareil et l'optique atterrissent dans les bons blocs")
    func placesDeviceFields() throws {
        let metadata = try Self.metadata()
        let tiff = try #require(ExifMetadataBuilder.tiff(for: metadata))
        #expect(tiff[kCGImagePropertyTIFFMake as String] as? String == "Apple")
        #expect(tiff[kCGImagePropertyTIFFModel as String] as? String == "iPhone 15 Pro")
        #expect(tiff[kCGImagePropertyTIFFSoftware as String] as? String == "iPanoramax 0.1.0")

        let exif = ExifMetadataBuilder.exif(for: metadata)
        #expect(exif[kCGImagePropertyExifFocalLength as String] as? Double == 6.86)
        #expect(exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? Int == 24)
    }
}
