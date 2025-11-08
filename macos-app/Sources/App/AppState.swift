import AppKit
import Combine
import Foundation

enum MarketWatchFeedOption: String, CaseIterable, Identifiable, Hashable {
    case marketplace = "1.1.0"
    case dowJones = "1.1.1"

    var id: String { rawValue }

    var feedLabel: String {
        switch self {
        case .marketplace:
            return "Marketplace"
        case .dowJones:
            return "Dow Jones"
        }
    }

    var pickerTitle: String {
        "\(feedLabel) (\(rawValue))"
    }

    var positionQueryValue: String { rawValue }

    var siteIdentifier: String {
        switch self {
        case .marketplace:
            return "marketwatch-marketplace"
        case .dowJones:
            return "marketwatch-dowjones"
        }
    }
}

struct MarketWatchArticle: Identifiable, Hashable {
    let id: String
    let url: String
    let headline: String?
    let publishedAt: String?
    let pageNumber: Int
    let feed: MarketWatchFeedOption
}

enum BloombergFeedOption: String, CaseIterable, Identifiable, Hashable {
    case markets = "phx-markets"
    case economics = "phx-economics-v2"
    case industries = "phx-industries"
    case technology = "phx-technology"
    case politics = "phx-politics"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .markets:
            return "Bloomberg (Markets)"
        case .economics:
            return "Bloomberg (Economics)"
        case .industries:
            return "Bloomberg (Industries)"
        case .technology:
            return "Bloomberg (Technology)"
        case .politics:
            return "Bloomberg (Politics)"
        }
    }

    var pickerTitle: String {
        "\(displayName): \(rawValue)"
    }

    var pageParameter: String { rawValue }

    var siteIdentifier: String {
        "bloomberg-\(rawValue)"
    }
}

struct BloombergArticle: Identifiable, Hashable {
    let id: String
    let url: String
    let headline: String?
    let publishedAt: String?
    let offset: Int
    let feed: BloombergFeedOption
}

private enum BloombergCrawlEndReason {
    case completed
    case duplicateStop
    case unexpectedResponse
    case cancelled
    case error
}

private struct BloombergArchiveResponse: Decodable {
    struct ArchiveStoryList: Decodable {
        struct Item: Decodable {
            let id: String?
            let url: String?
            let headline: String?
            let publishedAt: String?
        }
        let items: [Item]?
    }

    let archive_story_list: ArchiveStoryList?
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedSite: SiteProfile? = nil
    @Published var siteProfiles: [SiteProfile] = []
    @Published var automationStatus: AutomationStatus = .idle
    @Published var isJavaBridgeRunning: Bool = false
    @Published var safariDetected: Bool = false
    @Published var statusMessages: [String] = []
    @Published var liveStatusMessage: String = "待機中"
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
    @Published var lastAggregationLogFile: String? = nil
    @Published var marketWatchArticles: [MarketWatchArticle] = []
    @Published var marketWatchIsCrawling: Bool = false
    @Published var marketWatchStartPage: Int = 1
    @Published var marketWatchMaxPages: Int = 10_000
    @Published var marketWatchFeed: MarketWatchFeedOption = .marketplace
    @Published var marketWatchLastPageFetched: Int? = nil
    @Published var marketWatchLastFetchFeed: MarketWatchFeedOption? = nil
    @Published var marketWatchErrorMessage: String? = nil
    @Published var marketWatchSessionNewCount: Int = 0
    @Published var marketWatchSessionDuplicateCount: Int = 0
    @Published var marketWatchKnownCount: Int = 0
    @Published var shortSleepMean: Double = 2.0
    @Published var shortSleepVariation: Double = 2.0
    @Published var longSleepEnabled: Bool = false
    @Published var longSleepMean: Double = 14.0
    @Published var longSleepVariation: Double = 4.0
    @Published var autoRetryEnabled: Bool = true
    @Published var autoRetryMaxAttempts: Int = 5
    @Published var autoRetryDelaySeconds: Double = 15.0
    @Published var haltOnDuplicate: Bool = false
    @Published var bloombergArticles: [BloombergArticle] = []
    @Published var bloombergIsCrawling: Bool = false
    @Published var bloombergFeed: BloombergFeedOption = .markets
    @Published var bloombergStartOffset: Int = 0
    @Published var bloombergMaxPages: Int = 10_000
    @Published var bloombergLastOffsetFetched: Int? = nil
    @Published var bloombergLastFetchFeed: BloombergFeedOption? = nil
    @Published var bloombergErrorMessage: String? = nil
    @Published var bloombergSessionNewCount: Int = 0
    @Published var bloombergSessionDuplicateCount: Int = 0
    @Published var bloombergKnownCount: Int = 0
    @Published var bloombergCrossFeedEnabled: Bool = false
    @Published var bloombergParquetFiles: [String] = []
    @Published var bloombergSelectedParquetFile: String? = nil
    @Published var bloombergBodySourceURLs: [String] = []
    @Published var bloombergBodyLoadError: String? = nil
    @Published var bloombergPreviewLoading: Bool = false
    @Published var bloombergUseReaderMode: Bool = false {
        didSet {
            UserDefaults.standard.set(bloombergUseReaderMode, forKey: Self.bloombergUseReaderModeKey)
        }
    }


    private var statusLogInitialized = false

    private let safariController = SafariAccessibilityController()
    private let automationEngine = ScrollAutomationEngine()
    private let strategyClient = LoadMoreStrategyClient()
    private var cancellables: Set<AnyCancellable> = []
    private var loggerObserver: NSObjectProtocol?

    private var marketWatchTask: Task<Void, Never>? = nil
    private var marketWatchSeenArticleIds: Set<String> = []
    private var marketWatchFetchCount: Int = 0
    private var marketWatchNextLongPause: Int = Int.random(in: 10...20)
    private var bloombergTask: Task<Void, Never>? = nil
    private var bloombergSeenArticleIds: Set<String> = []
    private var bloombergFetchCount: Int = 0
    private var bloombergNextLongPause: Int = Int.random(in: 10...20)
    private var bloombergResumeOffset: Int = 0
    private var bloombergLastRawResponse: String? = nil
    private(set) var marketWatchRetryCount: Int = 0
    private(set) var bloombergRetryCount: Int = 0

    private static let linksInputDirectoryKey = "linksInputDirectory"
    private static let linksAggregatedDirectoryKey = "linksAggregatedDirectory"
    private static let bloombergUseReaderModeKey = "bloombergUseReaderMode"

