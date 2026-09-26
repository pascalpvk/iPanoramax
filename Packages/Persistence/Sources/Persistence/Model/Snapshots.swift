// SPDX-License-Identifier: MIT

import Foundation
import GeoKit
import ImageMetadataKit

/// Ce qu'il faut savoir d'un cliché pour l'inscrire dans la base, une fois le
/// JPEG écrit sur le disque.
///
/// Un type valeur, `Sendable`, et non un `Shot` : les objets SwiftData
/// appartiennent au contexte qui les a chargés et ne traversent pas les
/// frontières d'isolation. Tout ce qui entre dans ``CaptureStore`` et tout ce
/// qui en sort est donc une valeur.
public struct ShotDraft: Sendable, Hashable {

    public var id: UUID
    public var capturedAt: Date
    public var coordinate: Coordinate
    public var altitude: Double?
    public var horizontalAccuracy: Double?
    public var heading: Heading?
    public var byteCount: Int

    public init(
        id: UUID = UUID(),
        capturedAt: Date,
        coordinate: Coordinate,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        heading: Heading? = nil,
        byteCount: Int = 0
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.coordinate = coordinate
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.heading = heading
        self.byteCount = byteCount
    }

    /// Reprend les métadonnées déjà assemblées pour le fichier.
    ///
    /// Base et EXIF décrivent alors le même instant à partir de la même
    /// source : il n'y a pas deux vérités à réconcilier.
    public init(id: UUID = UUID(), metadata: CaptureMetadata, byteCount: Int = 0) {
        self.init(
            id: id,
            capturedAt: metadata.timestamp,
            coordinate: Coordinate(
                latitude: metadata.position.latitude,
                longitude: metadata.position.longitude
            ),
            altitude: metadata.position.altitude,
            horizontalAccuracy: metadata.position.horizontalAccuracy,
            heading: metadata.heading,
            byteCount: byteCount
        )
    }
}

/// Vue figée d'une session, détachée du contexte SwiftData.
public struct SessionSnapshot: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var state: SessionState
    public var mode: CaptureMode
    public var instanceHost: String?
    public var uploadSetID: UUID?
    public var visibility: String?
    public var shotCount: Int
}

/// Vue figée d'un cliché, détachée du contexte SwiftData.
public struct ShotSnapshot: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var sessionID: UUID
    public var index: Int
    public var capturedAt: Date
    public var coordinate: Coordinate
    public var altitude: Double?
    public var horizontalAccuracy: Double?
    public var heading: Heading?
    public var state: ShotState
    public var rejectionReason: String?
    public var byteCount: Int
}

extension CaptureSession {

    /// - Parameter shotCount: compté par une requête, pas par `shots.count` :
    ///   ce dernier chargerait toute la relation pour rendre un entier.
    func snapshot(shotCount: Int) -> SessionSnapshot {
        SessionSnapshot(
            id: id,
            title: title,
            startedAt: startedAt,
            endedAt: endedAt,
            state: state,
            mode: mode,
            instanceHost: instanceHost,
            uploadSetID: uploadSetID,
            visibility: visibility,
            shotCount: shotCount
        )
    }
}

extension Shot {

    var snapshot: ShotSnapshot {
        ShotSnapshot(
            id: id,
            sessionID: sessionID,
            index: index,
            capturedAt: capturedAt,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            heading: heading,
            state: state,
            rejectionReason: rejectionReason,
            byteCount: byteCount
        )
    }
}
