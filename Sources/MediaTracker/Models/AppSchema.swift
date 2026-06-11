import SwiftData

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

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AppSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
