// SPDX-License-Identifier: MIT

import Foundation

/// Distance entre deux points, par la formule de haversine.
///
/// Pas de `CLLocation.distance(from:)` : cette fonction doit rester utilisable
/// dans des tests qui rejouent une trace, sans dépendance à CoreLocation ni au
/// matériel. L'écart avec une géodésique exacte est de l'ordre de 0,3 % au pire,
/// bien en deçà de ce qui compte pour décider d'un déclenchement tous les
/// quelques mètres.
public enum Geodesy {

    /// Rayon moyen de la Terre, en mètres.
    public static let earthRadius: Double = 6_371_008.8

    public static func distance(from start: Coordinate, to end: Coordinate) -> Double {
        let phi1 = start.latitude * .pi / 180
        let phi2 = end.latitude * .pi / 180
        let deltaPhi = (end.latitude - start.latitude) * .pi / 180
        let deltaLambda = (end.longitude - start.longitude) * .pi / 180

        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }
}
