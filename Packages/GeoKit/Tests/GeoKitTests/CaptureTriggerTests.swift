// SPDX-License-Identifier: MIT

import Foundation
import ImageMetadataKit
import Testing
@testable import GeoKit

@Suite("Déclenchement")
struct CaptureTriggerTests {

    @Test("La première position déclenche toujours")
    func capturesFirstFix() {
        let trigger = CaptureTrigger(mode: .distance(metres: 5))
        let trace = SyntheticTrace.straightLine(speed: 1.4, interval: 1, count: 1)
        #expect(trigger.decision(for: trace[0]) == .capture(.first))
    }

    @Test("Marche à 1,4 m/s, une photo tous les 5 m")
    func capturesEveryFiveMetresWalking() {
        // 100 s de marche à 1,4 m/s = 140 m, échantillonnés chaque seconde.
        let trace = SyntheticTrace.straightLine(speed: 1.4, interval: 1, count: 101)
        let captured = CaptureTrigger.replay(trace, mode: .distance(metres: 5))

        // Le déclenchement ne peut tomber que sur un échantillon : il faut
        // quatre pas de 1,4 m pour franchir 5 m, soit un cliché toutes les 4 s.
        // Sur 0…100 s cela fait 26 clichés, pas 28 — l'espacement réel est de
        // 5,6 m et non de 5 m tout rond. C'est une propriété de
        // l'échantillonnage, pas un défaut : la distance demandée est un
        // minimum, jamais une valeur exacte.
        #expect(captured.count == 26)

        // Aucun couple consécutif ne doit être plus rapproché que le seuil.
        for (previous, next) in zip(captured, captured.dropFirst()) {
            let gap = Geodesy.distance(from: previous.coordinate, to: next.coordinate)
            #expect(gap >= 4.9)
        }
    }

    @Test("À l'arrêt, le mode distance ne déclenche qu'une fois")
    func doesNotFireWhileStationary() {
        let trace = SyntheticTrace.stationary(interval: 1, count: 60)
        let captured = CaptureTrigger.replay(trace, mode: .distance(metres: 5))
        #expect(captured.count == 1)
    }

    @Test("Le mode temps déclenche même immobile")
    func firesOnTimeEvenWhenStationary() {
        let trace = SyntheticTrace.stationary(interval: 1, count: 31)
        let captured = CaptureTrigger.replay(trace, mode: .time(seconds: 10))
        // t=0 puis 10, 20, 30.
        #expect(captured.count == 4)
    }

    @Test("Le mode manuel ne déclenche jamais tout seul")
    func neverFiresInManualMode() {
        let trace = SyntheticTrace.straightLine(speed: 1.4, interval: 1, count: 50)
        #expect(CaptureTrigger.replay(trace, mode: .manual).isEmpty)
    }

    @Test("Le plancher d'intervalle protège des cadences intenables")
    func minimumIntervalCapsRate() {
        // 50 km/h ≈ 13,9 m/s. Une règle de 5 m demanderait une photo toutes
        // les 0,36 s — plus vite que l'appareil ne sait encoder.
        let trace = SyntheticTrace.straightLine(speed: 13.9, interval: 0.1, count: 200)
        let captured = CaptureTrigger.replay(trace, mode: .distance(metres: 5), minimumInterval: 1)

        for (previous, next) in zip(captured, captured.dropFirst()) {
            let gap = next.timestamp.timeIntervalSince(previous.timestamp)
            #expect(gap >= 0.99)
        }
    }

    @Test("La progression indique ce qu'il reste à parcourir")
    func reportsRemainingDistance() {
        var trigger = CaptureTrigger(mode: .distance(metres: 10))
        let trace = SyntheticTrace.straightLine(speed: 1, interval: 1, count: 10)

        trigger.recordCapture(at: trace[0])
        // Après 4 s à 1 m/s, il reste environ 6 m.
        guard case .wait(let progress) = trigger.decision(for: trace[4]),
              let remaining = progress.distanceRemaining
        else {
            Issue.record("attendu : en attente, avec une distance restante")
            return
        }
        #expect(abs(remaining - 6) < 0.5)
    }

    @Test("La remise à zéro repart d'une séquence vierge")
    func resetStartsFresh() {
        var trigger = CaptureTrigger(mode: .distance(metres: 5))
        let trace = SyntheticTrace.straightLine(speed: 1.4, interval: 1, count: 10)

        trigger.recordCapture(at: trace[0])
        #expect(trigger.capturedCount == 1)
        #expect(trigger.decision(for: trace[1]) != .capture(.first))

        trigger.reset()
        #expect(trigger.capturedCount == 0)
        #expect(trigger.decision(for: trace[1]) == .capture(.first))
    }
}

@Suite("Assemblage des métadonnées")
struct CaptureMetadataAssemblerTests {

    @Test("Position, horodatage et cap arrivent dans les métadonnées")
    func assemblesFromSensors() throws {
        let assembler = CaptureMetadataAssembler(
            device: .init(make: "Apple", model: "iPhone 15 Pro"),
            software: "iPanoramax 0.1.0",
            timeZone: try #require(TimeZone(identifier: "Europe/Paris"))
        )
        let fix = Fix(
            coordinate: SyntheticTrace.start,
            altitude: 1_042,
            horizontalAccuracy: 4.5,
            speed: 12,
            course: 137,
            timestamp: SyntheticTrace.epoch
        )

        let metadata = assembler.metadata(fix: fix)
        #expect(metadata.position.latitude == 45.9237)
        #expect(metadata.position.altitude == 1_042)
        #expect(metadata.position.horizontalAccuracy == 4.5)
        #expect(metadata.position.speed == 12)
        #expect(metadata.timestamp == SyntheticTrace.epoch)
        #expect(metadata.heading?.trueDegrees == 137)
        #expect(metadata.heading?.source == .gpsCourse)
        #expect(metadata.device?.model == "iPhone 15 Pro")
    }

    @Test("Une précision ou une vitesse inconnue n'est pas inventée")
    func omitsUnknownMeasurements() {
        let assembler = CaptureMetadataAssembler()
        let fix = Fix(
            coordinate: SyntheticTrace.start,
            horizontalAccuracy: -1,
            speed: -1,
            course: -1,
            timestamp: SyntheticTrace.epoch
        )

        let metadata = assembler.metadata(fix: fix)
        #expect(metadata.position.horizontalAccuracy == nil)
        #expect(metadata.position.speed == nil)
        #expect(metadata.heading == nil)
    }
}
