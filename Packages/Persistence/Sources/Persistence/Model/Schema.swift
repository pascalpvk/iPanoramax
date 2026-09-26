// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// Première version du schéma.
///
/// Versionné dès le premier jour, alors qu'il n'y a rien à migrer. C'est
/// justement le moment où cela ne coûte rien : quand `UploadTask` arrivera en
/// phase 3, la base des premiers utilisateurs sera déjà estampillée et
/// l'ajout se fera par une étape de migration, pas par un effacement.
public enum SchemaV1: VersionedSchema {

    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [CaptureSession.self, Shot.self]
    }
}

/// Plan de migration du magasin de captures.
///
/// Une seule version, aucune étape : la liste grandira, l'appel qui la
/// consomme ne changera pas.
public enum CaptureMigrationPlan: SchemaMigrationPlan {

    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }

    public static var stages: [MigrationStage] { [] }
}

/// Fabrique le conteneur SwiftData du magasin de captures.
public enum CaptureContainer {

    /// Conteneur sur disque, à l'emplacement par défaut de l'application.
    public static func onDisk() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: CaptureMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema)
        )
    }

    /// Conteneur sur disque à un emplacement choisi. Sert aux tests qui
    /// vérifient qu'une base rouverte rend bien ce qu'on y avait mis.
    public static func at(_ url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: CaptureMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
    }

    /// Conteneur en mémoire, jeté avec le processus.
    public static func inMemory() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: CaptureMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }
}
