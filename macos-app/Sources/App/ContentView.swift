import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    var body: some View {
        TabView {
            controlPanel
                .tabItem { Label("コントロール", systemImage: "slider.horizontal.3") }
            linkPanel
                .tabItem { Label("リンク一覧", systemImage: "link") }
            aggregationPanel
                .tabItem { Label("データ集計", systemImage: "tray.full") }
        }
        .frame(minWidth: 600, minHeight: 440)
        .onAppear {
            loadInitialData()
        }
    }

    private func loadInitialData() {
        appState.loadSiteProfiles()
        appState.refreshSafariState()
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            Divider()
            siteStatusSection
            configurationSection
            automationControls
            statusSection
            Spacer()
        }
        .padding()
    }

    private var linkPanel: some View {
        NavigationView {
            List {
                Section(header: Text("記事カード数")) {
                    Text("\(appState.visibleArticleCount) 件")
                        .font(.headline)
                        .monospacedDigit()
                }

                if appState.lastCleanupRemovedCount != nil || appState.lastCleanupError != nil {
                    Section(header: Text("\(appState.lastCleanupSiteName ?? "クリーンアップ") のクリーンアップ結果")) {
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
                    }
                }

                if let url = appState.currentPageURL, !url.isEmpty {
                    Section(header: Text("現在のURL")) {
                        Text(url)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }

                Section(header: Text("最新リンク")) {
                    if appState.lastLinks.isEmpty {
                        Text("リンクはまだ取得されていません")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.lastLinks.indices, id: \.self) { index in
                            let link = appState.lastLinks[index]
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
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("収集リンク")
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
        VStack(alignment: .leading, spacing: 4) {
            Text("現在のサイト")
                .font(.headline)
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
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("動作設定")
                .font(.headline)
            Stepper(value: $appState.activationRetryLimit, in: 1...10) {
                Text("Safari フォーカス再取得回数: \(appState.activationRetryLimit)")
            }
            Text("Safari が他のウィンドウに隠れた場合に再取得を試みる最大回数")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var automationControls: some View {
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

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ステータス")
                .font(.headline)
            if appState.statusMessages.isEmpty {
                Text("メッセージはまだありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(appState.statusMessages.enumerated()), id: \.offset) { _, message in
                    Text(message)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var aggregationPanel: some View {
        NavigationView {
            Form {
                Section(header: Text("入力ディレクトリ")) {
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

                Section(header: Text("出力ディレクトリ")) {
                    TextField("集計結果の保存先", text: $appState.linksAggregatedDirectory)
                        .textFieldStyle(.roundedBorder)
                }

                Section(header: Text("Python 実行環境")) {
                    TextField("python コマンドパス", text: $appState.pythonBinaryPath)
                        .textFieldStyle(.roundedBorder)
                    Toggle("timestamp 列を保持する", isOn: $appState.keepTimestampOnAggregation)
                }

                Section(header: Text("スクリプト位置")) {
                    if let path = appState.aggregatorScriptLocation {
                        Text(path)
                            .font(.caption)
                            .textSelection(.enabled)
                    } else {
                        Text("aggregate_links.py が見つかっていません")
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("操作")) {
                    Button {
                        appState.aggregateLinks()
                    } label: {
                        if appState.isAggregatingLinks {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .frame(width: 16, height: 16)
                            Text("集計中…")
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

                if !appState.aggregationLog.isEmpty {
                    Section(header: Text("ログ")) {
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
            .navigationTitle("リンク集計")
        }
        .padding()
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
