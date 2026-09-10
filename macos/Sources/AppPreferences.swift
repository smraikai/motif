import Foundation

enum AppPreferences {
    static let bundleIdentifier = "io.github.itsdotdev.motif"
    static let legacyIdentifier = "io.github.itsdotdev.youtube-music.macos"

    static func migrate(defaults: UserDefaults = .standard, legacy: [String: Any]? = nil) {
        guard !defaults.bool(forKey: "migratedYouTubeMusicPreferences") else { return }
        let previous = legacy ?? defaults.persistentDomain(forName: legacyIdentifier) ?? [:]
        for key in ["queue", "volume"] where defaults.object(forKey: key) == nil {
            if let value = previous[key] { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: "migratedYouTubeMusicPreferences")
    }
}
