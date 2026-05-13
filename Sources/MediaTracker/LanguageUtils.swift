import Foundation

struct LanguageUtils {
    static func languageName(for code: String?) -> String {
        guard let code = code, !code.isEmpty else { return "Unknown" }
        
        // 1. Check for specific regional overrides or common TMDB codes
        let normalizedCode = code.lowercased()
        if normalizedCode == "en" { return "English" }
        if normalizedCode == "hi" { return "Hindi" }
        if normalizedCode == "ml" { return "Malayalam" }
        if normalizedCode == "ta" { return "Tamil" }
        if normalizedCode == "te" { return "Telugu" }
        if normalizedCode == "kn" { return "Kannada" }
        
        // 2. Try current locale first
        if let name = Locale.current.localizedString(forLanguageCode: code) {
            return name.capitalized
        }
        
        // 3. Fallback to English locale for a consistent UI
        if let enLocale = Locale(identifier: "en") as Locale?,
           let name = enLocale.localizedString(forLanguageCode: code) {
            return name.capitalized
        }
        
        return code.uppercased()
    }
}
