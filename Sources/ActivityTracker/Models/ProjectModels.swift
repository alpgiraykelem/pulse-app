import Foundation

// MARK: - Brand

struct Brand {
    let id: Int64
    let name: String
    let color: String
    let sortOrder: Int
}

// MARK: - Project

struct Project {
    let id: Int64
    let brandId: Int64
    let name: String
    let color: String
    let sortOrder: Int
}

// MARK: - Project Rule

enum RuleType: String, Codable {
    case terminalFolder
    case urlDomain
    case urlPath
    case pageTitle
    case figmaFile
    case bundleId
    case windowTitle
}

struct ProjectRule {
    let id: Int64
    let projectId: Int64
    let ruleType: RuleType
    let pattern: String
    let isRegex: Bool
    let priority: Int
}

// MARK: - Project Source

enum ProjectSource: String, Codable {
    case autoRule
    case manual
    case ai
}

// MARK: - Summaries for Reports

struct BrandSummary: Codable {
    let brandId: Int64
    let brandName: String
    let color: String
    let totalSeconds: Int
    let projects: [ProjectSummary]
}

struct ProjectSummary: Codable {
    let projectId: Int64
    let projectName: String
    let brandId: Int64
    let brandName: String
    let color: String
    let totalSeconds: Int
    let appBreakdown: [AppBreakdownEntry]
}

struct AppBreakdownEntry: Codable {
    let appName: String
    let seconds: Int
}

// MARK: - Unassigned Activity (for report UI)

struct UnassignedActivity: Codable {
    let id: Int64
    let appName: String
    let windowTitle: String
    let url: String?
    let extraInfo: String?
    let durationSeconds: Int
}

// MARK: - Project Data for HTML embedding

struct ProjectData: Codable {
    let brands: [BrandJSON]
    let projects: [ProjectJSON]
    let unassigned: [UnassignedActivity]
    let apiPort: Int
}

struct BrandJSON: Codable {
    let id: Int64
    let name: String
    let color: String
}

struct ProjectJSON: Codable {
    let id: Int64
    let brandId: Int64
    let brandName: String
    let name: String
    let color: String
}
