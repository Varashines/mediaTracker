import Foundation
import SwiftData

/// The app's schema, under version control.
///
/// Until now every schema change relied on SwiftData's implicit lightweight migration,
/// with no version identifier and no migration plan. That works while changes stay
/// additive, and fails silently the moment one does not: a renamed attribute, a narrowed
/// type, or a new **required** property on an existing entity all throw on open, and the
/// catch in `App.swift` answers by moving the store aside and starting empty.
///
/// This is the scaffold for doing better, without moving any type:
///
/// 1. `SchemaV1` pins the current shape and the version the store records.
/// 2. When a change is not lightweight-compatible, add `SchemaV2` with the new shape and
///    a `MigrationStage.custom(fromVersion:toVersion:willMigrate:didMigrate:)` between
///    them. `MediaTrackerMigrationPlan` already carries the chain, so adding a stage is a
///    local edit rather than a refactor.
/// 3. Never edit `SchemaV1.models` after a release — that is what makes the version a lie.
///
/// The models are the same top-level types the rest of the app uses; SwiftData does not
/// require them to be nested inside the versioned enum.
enum SchemaV1: VersionedSchema {
    /// Bump on the next *breaking* schema change, not on every app release.
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            MediaItem.self, MovieDetails.self, TVShowDetails.self,
            TVSeason.self, TVEpisode.self, CastMember.self, SeasonCastMember.self,
            NetworkEntity.self, GenreEntity.self, LanguageEntity.self,
            BadgeEntity.self, PersonImageEntity.self,
            StudioAliasEntity.self, SearchCacheEntity.self,
            MediaCollection.self, ProviderEntity.self, MediaFacetIndex.self,
            WatchCycle.self, WatchEvent.self
        ]
    }
}

/// The ordered version chain and its migration stages.
///
/// With one version the stage list is empty, and lightweight migration still handles
/// additive changes exactly as before — so adopting this changes no behaviour today. It
/// changes what is possible tomorrow.
enum MediaTrackerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

extension Schema {
    /// The schema the container should open, expressed through the version chain so the
    /// two cannot drift apart.
    static var current: Schema {
        Schema(SchemaV1.models)
    }
}
