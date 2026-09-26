// SPDX-License-Identifier: MIT

import Foundation
@testable import GeoKit

/// Fabrique des traces reproductibles : ligne droite à vitesse constante,
/// échantillonnée à intervalle fixe.
///
/// Suffisant pour valider une cadence sans sortir de chez soi. Ce que ça ne
/// remplace pas : le bruit d'un GPS urbain, les tunnels, les demi-tours. Ces
/// cas viendront de traces enregistrées sur le terrain.
enum SyntheticTrace {

    static let start = Coordinate(latitude: 45.9237, longitude: 6.8694)
    static let epoch = Date(timeIntervalSince1970: 1_788_098_709)

    /// Un mètre en degrés de latitude — constant, contrairement à la longitude.
    static let metreInDegreesOfLatitude = 1.0 / 111_320.0

    /// Trace plein nord.
    static func straightLine(
        speed: Double,
        interval: TimeInterval,
        count: Int,
        accuracy: Double = 5,
        from origin: Coordinate = start
    ) -> [Fix] {
        (0..<count).map { step in
            let elapsed = Double(step) * interval
            let metres = speed * elapsed
            return Fix(
                coordinate: Coordinate(
                    latitude: origin.latitude + metres * metreInDegreesOfLatitude,
                    longitude: origin.longitude
                ),
                altitude: 500,
                horizontalAccuracy: accuracy,
                speed: speed,
                course: 0,
                timestamp: epoch.addingTimeInterval(elapsed)
            )
        }
    }

    /// Trace immobile : même point, horloge qui avance.
    static func stationary(
        interval: TimeInterval,
        count: Int,
        accuracy: Double = 5
    ) -> [Fix] {
        (0..<count).map { step in
            Fix(
                coordinate: start,
                altitude: 500,
                horizontalAccuracy: accuracy,
                speed: 0,
                course: -1,
                timestamp: epoch.addingTimeInterval(Double(step) * interval)
            )
        }
    }
}
