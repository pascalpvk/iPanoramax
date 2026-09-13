// SPDX-License-Identifier: MIT

import Foundation

/// Mise en forme des horodatages EXIF.
///
/// Pas de `DateFormatter` : il n'est pas `Sendable`, il coûte cher à créer, et
/// ces formats sont trop simples pour le justifier. Des composantes de date et
/// un `String(format:)` suffisent, et se testent sans état caché.
enum ExifTimestamps {

    static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static let utc = TimeZone(secondsFromGMT: 0) ?? .gmt

    private static func components(_ date: Date, in timeZone: TimeZone) -> DateComponents {
        calendar(in: timeZone).dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
    }

    /// `GPSDateStamp` — `AAAA:MM:JJ` en UTC.
    static func gpsDateStamp(_ date: Date) -> String {
        let parts = components(date, in: utc)
        return String(format: "%04d:%02d:%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `GPSTimeStamp` — `HH:MM:SS` en UTC.
    static func gpsTimeStamp(_ date: Date) -> String {
        let parts = components(date, in: utc)
        return String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// `DateTimeOriginal` — `AAAA:MM:JJ HH:MM:SS` en heure **locale**.
    ///
    /// Ce champ ne porte aucun fuseau : seul, il est ambigu. Il s'accompagne
    /// donc toujours de ``offsetTime(_:in:)``.
    static func dateTimeOriginal(_ date: Date, in timeZone: TimeZone) -> String {
        let parts = components(date, in: timeZone)
        return String(
            format: "%04d:%02d:%02d %02d:%02d:%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
    }

    /// `OffsetTimeOriginal` — `+HH:MM`, la réponse d'EXIF 2.31 à l'ambiguïté
    /// de `DateTimeOriginal`.
    static func offsetTime(_ date: Date, in timeZone: TimeZone) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let absolute = abs(seconds)
        return String(format: "%@%02d:%02d", sign, absolute / 3600, (absolute % 3600) / 60)
    }

    /// `SubsecTimeOriginal` — millisecondes, sur trois chiffres.
    static func subsecondMilliseconds(_ date: Date) -> String {
        let parts = components(date, in: utc)
        let milliseconds = Int((Double(parts.nanosecond ?? 0) / 1_000_000).rounded())
        return String(format: "%03d", min(milliseconds, 999))
    }
}
