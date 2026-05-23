import Foundation

// Phase 3 Optimization: String Interning (Flyweight Pattern)
// Ensures unique string instances for common metadata across the app.
actor StringPool {
    static let shared = StringPool()
    private let cache: NSCache<NSString, NSString> = {
        let c = NSCache<NSString, NSString>()
        c.countLimit = 5000
        return c
    }()

    private init() {}

    func intern(_ string: String?) -> String? {
        guard let string = string, !string.isEmpty else { return nil }
        let key = string as NSString
        if let existing = cache.object(forKey: key) {
            return existing as String
        }
        cache.setObject(key, forKey: key)
        return string
    }

    func clear() { cache.removeAllObjects() }
}
