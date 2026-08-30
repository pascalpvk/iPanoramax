// SPDX-License-Identifier: MIT

import Foundation

/// Erreurs typées de l'API Panoramax.
///
/// Le typage n'est pas cosmétique : c'est ce qui permet à l'interface
/// d'expliquer *pourquoi* une photo a été refusée (hors zone de couverture,
/// doublon, EXIF invalide) au lieu d'afficher « erreur réseau ».
public enum PanoramaxError: Error, Sendable, Equatable {

    /// 401 — jeton absent, expiré, ou pas encore réclamé par un compte.
    case unauthorized

    /// 403 — le compte n'a pas la permission demandée.
    case forbidden

    /// 404 — ressource inconnue.
    case notFound

    /// Le jeton a été généré mais l'utilisateur n'a pas encore ouvert l'URL de
    /// revendication. Distinct de `.unauthorized` : ce n'est pas une erreur,
    /// c'est une étape du flux d'authentification.
    case tokenNotClaimed

    /// Le serveur a accepté le fichier mais l'a rejeté au traitement.
    case rejected(FileRejection)

    /// 429 — trop de requêtes.
    case rateLimited(retryAfter: TimeInterval?)

    /// Toute autre réponse d'erreur du serveur.
    case server(status: Int, message: String?)

    /// Réponse illisible.
    case decoding(String)

    /// Échec de transport (réseau coupé, TLS, délai dépassé).
    case transport(String)

    /// `true` si un nouvel essai a une chance d'aboutir.
    /// Pilote directement la politique de reprise de la file d'envoi.
    public var isRetryable: Bool {
        switch self {
        case .transport, .rateLimited:
            return true
        case .server(let status, _):
            return status >= 500
        case .unauthorized, .forbidden, .notFound, .tokenNotClaimed, .rejected, .decoding:
            return false
        }
    }
}

extension PanoramaxError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Session expirée. Reconnecte-toi à l'instance."
        case .forbidden:
            return "Ton compte n'a pas les droits nécessaires pour cette action."
        case .notFound:
            return "Ressource introuvable sur cette instance."
        case .tokenNotClaimed:
            return "Le jeton n'a pas encore été rattaché à un compte."
        case .rejected(let rejection):
            return rejection.message ?? "Photo refusée par le serveur (\(rejection.reason ?? "raison inconnue"))."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Trop de requêtes. Nouvel essai dans \(Int(retryAfter)) s."
            }
            return "Trop de requêtes. Réessaie dans un instant."
        case .server(let status, let message):
            return message ?? "Erreur du serveur (HTTP \(status))."
        case .decoding(let detail):
            return "Réponse illisible du serveur : \(detail)"
        case .transport(let detail):
            return "Connexion impossible : \(detail)"
        }
    }
}
