import Combine
import Foundation

@MainActor
final class ScrollAutomationEngine {
    let events = PassthroughSubject<AutomationEngineEvent, Never>()
    private var shouldStop = false
    private var pressCounters: [String: Int] = [:]
    private var nextLongPauseThreshold: [String: Int] = [:]

    func runAutomation(
        siteProvider: @escaping () -> SiteProfile?,
        safariController: SafariAccessibilityController,
        strategyClient: LoadMoreStrategyClient,
        activationRetryLimit: Int
    ) async throws {
        shouldStop = false
        safariController.resetStopFlag()

        Logger.shared.info("Automation started")

        do {
            try await safariController.prepareWorkerWindow()
        } catch {
            events.send(.error("Safari ウィンドウの準備に失敗しました"))
            throw error
        }

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
            let suppressCursorWarning = ["bloomberg", "marketwatch"].contains(site.identifier)
            if !suppressCursorWarning {
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
            Logger.shared.debug("Visible buttons: \(buttons.compactMap { $0.title }.joined(separator: ", "))")
            let linkSelector = site.strategy.options["linkSelector"]
            let linkSnapshots = safariController.collectLinks(selector: linkSelector)
            events.send(.linksUpdated(linkSnapshots))
            Logger.shared.info("Collected \(linkSnapshots.count) links (site: \(site.identifier))")
            let pageURL = safariController.currentURL()
            events.send(.pageURL(pageURL))
            let instruction = try await strategyClient.nextInstruction(for: site, buttonSnapshots: buttonSnapshots, linkSnapshots: linkSnapshots, pageURL: pageURL)
            switch instruction {
            case .press(let selector):
                try await performPress(selector, safariController: safariController, site: site)
                Logger.shared.info("Instruction: press for site \(site.identifier)")
            case .scroll(let distance):
                safariController.scroll(deltaY: distance)
                events.send(.scrolled("スクロール: \(distance)"))
                Logger.shared.info("Instruction: scroll \(distance) for site \(site.identifier)")
            case .wait(let seconds):
                let interval = max(seconds, 0)
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                Logger.shared.info("Instruction: wait \(seconds)s for site \(site.identifier)")
            case .noAction:
                try await Task.sleep(nanoseconds: 500_000_000)
                Logger.shared.info("Instruction: no action for site \(site.identifier)")
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
        safariController: SafariAccessibilityController,
        site: SiteProfile
    ) async throws {
        do {
            if let title = selector.titleContains {
                try safariController.pressElement(matching: selector)
                events.send(.buttonPressed("ボタン押下: \(title)"))
                if site.identifier == "marketwatch" {
                    let baseDelay = Double.random(in: 4.0...8.0)
                    try await Task.sleep(nanoseconds: UInt64(baseDelay * 1_000_000_000))

                    let currentCount = (pressCounters[site.identifier] ?? 0) + 1
                    pressCounters[site.identifier] = currentCount

                    let threshold = nextLongPauseThreshold[site.identifier] ?? Int.random(in: 10...20)
                    nextLongPauseThreshold[site.identifier] = threshold

                    if currentCount >= threshold {
                        let extraDelay = Double.random(in: 20.0...30.0)
                        Logger.shared.info("MarketWatch long pause for \(extraDelay) seconds")
                        try await Task.sleep(nanoseconds: UInt64(extraDelay * 1_000_000_000))
                        pressCounters[site.identifier] = 0
                        nextLongPauseThreshold[site.identifier] = Int.random(in: 10...20)
                    }
                } else {
                    let baseDelay = Double.random(in: 0.8...1.3)
                    try await Task.sleep(nanoseconds: UInt64(baseDelay * 1_000_000_000))
                }
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
