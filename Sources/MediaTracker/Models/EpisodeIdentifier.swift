import Foundation

/// Canonical spelling of an episode identifier, shared with Android's `MediaIds`.
///
/// Two forms circulate through the sync: the legacy `{showID}_{season}_{episode}` (what
/// `TVEpisode.uniqueID` and `user_episodes.episode_id` carry, so it has to stay the wire format)
/// and `tv_{showID}_s{season}_e{episode}` (what newer clients write into the ledger and into
/// `user_watch_events.episode_id`).
///
/// Comparing those literally is how one viewing ended up in the ledger twice: the event recorded
/// here used one spelling, the event pulled back from Android the other.
enum EpisodeIdentifier {

    /// Returns the `tv_{showID}_s{season}_e{episode}` form for either spelling. Values that fit
    /// neither shape (including the `nil` that movies carry) are returned unchanged.
    static func canonical(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let parts = raw.split(separator: "_")

        // Already canonical: tv_{show}_s{n}_e{n}
        if parts.count == 4, parts[0] == "tv", parts[2].hasPrefix("s"), parts[3].hasPrefix("e") {
            return raw
        }

        // Legacy: {show}_{season}_{episode}
        if parts.count == 3,
           let show = Int(parts[0]),
           let season = Int(parts[1]),
           let episode = Int(parts[2]) {
            return "tv_\(show)_s\(season)_e\(episode)"
        }

        return raw
    }
}
