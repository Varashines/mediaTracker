import SwiftData

// MARK: - V1 (original deployed schema)
enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }

    static var models: [any PersistentModel.Type] { [
        MediaItem.self, MovieDetails.self, TVShowDetails.self,
        TVSeason.self, TVEpisode.self, CastMember.self,
        NetworkEntity.self, GenreEntity.self, LanguageEntity.self,
        BadgeEntity.self, PersonImageEntity.self,
        StudioAliasEntity.self, SearchCacheEntity.self,
        MediaCollection.self
    ]}
}

// MARK: - V2 (adds ProviderEntity, removes cachedWatchProviderLogos & cachedTMDBStatus)
enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }

    static var models: [any PersistentModel.Type] { [
        MediaItem.self, MovieDetails.self, TVShowDetails.self,
        TVSeason.self, TVEpisode.self, CastMember.self,
        NetworkEntity.self, GenreEntity.self, LanguageEntity.self,
        BadgeEntity.self, PersonImageEntity.self,
        StudioAliasEntity.self, SearchCacheEntity.self,
        MediaCollection.self, ProviderEntity.self
    ]}
}

// MARK: - Migration Plan
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AppSchemaV1.self, AppSchemaV2.self] }

    static var stages: [MigrationStage] { [v1ToV2] }

    // V1 → V2: SwiftData lightweight migration handles:
    //   - New ProviderEntity table (auto-created)
    //   - Removed columns cachedWatchProviderLogos, cachedTMDBStatus (kept in SQLite, ignored by model)
    //   - Added #Index macro on MediaItem (index tables created automatically)
    static let v1ToV2 = MigrationStage.lightweight(
        fromVersion: AppSchemaV1.self,
        toVersion: AppSchemaV2.self
    )
}
