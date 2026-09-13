// SPDX-License-Identifier: MIT

import Foundation
import ImageIO

/// Inscrit des métadonnées dans un JPEG existant, **sans recompresser l'image**.
///
/// Dans l'application, le chemin nominal est de passer le dictionnaire de
/// ``ExifMetadataBuilder`` à `AVCapturePhotoSettings.metadata` avant la prise de
/// vue : zéro copie, zéro perte. Ce type sert aux fichiers déjà produits —
/// import depuis la photothèque, correction après coup, tests.
///
/// L'écriture repose sur `CGImageDestinationAddImageFromSource`, qui recopie les
/// données compressées telles quelles au lieu de les décoder puis de les
/// réencoder (voir Apple QA1895).
public enum ImageMetadataWriter {

    public enum Failure: Error, Sendable, Equatable {
        case unreadableSource
        case unsupportedFormat
        case writeFailed
    }

    /// Rend une copie du JPEG enrichie des métadonnées.
    ///
    /// Les propriétés déjà présentes sont conservées : on fusionne, on
    /// n'écrase pas ce que l'appareil a écrit (exposition, balance des blancs,
    /// profil colorimétrique).
    public static func writingMetadata(_ metadata: CaptureMetadata, into jpeg: Data) throws -> Data {
        try writingProperties(ExifMetadataBuilder.properties(for: metadata), into: jpeg)
    }

    /// Variante prenant un dictionnaire déjà construit.
    public static func writingProperties(_ properties: [String: Any], into jpeg: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source)
        else {
            throw Failure.unreadableSource
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else {
            throw Failure.unsupportedFormat
        }

        let existing = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        let merged = merging(existing, with: properties)

        CGImageDestinationAddImageFromSource(destination, source, 0, merged as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure.writeFailed
        }
        return output as Data
    }

    /// Relit les propriétés d'un JPEG. Sert surtout à vérifier ce qu'on vient
    /// d'écrire — un aller-retour est le seul test qui prouve quelque chose.
    public static func readingProperties(from jpeg: Data) throws -> [String: Any] {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else {
            throw Failure.unreadableSource
        }
        return properties
    }

    /// Fusion à deux niveaux : les sous-dictionnaires GPS, EXIF et TIFF sont
    /// fusionnés champ à champ plutôt que remplacés en bloc. Sans cela,
    /// renseigner la position effacerait tout le reste du bloc GPS.
    static func merging(_ base: [String: Any], with additions: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in additions {
            if let addition = value as? [String: Any],
               let existing = result[key] as? [String: Any] {
                result[key] = existing.merging(addition) { _, new in new }
            } else {
                result[key] = value
            }
        }
        return result
    }
}
