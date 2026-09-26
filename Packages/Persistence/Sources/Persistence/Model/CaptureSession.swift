// SPDX-License-Identifier: MIT

import Foundation
import GeoKit
import SwiftData

/// Où en est une session de capture, côté application.
///
/// L'avancement du **traitement serveur** (découpage, floutage) n'est
/// délibérément pas listé ici : il change sans nous, parfois plusieurs minutes
/// après l'envoi. On le lit en direct sur l'API, on ne le recopie pas.
public enum SessionState: String, Sendable, Codable, CaseIterable {
    /// La capture est en cours.
    case recording
    /// Capture terminée, rien n'est encore parti.
    case ready
    /// Un upload set existe et les fichiers partent.
    case sending
    /// Upload set clos. Le serveur peut encore être en train de traiter.
    case sent
    case failed
}

/// Une séquence de prises de vue : une sortie, un trajet, un tour d'horizon.
@Model
public final class CaptureSession {

    /// Identifiant stable, généré au démarrage. Sert aussi de nom au dossier
    /// qui porte les JPEG sur le disque.
    public var id: UUID

    public var title: String?
    public var startedAt: Date
    public var endedAt: Date?

    /// ``SessionState`` sous forme de chaîne.
    ///
    /// Pas l'énumération elle-même : `#Predicate` compare des chaînes sans
    /// difficulté, et une valeur écrite par une version ultérieure de l'app se
    /// relit encore — au lieu de faire échouer le décodage de la ligne entière.
    var stateRaw: String

    /// Type de déclenchement : `distance`, `time` ou `manual`.
    ///
    /// Deux colonnes plates plutôt qu'un `CaptureMode` sérialisé : le magasin
    /// reste lisible et interrogeable, et ajouter un mode dans `GeoKit` ne
    /// change pas la forme du schéma — donc pas de migration pour une raison
    /// qui n'en est pas une.
    var modeKind: String

    /// Mètres pour `distance`, secondes pour `time`, ignoré pour `manual`.
    var modeValue: Double

    /// Hôte de l'instance visée, par exemple `panoramax.openstreetmap.fr`.
    ///
    /// Retenu par session et non globalement : on change d'instance entre deux
    /// sorties, et une séquence déjà envoyée doit rester rattachée à celle qui
    /// l'a reçue.
    public var instanceHost: String?

    /// Upload set créé pour cette session, une fois l'envoi engagé.
    public var uploadSetID: UUID?

    /// Visibilité demandée au serveur (`public`, `owner-only`…). La liste des
    /// valeurs acceptées vient de `GET /api/configuration`, pas d'ici.
    public var visibility: String?

    @Relationship(deleteRule: .cascade, inverse: \Shot.session)
    public var shots: [Shot]

    public init(
        id: UUID = UUID(),
        title: String? = nil,
        startedAt: Date = Date(),
        mode: CaptureMode,
        instanceHost: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = nil
        self.stateRaw = SessionState.recording.rawValue
        self.modeKind = mode.storageKind
        self.modeValue = mode.storageValue
        self.instanceHost = instanceHost
        self.uploadSetID = nil
        self.visibility = nil
        self.shots = []
    }

    public var state: SessionState {
        get { SessionState(rawValue: stateRaw) ?? .recording }
        set { stateRaw = newValue.rawValue }
    }

    public var mode: CaptureMode {
        get { CaptureMode.fromStorage(kind: modeKind, value: modeValue) }
        set {
            modeKind = newValue.storageKind
            modeValue = newValue.storageValue
        }
    }
}

extension CaptureMode {

    var storageKind: String {
        switch self {
        case .distance: "distance"
        case .time: "time"
        case .manual: "manual"
        }
    }

    var storageValue: Double {
        switch self {
        case .distance(let metres): metres
        case .time(let seconds): seconds
        case .manual: 0
        }
    }

    /// Un `kind` inconnu retombe sur `manual` : mieux vaut une session qu'on
    /// déclenche à la main qu'une ligne illisible.
    static func fromStorage(kind: String, value: Double) -> CaptureMode {
        switch kind {
        case "distance": .distance(metres: value)
        case "time": .time(seconds: value)
        default: .manual
        }
    }
}
