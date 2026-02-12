import Foundation

struct AppConfig: Codable {
    var claudeApiKey: String?
}

enum ConfigManager {
    private static var configDir: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/activity-tracker")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var configFile: URL {
        configDir.appendingPathComponent("config.json")
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configFile),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return config
    }

    static func save(_ config: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configFile, options: .atomic)
    }

    static var claudeApiKey: String? {
        get { load().claudeApiKey }
        set {
            var config = load()
            config.claudeApiKey = newValue
            save(config)
        }
    }
}
