import Foundation

struct LanguageUtils {
    private static let enLocale = Locale(identifier: "en")

    static func languageName(for code: String?) -> String {
        guard let code = code, !code.isEmpty else { return "Unknown" }
        
        let normalizedCode = code.lowercased()
        if normalizedCode == "en" { return "English" }
        if normalizedCode == "hi" { return "Hindi" }
        if normalizedCode == "ml" { return "Malayalam" }
        if normalizedCode == "ta" { return "Tamil" }
        if normalizedCode == "te" { return "Telugu" }
        if normalizedCode == "kn" { return "Kannada" }
        
        if let name = Locale.current.localizedString(forLanguageCode: code) {
            return name.capitalized
        }
        
        if let name = enLocale.localizedString(forLanguageCode: code) {
            return name.capitalized
        }
        
        return code.uppercased()
    }
}
