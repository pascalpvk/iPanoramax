// SPDX-License-Identifier: MIT

import Foundation

/// Position d'un cliché, en degrés décimaux WGS84.
public struct GeoPosition: Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double
    /// Mètres, positif au-dessus du niveau de la mer.
    public var altitude: Double?
    /// Rayon d'incertitude en mètres. Panoramax le remonte en
    /// `quality:horizontal_accuracy`.
    public var horizontalAccuracy: Double?
    /// Mètres par seconde. Négatif signifie « inconnu » côté CoreLocation.
    public var speed: Double?

    public init(
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        speed: Double? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
    }
}

/// Cap de visée retenu, et sa provenance.
///
/// Ce type ne représente qu'un cap dont on est sûr. La boussole magnétique est
/// faussée dans un véhicule ; la route GPS est inutilisable à l'arrêt. Quand
/// aucune source n'est fiable, on n'en construit pas : un `GPSImgDirection`
/// absent se gère correctement côté Panoramax, alors qu'un cap faux dégrade la
/// séquence pour tous les réutilisateurs.
public struct Heading: Sendable, Hashable {

    public enum Source: String, Sendable, Hashable {
        /// Route suivie, issue du GPS. Fiable en mouvement.
        case gpsCourse
        /// Visée boussole corrigée de la déclinaison. Fiable à pied.
        case magneticCompass
    }

    /// Degrés depuis le nord **géographique**, dans `0..<360`.
    public var trueDegrees: Double
    public var source: Source

    public init(trueDegrees: Double, source: Source) {
        self.trueDegrees = trueDegrees.truncatingRemainder(dividingBy: 360)
        if self.trueDegrees < 0 { self.trueDegrees += 360 }
        self.source = source
    }
}

/// Orientation de l'appareil au déclenchement, en degrés.
public struct CameraAttitude: Sendable, Hashable {
    public var yaw: Double
    public var pitch: Double
    public var roll: Double

    public init(yaw: Double, pitch: Double, roll: Double) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }
}

/// Appareil et optique ayant produit le cliché.
///
/// Panoramax s'en sert pour déduire le modèle de caméra et le champ de vision :
/// ce n'est pas de la décoration.
public struct DeviceDescription: Sendable, Hashable {
    public var make: String
    public var model: String
    public var lensModel: String?
    /// Focale réelle, en millimètres.
    public var focalLength: Double?
    /// Équivalent 24×36, en millimètres.
    public var focalLengthIn35mm: Int?

    public init(
        make: String,
        model: String,
        lensModel: String? = nil,
        focalLength: Double? = nil,
        focalLengthIn35mm: Int? = nil
    ) {
        self.make = make
        self.model = model
        self.lensModel = lensModel
        self.focalLength = focalLength
        self.focalLengthIn35mm = focalLengthIn35mm
    }
}

/// Tout ce qu'iPanoramax sait d'un cliché au moment de l'inscrire dans le JPEG.
///
/// Type volontairement sans dépendance à CoreLocation ni CoreMotion : il se
/// teste sans matériel, et le pont depuis les capteurs vit dans `GeoKit`.
public struct CaptureMetadata: Sendable, Hashable {
    public var position: GeoPosition
    /// Instant de la prise de vue. L'heure UTC est le canal de référence.
    public var timestamp: Date
    /// Fuseau au moment de la capture, pour écrire `DateTimeOriginal` et son
    /// décalage sans ambiguïté.
    public var timeZone: TimeZone
    public var heading: Heading?
    public var attitude: CameraAttitude?
    public var device: DeviceDescription?
    /// Nom et version du logiciel producteur, ex. « iPanoramax 0.1.0 ».
    public var software: String?

    public init(
        position: GeoPosition,
        timestamp: Date,
        timeZone: TimeZone = .current,
        heading: Heading? = nil,
        attitude: CameraAttitude? = nil,
        device: DeviceDescription? = nil,
        software: String? = nil
    ) {
        self.position = position
        self.timestamp = timestamp
        self.timeZone = timeZone
        self.heading = heading
        self.attitude = attitude
        self.device = device
        self.software = software
    }
}
