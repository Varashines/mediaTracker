import Foundation
import SwiftData

// MARK: - Schema V1 (Current)
// This schema captures the current state of all models including indexes and unique constraints.
// Future schema changes should create V2, V3, etc. with corresponding migration steps.

enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        .init(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self,
            NetworkEntity.self, GenreEntity.self, LanguageEntity.self, BadgeEntity.self, PersonImageEntity.self,
            StudioAliasEntity.self, SearchCacheEntity.self, MediaCollection.self,
            ImageCacheEntity.self
        ]
    }
}

// MARK: - Migration Plan
// SwiftData uses this to automatically migrate between schema versions.
// Adding indexes and @Attribute(.unique) constraints are additive changes
// that do not require data transformation — SwiftData handles them automatically.

enum MediaTrackerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        [] // No custom migration stages needed — additive changes are handled automatically
    }
}
