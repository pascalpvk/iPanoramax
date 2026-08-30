// SPDX-License-Identifier: MIT

import Foundation

public enum SortMethod: String, Codable, Sendable, CaseIterable {
    case filenameAscending = "filename-asc"
    case filenameDescending = "filename-desc"
    case timeAscending = "time-asc"
    case timeDescending = "time-desc"
}

public enum Visibility: String, Codable, Sendable, CaseIterable {
    case anyone
    case ownerOnly = "owner-only"
    case loggedOnly = "logged-only"
}

/// Corps de `POST /api/upload_sets`.
///
/// Les valeurs de découpage laissées à `nil` sont remplacées par les défauts de
/// l'instance — c'est le comportement souhaité : on ne code pas en dur ce que
/// `GET /api/configuration` sait dire.
public struct UploadSetRequest: Codable, Sendable {
    public var title: String
    public var estimatedNbFiles: Int?
    public var splitDistance: Int?
    public var splitTime: Double?
    public var noSplit: Bool?
    public var duplicateDistance: Double?
    public var duplicateRotation: Int?
    public var noDeduplication: Bool?
    public var sortMethod: SortMethod?
    public var visibility: Visibility?
    public var relativeHeading: Int?
    public var userAgent: String?

    public init(
        title: String,
        estimatedNbFiles: Int? = nil,
        splitDistance: Int? = nil,
        splitTime: Double? = nil,
        noSplit: Bool? = nil,
        duplicateDistance: Double? = nil,
        duplicateRotation: Int? = nil,
        noDeduplication: Bool? = nil,
        sortMethod: SortMethod? = .timeAscending,
        visibility: Visibility? = nil,
        relativeHeading: Int? = nil,
        userAgent: String? = nil
    ) {
        self.title = title
        self.estimatedNbFiles = estimatedNbFiles
        self.splitDistance = splitDistance
        self.splitTime = splitTime
        self.noSplit = noSplit
        self.duplicateDistance = duplicateDistance
        self.duplicateRotation = duplicateRotation
        self.noDeduplication = noDeduplication
        self.sortMethod = sortMethod
        self.visibility = visibility
        self.relativeHeading = relativeHeading
        self.userAgent = userAgent
    }

    enum CodingKeys: String, CodingKey {
        case title, visibility
        case estimatedNbFiles = "estimated_nb_files"
        case splitDistance = "split_distance"
        case splitTime = "split_time"
        case noSplit = "no_split"
        case duplicateDistance = "duplicate_distance"
        case duplicateRotation = "duplicate_rotation"
        case noDeduplication = "no_deduplication"
        case sortMethod = "sort_method"
        case relativeHeading = "relative_heading"
        case userAgent = "user_agent"
    }
}

public struct ItemsStatus: Codable, Sendable, Hashable {
    public let prepared: Int?
    public let preparing: Int?
    public let broken: Int?
    public let rejected: Int?
    public let notProcessed: Int?

    enum CodingKeys: String, CodingKey {
        case prepared, preparing, broken, rejected
        case notProcessed = "not_processed"
    }

    public var total: Int {
        [prepared, preparing, broken, rejected, notProcessed].compactMap { $0 }.reduce(0, +)
    }
}

public struct AssociatedCollection: Codable, Sendable, Hashable {
    public let id: UUID
    public let title: String?
    public let nbItems: Int?
    public let ready: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, ready
        case nbItems = "nb_items"
    }
}

/// État d'un upload set (`GET /api/upload_sets/{id}`).
public struct UploadSet: Codable, Sendable {
    public let id: UUID
    public let title: String?
    public let createdAt: Date?
    public let completed: Bool?
    public let dispatched: Bool?
    public let ready: Bool?
    public let itemsStatus: ItemsStatus?
    public let associatedCollections: [AssociatedCollection]?

    enum CodingKeys: String, CodingKey {
        case id, title, completed, dispatched, ready
        case createdAt = "created_at"
        case itemsStatus = "items_status"
        case associatedCollections = "associated_collections"
    }
}

/// Motif de refus d'un fichier (`GET /api/upload_sets/{id}/files`).
public struct FileRejection: Codable, Sendable, Hashable {
    public let reason: String?
    public let severity: String?
    public let message: String?
}

public struct UploadSetFile: Codable, Sendable, Hashable {
    public let pictureId: UUID?
    public let fileName: String?
    public let size: Int?
    public let rejected: FileRejection?

    enum CodingKeys: String, CodingKey {
        case size, rejected
        case pictureId = "picture_id"
        case fileName = "file_name"
    }
}

struct UploadSetFilesResponse: Codable, Sendable {
    let files: [UploadSetFile]
}
