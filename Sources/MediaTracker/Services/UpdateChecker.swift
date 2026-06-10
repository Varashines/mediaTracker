import Foundation

struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let htmlURL: String
    let body: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
    }
}

struct ReleaseInfo: Sendable, Equatable {
    let version: String
    let url: String
    let notes: String?
    let isNewer: Bool
}

enum UpdateCheckResult: Sendable, Equatable {
    case success(ReleaseInfo)
    case error(String)
    case checking
}

struct UpdateChecker {
    private static let repo = "Varashines/mediaTracker"
    private static let apiURL = "https://api.github.com/repos/\(repo)/releases/latest"

    static func checkForUpdates() async -> UpdateCheckResult {
        guard let url = URL(string: apiURL) else {
            return .error("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .error("Invalid response")
            }
            guard http.statusCode == 200 else {
                if http.statusCode == 403 {
                    return .error("Rate limited. Try again later.")
                }
                return .error("Server error (\(http.statusCode))")
            }

            let decoder = JSONDecoder()
            let release = try decoder.decode(GitHubRelease.self, from: data)

            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            let latest = release.tagName
            let isNewer = compareVersions(current, latest) < 0

            return .success(ReleaseInfo(
                version: latest,
                url: release.htmlURL,
                notes: release.body,
                isNewer: isNewer
            ))
        } catch let error as URLError {
            if error.code == .notConnectedToInternet {
                return .error("No internet connection")
            }
            if error.code == .timedOut {
                return .error("Request timed out")
            }
            return .error(error.localizedDescription)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func compareVersions(_ v1: String, _ v2: String) -> Int {
        let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

        let parts1 = clean1.split(separator: ".").compactMap { Int($0) }
        let parts2 = clean2.split(separator: ".").compactMap { Int($0) }

        let maxLen = max(parts1.count, parts2.count)
        for i in 0..<maxLen {
            let a = i < parts1.count ? parts1[i] : 0
            let b = i < parts2.count ? parts2[i] : 0
            if a < b { return -1 }
            if a > b { return 1 }
        }
        return 0
    }
}
