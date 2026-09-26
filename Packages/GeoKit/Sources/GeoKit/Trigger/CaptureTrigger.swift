// SPDX-License-Identifier: MIT

import Foundation

/// Ce qui décide du déclenchement pendant une séquence.
public enum CaptureMode: Sendable, Hashable {
    /// Une photo tous les N mètres parcourus. Le mode naturel pour une
    /// séquence : la densité suit le terrain, pas l'allure.
    case distance(metres: Double)
    /// Une photo toutes les N secondes.
    case time(seconds: TimeInterval)
    /// Rien d'automatique ; c'est l'utilisateur qui déclenche.
    case manual
}

/// Décide quand prendre une photo, sans rien savoir de la caméra.
///
/// Logique pure et sans effet de bord : on lui donne des positions, elle rend
/// des décisions. C'est ce qui permet de valider une cadence en rejouant une
/// trace, plutôt qu'en marchant 500 m à chaque modification.
public struct CaptureTrigger: Sendable {

    public enum Decision: Sendable, Hashable {
        case capture(Reason)
        case wait(Progress)

        public enum Reason: Sendable, Hashable {
            /// Première photo de la séquence.
            case first
            case distance(travelled: Double)
            case time(elapsed: TimeInterval)
        }

        /// Ce qu'il reste à parcourir ou à attendre. Sert à l'affichage :
        /// « encore 4 m » vaut mieux qu'un écran qui ne dit rien.
        public struct Progress: Sendable, Hashable {
            public var distanceRemaining: Double?
            public var timeRemaining: TimeInterval?

            public init(distanceRemaining: Double? = nil, timeRemaining: TimeInterval? = nil) {
                self.distanceRemaining = distanceRemaining
                self.timeRemaining = timeRemaining
            }
        }
    }

    public var mode: CaptureMode

    /// Plancher absolu entre deux clichés, tous modes confondus.
    ///
    /// En voiture à 50 km/h, une règle de 5 m demanderait une photo toutes les
    /// 0,36 s — plus vite que l'appareil ne sait encoder. Sans ce plancher, la
    /// file de capture se remplit plus vite qu'elle ne se vide et la séquence
    /// se dégrade au lieu de s'enrichir.
    public var minimumInterval: TimeInterval

    public private(set) var lastCapture: Fix?
    public private(set) var capturedCount: Int

    public init(mode: CaptureMode, minimumInterval: TimeInterval = 0.5) {
        self.mode = mode
        self.minimumInterval = minimumInterval
        self.lastCapture = nil
        self.capturedCount = 0
    }

    /// Décision pour cette position. N'a aucun effet : appeler
    /// ``recordCapture(at:)`` quand la photo a réellement été prise.
    public func decision(for fix: Fix) -> Decision {
        guard case .manual = mode else {
            return automaticDecision(for: fix)
        }
        return .wait(Decision.Progress())
    }

    private func automaticDecision(for fix: Fix) -> Decision {
        guard let last = lastCapture else { return .capture(.first) }

        let elapsed = fix.timestamp.timeIntervalSince(last.timestamp)
        if elapsed < minimumInterval {
            return .wait(Decision.Progress(timeRemaining: minimumInterval - elapsed))
        }

        switch mode {
        case .distance(let metres):
            let travelled = Geodesy.distance(from: last.coordinate, to: fix.coordinate)
            if travelled >= metres {
                return .capture(.distance(travelled: travelled))
            }
            return .wait(Decision.Progress(distanceRemaining: metres - travelled))

        case .time(let seconds):
            if elapsed >= seconds {
                return .capture(.time(elapsed: elapsed))
            }
            return .wait(Decision.Progress(timeRemaining: seconds - elapsed))

        case .manual:
            return .wait(Decision.Progress())
        }
    }

    /// Enregistre qu'une photo vient d'être prise à cette position.
    public mutating func recordCapture(at fix: Fix) {
        lastCapture = fix
        capturedCount += 1
    }

    /// Repart de zéro, pour une nouvelle séquence.
    public mutating func reset() {
        lastCapture = nil
        capturedCount = 0
    }

    /// Rejoue une suite de positions et rend celles qui auraient déclenché.
    ///
    /// Le raccourci qui rend une cadence vérifiable sans sortir de chez soi.
    public static func replay(_ fixes: [Fix], mode: CaptureMode, minimumInterval: TimeInterval = 0.5) -> [Fix] {
        var trigger = CaptureTrigger(mode: mode, minimumInterval: minimumInterval)
        var captured: [Fix] = []
        for fix in fixes {
            if case .capture = trigger.decision(for: fix) {
                trigger.recordCapture(at: fix)
                captured.append(fix)
            }
        }
        return captured
    }
}
