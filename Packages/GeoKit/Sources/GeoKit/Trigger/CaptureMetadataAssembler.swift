// SPDX-License-Identifier: MIT

import Foundation
import ImageMetadataKit

/// Assemble ce que disent les capteurs en métadonnées prêtes à écrire.
///
/// C'est la couture entre `GeoKit`, qui lit le matériel, et
/// `ImageMetadataKit`, qui n'en sait rien. Isolée ici pour que ni l'un ni
/// l'autre n'ait à connaître les conventions du second.
public struct CaptureMetadataAssembler: Sendable {

    public var headingResolver: HeadingResolver
    public var device: DeviceDescription?
    public var software: String?
    public var timeZone: TimeZone

    public init(
        headingResolver: HeadingResolver = HeadingResolver(),
        device: DeviceDescription? = nil,
        software: String? = nil,
        timeZone: TimeZone = .current
    ) {
        self.headingResolver = headingResolver
        self.device = device
        self.software = software
        self.timeZone = timeZone
    }

    public func metadata(
        fix: Fix,
        compass: HeadingReading? = nil,
        attitude: CameraAttitude? = nil
    ) -> CaptureMetadata {
        CaptureMetadata(
            position: GeoPosition(
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude,
                altitude: fix.altitude,
                horizontalAccuracy: fix.horizontalAccuracy >= 0 ? fix.horizontalAccuracy : nil,
                speed: fix.hasValidSpeed ? fix.speed : nil
            ),
            // L'horodatage vient du GPS, pas de l'horloge de l'appareil :
            // c'est lui qui fait foi, et il est déjà en UTC.
            timestamp: fix.timestamp,
            timeZone: timeZone,
            heading: headingResolver.resolve(fix: fix, compass: compass),
            attitude: attitude,
            device: device,
            software: software
        )
    }
}
