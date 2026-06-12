import Foundation

@MainActor
final class PosterCacheService {
    static let shared = PosterCacheService()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let bundleID = Bundle.main.bundleIdentifier ?? "com.vara.MediaTracker"
        self.cacheDirectory = paths[0]
            .appendingPathComponent(bundleID)
            .appendingPathComponent("spotlight_posters")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func cachedPosterURL(for posterURL: String) -> URL? {
        let fileURL = cacheDirectory.appendingPathComponent(fileName(for: posterURL))
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    func ensurePosterCached(posterURL: String) async -> URL? {
        if let existing = cachedPosterURL(for: posterURL) {
            return existing
        }
        guard let url = URL(string: posterURL) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let fileURL = cacheDirectory.appendingPathComponent(fileName(for: posterURL))
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    func removePoster(posterURL: String) {
        let fileURL = cacheDirectory.appendingPathComponent(fileName(for: posterURL))
        try? fileManager.removeItem(at: fileURL)
    }

    func clearAll() {
        guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }
        for url in contents {
            try? fileManager.removeItem(at: url)
        }
    }

    private func fileName(for posterURL: String) -> String {
        posterURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "?", with: "_")
    }
}
