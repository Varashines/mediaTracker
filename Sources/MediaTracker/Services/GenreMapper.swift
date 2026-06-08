import Foundation

struct GenreMapper {
    /// Transforms a list of raw genres into standardized, atomic genre names.
    /// E.g., ["Action & Adventure", "Sci-Fi"] -> ["Action", "Adventure", "Science Fiction"]
    static func standardize(_ rawGenres: [String]) -> [String] {
        var results = Set<String>()
        
        for raw in rawGenres {
            let components = decompose(raw)
            for component in components {
                results.insert(map(component))
            }
        }
        
        return Array(results).sorted()
    }
    
    /// Splits compound genre strings based on common delimiters.
    private static func decompose(_ raw: String) -> [String] {
        let delimiters = CharacterSet(charactersIn: "&/")
        let components = raw.components(separatedBy: delimiters)
        
        var results: [String] = []
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased() == "and" { continue }
            
            // Handle cases like "War and Politics"
            let subComponents = trimmed.components(separatedBy: " and ")
            for sub in subComponents {
                let finalTrim = sub.trimmingCharacters(in: .whitespacesAndNewlines)
                if !finalTrim.isEmpty {
                    results.append(finalTrim)
                }
            }
        }
        return results
    }
    
    /// Maps inconsistent naming to standardized atomic categories.
    private static func map(_ genre: String) -> String {
        let lower = genre.lowercased()
        
        switch lower {
        case "sci-fi", "science fiction", "science-fiction":
            return "Science Fiction"
        case "tv movie":
            return "TV Movie"
        case "soap":
            return "Soap Opera"
        default:
            // Capitalize each word for consistency
            return genre.capitalized
        }
    }
}
