import Foundation

struct SiteProfile: Identifiable, Codable, Equatable, Hashable {
    let identifier: String
    let displayName: String
    let urlPattern: String
    let strategy: StrategyReference

    var id: String { identifier }
}

struct StrategyReference: Codable, Equatable, Hashable {
    let type: StrategyType
    let options: [String: String]
}

enum StrategyType: String, Codable {
    case cssSelector
    case textMatch
    case script
    case fallback
}
