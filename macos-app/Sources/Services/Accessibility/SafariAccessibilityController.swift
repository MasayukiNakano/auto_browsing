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
    private var workerWindowID: Int?
    private let workerWindowTitle = "AutoBrowsing Worker"
    private lazy var workerPlaceholderURL: String = {
        if let url = Bundle.main.url(forResource: "worker-placeholder", withExtension: "html") {
            return url.absoluteString
        }
        return "about:blank"
    }()

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

    func prepareWorkerWindow() async throws {
        if isWorkerWindowValid() { return }

        let script = """
        tell application "Safari"
            set targetTitle to "\(workerWindowTitle)"
            set placeholderURL to "\(workerPlaceholderURL)"
            set foundWindow to missing value
            repeat with w in windows
                try
                    if name of w is targetTitle then
                        set foundWindow to w
                        exit repeat
                    end if
                end try
            end repeat
            if foundWindow is missing value then
                make new document with properties {URL:placeholderURL}
                set foundWindow to front window
            else
                try
                    set URL of current tab of foundWindow to placeholderURL
                end try
            end if
            try
                set name of foundWindow to targetTitle
            end try
            set workerId to id of foundWindow
            activate
            return workerId
        end tell
        """

        guard let result = runAppleScript(script) else {
            throw AccessibilityError.safariActivationFailed
        }

        let idValue = Int(result.int32Value)
        guard idValue > 0 else {
            workerWindowID = nil
            throw AccessibilityError.safariActivationFailed
        }
        workerWindowID = idValue
        try await Task.sleep(nanoseconds: 200_000_000)
        executeJavaScript("document.title='\(workerWindowTitle)'")
    }

    func ensureWorkerWindowFrontmost(maxAttempts: Int) async throws {
        try await prepareWorkerWindow()
        let attempts = max(maxAttempts, 1)
        for _ in 0..<attempts {
            if bringWorkerWindowToFrontOnce() { return }
            try await Task.sleep(nanoseconds: 200_000_000)
            try await prepareWorkerWindow()
        }
        throw AccessibilityError.safariActivationFailed
    }

    private func bringWorkerWindowToFrontOnce() -> Bool {
        guard let id = workerWindowID else { return false }
        let script = """
        tell application "Safari"
            try
                set targetWindow to window id \(id)
                set current tab of targetWindow to tab 1 of targetWindow
                set index of targetWindow to 1
                activate
                return "OK"
            on error errMsg
                return "ERROR: " & errMsg
            end try
        end tell
        """

        guard let result = runAppleScript(script)?.stringValue else {
            workerWindowID = nil
            return false
        }

        if result == "OK" {
            focusFrontmostContent()
            return true
        } else {
            workerWindowID = nil
            return false
        }
    }

    func waitForDocumentReadyState(timeout: TimeInterval = 2.0) async -> Bool {
        let clampedTimeout = max(timeout, 0.2)
        let step: TimeInterval = 0.1
        let iterations = Int(clampedTimeout / step)

        for _ in 0..<max(iterations, 1) {
            if let readyState = evaluateJavaScriptReturningString("document.readyState")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
               readyState == "complete" {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
        }
        return false
    }

    private func isWorkerWindowValid() -> Bool {
        guard let id = workerWindowID else { return false }
        let script = """
        tell application "Safari"
            repeat with w in windows
                if id of w is \(id) then
                    return "OK"
                end if
            end repeat
            return "MISSING"
        end tell
        """

        guard let result = runAppleScript(script)?.stringValue else {
            workerWindowID = nil
            return false
        }

        if result == "OK" {
            return true
        } else {
            workerWindowID = nil
            return false
        }
    }

    private func windowSpecifier() -> String {
        if isWorkerWindowValid() {
            return "window id \(workerWindowID!)"
        }
        return "window 1"
    }

    private func tabSpecifier() -> String {
        return "tab 1 of \(windowSpecifier())"
    }

    func isSafariFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == safariBundleIdentifier
    }

    func ensureSafariFrontmost(maxAttempts: Int, delay: TimeInterval = 0.3) async throws {
        if isWorkerWindowValid() {
            try await ensureWorkerWindowFrontmost(maxAttempts: maxAttempts)
            return
        }

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
        if bringWorkerWindowToFrontOnce() { return true }
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
                return URL of \(tabSpecifier())
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

        let targetDocument = tabSpecifier()
        let appleScriptSource = """
        tell application "Safari"
            try
                do JavaScript "SCRIPT_PLACEHOLDER" in \(targetDocument)
                return "OK"
            on error errMsg
                return "ERROR: " & errMsg
            end try
        end tell
        """.replacingOccurrences(of: "SCRIPT_PLACEHOLDER", with: escaped)
        if let result = runAppleScript(appleScriptSource), let message = result.stringValue, message.hasPrefix("ERROR") {
            Logger.shared.debug("JavaScript 実行失敗: \(message)")
        }
    }

    func evaluateJavaScriptReturningString(_ script: String) -> String? {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let targetDocument = tabSpecifier()
        let appleScriptSource = """
        tell application "Safari"
            try
                do JavaScript "SCRIPT_PLACEHOLDER" in \(targetDocument)
            on error errMsg
                return "ERROR: " & errMsg
            end try
        end tell
        """.replacingOccurrences(of: "SCRIPT_PLACEHOLDER", with: escaped)

        guard let descriptor = runAppleScript(appleScriptSource) else { return nil }
        guard let value = descriptor.stringValue, !value.hasPrefix("ERROR") else { return nil }
        return value
    }

    func setDocumentURL(_ urlString: String) -> Bool {
        let escapedURL = urlString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let targetDocument = tabSpecifier()
        let appleScriptSource = """
        tell application "Safari"
            try
                set URL of \(targetDocument) to "\(escapedURL)"
                return "OK"
            on error errMsg
                return "ERROR: " & errMsg
            end try
        end tell
        """
        guard let result = runAppleScript(appleScriptSource)?.stringValue else { return false }
        return result.hasPrefix("OK")
    }

    func performCleanupScript(named key: String) -> CleanupReport? {
        guard let scriptSource = CleanupScripts.script(for: key) else { return nil }

        let escaped = scriptSource
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let targetDocument = tabSpecifier()
        let appleScriptSource = """
        tell application "Safari"
            try
                do JavaScript "SCRIPT_PLACEHOLDER" in \(targetDocument)
            on error errMsg
                return "ERROR: " & errMsg
            end try
        end tell
        """.replacingOccurrences(of: "SCRIPT_PLACEHOLDER", with: escaped)

        guard let descriptor = runAppleScript(appleScriptSource),
              let resultString = descriptor.stringValue,
              !resultString.hasPrefix("ERROR"),
              let data = resultString.data(using: .utf8) else {
            Logger.shared.debug("Cleanup スクリプト実行失敗: AppleScript error")
            return nil
        }

        do {
            return try cleanupDecoder.decode(CleanupReport.self, from: data)
        } catch {
            Logger.shared.debug("Cleanup レポートのデコードに失敗: \(error.localizedDescription)")
            return nil
        }
    }

    func collectMarketWatchLinks(pageNumber _: Int = 0, limit: Int = 400) -> [StrategyLinkSnapshot] {
        let jsTemplate = #"""
        (function collectMarketWatchArticles() {
            try {
                const seen = new Set();
                const items = [];
                const containers = document.querySelectorAll("div.element--article");
                for (let i = 0; i < containers.length; i += 1) {
                    const container = containers[i];
                    const anchor = container.querySelector("a.link[href]");
                    if (!anchor) { continue; }
                    let href = anchor.href || anchor.getAttribute("href");
                    if (!href) { continue; }
                    try { href = new URL(href, window.location.href).href; } catch (err) {}
                    if (!href || seen.has(href)) { continue; }
                    seen.add(href);

                    const text = (anchor.innerText || anchor.textContent || "").trim();
                    let publishedAt = null;
                    const timeCandidate = container.querySelector("time[datetime], time[data-est], span.article__timestamp, span.timestamp__time, span.timestamp__date");
                    if (timeCandidate) {
                        const attrs = ["datetime", "data-est", "data-timestamp", "title"];
                        for (let j = 0; j < attrs.length; j += 1) {
                            const attrValue = timeCandidate.getAttribute(attrs[j]);
                            if (attrValue && attrValue.trim()) {
                                publishedAt = attrValue.trim();
                                break;
                            }
                        }
                        if (!publishedAt) {
                            const raw = (timeCandidate.innerText || timeCandidate.textContent || "").trim();
                            if (raw) {
                                publishedAt = raw;
                            }
                        }
                    }

                    items.push({ href, text, publishedAt });
                    if (items.length >= LIMIT_PLACEHOLDER) { break; }
                }
                return JSON.stringify(items);
            } catch (err) {
                return "[]";
            }
        })();
        """#

        let js = jsTemplate
            .replacingOccurrences(of: "LIMIT_PLACEHOLDER", with: String(limit))
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let appleScriptSource = """
        tell application "Safari"
            try
                do JavaScript "SCRIPT_PLACEHOLDER" in \(tabSpecifier())
            on error errMsg
                return "ERROR: " & errMsg
            end try
        end tell
        """.replacingOccurrences(of: "SCRIPT_PLACEHOLDER", with: js)

        guard let descriptor = runAppleScript(appleScriptSource),
              let resultString = descriptor.stringValue,
              !resultString.hasPrefix("ERROR"),
              let data = resultString.data(using: .utf8) else {
            return []
        }

        do {
            return try JSONDecoder().decode([StrategyLinkSnapshot].self, from: data)
        } catch {
            Logger.shared.debug("MarketWatch リンクのデコードに失敗: \(error.localizedDescription)")
            return []
        }
    }

    func collectLinks(limit: Int = 400, selector: String? = nil) -> [StrategyLinkSnapshot] {
        let jsTemplateAllLinks = #"""
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

        let jsTemplateWithSelector = #"""
        (function collectLinksWithSelector() {
            try {
                const selector = SELECTOR_PLACEHOLDER;
                const seen = new Set();
                const items = [];
                const nodes = document.querySelectorAll(selector);
                for (let i = 0; i < nodes.length; i += 1) {
                    const node = nodes[i];
                    let href = node.href || node.getAttribute('href');
                    if (!href) { continue; }
                    try { href = new URL(href, window.location.href).href; } catch (e) {}
                    if (!href || seen.has(href)) { continue; }
                    seen.add(href);
                    const text = (node.innerText || node.textContent || "").trim();
                    items.push({ href, text });
                    if (items.length >= LIMIT_PLACEHOLDER) { break; }
                }
                return JSON.stringify(items);
            } catch (err) {
                return "[]";
            }
        })();
        """#

        let rawJS: String
        if let selector, !selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let escapedSelector = selector
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ")
            rawJS = jsTemplateWithSelector
                .replacingOccurrences(of: "LIMIT_PLACEHOLDER", with: String(limit))
                .replacingOccurrences(of: "SELECTOR_PLACEHOLDER", with: "\"" + escapedSelector + "\"")
        } else {
            rawJS = jsTemplateAllLinks.replacingOccurrences(of: "LIMIT_PLACEHOLDER", with: String(limit))
        }

        let js = rawJS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let appleScriptSource = """
        tell application "Safari"
            try
                do JavaScript "SCRIPT_PLACEHOLDER" in \(tabSpecifier())
            on error errMsg
                return "ERROR: " & errMsg
            end try
        end tell
        """.replacingOccurrences(of: "SCRIPT_PLACEHOLDER", with: js)

        guard let descriptor = runAppleScript(appleScriptSource),
              let resultString = descriptor.stringValue,
              !resultString.hasPrefix("ERROR"),
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

    func enableReaderMode() async {
        Logger.shared.debug("Reader モード切り替えワークフロー開始")
        guard await waitForReaderAvailability(timeout: 8.0) else {
            Logger.shared.debug("リーダー表示が利用可能になる前にタイムアウトしました")
            return
        }
        if await setReaderProperty(true) {
            Logger.shared.debug("Reader モードが有効になりました (direct)")
            return
        }
        Logger.shared.debug("リーダー直接切り替えに失敗したためショートカットを送信します")
        sendReaderShortcut()
        if await waitForReaderEnabled(timeout: 5.0) {
            Logger.shared.debug("Reader モードがショートカットで有効になりました")
        } else {
            Logger.shared.debug("Reader モードの有効化に失敗しました")
        }
    }

    private func waitForReaderAvailability(timeout: TimeInterval) async -> Bool {
        let iterations = Int(timeout / 0.3)
        for i in 0..<max(iterations, 1) {
            if await isReaderAvailable() {
                Logger.shared.debug("Reader モード利用可能を確認 (attempt \(i + 1))")
                return true
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return false
    }

    private func waitForReaderEnabled(timeout: TimeInterval) async -> Bool {
        let iterations = Int(timeout / 0.3)
        for _ in 0..<max(iterations, 1) {
            if await isReaderEnabled() {
                return true
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return false
    }

    private func isReaderAvailable() async -> Bool {
        let script = tabTellScript(body: "return reader available")

        guard let result = runAppleScript(script)?.stringValue else { return false }
        if result == "true" || result == "false" {
            return result == "true"
        }
        Logger.shared.debug("reader available の取得に失敗: \(result)")
        return false
    }

    private func isReaderEnabled() async -> Bool {
        let script = tabTellScript(body: "return reader")

        guard let result = runAppleScript(script)?.stringValue else { return false }
        if result == "true" || result == "false" {
            return result == "true"
        }
        Logger.shared.debug("reader の取得に失敗: \(result)")
        return false
    }

    private func setReaderProperty(_ newValue: Bool) async -> Bool {
        let script = tabTellScript(body: "set reader to \(newValue as NSNumber)" + "\n                    return reader")

        guard let result = runAppleScript(script)?.stringValue else {
            Logger.shared.debug("reader 設定を呼び出しましたが応答がありません")
            return false
        }
        if result == "true" {
            return true
        }
        Logger.shared.debug("reader 設定に失敗: \(result)")
        return false
    }

    private func sendReaderShortcut() {
        Logger.shared.debug("Reader ショートカット (⌘⇧R) を送信します")
        let activateScript = """
        tell application "Safari"
            try
                activate
                return "OK"
            on error errMsg
                return "ERROR: " & errMsg
            end try
        end tell
        """
        _ = runAppleScript(activateScript)

        let script = """
        tell application "System Events"
            try
                tell process "Safari"
                    keystroke "r" using {command down, shift down}
                    return "OK"
                end tell
            on error errMsg
                return "ERROR: " & errMsg
            end try
        end tell
        """

        if let result = runAppleScript(script)?.stringValue,
           result.hasPrefix("ERROR") {
            Logger.shared.debug("Reader ショートカット送信に失敗: \(result)")
        } else {
            Logger.shared.debug("Reader ショートカットを送信しました")
        }
    }

    private func tabTellScript(body: String) -> String {
        let indented = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "            " + $0 }
            .joined(separator: "\n")

        return """
tell application "Safari"
    try
        tell window 1
            tell current tab
\(indented)
            end tell
        end tell
    on error errMsg
        return "ERROR: " & errMsg
    end try
end tell
"""
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

    private func runAppleScript(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else {
            Logger.shared.debug("AppleScript 作成に失敗: \(source.prefix(120))...")
            return nil
        }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo, let message = errorInfo[NSAppleScript.errorMessage] as? String {
            Logger.shared.debug("AppleScript 実行失敗: \(message)")
            return nil
        }
        return descriptor
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
