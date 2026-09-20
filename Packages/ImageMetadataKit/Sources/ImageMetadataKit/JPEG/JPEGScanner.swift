// SPDX-License-Identifier: MIT

import Foundation

public enum JPEGError: Error, Sendable, Equatable {
    case notAJPEG
    /// Position, relative au début du fichier, où l'analyse a dérapé.
    case malformedSegment(offset: Int)
    /// Un segment JPEG ne peut pas dépasser 65 535 octets, longueur comprise.
    case packetTooLarge(bytes: Int)
}

/// Un segment repéré dans l'en-tête d'un JPEG.
struct JPEGSegment: Sendable, Hashable {
    /// Octet suivant le `FF` : `0xE1` pour APP1, `0xDA` pour SOS.
    let marker: UInt8
    /// Étendue complète, du `FF` au dernier octet du segment.
    let range: Range<Int>
    /// Charge utile seule, après les deux octets de longueur.
    let payload: Range<Int>
}

/// Parcourt l'en-tête d'un JPEG jusqu'au début des données compressées.
///
/// Un JPEG est une suite de segments `FF xx` portant chacun sa longueur sur
/// deux octets — sauf SOI, EOI, TEM et les marqueurs de redémarrage, qui n'ont
/// pas de charge utile. Après SOS (`FFDA`) commence le flux entropique, où un
/// `FF` n'est plus un marqueur : le parcours s'y arrête, sous peine de lire du
/// bruit comme une structure.
///
/// Toutes les positions rendues sont relatives au **début logique** de la
/// donnée : `Data` peut avoir un `startIndex` non nul, et l'oublier produit des
/// fichiers corrompus de façon intermittente.
enum JPEGScanner {

    static let startOfImage: UInt8 = 0xD8
    static let endOfImage: UInt8 = 0xD9
    static let startOfScan: UInt8 = 0xDA
    static let temporary: UInt8 = 0x01
    static let app1: UInt8 = 0xE1

    static func isApplicationMarker(_ marker: UInt8) -> Bool {
        (0xE0...0xEF).contains(marker)
    }

    static func hasNoPayload(_ marker: UInt8) -> Bool {
        marker == startOfImage
            || marker == endOfImage
            || marker == temporary
            || (0xD0...0xD7).contains(marker)
    }

    /// Segments situés après SOI, dans l'ordre, SOS compris et inclus.
    static func segments(in data: Data) throws -> [JPEGSegment] {
        let base = data.startIndex
        let count = data.count
        guard count >= 4, data[base] == 0xFF, data[base + 1] == startOfImage else {
            throw JPEGError.notAJPEG
        }

        var segments: [JPEGSegment] = []
        var offset = 2

        while offset + 1 < count {
            guard data[base + offset] == 0xFF else {
                throw JPEGError.malformedSegment(offset: offset)
            }

            // Des `FF` de bourrage peuvent précéder le marqueur lui-même.
            var markerOffset = offset + 1
            while markerOffset < count, data[base + markerOffset] == 0xFF {
                markerOffset += 1
            }
            guard markerOffset < count else {
                throw JPEGError.malformedSegment(offset: offset)
            }
            let marker = data[base + markerOffset]

            if hasNoPayload(marker) {
                let end = markerOffset + 1
                segments.append(JPEGSegment(marker: marker, range: offset..<end, payload: end..<end))
                offset = end
                continue
            }

            let lengthOffset = markerOffset + 1
            guard lengthOffset + 1 < count else {
                throw JPEGError.malformedSegment(offset: offset)
            }
            let length = Int(data[base + lengthOffset]) << 8 | Int(data[base + lengthOffset + 1])
            guard length >= 2, lengthOffset + length <= count else {
                throw JPEGError.malformedSegment(offset: offset)
            }

            let end = lengthOffset + length
            segments.append(
                JPEGSegment(marker: marker, range: offset..<end, payload: (lengthOffset + 2)..<end)
            )
            if marker == startOfScan { break }
            offset = end
        }
        return segments
    }
}
