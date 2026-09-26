// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import GeoKit

@Suite("Filtrage des positions")
struct FixFilterTests {

    let filter = FixFilter(maximumHorizontalAccuracy: 10, maximumAge: 5)
    let now = SyntheticTrace.epoch

    func makeFix(accuracy: Double, age: TimeInterval = 0) -> Fix {
        Fix(
            coordinate: SyntheticTrace.start,
            horizontalAccuracy: accuracy,
            timestamp: now.addingTimeInterval(-age)
        )
    }

    @Test("Une position précise et fraîche est acceptée")
    func acceptsGoodFix() {
        #expect(filter.accepts(makeFix(accuracy: 4.5), now: now))
    }

    @Test("Une précision négative signale une position inexploitable")
    func rejectsInvalidPosition() {
        #expect(filter.rejection(for: makeFix(accuracy: -1), now: now) == .invalidPosition)
    }

    @Test("Au-delà du seuil de précision, on s'abstient")
    func rejectsImpreciseFix() {
        let rejection = filter.rejection(for: makeFix(accuracy: 42), now: now)
        #expect(rejection == .tooImprecise(accuracy: 42, limit: 10))
    }

    @Test("Le seuil est inclusif")
    func acceptsExactlyAtLimit() {
        #expect(filter.accepts(makeFix(accuracy: 10), now: now))
        #expect(!filter.accepts(makeFix(accuracy: 10.1), now: now))
    }

    @Test("Une position trop ancienne est écartée")
    func rejectsStaleFix() {
        #expect(filter.accepts(makeFix(accuracy: 5, age: 4), now: now))
        let rejection = filter.rejection(for: makeFix(accuracy: 5, age: 12), now: now)
        #expect(rejection == .tooOld(age: 12, limit: 5))
    }
}
