// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import GeoKit

@Suite("Distances")
struct GeodesyTests {

    @Test("Un point avec lui-même est à distance nulle")
    func zeroForSamePoint() {
        let point = Coordinate(latitude: 45.9237, longitude: 6.8694)
        #expect(Geodesy.distance(from: point, to: point) == 0)
    }

    @Test("Un degré de latitude fait environ 111 km")
    func matchesKnownLatitudeSpacing() {
        let south = Coordinate(latitude: 45, longitude: 6)
        let north = Coordinate(latitude: 46, longitude: 6)
        let metres = Geodesy.distance(from: south, to: north)
        #expect(abs(metres - 111_195) < 500)
    }

    @Test("Cent mètres de trace synthétique en font bien cent")
    func matchesSyntheticTrace() {
        let trace = SyntheticTrace.straightLine(speed: 1, interval: 100, count: 2)
        let metres = Geodesy.distance(from: trace[0].coordinate, to: trace[1].coordinate)
        #expect(abs(metres - 100) < 1)
    }

    @Test("La distance est symétrique")
    func isSymmetric() {
        let chamonix = Coordinate(latitude: 45.9237, longitude: 6.8694)
        let annecy = Coordinate(latitude: 45.8992, longitude: 6.1294)
        let there = Geodesy.distance(from: chamonix, to: annecy)
        let back = Geodesy.distance(from: annecy, to: chamonix)
        #expect(abs(there - back) < 0.001)
        #expect(there > 50_000 && there < 62_000)
    }
}
