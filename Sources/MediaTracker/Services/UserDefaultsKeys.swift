import Foundation

enum UserDefaultsKeys: String {
    // API Keys
    case tmdbAPIKey = "tmdb_api_key"
    case omdbAPIKey = "omdb_api_key"
    case mmAPIKey = "mm_api_key"
    case mmDebugMode = "mm_debug_mode"
    
    // System
    case hapticsEnabled = "haptics_enabled"
    case audioEnabled = "audio_enabled"
    case preventSleepMode = "prevent_sleep_mode"
    case skipStartupTasks = "skip_startup_background_tasks"
    case autoMarkEpisodesWatched = "auto_mark_episodes_watched"
    
    // Appearance
    case themePreference = "theme_preference"
    case customThemePalette = "custom_theme_palette"
    case backgroundIntensity = "background_intensity"
    
    // Notifications
    case notificationsEnabled = "notifications_enabled"
    case notificationsMovies = "notifications_movies"
    case notificationsTV = "notifications_tv"
    case notificationsTime = "notifications_time"
    
    // Discovery
    case hiddenStudios = "hidden_studios"
    case studioAliases = "studio_aliases"
    
    // Collections
    case pinnedSystemCategories = "pinned_system_categories"
    
    // Search
    case recentSearches = "recent_searches"
    
    // Migrations
    case genreDeconstructionV1 = "genre_deconstruction_v1"
    case colorExtractionVersion = "colorExtractionVersion"
    
    // Taste weights
    case tasteWeightGenre = "taste_weight_genre"
    case tasteWeightCreator = "taste_weight_creator"
    case tasteWeightCast = "taste_weight_cast"
    case tasteWeightNetwork = "taste_weight_network"
    case tasteWeightLang = "taste_weight_lang"
    
    // Spotlight
    case spotlightSearchQuery = "spotlight_search_query"
    case spotlightOpenID = "spotlight_open_id"
}
