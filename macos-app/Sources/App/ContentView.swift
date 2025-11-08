import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    var body: some View {
        TabView {
            bloombergPanel
                .tabItem { Label("Bloomberg", systemImage: "globe") }
            marketWatchPanel
                .tabItem { Label("Dow Jones", systemImage: "newspaper") }
            otherSitesPanel
                .tabItem { Label("その他のサイト", systemImage: "list.bullet") }
            settingsPanel
                .tabItem { Label("設定", systemImage: "slider.horizontal.3") }
            aggregationPanel
                .tabItem { Label("データ集計", systemImage: "tray.full") }
            bodyFetchPanel
                .tabItem { Label("本文取得", systemImage: "doc.text") }
        }
        .frame(minWidth: 600, minHeight: 440)
        .onAppear {
            loadInitialData()
        }
    }

    private func loadInitialData() {
        appState.loadSiteProfiles()
        appState.refreshSafariState()
        appState.refreshBloombergParquetSources()
    }

    private func activateAppWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let keyWindow = NSApp.keyWindow {
            keyWindow.makeKeyAndOrderFront(nil)
        } else if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                configurationSection
                sleepSettingsBox
                retrySettingsBox
                linkStorageSection
                articleCountBox
                cleanupBox
                currentURLBox
                latestLinksBox
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }

    private var otherSitesPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                siteStatusSection
                automationControls
                statusBox
                statusHistoryBox
                retryStatusBox
                articleCountBox
                cleanupBox
                currentURLBox
                latestLinksBox
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Auto Browsing Controller")
                .font(.title2)
                .bold()
            Text("Safari のロードモアを自動化する実験用ツール")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var siteStatusSection: some View {
        GroupBox("現在のサイト") {
            VStack(alignment: .leading, spacing: 4) {
                if let site = appState.selectedSite {
                    Text(site.displayName)
                        .font(.callout)
                    Text("戦略: \(strategyDescription(for: site.strategy))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("サイトはまだ選択されていません")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var configurationSection: some View {
        GroupBox("動作設定") {
            VStack(alignment: .leading, spacing: 8) {
                Stepper(value: $appState.activationRetryLimit, in: 1...10) {
                    Text("Safari フォーカス再取得回数: \(appState.activationRetryLimit)")
                }
                Text("Safari が他のウィンドウに隠れた場合に再取得を試みる最大回数")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var linkStorageSection: some View {
        GroupBox("リンク保存設定") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("出力ディレクトリ")
                        .font(.subheadline)
                    Text(appState.linksInputDirectory)
                        .font(.caption)
                        .textSelection(.enabled)
                    HStack {
                        Button {
                            appState.chooseLinksInputDirectory()
                        } label: {
                            Label("指定", systemImage: "folder.badge.plus")
                        }
                        Button {
                            appState.revealLinksInputDirectory()
                        } label: {
                            Label("表示", systemImage: "folder")
                        }
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("集計出力ディレクトリ")
                        .font(.subheadline)
                    Text(appState.linksAggregatedDirectory)
                        .font(.caption)
                        .textSelection(.enabled)
                    HStack {
                        Button {
                            appState.chooseLinksAggregatedDirectory()
                        } label: {
                            Label("指定", systemImage: "folder.badge.plus")
                        }
                        Button {
                            appState.revealLinksAggregatedDirectory()
                        } label: {
                            Label("表示", systemImage: "folder")
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var automationControls: some View {
        GroupBox("操作") {
            HStack(spacing: 12) {
                Button(action: appState.startAutomation) {
                    Label("開始", systemImage: "play.fill")
                }
                .disabled(appState.automationStatus == .running)

                Button(action: appState.stopAutomation) {
                    Label("停止", systemImage: "stop.fill")
                }
                .disabled(appState.automationStatus == .idle)

                Spacer()

                if appState.safariDetected {
                    Label("Safari 検出", systemImage: "safari")
                        .foregroundColor(.green)
                } else {
                    Label("Safari 未検出", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
            }
        }
    }

    private var statusBox: some View {
        GroupBox("現在の状態") {
            Text(appState.liveStatusMessage.isEmpty ? "待機中" : appState.liveStatusMessage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusHistoryBox: some View {
        GroupBox("最近のログ") {
            if appState.statusMessages.isEmpty {
                Text("メッセージはまだありません")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(appState.statusMessages.enumerated()), id: \.offset) { _, message in
                        Text(message)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var articleCountBox: some View {
        GroupBox("記事カード数") {
            Text("\(appState.visibleArticleCount) 件")
                .font(.headline)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cleanupBox: some View {
        GroupBox("クリーンアップ結果") {
            VStack(alignment: .leading, spacing: 4) {
                if let error = appState.lastCleanupError, !error.isEmpty {
                    Text("エラー: \(error)")
                        .foregroundColor(.red)
                }
                if let removed = appState.lastCleanupRemovedCount {
                    Text("削除: \(removed) 件")
                        .monospacedDigit()
                } else {
                    Text("削除件数は未取得です")
                        .foregroundStyle(.secondary)
                }
                if let before = appState.lastCleanupVisibleBefore,
                   let limit = appState.lastCleanupLimit {
                    Text("処理前: \(before) 件 / 上限: \(limit) 件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let site = appState.lastCleanupSiteName {
                    Text("対象サイト: \(site)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var currentURLBox: some View {
        GroupBox("現在のURL") {
            if let url = appState.currentPageURL, !url.isEmpty {
                Text(url)
                    .font(.caption)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("URLはまだ取得されていません")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var latestLinksBox: some View {
        GroupBox("最新リンク") {
            if appState.lastLinks.isEmpty {
                Text("リンクはまだ取得されていません")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    let lastIndex = appState.lastLinks.count - 1
                    ForEach(Array(appState.lastLinks.enumerated()), id: \.offset) { index, link in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(link.href)
                                .font(.callout)
                                .textSelection(.enabled)
                            if let text = link.text, !text.isEmpty {
                                Text(text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if index != lastIndex {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var sleepSettingsBox: some View {
        GroupBox("スリープ設定") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("短期スリープ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("平均秒数")
                        Spacer()
                        TextField("平均", value: $appState.shortSleepMean, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("± 秒数")
                        Spacer()
                        TextField("変動", value: $appState.shortSleepVariation, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("長期スリープを有効にする", isOn: $appState.longSleepEnabled)
                    HStack {
                        Text("長期平均秒数")
                        Spacer()
                        TextField("平均", value: $appState.longSleepMean, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .disabled(!appState.longSleepEnabled)
                    }
                    HStack {
                        Text("長期 ± 秒数")
                        Spacer()
                        TextField("変動", value: $appState.longSleepVariation, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .disabled(!appState.longSleepEnabled)
                    }
                }
            }
        }
    }

    private var retrySettingsBox: some View {
        GroupBox("自動再開設定") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("自動再開を有効にする", isOn: $appState.autoRetryEnabled)
                HStack {
                    Text("最大試行回数")
                    Spacer()
                    Stepper(value: $appState.autoRetryMaxAttempts, in: 1...10) {
                        Text("\(appState.autoRetryMaxAttempts)")
                    }
                    .disabled(!appState.autoRetryEnabled)
                }
                HStack {
                    Text("再開までの待機秒数")
                    Spacer()
                    TextField("待機秒", value: $appState.autoRetryDelaySeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .disabled(!appState.autoRetryEnabled)
                }
            }
        }
    }

    private var retryStatusBox: some View {
        GroupBox("自動再開ステータス") {
            VStack(alignment: .leading, spacing: 4) {
                Text("MarketWatch リトライ: \(appState.autoRetryEnabled ? "\(appState.marketWatchRetryCount)" : "-")")
                Text("Bloomberg リトライ: \(appState.autoRetryEnabled ? "\(appState.bloombergRetryCount)" : "-")")
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metricBox(newCount: Int, duplicateCount: Int, knownCount: Int) -> some View {
        GroupBox("集計情報") {
            VStack(alignment: .leading, spacing: 4) {
                Text("今セッション追加: \(newCount) 件")
                Text("今セッション重複: \(duplicateCount) 件")
                Text("既知リンク合計: \(knownCount) 件")
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bloombergStatusSummary: String? {
        guard let offset = appState.bloombergLastOffsetFetched else { return nil }
        let feedLabel = appState.bloombergLastFetchFeed?.displayName ?? appState.bloombergFeed.displayName
        return "最終取得オフセット (\(feedLabel)): \(offset)"
    }

    private var bloombergErrorSummary: String? {
        guard let message = appState.bloombergErrorMessage, !message.isEmpty else { return nil }
        let feedLabel = appState.bloombergLastFetchFeed?.displayName ?? appState.bloombergFeed.displayName
        return "エラー (\(feedLabel)): \(message)"
    }

    private var marketWatchStatusSummary: String? {
        guard let page = appState.marketWatchLastPageFetched else { return nil }
        let feedLabel = appState.marketWatchLastFetchFeed?.feedLabel ?? appState.marketWatchFeed.feedLabel
        return "最終取得ページ (\(feedLabel)): \(page)"
    }

    private var marketWatchErrorSummary: String? {
        guard let message = appState.marketWatchErrorMessage, !message.isEmpty else { return nil }
        let feedLabel = appState.marketWatchLastFetchFeed?.feedLabel ?? appState.marketWatchFeed.feedLabel
        return "エラー (\(feedLabel)): \(message)"
    }

    private var bloombergPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        GroupBox("設定") {
                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("フィード")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Picker("フィード", selection: $appState.bloombergFeed) {
                                        ForEach(BloombergFeedOption.allCases) { option in
                                            Text(option.pickerTitle).tag(option)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 240)
                                    .disabled(appState.bloombergCrossFeedEnabled)
                                }

                                Toggle("全カテゴリを順番に取得", isOn: $appState.bloombergCrossFeedEnabled)
                                    .font(.caption)
                                    .toggleStyle(.switch)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("開始オフセット (10刻み)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        TextField("開始オフセット", value: $appState.bloombergStartOffset, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 160)
                                            .onTapGesture(perform: activateAppWindow)
                                        Stepper("", value: $appState.bloombergStartOffset, in: 0...10_000, step: 10)
                                            .labelsHidden()
                                    }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("取得ページ数")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        TextField("ページ数", value: $appState.bloombergMaxPages, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 160)
                                            .onTapGesture(perform: activateAppWindow)
                                        Stepper("", value: $appState.bloombergMaxPages, in: 1...100_000)
                                            .labelsHidden()
                                    }
                                }

                                Toggle("重複検出で停止", isOn: $appState.haltOnDuplicate)
                                    .font(.caption)
                                    .toggleStyle(.switch)
                                    .disabled(appState.bloombergCrossFeedEnabled)
                            }
                            .padding(.vertical, 4)
                        }

                        crawlerControlsBox(
                            isRunning: appState.bloombergIsCrawling,
                            startAction: appState.startBloombergCrawl,
                            stopAction: appState.stopBloombergCrawl,
                            statusText: bloombergStatusSummary,
                            errorText: bloombergErrorSummary
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                        statusBox
                        metricBox(newCount: appState.bloombergSessionNewCount, duplicateCount: appState.bloombergSessionDuplicateCount, knownCount: appState.bloombergKnownCount)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                statusHistoryBox

                articleHistoryBox(
                    title: "取得済み記事",
                    emptyMessage: "記事はまだ取得されていません",
                    articles: appState.bloombergArticles
                ) { article in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(article.headline ?? "(タイトルなし)")
                            .font(.headline)
                        if let published = article.publishedAt, !published.isEmpty {
                            Text("公開日: \(published)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(article.url)
                            .font(.caption)
                            .textSelection(.enabled)
                        HStack {
                            Text(article.feed.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("オフセット \(article.offset)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("開く") {
                                appState.openURLInSafari(article.url)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }

    private var marketWatchPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        GroupBox("設定") {
                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("フィード")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Picker("フィード", selection: $appState.marketWatchFeed) {
                                        ForEach(MarketWatchFeedOption.allCases) { option in
                                            Text(option.pickerTitle).tag(option)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 220)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("開始ページ")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        TextField("開始ページ", value: $appState.marketWatchStartPage, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 160)
                                            .onTapGesture(perform: activateAppWindow)
                                        Stepper("", value: $appState.marketWatchStartPage, in: 1...10_000)
                                            .labelsHidden()
                                    }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("取得ページ数")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        TextField("ページ数", value: $appState.marketWatchMaxPages, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 160)
                                            .onTapGesture(perform: activateAppWindow)
                                        Stepper("", value: $appState.marketWatchMaxPages, in: 1...100_000)
                                            .labelsHidden()
                                    }
                                }

                                Toggle("重複検出で停止", isOn: $appState.haltOnDuplicate)
                                    .font(.caption)
                                    .toggleStyle(.switch)
                            }
                            .padding(.vertical, 4)
                        }

                        crawlerControlsBox(
                            isRunning: appState.marketWatchIsCrawling,
                            startAction: appState.startMarketWatchCrawl,
                            stopAction: appState.stopMarketWatchCrawl,
                            statusText: marketWatchStatusSummary,
                            errorText: marketWatchErrorSummary
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    statusBox
                        metricBox(newCount: appState.marketWatchSessionNewCount, duplicateCount: appState.marketWatchSessionDuplicateCount, knownCount: appState.marketWatchKnownCount)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                statusHistoryBox

                articleHistoryBox(
                    title: "取得済みリンク",
                    emptyMessage: "リンクはまだ取得されていません",
                    articles: appState.marketWatchArticles
                ) { article in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(article.url)
                            .font(.caption)
                            .textSelection(.enabled)
                        if let headline = article.headline, !headline.isEmpty {
                            Text(headline)
                                .font(.callout)
                        }
                        if let published = article.publishedAt, !published.isEmpty {
                            Text(published)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(article.feed.feedLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text("ページ \(article.pageNumber)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("開く") {
                                appState.openURLInSafari(article.url)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }

    private var aggregationPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("入力ディレクトリ") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("links-output ディレクトリ", text: $appState.linksInputDirectory)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            appState.refreshAggregatorScriptLocation()
                        } label: {
                            Label("パスを再検出", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .disabled(appState.isAggregatingLinks)
                    }
                }

                GroupBox("出力ディレクトリ") {
                    TextField("集計結果の保存先", text: $appState.linksAggregatedDirectory)
                        .textFieldStyle(.roundedBorder)
                }

                GroupBox("Python 実行環境") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("python コマンドパス", text: $appState.pythonBinaryPath)
                            .textFieldStyle(.roundedBorder)
                        Toggle("timestamp 列を保持する", isOn: $appState.keepTimestampOnAggregation)
                    }
                }

                GroupBox("スクリプト位置") {
                    if let path = appState.aggregatorScriptLocation {
                        Text(path)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("aggregate_links.py が見つかっていません")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                GroupBox("操作") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            appState.aggregateLinks()
                        } label: {
                            if appState.isAggregatingLinks {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("集計中…")
                                }
                            } else {
                                Label("集計を実行", systemImage: "play.rectangle")
                            }
                        }
                        .disabled(appState.isAggregatingLinks)

                        if !appState.aggregationStatusMessage.isEmpty {
                            Text(appState.aggregationStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let logFile = appState.lastAggregationLogFile {
                    GroupBox("ログファイル") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(logFile)
                                .font(.caption)
                                .textSelection(.enabled)
                            Button {
                                appState.revealLastAggregationLogFile()
                            } label: {
                                Label("Finder で表示", systemImage: "doc.text.magnifyingglass")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if !appState.aggregationLog.isEmpty {
                    GroupBox("ログ") {
                        ScrollView {
                            Text(appState.aggregationLog)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 160)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }

    private var bodyFetchPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Bloomberg パーケット") {
                    VStack(alignment: .leading, spacing: 8) {
                        if appState.bloombergParquetFiles.isEmpty {
                            Text("Bloomberg のパーケットファイルが見つかりません")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("パーケットファイル", selection: Binding(
                                get: { appState.bloombergSelectedParquetFile ?? "" },
                                set: { appState.bloombergSelectedParquetFile = $0.isEmpty ? nil : $0 }
                            )) {
                                ForEach(appState.bloombergParquetFiles, id: \.self) { path in
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .tag(path)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 280)
                        }

                        HStack(spacing: 12) {
                            Button {
                                appState.refreshBloombergParquetSources()
                            } label: {
                                Label("リストを更新", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                appState.loadBloombergBodySources()
                            } label: {
                                Label("URL を読み込み", systemImage: "doc.text.magnifyingglass")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.bloombergSelectedParquetFile == nil)
                        }

                        if let error = appState.bloombergBodyLoadError, !error.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                GroupBox("本文取得対象 URL") {
                    if appState.bloombergBodySourceURLs.isEmpty {
                        Text("URL はまだ読み込まれていません")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let first = appState.bloombergBodySourceURLs.first {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(first)
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 12) {
                            Button {
                                appState.openBloombergPreviewInSafari()
                            } label: {
                                if appState.bloombergPreviewLoading {
                                    ProgressView()
                                } else {
                                    Label("Safari で開く", systemImage: "safari")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.bloombergPreviewLoading)

                            Button {
                                appState.manuallyEnableReaderMode()
                            } label: {
                                Label("リーダーを適用", systemImage: "doc.richtext")
                            }
                            .buttonStyle(.bordered)
                            .disabled(appState.bloombergPreviewLoading)

                            Toggle("リーダーで開く", isOn: $appState.bloombergUseReaderMode)
                                .toggleStyle(.switch)
                                .disabled(appState.bloombergPreviewLoading)
                                .labelsHidden()
                                .accessibilityLabel("リーダー表示を強制")

                            if appState.bloombergBodySourceURLs.count > 1 {
                                Text("他 \(appState.bloombergBodySourceURLs.count - 1) 件")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }

    private func crawlerControlsBox(
        isRunning: Bool,
        startAction: @escaping () -> Void,
        stopAction: @escaping () -> Void,
        statusText: String?,
        errorText: String?
    ) -> some View {
        GroupBox("操作") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button(action: startAction) {
                        Label("開始", systemImage: "play.fill")
                    }
                    .disabled(isRunning)

                    Button(action: stopAction) {
                        Label("停止", systemImage: "stop.fill")
                    }
                    .disabled(!isRunning)
                }

                if isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("実行中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let statusText {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func articleHistoryBox<Data: RandomAccessCollection, Row: View>(
        title: String,
        emptyMessage: String,
        articles: Data,
        @ViewBuilder row: @escaping (Data.Element) -> Row
    ) -> some View where Data.Element: Identifiable {
        GroupBox("\(title) (最新 \(articles.count) 件)") {
            if articles.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(articles.enumerated()), id: \.element.id) { entry in
                    row(entry.element)
                    if entry.offset < articles.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func strategyDescription(for strategy: StrategyReference) -> String {
        switch strategy.type {
        case .cssSelector:
            return "CSS セレクタ"
        case .textMatch:
            return "テキスト一致"
        case .script:
            return "スクリプト"
        case .fallback:
            return "フォールバック"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
