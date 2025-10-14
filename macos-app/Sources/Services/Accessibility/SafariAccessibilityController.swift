import AppKit
import ApplicationServices
import CoreGraphics

struct AccessibilityNotTrustedError: Error {}

enum AccessibilityError: Error {
    case elementNotFound
    case actionFailed(AXError)
    case safariActivationFailed
}

struct AccessibilityButtonDescriptor {
    let element: AXUIElement
    let title: String?
    let role: String?
}

struct CleanupReport: Decodable {
    let removed: Int
    let visibleBefore: Int?
    let limit: Int?
    let error: String?
}

@MainActor
final class SafariAccessibilityController {
    private let safariBundleIdentifier = "com.apple.Safari"
    private var shouldStop = false
    private let cleanupDecoder = JSONDecoder()

    func prepareAccessibilityIfNeeded() throws {
        if !AXIsProcessTrusted() {
            throw AccessibilityNotTrustedError()
        }
    }

    func stop() {
        shouldStop = true
    }

    func resetStopFlag() {
        shouldStop = false
    }

    func isSafariFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == safariBundleIdentifier
    }

    func ensureSafariFrontmost(maxAttempts: Int, delay: TimeInterval = 0.3) async throws {
        let attempts = max(maxAttempts, 1)
        let waitDuration = max(delay, 0.1)
        let nanos = UInt64(waitDuration * 1_000_000_000)

        if bringSafariToFrontIfPossible() { return }

        for index in 0..<attempts {
            if let application = NSRunningApplication.runningApplications(withBundleIdentifier: safariBundleIdentifier).first {
                if application.activate(options: [.activateIgnoringOtherApps]) {
                    try await Task.sleep(nanoseconds: nanos)
                    if bringSafariToFrontIfPossible() { return }
                }
            } else {
                Logger.shared.debug("Safari プロセスが見つかりません")
            }

            if index < attempts - 1 {
                try await Task.sleep(nanoseconds: nanos)
            }
        }

        if bringSafariToFrontIfPossible() { return }
        throw AccessibilityError.safariActivationFailed
    }

    private func bringSafariToFrontIfPossible() -> Bool {
        guard isSafariFrontmost() else { return false }
        focusFrontmostContent()
        return true
    }

    func pressButton(withTitle title: String) throws {
        try pressElement(matching: AccessibilitySelector(titleContains: title, role: kAXButtonRole as String))
    }

    func pressElement(_ element: AXUIElement) throws {
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if result != .success {
            throw AccessibilityError.actionFailed(result)
        }
    }

    func pressElement(matching selector: AccessibilitySelector) throws {
        let candidates = try collectVisibleButtons()
        guard let match = candidates.first(where: { descriptor in
            if let requiredRole = selector.role {
                guard let actualRole = descriptor.role, actualRole == requiredRole else {
                    return false
                }
            }

            if let needle = selector.titleContains {
                guard let buttonTitle = descriptor.title,
                      buttonTitle.localizedCaseInsensitiveContains(needle) else {
                    return false
                }
            }

            return selector.titleContains != nil || selector.role != nil
        }) else {
            throw AccessibilityError.elementNotFound
        }
        try pressElement(match.element)
    }

    func scroll(deltaY: Double) {
        guard !shouldStop else { return }

        let direction = deltaY >= 0 ? 1.0 : -1.0
        let magnitude = max(abs(deltaY), 120)
        let steps = max(Int(magnitude / 60), 1)

        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        for step in 0..<steps {
            let progress = Double(step) / Double(max(steps - 1, 1))
            let eased = easeOut(progress)
            let chunkValue = direction * max(40.0, (magnitude / Double(steps)) * eased)
            let limited = max(Double(Int32.min), min(Double(Int32.max), chunkValue))
            let wheel = Int32(limited.rounded())
            if let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1, wheel1: wheel, wheel2: 0, wheel3: 0) {
                event.post(tap: .cghidEventTap)
            }
            usleep(10_000)
        }
    }

    func collectVisibleButtons() throws -> [AccessibilityButtonDescriptor] {
        guard let window = try frontmostWindow() else { return [] }
        var descriptors: [AccessibilityButtonDescriptor] = []
        let targetRoles: Set<String> = [kAXButtonRole as String]
        enumerate(element: window) { element, _ in
            guard let role = accessibilityRole(of: element), targetRoles.contains(role) else {
                return
            }
            var titleValue: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
            var title = titleValue as? String
            if title?.isEmpty ?? true {
                var valueRef: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
                if let valueString = valueRef as? String, !valueString.isEmpty {
                    title = valueString
                }
            }
            descriptors.append(AccessibilityButtonDescriptor(element: element, title: title, role: role))
        }
        return descriptors
    }

    func currentURL() -> String? {
        let scriptSource = """
        tell application "Safari"
            try
                return URL of document 1
            on error
                return ""
            end try
        end tell
        """
        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else { return nil }
        return descriptor.stringValue
    }

    func executeJavaScript(_ script: String) {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let appleScriptSource = """
        tell application "Safari"
            do JavaScript "SCRIPT_PLACEHOLDER" in document 1
        end tell
        """.replacingOccurrences(of: "SCRIPT_PLACEHOLDER", with: escaped)

        guard let appleScript = NSAppleScript(source: appleScriptSource) else { return }
        var errorInfo: NSDictionary?
        _ = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo, let message = errorInfo[NSAppleScript.errorMessage] as? String {
            Logger.shared.debug("JavaScript 実行失敗: \(message)")
        }
    }

    func performCleanupScript(named key: String) -> CleanupReport? {
        guard let scriptSource = CleanupScripts.script(for: key) else { return nil }

        let escaped = scriptSource
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let appleScriptSource = """
        tell application "Safari"
            do JavaScript "SCRIPT_PLACEHOLDER" in document 1
        end tell
        """.replacingOccurrences(of: "SCRIPT_PLACEHOLDER", with: escaped)

        guard let appleScript = NSAppleScript(source: appleScriptSource) else { return nil }
        var errorInfo: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&errorInfo)
        guard errorInfo == nil,
              let resultString = descriptor.stringValue,
              let data = resultString.data(using: .utf8) else {
            if let errorInfo, let message = errorInfo[NSAppleScript.errorMessage] as? String {
                Logger.shared.debug("Cleanup スクリプト実行失敗: \(message)")
            }
            return nil
        }

        do {
            return try cleanupDecoder.decode(CleanupReport.self, from: data)
        } catch {
            Logger.shared.debug("Cleanup レポートのデコードに失敗: \(error.localizedDescription)")
            return nil
        }
    }

    func collectLinks(limit: Int = 400) -> [StrategyLinkSnapshot] {
        let jsTemplate = #"""
        (function collectLinks() {
            try {
                const seen = new Set();
                const items = [];
                const anchors = document.querySelectorAll("a[href]");
                for (let i = 0; i < anchors.length; i += 1) {
                    const a = anchors[i];
                    const href = a.href;
                    if (!href || seen.has(href)) { continue; }
                    seen.add(href);
                    const text = (a.innerText || "").trim();
                    items.push({ href, text });
                    if (items.length >= LIMIT_PLACEHOLDER) { break; }
                }
                return JSON.stringify(items);
            } catch (err) {
                return "[]";
            }
        })();
        """#

        var js = jsTemplate.replacingOccurrences(of: "LIMIT_PLACEHOLDER", with: String(limit))
        js = js
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let appleScriptSource = """
        tell application "Safari"
            do JavaScript "SCRIPT_PLACEHOLDER" in document 1
        end tell
        """.replacingOccurrences(of: "SCRIPT_PLACEHOLDER", with: js)

        guard let script = NSAppleScript(source: appleScriptSource) else {
            return []
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil,
              let resultString = descriptor.stringValue,
              let data = resultString.data(using: .utf8) else {
            return []
        }

        do {
            return try JSONDecoder().decode([StrategyLinkSnapshot].self, from: data)
        } catch {
            Logger.shared.debug("リンクのデコードに失敗: \(error.localizedDescription)")
            return []
        }
    }

    func isMouseCursorInsideSafariWindow() -> Bool {
        guard let frame = safariWindowFrame() else { return false }
        let cursor = currentCursorLocationTopLeftOrigin()
        return frame.contains(cursor)
    }

    private func easeOut(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    private func focusFrontmostContent() {
        guard let applicationElement = frontmostApplicationElement(),
              let window = try? frontmostWindow() else { return }
        _ = AXUIElementSetAttributeValue(applicationElement, kAXFocusedWindowAttribute as CFString, window)
        if let webArea = firstElement(withRole: "AXWebArea", in: window) {
            _ = AXUIElementSetAttributeValue(applicationElement, kAXFocusedUIElementAttribute as CFString, webArea)
        }
    }

    private func firstElement(withRole targetRole: String, in element: AXUIElement) -> AXUIElement? {
        if accessibilityRole(of: element) == targetRole {
            return element
        }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        guard let childArray = children as? [AXUIElement] else { return nil }
        for child in childArray {
            if let match = firstElement(withRole: targetRole, in: child) {
                return match
            }
        }
        return nil
    }

    private func accessibilityRole(of element: AXUIElement) -> String? {
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        return role as? String
    }

    private func frontmostWindow() throws -> AXUIElement? {
        guard let application = frontmostApplicationElement(),
              let windows = copyAttribute(application, attribute: kAXWindowsAttribute as CFString) as? [AXUIElement] else {
            return nil
        }
        return windows.first
    }

    private func safariWindowFrame() -> CGRect? {
        guard let window = try? frontmostWindow() else { return nil }
        guard let positionRef = copyAttribute(window, attribute: kAXPositionAttribute as CFString),
              let sizeRef = copyAttribute(window, attribute: kAXSizeAttribute as CFString) else {
            return nil
        }
        let positionValue = unsafeDowncast(positionRef, to: AXValue.self)
        let sizeValue = unsafeDowncast(sizeRef, to: AXValue.self)
        guard let position = axValueToCGPoint(positionValue),
              let size = axValueToCGSize(sizeValue) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func currentCursorLocationTopLeftOrigin() -> CGPoint {
        let cgPoint = CGEvent(source: nil)?.location ?? NSEvent.mouseLocation
        return cgPoint
    }

    private func frontmostApplicationElement() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    private func copyAttribute(_ element: AXUIElement, attribute: CFString) -> AnyObject? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute, &value)
        return value
    }

    private func enumerate(element: AXUIElement, handler: (AXUIElement, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard let children = value as? [AXUIElement] else { return }
        for child in children {
            var stop = ObjCBool(false)
            handler(child, &stop)
            if stop.boolValue { return }
            enumerate(element: child, handler: handler)
        }
    }

    private func axValueToCGPoint(_ value: AXValue) -> CGPoint? {
        guard AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(value, .cgPoint, &point)
        return point
    }

    private func axValueToCGSize(_ value: AXValue) -> CGSize? {
        guard AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        AXValueGetValue(value, .cgSize, &size)
        return size
    }
}

extension AccessibilityError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .elementNotFound:
            return "該当するボタンが見つかりませんでした"
        case .actionFailed(let error):
            return "アクセシビリティ操作に失敗しました (AXError: \(error.rawValue))"
        case .safariActivationFailed:
            return "Safari を前面に戻せませんでした"
        }
    }
}
