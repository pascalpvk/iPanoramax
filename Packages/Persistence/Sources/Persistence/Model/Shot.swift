// SPDX-License-Identifier: MIT

import Foundation
import ImageMetadataKit
import SwiftData

/// Où en est un cliché dans son voyage vers l'instance.
public enum ShotState: String, Sendable, Codable, CaseIterable {
    /// Sur le disque, pas encore envoyé.
    case captured
    case sending
    /// Le serveur a accepté le fichier. Il peut encore le traiter ensuite.
    case sent
    /// Refusé à l'ingestion. Le motif est conservé tel que rendu par le serveur.
    case rejected
}

/// Un déclenchement : un fichier sur le disque, une ligne ici.
@Model
public final class Shot {

    /// Identifiant du cliché, généré au déclenchement.
    ///
    /// C'est aussi le `picture_id` envoyé à Panoramax **et** le nom du fichier
    /// sur le disque. Un seul identifiant de l'obturateur à l'ingestion : c'est
    /// ce qui rend l'envoi rejouable après une coupure réseau sans créer de
    /// doublon côté serveur.
    public var id: UUID

    /// Session d'appartenance, dupliquée hors de la relation.
    ///
    /// `#Predicate` traverse mal les relations ; une colonne plate rend les
    /// requêtes triviales. Le prix est de seize octets par ligne.
    public var sessionID: UUID

    /// Rang dans la séquence. Strictement croissant, jamais réattribué après
    /// une suppression : deux clichés ne peuvent pas échanger leur place.
    public var index: Int

    /// Horodatage du **point GPS**, pas de l'horloge de l'appareil.
    public var capturedAt: Date

    public var latitude: Double
    public var longitude: Double
    public var altitude: Double?

    /// Rayon d'incertitude en mètres, ou `nil` si la position était invalide.
    public var horizontalAccuracy: Double?

    /// Cap en degrés depuis le nord géographique.
    public var headingDegrees: Double?

    /// `Heading.Source` sous forme de chaîne : savoir si le cap vient du GPS ou
    /// de la boussole explique après coup une séquence dont les vignettes
    /// regardent de travers.
    var headingSourceRaw: String?

    var stateRaw: String

    /// Motif de refus rendu par le serveur, conservé mot pour mot.
    public var rejectionReason: String?

    /// Taille du JPEG sur le disque. Permet d'annoncer le poids d'une séquence
    /// avant de la faire partir en 4G, sans parcourir le dossier.
    public var byteCount: Int

    public var session: CaptureSession?

    public init(draft: ShotDraft, sessionID: UUID, index: Int) {
        self.id = draft.id
        self.sessionID = sessionID
        self.index = index
        self.capturedAt = draft.capturedAt
        self.latitude = draft.coordinate.latitude
        self.longitude = draft.coordinate.longitude
        self.altitude = draft.altitude
        self.horizontalAccuracy = draft.horizontalAccuracy
        self.headingDegrees = draft.heading?.trueDegrees
        self.headingSourceRaw = draft.heading?.source.rawValue
        self.stateRaw = ShotState.captured.rawValue
        self.rejectionReason = nil
        self.byteCount = draft.byteCount
        self.session = nil
    }

    public var state: ShotState {
        get { ShotState(rawValue: stateRaw) ?? .captured }
        set { stateRaw = newValue.rawValue }
    }

    public var heading: Heading? {
        guard let headingDegrees else { return nil }
        let source = headingSourceRaw.flatMap { Heading.Source(rawValue: $0) } ?? .gpsCourse
        return Heading(trueDegrees: headingDegrees, source: source)
    }
}
