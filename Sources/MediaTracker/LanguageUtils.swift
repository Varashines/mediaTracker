import Foundation

struct LanguageUtils {
    static func languageName(for code: String?) -> String {
        guard let code = code, !code.isEmpty else { return "Unknown" }
        
        // Try current locale first
        if let name = Locale.current.localizedString(forLanguageCode: code) {
            return name.capitalized
        }
        
        // Fallback to English locale
        if let enLocale = Locale(identifier: "en") as Locale?,
           let name = enLocale.localizedString(forLanguageCode: code) {
            return name.capitalized
        }
        
        return code.uppercased()
    }
}
