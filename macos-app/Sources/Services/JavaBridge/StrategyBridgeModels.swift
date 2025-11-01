import Foundation

struct StrategyRequestPayload: Codable {
    let siteId: String
    let url: String?
    let visibleButtons: [StrategyButtonSnapshot]
    let links: [StrategyLinkSnapshot]
    let metadata: [String: String]?

    init(siteId: String, url: String? = nil, visibleButtons: [StrategyButtonSnapshot] = [], links: [StrategyLinkSnapshot] = [], metadata: [String: String]? = nil) {
        self.siteId = siteId
        self.url = url
        self.visibleButtons = visibleButtons
        self.links = links
        self.metadata = metadata
    }
}

struct StrategyButtonSnapshot: Codable {
    let title: String?
    let role: String?

    init(title: String?, role: String?) {
        self.title = title
        self.role = role
    }
}

struct StrategyLinkSnapshot: Codable {
    let href: String
    let text: String?
    let publishedAt: String?

    init(href: String, text: String?, publishedAt: String? = nil) {
        self.href = href
        self.text = text
        self.publishedAt = publishedAt
    }
}

struct StrategyResponsePayload: Codable {
    let success: Bool
    let action: StrategyActionPayload
    let message: String?
    let query: StrategyQueryPayload?
    let scrollDistance: Double?
    let waitSeconds: Double?
    let script: String?
}

enum StrategyActionPayload: String, Codable {
    case press = "PRESS"
    case scroll = "SCROLL"
    case wait = "WAIT"
    case noAction = "NO_ACTION"
    case error = "ERROR"
}

struct StrategyQueryPayload: Codable {
    let titleContains: String?
    let role: String?
}

struct StrategyServerEvent: Codable {
    let event: String
    let name: String?
    let message: String?
}

enum LoadMoreStrategyBridgeError: Error {
    case processUnavailable
    case unexpectedTermination
    case responseMismatch
    case strategyFailure(String)
    case decodingFailure(String)
}
