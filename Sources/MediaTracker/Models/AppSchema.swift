import SwiftData

// MARK: - Model list (no versioned migration plan — SwiftData auto-migrates additive changes)
// V1 original: MediaItem, MovieDetails, TVShowDetails, TVSeason, TVEpisode, CastMember,
//              NetworkEntity, GenreEntity, LanguageEntity, BadgeEntity, PersonImageEntity,
//              StudioAliasEntity, SearchCacheEntity, MediaCollection
// V2 added: ProviderEntity, dropped cachedWatchProviderLogos & cachedTMDBStatus
// Current: all of the above plus cachedWatchProviderLogoPaths on MediaItem
