import Foundation

enum AutomationEngineEvent {
    case scrolled(String)
    case buttonPressed(String)
    case pageURL(String?)
    case linksUpdated([StrategyLinkSnapshot])
    case cleanupInfo(siteName: String, report: CleanupReport)
    case stopped
    case error(String)
}
