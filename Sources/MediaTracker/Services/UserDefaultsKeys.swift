import Foundation

enum UserDefaultsKeys: String {
    case tmdbAPIKey = "tmdb_api_key"
    case omdbAPIKey = "omdb_api_key"
    case autoMarkEpisodesWatched = "auto_mark_episodes_watched"
    case preventSleepMode = "prevent_sleep_mode"
    case genreDeconstructionV1 = "genre_deconstruction_v1"
    case hiddenStudios = "hidden_studios"
    case tasteWeightGenre = "taste_weight_genre"
    case tasteWeightCreator = "taste_weight_creator"
    case tasteWeightCast = "taste_weight_cast"
    case tasteWeightNetwork = "taste_weight_network"
    case tasteWeightLang = "taste_weight_lang"
    case hapticsEnabled = "haptics_enabled"
    case audioEnabled = "audio_enabled"
    case studioAliases = "studio_aliases"
    case skipStartupTasks = "skip_startup_background_tasks"
    case mmDebugMode = "mm_debug_mode"
    case mmAPIKey = "mm_api_key"
}
