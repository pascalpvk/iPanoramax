// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import ImageMetadataKit

@Suite("Horodatages EXIF")
struct ExifTimestampsTests {

    /// 30 août 2026, 14:05:09,250 UTC — soit 16:05:09 à Paris (UTC+2).
    private static let instant = Date(timeIntervalSince1970: 1_788_098_709.25)

    private static func paris() throws -> TimeZone {
        try #require(TimeZone(identifier: "Europe/Paris"))
    }

    @Test("GPSDateStamp et GPSTimeStamp sont en UTC")
    func formatsGPSStampsInUTC() {
        #expect(ExifTimestamps.gpsDateStamp(Self.instant) == "2026:08:30")
        #expect(ExifTimestamps.gpsTimeStamp(Self.instant) == "14:05:09")
    }

    @Test("DateTimeOriginal est en heure locale, accompagné de son décalage")
    func formatsLocalStampWithOffset() throws {
        let paris = try Self.paris()
        #expect(ExifTimestamps.dateTimeOriginal(Self.instant, in: paris) == "2026:08:30 16:05:09")
        #expect(ExifTimestamps.offsetTime(Self.instant, in: paris) == "+02:00")
    }

    @Test("Le décalage suit l'heure d'hiver")
    func followsWinterTime() throws {
        let paris = try Self.paris()
        // 15 janvier 2026, 12:00 UTC — Paris est alors à UTC+1.
        let winter = Date(timeIntervalSince1970: 1_768_478_400)
        #expect(ExifTimestamps.offsetTime(winter, in: paris) == "+01:00")
        #expect(ExifTimestamps.dateTimeOriginal(winter, in: paris) == "2026:01:15 13:00:00")
    }

    @Test("Un fuseau à l'ouest de Greenwich porte un décalage négatif")
    func formatsNegativeOffset() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        #expect(ExifTimestamps.offsetTime(Self.instant, in: newYork) == "-04:00")
    }

    @Test("Les sous-secondes tiennent sur trois chiffres")
    func formatsMilliseconds() {
        #expect(ExifTimestamps.subsecondMilliseconds(Self.instant) == "250")
        #expect(ExifTimestamps.subsecondMilliseconds(Date(timeIntervalSince1970: 0)) == "000")
    }
}
