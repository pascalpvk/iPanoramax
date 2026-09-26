// SPDX-License-Identifier: MIT

import Foundation
import ImageMetadataKit
import Testing
@testable import GeoKit

@Suite("Choix du cap")
struct HeadingResolverTests {

    let resolver = HeadingResolver(minimumSpeedForCourse: 2, maximumCompassUncertainty: 20)

    func makeFix(speed: Double, course: Double) -> Fix {
        Fix(
            coordinate: SyntheticTrace.start,
            horizontalAccuracy: 5,
            speed: speed,
            course: course,
            timestamp: SyntheticTrace.epoch
        )
    }

    func makeCompass(_ degrees: Double, accuracy: Double = 5) -> HeadingReading {
        HeadingReading(trueHeading: degrees, accuracy: accuracy, timestamp: SyntheticTrace.epoch)
    }

    @Test("En mouvement, la route GPS l'emporte sur la boussole")
    func prefersCourseWhenMoving() {
        let heading = resolver.resolve(fix: makeFix(speed: 12, course: 137), compass: makeCompass(42))
        #expect(heading?.trueDegrees == 137)
        #expect(heading?.source == .gpsCourse)
    }

    @Test("À l'arrêt, la boussole l'emporte — une route GPS immobile dérive")
    func prefersCompassWhenStill() {
        let heading = resolver.resolve(fix: makeFix(speed: 0, course: 300), compass: makeCompass(42))
        #expect(heading?.trueDegrees == 42)
        #expect(heading?.source == .magneticCompass)
    }

    @Test("Au pas de marche, la boussole reste la meilleure source")
    func prefersCompassAtWalkingPace() {
        let heading = resolver.resolve(fix: makeFix(speed: 1.4, course: 300), compass: makeCompass(42))
        #expect(heading?.source == .magneticCompass)
    }

    @Test("Une boussole trop incertaine n'est pas utilisée")
    func ignoresUncertainCompass() {
        let heading = resolver.resolve(fix: makeFix(speed: 0, course: -1), compass: makeCompass(42, accuracy: 55))
        #expect(heading == nil)
    }

    @Test("Sans source fiable, aucun cap n'est écrit")
    func writesNothingWithoutReliableSource() {
        #expect(resolver.resolve(fix: makeFix(speed: 0, course: -1), compass: nil) == nil)
        // Rapide mais route inconnue, et pas de boussole : rien non plus.
        #expect(resolver.resolve(fix: makeFix(speed: 12, course: -1), compass: nil) == nil)
    }

    @Test("Une vitesse inconnue ne vaut pas une vitesse nulle")
    func treatsUnknownSpeedAsNotMoving() {
        let fix = Fix(
            coordinate: SyntheticTrace.start,
            horizontalAccuracy: 5,
            speed: -1,
            course: 137,
            timestamp: SyntheticTrace.epoch
        )
        #expect(resolver.resolve(fix: fix, compass: makeCompass(42))?.source == .magneticCompass)
    }
}
