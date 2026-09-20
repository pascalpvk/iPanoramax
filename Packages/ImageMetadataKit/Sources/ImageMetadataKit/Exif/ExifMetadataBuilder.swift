// SPDX-License-Identifier: MIT

import Foundation
import ImageIO

/// Traduit une ``CaptureMetadata`` en dictionnaire de propriétés ImageIO.
///
/// C'est le format qu'attendent à la fois `CGImageDestination` et
/// `AVCapturePhotoSettings.metadata`. Passer ce dictionnaire à
/// `AVCapturePhotoSettings` **avant** la prise de vue évite un ré-encodage du
/// JPEG, donc une perte de qualité : c'est le chemin à privilégier dans l'app,
/// ``ImageMetadataWriter`` n'étant qu'un filet pour les fichiers déjà produits.
public enum ExifMetadataBuilder {

    /// Dictionnaire complet, prêt pour ImageIO.
    public static func properties(for metadata: CaptureMetadata) -> [String: Any] {
        var properties: [String: Any] = [:]
        properties[kCGImagePropertyGPSDictionary as String] = gps(for: metadata)
        properties[kCGImagePropertyExifDictionary as String] = exif(for: metadata)
        if let tiff = tiff(for: metadata) {
            properties[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        return properties
    }

    // MARK: - GPS

    /// Panoramax exige position **et** horodatage : sans eux, la photo est
    /// rejetée à l'ingestion. Tout le reste est optionnel.
    static func gps(for metadata: CaptureMetadata) -> [String: Any] {
        var gps: [String: Any] = [:]
        let position = metadata.position

        // La valeur est absolue ; c'est la référence qui porte le signe.
        gps[kCGImagePropertyGPSLatitude as String] = abs(position.latitude)
        gps[kCGImagePropertyGPSLatitudeRef as String] = position.latitude < 0 ? "S" : "N"
        gps[kCGImagePropertyGPSLongitude as String] = abs(position.longitude)
        gps[kCGImagePropertyGPSLongitudeRef as String] = position.longitude < 0 ? "W" : "E"

        // Horodatage UTC : le canal le plus fiable, car sans ambiguïté de fuseau.
        gps[kCGImagePropertyGPSDateStamp as String] = ExifTimestamps.gpsDateStamp(metadata.timestamp)
        gps[kCGImagePropertyGPSTimeStamp as String] = ExifTimestamps.gpsTimeStamp(metadata.timestamp)

        if let altitude = position.altitude {
            gps[kCGImagePropertyGPSAltitude as String] = abs(altitude)
            gps[kCGImagePropertyGPSAltitudeRef as String] = altitude < 0 ? 1 : 0
        }
        if let speed = position.speed, speed >= 0 {
            gps[kCGImagePropertyGPSSpeed as String] = speed * 3.6
            gps[kCGImagePropertyGPSSpeedRef as String] = "K"
        }
        if let accuracy = position.horizontalAccuracy, accuracy >= 0 {
            gps[kCGImagePropertyGPSHPositioningError as String] = accuracy
        }

        // On n'écrit un cap que si l'on en est sûr : voir ``Heading``.
        if let heading = metadata.heading {
            gps[kCGImagePropertyGPSImgDirection as String] = heading.trueDegrees
            gps[kCGImagePropertyGPSImgDirectionRef as String] = "T"
            if heading.source == .gpsCourse {
                // GPSTrack décrit la route suivie, pas la visée : ne le remplir
                // que lorsque le cap vient effectivement du déplacement.
                gps[kCGImagePropertyGPSTrack as String] = heading.trueDegrees
                gps[kCGImagePropertyGPSTrackRef as String] = "T"
            }
        }
        return gps
    }

    // MARK: - EXIF

    static func exif(for metadata: CaptureMetadata) -> [String: Any] {
        var exif: [String: Any] = [:]
        let stamp = ExifTimestamps.dateTimeOriginal(metadata.timestamp, in: metadata.timeZone)
        let offset = ExifTimestamps.offsetTime(metadata.timestamp, in: metadata.timeZone)

        exif[kCGImagePropertyExifDateTimeOriginal as String] = stamp
        exif[kCGImagePropertyExifDateTimeDigitized as String] = stamp
        exif[kCGImagePropertyExifOffsetTimeOriginal as String] = offset
        exif[kCGImagePropertyExifOffsetTimeDigitized as String] = offset
        exif[kCGImagePropertyExifSubsecTimeOriginal as String] =
            ExifTimestamps.subsecondMilliseconds(metadata.timestamp)

        if let device = metadata.device {
            if let focalLength = device.focalLength {
                exif[kCGImagePropertyExifFocalLength as String] = focalLength
            }
            if let equivalent = device.focalLengthIn35mm {
                exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] = equivalent
            }
            if let lens = device.lensModel {
                exif[kCGImagePropertyExifLensModel as String] = lens
            }
            exif[kCGImagePropertyExifLensMake as String] = device.make
        }
        return exif
    }

    // MARK: - TIFF

    static func tiff(for metadata: CaptureMetadata) -> [String: Any]? {
        var tiff: [String: Any] = [:]
        if let device = metadata.device {
            tiff[kCGImagePropertyTIFFMake as String] = device.make
            tiff[kCGImagePropertyTIFFModel as String] = device.model
        }
        if let software = metadata.software {
            tiff[kCGImagePropertyTIFFSoftware as String] = software
        }
        tiff[kCGImagePropertyTIFFDateTime as String] =
            ExifTimestamps.dateTimeOriginal(metadata.timestamp, in: metadata.timeZone)
        return tiff.isEmpty ? nil : tiff
    }
}
