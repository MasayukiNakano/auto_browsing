import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var selectedSite: SiteProfile? = nil
    @Published var siteProfiles: [SiteProfile] = []
    @Published var automationStatus: AutomationStatus = .idle
    @Published var isJavaBridgeRunning: Bool = false
    @Published var safariDetected: Bool = false
    @Published var statusMessages: [String] = []
    @Published var activationRetryLimit: Int = 3
    @Published var currentPageURL: String? = nil
    @Published var lastLinks: [StrategyLinkSnapshot] = []
    @Published var visibleArticleCount: Int = 0
    @Published var lastCleanupRemovedCount: Int? = nil
    @Published var lastCleanupVisibleBefore: Int? = nil
    @Published var lastCleanupLimit: Int? = nil
    @Published var lastCleanupError: String? = nil
    @Published var lastCleanupSiteName: String? = nil
    @Published var linksInputDirectory: String
    @Published var linksAggregatedDirectory: String
    @Published var aggregationStatusMessage: String = ""
    @Published var aggregationLog: String = ""
    @Published var isAggregatingLinks: Bool = false
    @Published var aggregatorScriptLocation: String? = nil
    @Published var pythonBinaryPath: String = "/usr/bin/python3"
    @Published var keepTimestampOnAggregation: Bool = true

    private let safariController = SafariAccessibilityController()
    private let automationEngine = ScrollAutomationEngine()
    private let strategyClient = LoadMoreStrategyClient()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let defaults = AppState.defaultLinkDirectories()
        self.linksInputDirectory = defaults.input
        self.linksAggregatedDirectory = defaults.output

        wireBindings()
        refreshAggregatorScriptLocation()
    }

    func refreshSafariState() {
        safariDetected = safariController.isSafariFrontmost()
    }

    func loadSiteProfiles() {
        do {
            let profiles = try SiteProfileLoader().loadProfiles()
            siteProfiles = profiles
            if let url = currentPageURL {
                selectSiteIfMatching(url: url)
            }
            selectedSite = selectedSite ?? profiles.first
        } catch {
            Logger.shared.error("Failed to load site profiles: \(error.localizedDescription)")
            prependStatusMessage("設定ファイルの読み込みに失敗しました")
        }
    }

    func startAutomation() {
        guard automationStatus == .idle else { return }
        automationStatus = .running
        Task {
            await runAutomationLoop()
        }
    }

    func stopAutomation() {
        automationStatus = .idle
        automationEngine.stop()
        safariController.stop()
        Task { await strategyClient.stop() }
        prependStatusMessage("自動操作を停止しました")
    }

    private func wireBindings() {
        automationEngine.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                switch event {
                case .scrolled(let description):
                    self?.prependStatusMessage(description)
                    self?.refreshSafariState()
                case .buttonPressed(let description):
                    self?.prependStatusMessage(description)
                    self?.refreshSafariState()
                case .pageURL(let url):
                    self?.currentPageURL = url
                    if let url {
                        self?.selectSiteIfMatching(url: url)
                    }
                case .linksUpdated(let links):
                    self?.lastLinks = links
                    self?.visibleArticleCount = links.count
                case .cleanupInfo(let siteName, let report):
                    self?.lastCleanupSiteName = siteName
                    self?.lastCleanupRemovedCount = report.removed
                    self?.lastCleanupVisibleBefore = report.visibleBefore
                    self?.lastCleanupLimit = report.limit
                    self?.lastCleanupError = report.error

                    if let error = report.error, !error.isEmpty {
                        self?.prependStatusMessage("\(siteName) のクリーンアップに失敗しました: \(error)")
                    } else if report.removed > 0 {
                        let before = report.visibleBefore.map(String.init) ?? "-"
                        let limit = report.limit.map(String.init) ?? "-"
                        self?.prependStatusMessage("\(siteName) で古い記事を \(report.removed) 件削除 (処理前: \(before) / 上限: \(limit))")
                    }
                case .stopped:
                    self?.automationStatus = .idle
                    self?.refreshSafariState()
                case .error(let message):
                    self?.automationStatus = .idle
                    self?.prependStatusMessage(message)
                    self?.refreshSafariState()
                }
            }
            .store(in: &cancellables)
    }

    private func prependStatusMessage(_ message: String) {
        statusMessages.insert(message, at: 0)
        if statusMessages.count > 3 {
            statusMessages = Array(statusMessages.prefix(3))
        }
    }

    private func runAutomationLoop() async {
        guard selectedSite != nil else {
            automationStatus = .idle
            prependStatusMessage("サイト設定が選択されていません")
            return
        }

        do {
            try safariController.prepareAccessibilityIfNeeded()
        } catch {
            automationStatus = .idle
            prependStatusMessage("アクセシビリティの権限を確認してください")
            return
        }

        do {
            try await automationEngine.runAutomation(
                siteProvider: { [weak self] in
                    guard let self else { return nil }
                    return self.selectedSite
                },
                safariController: safariController,
                strategyClient: strategyClient,
                activationRetryLimit: activationRetryLimit
            )
        } catch {
            automationStatus = .idle
            prependStatusMessage("自動化に失敗しました: \(error.localizedDescription)")
        }
    }

    func aggregateLinks() {
        guard !isAggregatingLinks else { return }

        let fileManager = FileManager.default
        let basePath = linksInputDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputPath = linksAggregatedDirectory.trimmingCharacters(in: .whitespacesAndNewlines)

        guard fileManager.fileExists(atPath: basePath) else {
            aggregationStatusMessage = "入力ディレクトリが見つかりません: \(basePath)"
            return
        }

        guard let scriptPath = locateAggregatorScript() else {
            aggregationStatusMessage = "aggregate_links.py が見つかりませんでした"
            aggregatorScriptLocation = nil
            return
        }
        aggregatorScriptLocation = scriptPath

        aggregationStatusMessage = "集計を実行中..."
        aggregationLog = ""
        isAggregatingLinks = true

        let pythonPath = pythonBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let keepTimestamp = keepTimestampOnAggregation

        Task.detached { [weak self] in
            guard let self else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            var arguments: [String] = [scriptPath, "--base", basePath, "--output", outputPath]
            if keepTimestamp {
                arguments.append("--keep-timestamp")
            }
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: basePath)

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                await MainActor.run {
                    self.aggregationStatusMessage = "プロセスの起動に失敗しました: \(error.localizedDescription)"
                    self.isAggregatingLinks = false
                }
                return
            }

            process.waitUntilExit()

            let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let outputText = String(data: outputData, encoding: .utf8) ?? ""
            let errorText = String(data: errorData, encoding: .utf8) ?? ""
            let combinedLog = [outputText, errorText]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")

            let status = process.terminationStatus == 0
            await MainActor.run {
                self.aggregationLog = combinedLog
                if status {
                    self.aggregationStatusMessage = "集計が完了しました"
                } else {
                    self.aggregationStatusMessage = "集計に失敗しました (終了コード: \(process.terminationStatus))"
                }
                self.isAggregatingLinks = false
            }
        }
    }

    func refreshAggregatorScriptLocation() {
        aggregatorScriptLocation = locateAggregatorScript()
    }

    private func selectSiteIfMatching(url: String) {
        guard !siteProfiles.isEmpty else { return }
        let matches = siteProfiles.compactMap { profile -> (SiteProfile, Int)? in
            guard url.range(of: profile.urlPattern, options: [.regularExpression, .caseInsensitive]) != nil else {
                return nil
            }
            return (profile, matchPriority(for: profile))
        }

        guard let bestMatch = matches.max(by: { $0.1 < $1.1 })?.0 else { return }

        if selectedSite?.identifier != bestMatch.identifier {
            selectedSite = bestMatch
            prependStatusMessage("URLに基づき \(bestMatch.displayName) を選択しました")
        }
    }

    private func matchPriority(for profile: SiteProfile) -> Int {
        if profile.urlPattern == ".*" { return Int.min }
        return profile.urlPattern.replacingOccurrences(of: "\\\\", with: "").count
    }

    private static func defaultLinkDirectories() -> (input: String, output: String) {
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let input = current
            .appendingPathComponent("java-strategy")
            .appendingPathComponent("build")
            .appendingPathComponent("install")
            .appendingPathComponent("load-more-strategy")
            .appendingPathComponent("bin")
            .appendingPathComponent("links-output")
            .path
        let output = URL(fileURLWithPath: input)
            .appendingPathComponent("aggregated")
            .path
        return (input, output)
    }

    private func locateAggregatorScript() -> String? {
        let fileManager = FileManager.default
        var candidates: [String] = []

        if let envPath = ProcessInfo.processInfo.environment["AUTO_BROWSING_AGGREGATOR"] {
            candidates.append(envPath)
        }

        let cwd = FileManager.default.currentDirectoryPath
        candidates.append(contentsOf: [
            "\(cwd)/scripts/aggregate_links.py",
            "\(cwd)/../scripts/aggregate_links.py",
            "\(cwd)/../../scripts/aggregate_links.py"
        ])

        if let bundleURL = Bundle.main.url(forResource: "aggregate_links", withExtension: "py", subdirectory: "scripts") {
            candidates.append(bundleURL.path)
        }

        let bundleResourcePath = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
        let bundleScriptInScripts = bundleResourcePath
            .appendingPathComponent("scripts")
            .appendingPathComponent("aggregate_links.py")
            .path
        let bundleScriptRoot = bundleResourcePath
            .appendingPathComponent("aggregate_links.py")
            .path
        candidates.append(contentsOf: [bundleScriptInScripts, bundleScriptRoot])

        return candidates.first(where: { fileManager.fileExists(atPath: $0) })
    }
}

enum AutomationStatus {
    case idle
    case running
}