    init() {
        let defaults = AppState.defaultLinkDirectories()
        let storedInput = UserDefaults.standard.string(forKey: Self.linksInputDirectoryKey)
        let storedOutput = UserDefaults.standard.string(forKey: Self.linksAggregatedDirectoryKey)
        let storedReaderMode = UserDefaults.standard.object(forKey: Self.bloombergUseReaderModeKey) as? Bool

        self.linksInputDirectory = storedInput?.isEmpty == false ? storedInput! : defaults.input
        self.linksAggregatedDirectory = storedOutput?.isEmpty == false ? storedOutput! : defaults.output
        self.bloombergUseReaderMode = storedReaderMode ?? false

        wireBindings()
        refreshAggregatorScriptLocation()
        updateLinkOutputEnvironment()
        loggerObserver = NotificationCenter.default.addObserver(forName: .loggerMessage, object: nil, queue: .main) { [weak self] notification in
            guard let message = notification.userInfo?["message"] as? String else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.prependStatusMessage(message)
            }
        }
        initializeStatusLogFileIfNeeded()
        refreshBloombergParquetSources()
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
        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "HH:mm:ss"
        let time = timestampFormatter.string(from: Date())
        let entry = "[" + time + "] " + message
        statusMessages.insert(entry, at: 0)
        if statusMessages.count > 10 {
            statusMessages.removeLast(statusMessages.count - 10)
        }
        appendStatusLog(entry)
    }

    private func updateLiveStatus(_ message: String) {
        liveStatusMessage = message.isEmpty ? "待機中" : message
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

        if !fileManager.fileExists(atPath: outputPath) {
            do {
                try fileManager.createDirectory(atPath: outputPath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                aggregationStatusMessage = "出力ディレクトリを作成できませんでした: \(error.localizedDescription)"
                isAggregatingLinks = false
                return
            }
        }

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
                .components(separatedBy: "\n")
                .suffix(10)
                .joined(separator: "\n")

        let logFilePath = await MainActor.run {
            self.writeAggregationLogFileIfNeeded(log: combinedLog, outputPath: outputPath)
        }

            let status = process.terminationStatus == 0
            await MainActor.run {
                self.aggregationLog = combinedLog
                if status {
                    self.aggregationStatusMessage = "集計が完了しました"
                } else {
                    self.aggregationStatusMessage = "集計に失敗しました (終了コード: \(process.terminationStatus))"
                }
                self.isAggregatingLinks = false
                self.lastAggregationLogFile = logFilePath
                if let logFilePath {
                    self.prependStatusMessage("集計ログを保存しました: \(logFilePath)")
                }
            }
        }
    }

    func refreshAggregatorScriptLocation() {
        aggregatorScriptLocation = locateAggregatorScript()
    }

    func chooseLinksInputDirectory() {
        guard let url = openDirectoryPanel(initialPath: linksInputDirectory) else { return }
        let path = url.path
        linksInputDirectory = path
        UserDefaults.standard.set(path, forKey: Self.linksInputDirectoryKey)
        updateLinkOutputEnvironment()
    }

    func chooseLinksAggregatedDirectory() {
        guard let url = openDirectoryPanel(initialPath: linksAggregatedDirectory) else { return }
        let path = url.path
        linksAggregatedDirectory = path
        UserDefaults.standard.set(path, forKey: Self.linksAggregatedDirectoryKey)
        updateLinkOutputEnvironment()
    }

    func startMarketWatchCrawl() {
        guard !marketWatchIsCrawling else { return }
        marketWatchTask?.cancel()
        marketWatchArticles.removeAll()
        let marketWatchReference = marketWatchReferenceURL(startPage: marketWatchStartPage, feed: marketWatchFeed)
        let knownMarketWatchLinks = loadKnownLinks(
            siteId: marketWatchFeed.siteIdentifier,
            referencePageURL: marketWatchReference
        )
        if !knownMarketWatchLinks.isEmpty {
            marketWatchSeenArticleIds = knownMarketWatchLinks
            marketWatchKnownCount = knownMarketWatchLinks.count
            prependStatusMessage("既存 MarketWatch リンクを \(marketWatchKnownCount) 件読み込みました")
        } else if !marketWatchSeenArticleIds.isEmpty {
            marketWatchKnownCount = marketWatchSeenArticleIds.count
            prependStatusMessage("既存 MarketWatch リンクはキャッシュから \(marketWatchKnownCount) 件保持されています")
        } else {
            marketWatchSeenArticleIds.removeAll()
            marketWatchKnownCount = 0
            prependStatusMessage("既存 MarketWatch リンクは見つかりませんでした")
        }
        marketWatchFetchCount = 0
        marketWatchNextLongPause = Int.random(in: 10...20)
        marketWatchErrorMessage = nil
        marketWatchLastPageFetched = nil
        marketWatchLastFetchFeed = nil
        marketWatchSessionNewCount = 0
        marketWatchSessionDuplicateCount = 0
        marketWatchIsCrawling = true
        marketWatchRetryCount = 0
        let feed = marketWatchFeed
        prependStatusMessage("\(feedDisplayName(for: feed)) クロールを開始します (開始ページ: \(marketWatchStartPage), ページ数: \(marketWatchMaxPages))")
        updateLiveStatus("\(feedDisplayName(for: feed)) ページ \(marketWatchStartPage) の取得を準備中")

        let startPage = marketWatchStartPage
        let maxPages = marketWatchMaxPages
        let selectedFeed = feed

        marketWatchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.safariController.prepareWorkerWindow()
                try await self.safariController.ensureWorkerWindowFrontmost(maxAttempts: max(self.activationRetryLimit, 1))
            } catch {
                self.marketWatchIsCrawling = false
                self.marketWatchErrorMessage = "Safari ウィンドウ準備に失敗しました: \(error.localizedDescription)"
                return
            }
            await self.crawlMarketWatch(startPage: startPage, maxPages: maxPages, feed: selectedFeed)
        }
    }

    func stopMarketWatchCrawl() {
        guard marketWatchIsCrawling else { return }
        marketWatchIsCrawling = false
        marketWatchTask?.cancel()
        marketWatchTask = nil
        let feed = marketWatchLastFetchFeed ?? marketWatchFeed
        prependStatusMessage("\(feedDisplayName(for: feed)) クロールを停止しました")
        updateLiveStatus("\(feedDisplayName(for: feed)) クロールを停止しました")
    }

    func startBloombergCrawl() {
        guard !bloombergIsCrawling else { return }
        bloombergTask?.cancel()
        bloombergArticles.removeAll()
        let feedsToProcess: [BloombergFeedOption]
        if bloombergCrossFeedEnabled {
            feedsToProcess = BloombergFeedOption.allCases
            prependStatusMessage("Bloomberg 全カテゴリ横断モードを開始します (\(feedsToProcess.count) フィード)")
            updateLiveStatus("Bloomberg 横断モードを開始しました")
        } else {
            feedsToProcess = [bloombergFeed]
        }
        bloombergFetchCount = 0
        bloombergNextLongPause = Int.random(in: 10...20)
        bloombergErrorMessage = nil
        bloombergLastOffsetFetched = nil
        bloombergLastFetchFeed = nil
        bloombergSessionNewCount = 0
        bloombergSessionDuplicateCount = 0
        bloombergRetryCount = 0
        bloombergIsCrawling = true

        let initialOffset = bloombergCrossFeedEnabled ? 0 : max(0, bloombergStartOffset)
        let maxPages = bloombergMaxPages
        if !bloombergCrossFeedEnabled, let feed = feedsToProcess.first {
            let message = "\(bloombergFeedDisplayName(for: feed)) クロールを開始します (開始オフセット: \(initialOffset), ページ数: \(maxPages))"
            prependStatusMessage(message)
            updateLiveStatus("\(bloombergFeedDisplayName(for: feed)) オフセット \(initialOffset) の取得を準備中")
        } else if bloombergCrossFeedEnabled {
            updateLiveStatus("Bloomberg 横断モード: 初期化中")
        }
        let stopOnDuplicate = bloombergCrossFeedEnabled ? true : haltOnDuplicate

        bloombergTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.bloombergIsCrawling = false
                self.bloombergTask = nil
                self.bloombergStartOffset = max(0, self.bloombergResumeOffset)
            }
            do {
                try await self.safariController.prepareWorkerWindow()
                try await self.safariController.ensureWorkerWindowFrontmost(maxAttempts: max(self.activationRetryLimit, 1))
            } catch {
                self.bloombergIsCrawling = false
                self.bloombergErrorMessage = "Safari ウィンドウ準備に失敗しました: \(error.localizedDescription)"
                self.updateLiveStatus("Bloomberg クロールを開始できませんでした: \(error.localizedDescription)")
                return
            }
            for (index, feed) in feedsToProcess.enumerated() {
                if Task.isCancelled || !self.bloombergIsCrawling { break }
                let startOffset = index == 0 ? initialOffset : 0
                self.prepareBloombergFeedStart(feed: feed, startOffset: startOffset)
                if self.bloombergCrossFeedEnabled {
                    self.prependStatusMessage("Bloomberg 横断モード: \(self.bloombergFeedDisplayName(for: feed)) を処理します (開始オフセット: \(startOffset))")
                    self.updateLiveStatus("Bloomberg 横断モード: \(self.bloombergFeedDisplayName(for: feed)) を処理中")
                } else if index > 0 {
                    self.prependStatusMessage("\(self.bloombergFeedDisplayName(for: feed)) クロールを開始します (開始オフセット: \(startOffset), ページ数: \(maxPages))")
                    self.updateLiveStatus("\(self.bloombergFeedDisplayName(for: feed)) オフセット \(startOffset) の取得を準備中")
                }
                let reason = await self.crawlBloomberg(startOffset: startOffset, maxPages: maxPages, feed: feed, stopOnDuplicate: stopOnDuplicate)
                switch reason {
                case .completed, .unexpectedResponse:
                    self.updateLiveStatus("\(self.bloombergFeedDisplayName(for: feed)) クロールが完了しました")
                    continue
                case .duplicateStop:
                    self.updateLiveStatus("\(self.bloombergFeedDisplayName(for: feed)) 重複検出のため終了しました")
                    continue
                case .cancelled, .error:
                    self.updateLiveStatus("\(self.bloombergFeedDisplayName(for: feed)) クロールが中断されました")
                    return
                }
            }
            self.updateLiveStatus("Bloomberg クロールを完了しました")
        }
    }

    func stopBloombergCrawl() {
        guard bloombergIsCrawling else { return }
        bloombergIsCrawling = false
        bloombergTask?.cancel()
        bloombergTask = nil
        let feed = bloombergLastFetchFeed ?? bloombergFeed
        prependStatusMessage("\(bloombergFeedDisplayName(for: feed)) クロールを停止しました")
        updateLiveStatus("\(bloombergFeedDisplayName(for: feed)) クロールを停止しました")
    }

    func revealLinksInputDirectory() {
        revealDirectory(at: linksInputDirectory)
    }

    func revealLinksAggregatedDirectory() {
        revealDirectory(at: linksAggregatedDirectory)
    }

    func revealLastAggregationLogFile() {
        guard let path = lastAggregationLogFile else { return }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openURLInSafari(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshBloombergParquetSources() {
        let directories = [linksInputDirectory, linksAggregatedDirectory]
        var found: Set<String> = []
        let fileManager = FileManager.default

        for path in directories {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let directoryURL = URL(fileURLWithPath: trimmed, isDirectory: true)
            guard let contents = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for url in contents where url.pathExtension.lowercased() == "parquet" {
                let name = url.lastPathComponent.lowercased()
                if name.contains("bloomberg") {
                    found.insert(url.path)
                }
            }
        }

        let sorted = found.sorted { lhs, rhs in
            let l = URL(fileURLWithPath: lhs).lastPathComponent
            let r = URL(fileURLWithPath: rhs).lastPathComponent
            if l == r { return lhs < rhs }
            return l < r
        }

        bloombergParquetFiles = sorted
        if let selected = bloombergSelectedParquetFile, sorted.contains(selected) {
            bloombergSelectedParquetFile = selected
        } else {
            bloombergSelectedParquetFile = sorted.first
        }
    }

    func loadBloombergBodySources() {
        bloombergBodyLoadError = nil
        bloombergBodySourceURLs = []
        guard let selected = bloombergSelectedParquetFile else {
            bloombergBodyLoadError = "パーケットファイルが選択されていません"
            return
        }

        let parquetURL = URL(fileURLWithPath: selected)
        let knownURL = parquetURL.appendingPathExtension("known")
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: knownURL.path) else {
            bloombergBodyLoadError = "\(knownURL.lastPathComponent) が見つかりません。最新のクロールを実行してください。"
            return
        }

        do {
            let content = try String(contentsOf: knownURL, encoding: .utf8)
            let lines = content
                .split(whereSeparator: { $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            bloombergBodySourceURLs = lines
            Logger.shared.debug("Bloomberg URL を \(lines.count) 件読み込みました (\(knownURL.lastPathComponent))")
            if lines.isEmpty {
                bloombergBodyLoadError = "URL が見つかりませんでした"
            }
        } catch {
            bloombergBodyLoadError = "URL の読み込みに失敗しました: \(error.localizedDescription)"
        }
    }

    func openBloombergPreviewInSafari() {
        guard !bloombergPreviewLoading else { return }
        guard let urlString = bloombergBodySourceURLs.first, !urlString.isEmpty else {
            bloombergBodyLoadError = "プレビューする URL がありません"
            return
        }

        Logger.shared.debug("Bloomberg プレビュー URL を Safari で開きます: \(urlString)")
        bloombergPreviewLoading = true
        bloombergBodyLoadError = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.bloombergPreviewLoading = false }
            let result = await self.runSafariReaderScript(with: urlString, useReaderMode: self.bloombergUseReaderMode)
            switch result {
            case .success(let message):
                Logger.shared.debug("Reader script output: \(message)")
                if let html = await self.captureBloombergReaderHTML() {
                    Logger.shared.debug("Reader HTML captured (\(html.count) chars)")
                    self.saveBloombergPreviewHTML(html)
                    self.updateLiveStatus("Bloomberg 記事HTMLを取得しました (\(html.count) 文字)")
                } else {
                    let errorMessage = "Reader HTML の取得に失敗しました"
                    self.bloombergBodyLoadError = errorMessage
                    Logger.shared.error(errorMessage)
                }
            case .failure(let error):
                self.bloombergBodyLoadError = error.localizedDescription
                Logger.shared.error("Reader script failed: \(error.localizedDescription)")
            }
        }
    }

    func manuallyEnableReaderMode() {
        Logger.shared.debug("手動リーダーモード適用を試みます")
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let urlString = self.bloombergBodySourceURLs.first, !urlString.isEmpty else {
                self.bloombergBodyLoadError = "URL がないため手動適用できません"
                return
            }
            let result = await self.runSafariReaderScript(with: urlString, useReaderMode: true)
            switch result {
            case .success(let message):
                Logger.shared.debug("Reader script output (manual): \(message)")
            case .failure(let error):
                self.bloombergBodyLoadError = error.localizedDescription
                Logger.shared.error("Reader script failed (manual): \(error.localizedDescription)")
            }
        }
    }

    private enum ReaderScriptResult {
        case success(String)
        case failure(Error)
    }

    private func runSafariReaderScript(with url: String, useReaderMode: Bool) async -> ReaderScriptResult {
        guard let scriptURL = Bundle.module.url(forResource: "SafariReader", withExtension: "applescript") else {
            return .failure(NSError(domain: "ReaderScript", code: -1, userInfo: [NSLocalizedDescriptionKey: "SafariReader.applescript が見つかりません"]))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [scriptURL.path, url, useReaderMode ? "reader" : "plain"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

            if process.terminationStatus == 0 {
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return .success(trimmed)
                } else {
                    return .failure(NSError(domain: "ReaderScript", code: -4, userInfo: [NSLocalizedDescriptionKey: "Reader script returned empty output"]))
                }
            } else {
                let message = output.isEmpty ? "osascript が異常終了しました (コード \(process.terminationStatus))" : output
                return .failure(NSError(domain: "ReaderScript", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message]))
            }
        } catch {
            return .failure(error)
        }
    }

    @MainActor
    private func crawlMarketWatch(startPage: Int, maxPages: Int, feed: MarketWatchFeedOption) async {
        defer {
            marketWatchIsCrawling = false
            marketWatchTask = nil
        }

        var offset = 0
        while offset < maxPages {
            if Task.isCancelled || !marketWatchIsCrawling {
                updateLiveStatus("\(feedDisplayName(for: feed)) クロールはキャンセルされました")
                break
            }
            let pageNumber = startPage + offset
            let urlString = "https://www.marketwatch.com/latest-news?pageNumber=\(pageNumber)&position=\(feed.positionQueryValue)&partial=true"

            updateLiveStatus("\(feedDisplayName(for: feed)) ページ \(pageNumber) を取得中")
            prependStatusMessage("\(feedDisplayName(for: feed)) ページ \(pageNumber) を読み込み中")

            do {
                try await openMarketWatchPage(urlString: urlString, pageNumber: pageNumber)

                let snapshots = safariController.collectMarketWatchLinks(limit: 400)
                let articles = snapshots.map { snapshot in
                    MarketWatchArticle(
                        id: snapshot.href,
                        url: snapshot.href,
                        headline: snapshot.text,
                        publishedAt: snapshot.publishedAt,
                        pageNumber: pageNumber,
                        feed: feed
                    )
                }
                let newArticles = articles.filter { article in
                    marketWatchSeenArticleIds.insert(article.url).inserted
                }
                let duplicateDetected = newArticles.count < articles.count

                if !newArticles.isEmpty {
                    marketWatchArticles.append(contentsOf: newArticles)
                    marketWatchArticles.sort { lhs, rhs in
                        if lhs.pageNumber == rhs.pageNumber {
                            return lhs.url < rhs.url
                        }
                        return lhs.pageNumber < rhs.pageNumber
                    }
                    if marketWatchArticles.count > 10 {
                        marketWatchArticles = Array(marketWatchArticles.suffix(10))
                    }
                    prependStatusMessage("\(feedDisplayName(for: feed)) ページ \(pageNumber) から \(newArticles.count) 件のリンクを取得しました")
                    persistMarketWatchLinks(newArticles, pageURL: urlString, feed: feed)
                    marketWatchSessionNewCount += newArticles.count
                    marketWatchSessionDuplicateCount += (articles.count - newArticles.count)
                    updateLiveStatus("\(feedDisplayName(for: feed)) ページ \(pageNumber) の処理完了 (新規 \(newArticles.count) 件)")
                    if haltOnDuplicate && duplicateDetected {
                        prependStatusMessage("重複判定により MarketWatch クロールを停止します")
                        updateLiveStatus("\(feedDisplayName(for: feed)) 重複検出のためクロールを停止しました")
                        break
                    }
                } else {
                    prependStatusMessage("\(feedDisplayName(for: feed)) ページ \(pageNumber) で新規リンクはありませんでした")
                    updateLiveStatus("\(feedDisplayName(for: feed)) ページ \(pageNumber) は新規リンクなし")
                    if haltOnDuplicate {
                        prependStatusMessage("重複判定により MarketWatch クロールを停止します")
                        updateLiveStatus("\(feedDisplayName(for: feed)) 重複検出のためクロールを停止しました")
                        break
                    }
                }

                marketWatchLastPageFetched = pageNumber
                marketWatchLastFetchFeed = feed
                marketWatchRetryCount = 0

                marketWatchFetchCount += 1
                var delay = randomInterval(mean: shortSleepMean, variation: shortSleepVariation)
                if longSleepEnabled, marketWatchFetchCount >= marketWatchNextLongPause {
                    let extra = randomInterval(mean: longSleepMean, variation: longSleepVariation)
                    delay += extra
                    prependStatusMessage("\(feedDisplayName(for: feed)) クロールで \(String(format: "%.1f", extra)) 秒の長い休止を挿入します")
                    marketWatchFetchCount = 0
                    marketWatchNextLongPause = Int.random(in: 10...20)
                }

                updateLiveStatus("\(feedDisplayName(for: feed)) 次のページまで \(String(format: "%.1f", delay)) 秒待機中")
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    updateLiveStatus("\(feedDisplayName(for: feed)) クロール待機がキャンセルされました")
                    break
                }

                offset += 1
            } catch {
                marketWatchErrorMessage = error.localizedDescription
                prependStatusMessage("\(feedDisplayName(for: feed)) ページ \(pageNumber) の取得に失敗しました: \(error.localizedDescription)")
                if autoRetryEnabled, marketWatchRetryCount < autoRetryMaxAttempts {
                    marketWatchRetryCount += 1
                    let remaining = autoRetryMaxAttempts - marketWatchRetryCount
                    let waitSeconds = max(1.0, autoRetryDelaySeconds)
                    prependStatusMessage("MarketWatch 再開まで \(String(format: "%.1f", waitSeconds)) 秒待機します (残り \(remaining))")
                    updateLiveStatus("\(feedDisplayName(for: feed)) 再試行まで \(String(format: "%.1f", waitSeconds)) 秒待機中 (残り \(remaining))")
                    do {
                        try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                    } catch {
                        updateLiveStatus("\(feedDisplayName(for: feed)) 再試行待機がキャンセルされました")
                        break
                    }
                    continue
                }
                updateLiveStatus("\(feedDisplayName(for: feed)) クロールを終了します (エラー)")
                break
            }
        }

        prependStatusMessage("\(feedDisplayName(for: feed)) クロールを完了しました")
        updateLiveStatus("\(feedDisplayName(for: feed)) クロールを完了しました")
    }

    private func openMarketWatchPage(urlString: String, pageNumber: Int) async throws {
        do {
            try await safariController.ensureWorkerWindowFrontmost(maxAttempts: max(activationRetryLimit, 1))
        } catch {
            throw NSError(domain: "MarketWatch", code: -3, userInfo: [NSLocalizedDescriptionKey: "Safari を前面にできませんでした"])
        }

        let escapedURL = urlString.replacingOccurrences(of: "'", with: "%27")
        safariController.executeJavaScript("window.location.href = '" + escapedURL + "'")

        var matched = false
        for _ in 0..<60 {
            if Task.isCancelled || !marketWatchIsCrawling { return }
            try await Task.sleep(nanoseconds: 500_000_000)
            if let current = safariController.currentURL(), current.contains("pageNumber=\(pageNumber)") {
                matched = true
                break
            }
        }

        if !matched {
            throw NSError(domain: "MarketWatch", code: -4, userInfo: [NSLocalizedDescriptionKey: "ページ読み込みがタイムアウトしました"])
        }

        let dwell = Double.random(in: 1.5...3.0)
        try await Task.sleep(nanoseconds: UInt64(dwell * 1_000_000_000))
    }

    private func feedDisplayName(for feed: MarketWatchFeedOption) -> String {
        "Dow Jones (\(feed.feedLabel))"
    }

    private func persistMarketWatchLinks(_ articles: [MarketWatchArticle], pageURL: String, feed: MarketWatchFeedOption) {
        guard !articles.isEmpty else { return }
        let snapshots = articles.map {
            StrategyLinkSnapshot(
                href: $0.url,
                text: $0.headline,
                publishedAt: $0.publishedAt
            )
        }
        Task { [weak self] in
            guard let self else { return }
            await self.strategyClient.recordLinks(siteId: feed.siteIdentifier, pageURL: pageURL, links: snapshots)
        }
    }

    @MainActor
    private func crawlBloomberg(startOffset: Int, maxPages: Int, feed: BloombergFeedOption, stopOnDuplicate: Bool) async -> BloombergCrawlEndReason {
        var currentOffset = max(0, startOffset)
        bloombergResumeOffset = currentOffset
        var endReason: BloombergCrawlEndReason = .completed

        for _ in 0..<maxPages {
            if Task.isCancelled || !bloombergIsCrawling {
                endReason = .cancelled
                break
            }

            let feedName = bloombergFeedDisplayName(for: feed)
            let apiURL = "https://www.bloomberg.com/lineup-next/api/paginate?id=archive_story_list&page=\(feed.pageParameter)&offset=\(currentOffset)&variation=archive&type=lineup_content"
            updateLiveStatus("\(feedName) オフセット \(currentOffset) を取得中")
            prependStatusMessage("\(feedName) オフセット \(currentOffset) を取得中")

            do {
                try await ensureSafariFrontmostForBloomberg()

                guard safariController.setDocumentURL(apiURL) else {
                    throw NSError(domain: "Bloomberg", code: -20, userInfo: [NSLocalizedDescriptionKey: "URL を設定できませんでした"])
                }

                var matched = false
                for _ in 0..<60 {
                    if Task.isCancelled || !bloombergIsCrawling { return .cancelled }
                    try await Task.sleep(nanoseconds: 250_000_000)
                    if let current = safariController.currentURL(),
                       current.contains("page=\(feed.pageParameter)") && current.contains("offset=\(currentOffset)") {
                        matched = true
                        break
                    }
                }

                if !matched {
                    throw NSError(domain: "Bloomberg", code: -21, userInfo: [NSLocalizedDescriptionKey: "ページ読み込みがタイムアウトしました"])
                }

                if !(await safariController.waitForDocumentReadyState(timeout: 2.0)) {
                    throw NSError(domain: "Bloomberg", code: -22, userInfo: [NSLocalizedDescriptionKey: "API レスポンスを取得できませんでした"])
                }

                var rawBody: String? = nil
                let maxBodyChecks = 40
                for attempt in 0..<maxBodyChecks {
                    if let body = safariController.evaluateJavaScriptReturningString("document.body.innerText")?.trimmed(), !body.isEmpty {
                        if bloombergLastRawResponse == nil || body != bloombergLastRawResponse {
                            rawBody = body
                            break
                        }
                    }
                    let backoff = min(1.0, 0.2 + Double(attempt) * 0.05)
                    try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                }

                guard let rawBody = rawBody else {
                    throw NSError(domain: "Bloomberg", code: -23, userInfo: [NSLocalizedDescriptionKey: "新しい API レスポンスを確認できませんでした"])
                }
                let articles = parseBloombergArticles(from: rawBody, offset: currentOffset, feed: feed)
                if !articles.isEmpty {
                    bloombergLastRawResponse = rawBody
                }
                let newArticles = articles.filter { article in
                    let key = article.url
                    guard !key.isEmpty, bloombergSeenArticleIds.insert(key).inserted else { return false }
                    if !article.id.isEmpty {
                        bloombergSeenArticleIds.insert(article.id)
                    }
                    return true
                }
                let duplicateDetected = newArticles.count < articles.count

                if articles.isEmpty {
                    let warning = "Bloomberg 側が想定外の応答を返しました。Safari で手動認証後に再試行してください。"
                    prependStatusMessage(warning)
                    updateLiveStatus("\(feedName) 想定外の応答を検出しました")
                    bloombergErrorMessage = "Bloomberg unexpected response"
                    bloombergResumeOffset = currentOffset
                    if autoRetryEnabled, bloombergRetryCount < autoRetryMaxAttempts {
                        bloombergRetryCount += 1
                        let remaining = autoRetryMaxAttempts - bloombergRetryCount
                        let waitSeconds = max(1.0, autoRetryDelaySeconds)
                        prependStatusMessage("Bloomberg 再開まで \(String(format: "%.1f", waitSeconds)) 秒待機します (残り \(remaining))")
                        updateLiveStatus("\(feedName) 再試行まで \(String(format: "%.1f", waitSeconds)) 秒待機中 (残り \(remaining))")
                        do {
                            try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                        } catch {
                            updateLiveStatus("\(feedName) 再試行待機がキャンセルされました")
                            break
                        }
                        continue
                    } else if autoRetryEnabled {
                        prependStatusMessage("Bloomberg 自動再開の上限に達しました。Safari で手動対応後に再試行してください。")
                        updateLiveStatus("\(feedName) 自動再開の上限に達しました")
                    }
                    break
                }

                if !newArticles.isEmpty {
                    bloombergArticles.append(contentsOf: newArticles)
                    bloombergArticles.sort { lhs, rhs in
                        if lhs.offset == rhs.offset {
                            return (lhs.headline ?? lhs.url) < (rhs.headline ?? rhs.url)
                        }
                        return lhs.offset < rhs.offset
                    }
                    if bloombergArticles.count > 10 {
                        bloombergArticles = Array(bloombergArticles.suffix(10))
                    }
                    prependStatusMessage("\(bloombergFeedDisplayName(for: feed)) オフセット \(currentOffset) から \(newArticles.count) 件のリンクを取得しました")
                    persistBloombergLinks(newArticles, pageURL: apiURL, feed: feed)

                    bloombergLastOffsetFetched = currentOffset
                    bloombergLastFetchFeed = feed
                    bloombergErrorMessage = nil
                    bloombergSessionNewCount += newArticles.count
                    bloombergSessionDuplicateCount += (articles.count - newArticles.count)
                    bloombergRetryCount = 0
                    updateLiveStatus("\(feedName) オフセット \(currentOffset) の処理完了 (新規 \(newArticles.count) 件)")

                    if stopOnDuplicate && duplicateDetected {
                        prependStatusMessage("重複判定により Bloomberg クロールを停止します")
                        bloombergResumeOffset = currentOffset
                        endReason = .duplicateStop
                        updateLiveStatus("\(feedName) 重複検出のためクロールを停止しました")
                        break
                    }

                    bloombergResumeOffset = currentOffset + newArticles.count
                    currentOffset = bloombergResumeOffset
                } else {
                    prependStatusMessage("\(bloombergFeedDisplayName(for: feed)) オフセット \(currentOffset) で新規リンクはありませんでした")
                    bloombergLastOffsetFetched = currentOffset
                    bloombergLastFetchFeed = feed
                    bloombergResumeOffset = currentOffset
                    updateLiveStatus("\(feedName) オフセット \(currentOffset) は新規リンクなし")
                    if stopOnDuplicate {
                        prependStatusMessage("重複判定により Bloomberg クロールを停止します")
                        endReason = .duplicateStop
                        updateLiveStatus("\(feedName) 重複検出のためクロールを停止しました")
                        break
                    }
                    if articles.isEmpty {
                        bloombergErrorMessage = "Bloomberg unexpected response"
                        if autoRetryEnabled, bloombergRetryCount < autoRetryMaxAttempts {
                            bloombergRetryCount += 1
                            let remaining = autoRetryMaxAttempts - bloombergRetryCount
                            let waitSeconds = max(1.0, autoRetryDelaySeconds)
                            prependStatusMessage("Bloomberg 再開まで \(String(format: "%.1f", waitSeconds)) 秒待機します (残り \(remaining))")
                            updateLiveStatus("\(feedName) 再試行まで \(String(format: "%.1f", waitSeconds)) 秒待機中 (残り \(remaining))")
                            do {
                                try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                            } catch {
                                endReason = .cancelled
                                updateLiveStatus("\(feedName) 再試行待機がキャンセルされました")
                                break
                            }
                            continue
                        } else {
                            endReason = .unexpectedResponse
                            updateLiveStatus("\(feedName) 想定外の応答により終了しました")
                            break
                        }
                    }
                    let fallbackStep = max(articles.count, 10)
                    currentOffset += fallbackStep
                    bloombergResumeOffset = currentOffset
                    continue
                }
            } catch {
                bloombergErrorMessage = error.localizedDescription
                prependStatusMessage("\(bloombergFeedDisplayName(for: feed)) オフセット \(currentOffset) の取得に失敗しました: \(error.localizedDescription)")
                updateLiveStatus("\(feedName) オフセット \(currentOffset) の取得に失敗しました")
                bloombergLastOffsetFetched = currentOffset
                bloombergResumeOffset = currentOffset
                if autoRetryEnabled, bloombergRetryCount < autoRetryMaxAttempts {
                    bloombergRetryCount += 1
                    let remaining = autoRetryMaxAttempts - bloombergRetryCount
                    let waitSeconds = max(1.0, autoRetryDelaySeconds)
                    prependStatusMessage("Bloomberg 再開まで \(String(format: "%.1f", waitSeconds)) 秒待機します (残り \(remaining))")
                    updateLiveStatus("\(feedName) 再試行まで \(String(format: "%.1f", waitSeconds)) 秒待機中 (残り \(remaining))")
                    do {
                        try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                    } catch {
                        endReason = .cancelled
                        updateLiveStatus("\(feedName) 再試行待機がキャンセルされました")
                        break
                    }
                    continue
                }
                endReason = Task.isCancelled || !bloombergIsCrawling ? .cancelled : .error
                if endReason == .cancelled {
                    updateLiveStatus("\(feedName) クロールがキャンセルされました")
                } else {
                    updateLiveStatus("\(feedName) クロールを終了します (エラー)")
                }
                break
            }

            bloombergFetchCount += 1
            var delay = randomInterval(mean: shortSleepMean, variation: shortSleepVariation)
            if longSleepEnabled, bloombergFetchCount >= bloombergNextLongPause {
                let extra = randomInterval(mean: longSleepMean, variation: longSleepVariation)
                delay += extra
                prependStatusMessage("\(bloombergFeedDisplayName(for: feed)) クロールで \(String(format: "%.1f", extra)) 秒の長い休止を挿入します")
                bloombergFetchCount = 0
                bloombergNextLongPause = Int.random(in: 10...20)
            }

            updateLiveStatus("\(feedName) 次のオフセットまで \(String(format: "%.1f", delay)) 秒待機中")
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                endReason = .cancelled
                updateLiveStatus("\(feedName) 待機がキャンセルされました")
                break
            }
        }

        let finishedFeedName = bloombergFeedDisplayName(for: feed)
        prependStatusMessage("\(finishedFeedName) クロールを完了しました")
        updateLiveStatus("\(finishedFeedName) クロールを完了しました")
        return endReason
    }

    private func prepareBloombergFeedStart(feed: BloombergFeedOption, startOffset: Int) {
        let referenceURL = bloombergReferenceURL(offset: startOffset, feed: feed)
        let knownBloombergLinks = loadKnownLinks(
            siteId: feed.siteIdentifier,
            referencePageURL: referenceURL
        )

        if !knownBloombergLinks.isEmpty {
            bloombergSeenArticleIds = knownBloombergLinks
            bloombergKnownCount = knownBloombergLinks.count
            prependStatusMessage("\(bloombergFeedDisplayName(for: feed)) の既存リンクを \(bloombergKnownCount) 件読み込みました")
        } else if !bloombergCrossFeedEnabled, !bloombergSeenArticleIds.isEmpty {
            bloombergKnownCount = bloombergSeenArticleIds.count
            prependStatusMessage("\(bloombergFeedDisplayName(for: feed)) の既存リンクはキャッシュから \(bloombergKnownCount) 件保持されています")
        } else {
            bloombergSeenArticleIds.removeAll()
            bloombergKnownCount = 0
            prependStatusMessage("\(bloombergFeedDisplayName(for: feed)) の既存リンクは見つかりませんでした")
        }

        bloombergLastRawResponse = nil
        bloombergResumeOffset = max(0, startOffset)
    }

    private func ensureSafariFrontmostForBloomberg() async throws {
        do {
            try await safariController.ensureWorkerWindowFrontmost(maxAttempts: max(activationRetryLimit, 1))
        } catch {
            throw NSError(domain: "Bloomberg", code: -12, userInfo: [NSLocalizedDescriptionKey: "Safari を前面にできませんでした"])
        }
    }

    private func bloombergFeedDisplayName(for feed: BloombergFeedOption) -> String {
        feed.displayName
    }

    private func persistBloombergLinks(_ articles: [BloombergArticle], pageURL: String, feed: BloombergFeedOption) {
        guard !articles.isEmpty else { return }
        let snapshots = articles.map { StrategyLinkSnapshot(href: $0.url, text: $0.headline, publishedAt: $0.publishedAt) }
        Task { [weak self] in
            guard let self else { return }
            await self.strategyClient.recordLinks(siteId: feed.siteIdentifier, pageURL: pageURL, links: snapshots)
        }
    }

    private func loadKnownLinks(siteId: String, referencePageURL: String) -> Set<String> {
        guard !siteId.isEmpty, !referencePageURL.isEmpty else { return [] }

        let fileKey = parquetFileKey(siteId: siteId, pageURL: referencePageURL)
        let directory = URL(fileURLWithPath: linksInputDirectory)
        let candidateNames = [
            fileKey + ".parquet.known",
            fileKey + ".known"
        ]

        for name in candidateNames {
            let knownURL = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: knownURL.path) {
                do {
                    let content = try String(contentsOf: knownURL, encoding: .utf8)
                    let lines = content
                        .split(whereSeparator: { $0.isNewline })
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    return Set(lines)
                } catch {
                    prependStatusMessage("既存リンクの読み込みに失敗しました: \(error.localizedDescription)")
                    return []
                }
            }
        }

        return []
    }

    private func parquetFileKey(siteId: String, pageURL: String) -> String {
        let sanitizedSite = sanitizeFileName(siteId.isEmpty ? "default" : siteId)

        guard let url = URL(string: pageURL) else { return sanitizedSite }
        let segments = url.path.split(separator: "/").compactMap { segment -> String? in
            let sanitized = sanitizeFileName(String(segment))
            return sanitized.isEmpty ? nil : sanitized
        }

        if let firstSegment = segments.first {
            return sanitizedSite + "_" + firstSegment
        }

        return sanitizedSite
    }

    private func sanitizeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let filtered = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let sanitized = String(filtered)
        if sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "default"
        }
        return sanitized
    }

    private func randomInterval(mean: Double, variation: Double) -> Double {
        let safeMean = max(0.0, mean)
        let safeVar = max(0.0, variation)
        let lower = max(0.1, safeMean - safeVar)
        let upper = max(lower + 0.1, safeMean + safeVar)
        return Double.random(in: lower...upper)
    }

    private func marketWatchReferenceURL(startPage: Int, feed: MarketWatchFeedOption) -> String {
        return "https://www.marketwatch.com/latest-news?pageNumber=\(startPage)&position=\(feed.positionQueryValue)&partial=true"
    }

    private func bloombergReferenceURL(offset: Int, feed: BloombergFeedOption) -> String {
        let normalizedOffset = max(0, offset)
        return "https://www.bloomberg.com/lineup-next/api/paginate?id=archive_story_list&page=\(feed.pageParameter)&offset=\(normalizedOffset)&variation=archive&type=lineup_content"
    }

    private func parseBloombergArticles(from rawBody: String, offset: Int, feed: BloombergFeedOption) -> [BloombergArticle] {
        guard let data = rawBody.data(using: .utf8) else {
            Logger.shared.debug("Bloomberg レスポンスをデータ化できませんでした")
            return []
        }

        do {
            let response = try JSONDecoder().decode(BloombergArchiveResponse.self, from: data)
            let items = response.archive_story_list?.items ?? []
            return items.compactMap { item -> BloombergArticle? in
                guard var url = item.url?.trimmed(), !url.isEmpty else { return nil }
                if !url.hasPrefix("http") {
                    url = "https://www.bloomberg.com" + url
                }

                let identifier = (item.id?.trimmed()).flatMap { $0.isEmpty ? nil : $0 } ?? url
                let headline = item.headline?.trimmed()
                let published = item.publishedAt?.trimmed()

                let normalizedHeadline = (headline?.isEmpty ?? true) ? nil : headline
                let normalizedPublished = (published?.isEmpty ?? true) ? nil : published

                return BloombergArticle(
                    id: identifier,
                    url: url,
                    headline: normalizedHeadline,
                    publishedAt: normalizedPublished,
                    offset: offset,
                    feed: feed
                )
            }
        } catch {
            Logger.shared.debug("Bloomberg JSON のデコードに失敗: \(error.localizedDescription)")
            return []
        }
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
        let fileManager = FileManager.default

        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let base = appSupport
                .appendingPathComponent("AutoBrowsing", isDirectory: true)
                .appendingPathComponent("links-output", isDirectory: true)
            let aggregated = base.appendingPathComponent("aggregated", isDirectory: true)
            do {
                try fileManager.createDirectory(at: aggregated, withIntermediateDirectories: true, attributes: nil)
                return (base.path, aggregated.path)
            } catch {
                print("[status-log] failed to prepare Application Support directories: \(error.localizedDescription)")
            }
        }

        let current = URL(fileURLWithPath: fileManager.currentDirectoryPath).standardized
        let rootCandidates: [URL] = [
            current.deletingLastPathComponent().appendingPathComponent("java-strategy"),
            current.appendingPathComponent("java-strategy")
        ]

        for root in rootCandidates {
            let linksOutput = root
                .appendingPathComponent("build")
                .appendingPathComponent("install")
                .appendingPathComponent("load-more-strategy")
                .appendingPathComponent("bin")
                .appendingPathComponent("links-output")
                .standardized
            if fileManager.fileExists(atPath: linksOutput.path) {
                let aggregated = linksOutput.appendingPathComponent("aggregated")
                return (linksOutput.path, aggregated.path)
            }
        }

        let fallbackRoot = current.appendingPathComponent("java-strategy")
        let fallbackInput = fallbackRoot
            .appendingPathComponent("build")
            .appendingPathComponent("install")
            .appendingPathComponent("load-more-strategy")
            .appendingPathComponent("bin")
            .appendingPathComponent("links-output")
            .standardized
        let fallbackOutput = fallbackInput.appendingPathComponent("aggregated")
        return (fallbackInput.path, fallbackOutput.path)
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

    private func updateLinkOutputEnvironment() {
        let path = linksInputDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        setenv("AUTO_BROWSING_LINKS_OUTPUT", path, 1)
        statusLogInitialized = false
        initializeStatusLogFileIfNeeded()
        prependStatusMessage("リンク出力先: \(path)")
    }

    private func writeAggregationLogFileIfNeeded(log: String, outputPath: String) -> String? {
        let trimmed = log.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let directory = URL(fileURLWithPath: outputPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            let destination = directory.appendingPathComponent("aggregation-log.txt")
            try trimmed.appending("\n").write(to: destination, atomically: true, encoding: .utf8)
            return destination.path
        } catch {
            aggregationStatusMessage = "ログ書き込みに失敗しました: \(error.localizedDescription)"
            return nil
        }
    }

    private func appendStatusLog(_ entry: String) {
        guard let directory = statusLogDirectory() else { return }
        initializeStatusLogFileIfNeeded()
        let fileURL = directory.appendingPathComponent("status-log.txt")

        do {
            let line = entry + "\n"
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    try data.write(to: fileURL, options: .atomic)
                }
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
        } catch {
            print("[status-log] failed to write log: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func captureBloombergReaderHTML(timeout: TimeInterval = 15.0, pollInterval: TimeInterval = 0.25) async -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        let javascript = "(() => { const doc = document.documentElement; if (!doc) { return ''; } return doc.outerHTML || ''; })()"

        while Date() < deadline {
            if let html = safariController.evaluateJavaScriptReturningString(javascript) {
                let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return html
                }
            }

            do {
                let interval = max(0.05, min(pollInterval, 1.0))
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                return nil
            }
        }

        return nil
    }

    private func saveBloombergPreviewHTML(_ html: String) {
        guard !html.isEmpty else { return }
        guard let directory = statusLogDirectory() else {
            Logger.shared.error("Bloomberg HTML 保存先の検出に失敗しました")
            return
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            let fileURL = directory.appendingPathComponent("bloomberg.html")
            try html.write(to: fileURL, atomically: true, encoding: .utf8)
            prependStatusMessage("Bloomberg プレビュー HTML を保存しました: \(fileURL.path)")
        } catch {
            Logger.shared.error("Bloomberg HTML の保存に失敗: \(error.localizedDescription)")
            prependStatusMessage("Bloomberg HTML の保存に失敗しました: \(error.localizedDescription)")
        }
    }

    private func statusLogDirectory() -> URL? {
        let preferred = linksAggregatedDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = linksInputDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = preferred.isEmpty ? fallback : preferred
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func initializeStatusLogFileIfNeeded() {
        guard !statusLogInitialized else { return }
        guard let directory = statusLogDirectory() else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            let fileURL = directory.appendingPathComponent("status-log.txt")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let archiveDirectory = directory.appendingPathComponent("status-log-archive", isDirectory: true)
                try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true, attributes: nil)

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                let timestamp = formatter.string(from: Date())
                let archiveURL = archiveDirectory.appendingPathComponent("status-log-\(timestamp).txt")

                do {
                    try FileManager.default.moveItem(at: fileURL, to: archiveURL)
                } catch {
                    print("[status-log] failed to archive existing log: \(error.localizedDescription)")
                }
            }

            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try "".write(to: fileURL, atomically: true, encoding: .utf8)
            }
            statusLogInitialized = true
        } catch {
            print("[status-log] failed to initialize: \(error.localizedDescription)")
        }
    }

    private func openDirectoryPanel(initialPath: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        if FileManager.default.fileExists(atPath: initialPath) {
            panel.directoryURL = URL(fileURLWithPath: initialPath)
        }
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return nil }
        return url
    }

    private func revealDirectory(at path: String) {
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                aggregationStatusMessage = "フォルダを作成できませんでした: \(error.localizedDescription)"
                return
            }
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AutomationStatus {
    case idle
    case running
}
