// SPDX-License-Identifier: MIT

import Foundation

/// Motif pour lequel une position est écartée.
public enum FixRejection: Sendable, Hashable {
    /// CoreLocation rend une précision négative quand la position n'est pas
    /// exploitable du tout.
    case invalidPosition
    case tooImprecise(accuracy: Double, limit: Double)
    case tooOld(age: TimeInterval, limit: TimeInterval)

    public var description: String {
        switch self {
        case .invalidPosition:
            "position invalide"
        case .tooImprecise(let accuracy, let limit):
            "précision \(Int(accuracy)) m, au-delà de la limite de \(Int(limit)) m"
        case .tooOld(let age, let limit):
            "position vieille de \(Int(age)) s, au-delà de \(Int(limit)) s"
        }
    }
}

/// Écarte les positions sur lesquelles on refuse de déclencher.
///
/// Une photo mal placée est pire qu'une photo manquante : elle entre dans le
/// commun et y reste. Le seuil par défaut de 10 m correspond à ce qu'un iPhone
/// atteint en ciel dégagé ; en ville dense il se dégrade, et c'est justement là
/// qu'il faut s'abstenir plutôt que de publier une trace en zigzag.
public struct FixFilter: Sendable {

    public var maximumHorizontalAccuracy: Double
    public var maximumAge: TimeInterval

    public init(maximumHorizontalAccuracy: Double = 10, maximumAge: TimeInterval = 5) {
        self.maximumHorizontalAccuracy = maximumHorizontalAccuracy
        self.maximumAge = maximumAge
    }

    /// Rend le motif de rejet, ou `nil` si la position est acceptable.
    public func rejection(for fix: Fix, now: Date) -> FixRejection? {
        guard fix.horizontalAccuracy >= 0 else { return .invalidPosition }
        if fix.horizontalAccuracy > maximumHorizontalAccuracy {
            return .tooImprecise(accuracy: fix.horizontalAccuracy, limit: maximumHorizontalAccuracy)
        }
        let age = now.timeIntervalSince(fix.timestamp)
        if age > maximumAge {
            return .tooOld(age: age, limit: maximumAge)
        }
        return nil
    }

    public func accepts(_ fix: Fix, now: Date) -> Bool {
        rejection(for: fix, now: now) == nil
    }
}
