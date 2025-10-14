import Combine
import Foundation

@MainActor
final class ScrollAutomationEngine {
    let events = PassthroughSubject<AutomationEngineEvent, Never>()
    private var shouldStop = false

    func runAutomation(
        siteProvider: @escaping () -> SiteProfile?,
        safariController: SafariAccessibilityController,
        strategyClient: LoadMoreStrategyClient,
        activationRetryLimit: Int
    ) async throws {
        shouldStop = false
        safariController.resetStopFlag()

        Logger.shared.info("Automation started")

        let focusAttempts = max(activationRetryLimit, 1)
        var lastSiteIdentifier: String?

        while !Task.isCancelled && !shouldStop {
            guard let site = siteProvider() else {
                events.send(.error("サイト設定が選択されていません"))
                break
            }

            if lastSiteIdentifier != site.identifier {
                lastSiteIdentifier = site.identifier
                Logger.shared.info("Automation switched to site: \(site.identifier)")
            }

            do {
                try await safariController.ensureSafariFrontmost(maxAttempts: focusAttempts)
            } catch {
                events.send(.error("Safari のフォーカス再取得に失敗しました"))
                throw error
            }

            let cursorInside = safariController.isMouseCursorInsideSafariWindow()
            if site.identifier != "bloomberg" {
                if cursorInside {
                    events.send(.scrolled("Safariウィンドウ上でスクロールしています"))
                } else {
                    events.send(.scrolled("警告: マウスカーソルがSafariウィンドウ上にありません"))
                }
            }

            if let cleanupKey = site.strategy.options["cleanupScriptKey"],
               let report = safariController.performCleanupScript(named: cleanupKey) {
                events.send(.cleanupInfo(siteName: site.displayName, report: report))
            }

            let buttons = (try? safariController.collectVisibleButtons()) ?? []
            let buttonSnapshots = buttons.map { descriptor in
                StrategyButtonSnapshot(title: descriptor.title, role: descriptor.role ?? "AXButton")
            }
            let linkSnapshots = safariController.collectLinks()
            events.send(.linksUpdated(linkSnapshots))
            let pageURL = safariController.currentURL()
            events.send(.pageURL(pageURL))
            let instruction = try await strategyClient.nextInstruction(for: site, buttonSnapshots: buttonSnapshots, linkSnapshots: linkSnapshots, pageURL: pageURL)
            switch instruction {
            case .press(let selector):
                try await performPress(selector, safariController: safariController)
            case .scroll(let distance):
                safariController.scroll(deltaY: distance)
                events.send(.scrolled("スクロール: \(distance)"))
            case .wait(let seconds):
                let interval = max(seconds, 0)
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            case .noAction:
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        events.send(.stopped)
        Logger.shared.info("Automation loop finished")
    }

    func stop() {
        shouldStop = true
    }

    private func performPress(
        _ selector: AccessibilitySelector,
        safariController: SafariAccessibilityController
    ) async throws {
        do {
            if let title = selector.titleContains {
                try safariController.pressElement(matching: selector)
                events.send(.buttonPressed("ボタン押下: \(title)"))
                try await Task.sleep(nanoseconds: 500_000_000)
            } else {
                events.send(.error("選択条件が未定義のためクリックできません"))
            }
        } catch {
            if let accessibilityError = error as? AccessibilityError, case .elementNotFound = accessibilityError {
                events.send(.error("ボタンが見つからなかったためスクロールを継続します"))
                return
            }
            events.send(.error("ボタン押下に失敗: \(error.localizedDescription)"))
            throw error
        }
    }
}
