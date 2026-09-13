// SPDX-License-Identifier: MIT

import Foundation

/// Insère un paquet XMP dans un JPEG, sous forme de segment APP1.
///
/// `ImageIO` écrit très bien l'EXIF mais ne sait pas écrire du XMP arbitraire.
/// Or Panoramax lit l'attitude de l'appareil dans `Xmp.Camera.Yaw/Pitch/Roll`.
/// D'où ce module : une centaine de lignes de manipulation d'octets, isolée et
/// testée, plutôt qu'une dépendance à une bibliothèque C++ dont la licence
/// serait à examiner.
public enum XMPInjector {

    /// Identifiant du segment APP1 XMP, suivi d'un octet nul.
    static let signature = "http://ns.adobe.com/xap/1.0/"

    static var signatureBytes: [UInt8] { Array(signature.utf8) + [0] }

    /// La longueur d'un segment tient sur deux octets, elle-même comprise.
    static let maximumSegmentLength = 65_535

    // MARK: - Construction du paquet

    /// Paquet XMP correspondant à ce qu'on sait du cliché, ou `nil` s'il n'y a
    /// rien à écrire — un segment vide n'apporterait que du poids.
    public static func packet(for metadata: CaptureMetadata) -> String? {
        guard let attitude = metadata.attitude else { return nil }
        return packet(for: attitude, toolkit: metadata.software ?? "iPanoramax")
    }

    /// L'espace de noms `Camera` est celui de Pix4D, `http://pix4d.com/camera/1.0/`.
    /// C'est celui qu'exiv2 — donc Panoramax — associe au préfixe `Camera`.
    public static func packet(for attitude: CameraAttitude, toolkit: String) -> String {
        """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="\(escaped(toolkit))">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""
              xmlns:Camera="http://pix4d.com/camera/1.0/"
              Camera:Yaw="\(degrees(attitude.yaw))"
              Camera:Pitch="\(degrees(attitude.pitch))"
              Camera:Roll="\(degrees(attitude.roll))"/>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }

    /// Point décimal garanti quelle que soit la langue de l'appareil : une
    /// virgule produirait du XMP invalide, silencieusement ignoré à l'ingestion.
    static func degrees(_ value: Double) -> String {
        String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Lecture

    /// Rend le paquet XMP présent dans le fichier, s'il y en a un.
    public static func extractingPacket(from jpeg: Data) throws -> String? {
        let base = jpeg.startIndex
        guard let segment = try JPEGScanner.segments(in: jpeg).first(where: { isXMP($0, in: jpeg) })
        else { return nil }

        let start = base + segment.payload.lowerBound + signatureBytes.count
        let end = base + segment.payload.upperBound
        guard start <= end else { return nil }
        return String(data: jpeg[start..<end], encoding: .utf8)
    }

    // MARK: - Écriture

    /// Insère le paquet en **remplaçant** un éventuel segment XMP existant.
    ///
    /// Deux paquets XMP dans un même fichier, c'est un fichier dont le sens
    /// dépend du lecteur : la plupart retiennent le premier, certains le
    /// dernier. On n'en laisse donc jamais deux.
    public static func injecting(_ packet: String, into jpeg: Data) throws -> Data {
        let payload = Array(packet.utf8)
        let segmentLength = 2 + signatureBytes.count + payload.count
        guard segmentLength <= maximumSegmentLength else {
            throw JPEGError.packetTooLarge(bytes: payload.count)
        }

        let cleaned = try removingPacket(from: jpeg)
        let insertion = try insertionOffset(in: cleaned)
        let base = cleaned.startIndex

        var segment = Data([0xFF, JPEGScanner.app1])
        segment.append(UInt8(truncatingIfNeeded: segmentLength >> 8))
        segment.append(UInt8(truncatingIfNeeded: segmentLength))
        segment.append(contentsOf: signatureBytes)
        segment.append(contentsOf: payload)

        var result = Data()
        result.append(cleaned[base..<(base + insertion)])
        result.append(segment)
        result.append(cleaned[(base + insertion)...])
        return result
    }

    /// Retire tous les segments XMP. Rend une copie même s'il n'y avait rien,
    /// pour que l'appelant travaille toujours sur une donnée réindexée à zéro.
    public static func removingPacket(from jpeg: Data) throws -> Data {
        let base = jpeg.startIndex
        let found = try JPEGScanner.segments(in: jpeg).filter { isXMP($0, in: jpeg) }
        guard !found.isEmpty else { return Data(jpeg) }

        var result = Data()
        var cursor = 0
        for segment in found {
            result.append(jpeg[(base + cursor)..<(base + segment.range.lowerBound)])
            cursor = segment.range.upperBound
        }
        result.append(jpeg[(base + cursor)...])
        return result
    }

    // MARK: - Placement

    /// Le XMP se place après le dernier segment APPn de tête.
    ///
    /// L'APP1 Exif doit rester le premier segment après SOI : beaucoup de
    /// lecteurs en dépendent, et le déplacer revient à perdre l'EXIF pour eux.
    static func insertionOffset(in jpeg: Data) throws -> Int {
        var offset = 2
        for segment in try JPEGScanner.segments(in: jpeg) {
            guard JPEGScanner.isApplicationMarker(segment.marker) else { break }
            offset = segment.range.upperBound
        }
        return offset
    }

    static func isXMP(_ segment: JPEGSegment, in jpeg: Data) -> Bool {
        guard segment.marker == JPEGScanner.app1 else { return false }
        let expected = signatureBytes
        guard segment.payload.count >= expected.count else { return false }
        let base = jpeg.startIndex
        let start = base + segment.payload.lowerBound
        return Array(jpeg[start..<(start + expected.count)]) == expected
    }
}
