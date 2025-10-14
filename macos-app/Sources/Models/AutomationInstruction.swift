import ApplicationServices
import Foundation

enum AutomationInstruction {
    case press(AccessibilitySelector)
    case scroll(distance: Double)
    case wait(TimeInterval)
    case noAction
}

struct AccessibilitySelector: Codable, Equatable {
    let titleContains: String?
    let role: String?

    init(titleContains: String? = nil, role: String? = nil) {
        self.titleContains = titleContains
        self.role = role
    }
}
