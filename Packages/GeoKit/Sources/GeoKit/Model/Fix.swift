// SPDX-License-Identifier: MIT

import Foundation

/// Un point en degrés décimaux WGS84.
public struct Coordinate: Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Une mesure de position, telle que la rend le GPS.
///
/// Les conventions de CoreLocation sont conservées, y compris les valeurs
/// négatives qui signifient « inconnu » : les traduire ici masquerait la
/// différence entre « à l'arrêt » et « vitesse non mesurée », qui est
/// précisément ce dont dépend le choix du cap.
public struct Fix: Sendable, Hashable {
    public var coordinate: Coordinate
    public var altitude: Double?
    /// Rayon d'incertitude en mètres. Négatif : position invalide.
    public var horizontalAccuracy: Double
    /// Mètres par seconde. Négatif : inconnue.
    public var speed: Double
    /// Route suivie, degrés depuis le nord géographique. Négatif : inconnue.
    public var course: Double
    public var timestamp: Date

    public init(
        coordinate: Coordinate,
        altitude: Double? = nil,
        horizontalAccuracy: Double,
        speed: Double = -1,
        course: Double = -1,
        timestamp: Date
    ) {
        self.coordinate = coordinate
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.course = course
        self.timestamp = timestamp
    }

    public var hasValidCourse: Bool { course >= 0 }
    public var hasValidSpeed: Bool { speed >= 0 }
}

/// Une lecture de boussole.
public struct HeadingReading: Sendable, Hashable {
    /// Degrés depuis le nord **géographique**. Négatif : invalide.
    public var trueHeading: Double
    /// Incertitude en degrés. Négatif : lecture inutilisable.
    public var accuracy: Double
    public var timestamp: Date

    public init(trueHeading: Double, accuracy: Double, timestamp: Date) {
        self.trueHeading = trueHeading
        self.accuracy = accuracy
        self.timestamp = timestamp
    }

    public var isUsable: Bool { trueHeading >= 0 && accuracy >= 0 }
}
