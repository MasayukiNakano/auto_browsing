# Auto Browsing Prototype

macOS ネイティブアプリ (SwiftUI) と Java 製ロードモア判定モジュールで構成される自動ページ送りツールの下準備です。Safari のアクセシビリティ API を経由してスクロールや "Load more" ボタン押下を行い、個別サイト固有の判定ロジックは Java モジュールで差し替えできる想定です。

## プロジェクト構成

- `macos-app/` — SwiftUI + AppKit による macOS アプリ本体。アクセシビリティ制御、スクロール制御、Java モジュールとの橋渡しを担当します。
- `java-strategy/` — サイトごとのロードモア判定ロジックを提供する Java アプリ。標準入出力で Swift アプリと通信する想定のサンプル実装です。

## Swift アプリ (macos-app)

```bash
cd macos-app
swift build      # ビルド
swift test       # サンプル設定の読み込みテスト
swift run        # デバッグ起動 (Xcode でも開発可能)
```

主なポイント:

- `AppState` が UI 状態と自動化フローを管理します。
- `SafariAccessibilityController` が AXUIElement を使って Safari を操作します。
- `ScrollAutomationEngine` が戦略クライアントからの指示を受け取り、スクロールやボタン押下を実行します。
- `LoadMoreStrategyClient` は将来的に Java プロセスと連携するクラスで、現状はスタブ実装になっています。
- サイト定義は `Sources/Resources/sites.json` に格納され、アプリ起動時に読み込まれます。

> ⚠️ 初回起動時には「システム設定 > プライバシーとセキュリティ > アクセシビリティ」でアプリに操作許可を付与してください。

## Java モジュール (java-strategy)

```bash
cd java-strategy
./gradlew test   # JUnit によるサンプルテスト
./gradlew run    # StrategyServer を起動 (標準入出力で待機)
```

主なポイント:

- `StrategyServer` が JSON で受け渡しする簡易サーバです (プロトコルは README 内のコメント参照)。
- `StrategyRegistry` でサイト ID やホストごとに `LoadMoreStrategy` 実装を切り替えます。Bloomberg 用戦略 (`BloombergStrategy`) も登録済みです。
- Swift から送られたリンク情報を `LinkParquetWriter` が `links-output/<siteId>.parquet` に追記します (セッションを跨いでも保持)。
- `scripts/aggregate_links.py` で `links-output/*.parquet` を読み込み、重複 URL を除去した結果を `links-output/aggregated/<siteId>.parquet` に書き出せます。
- `StrategyAction` / `LoadMoreResponse` が Swift 側との共通フォーマットです。

Gradle 実行環境が無い場合は `JAVA_HOME` が指す JDK17 以上を準備し、`gradle wrapper` などでセットアップしてください。

## Swift と Java の接続について

現状の Swift 側実装 (`LoadMoreStrategyClient`) はスタブ（ローカルロジック）ですが、次のような形で連携を組み立てられる想定です。

1. `StrategyServer` を独立プロセスとして起動 (`Process` で `java -jar ...`)。
2. 標準入力に `LoadMoreRequest` (JSON) を書き込み、標準出力から `LoadMoreResponse` を受け取る。
3. 受け取ったレスポンスを `AutomationInstruction` に変換し、`ScrollAutomationEngine` に渡す。
4. プロセス死活監視やタイムアウト、再起動などを `LoadMoreStrategyClient` 内で扱う。

このフローに必要な土台 (レスポンス型 / AutomationInstruction / サイト設定) はすでに用意済みです。通信部分を実装すれば、サイトごとの Java 戦略に切り替えられます。

サンプルリクエスト/レスポンス:

```json
{
  "siteId": "demo-news",
  "url": "https://news.example.com/list",
  "visibleButtons": [
    { "title": "Load more", "role": "AXButton" }
  ]
}
```

```json
{
  "success": true,
  "action": "PRESS",
  "query": { "titleContains": "Load more" }
}
```

### リンク集計スクリプト

自動化の過程で取得したリンクは `links-output/<siteId>.parquet` に追記されます。
後続処理で重複 URL を除去したい場合は `scripts/aggregate_links.py` を実行してください。

```bash
python3 scripts/aggregate_links.py               # links-output/aggregated/ 以下に出力
python3 scripts/aggregate_links.py --keep-timestamp
python3 scripts/aggregate_links.py --base custom-dir --output result-dir
```

Swift 側から実行したい場合は `Process` を使って `python3` を呼び出せます。

```swift
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
task.arguments = ["scripts/aggregate_links.py"]
try task.run()
task.waitUntilExit()
```

## 今後の拡張アイデア

- Swift 側 `LoadMoreStrategyClient` に Java プロセス起動と JSON リクエスト/レスポンス処理を実装する。
- Java モジュールで HTML パーサ (jsoup など) や機械学習/OCR を導入し、より高度なページ解析を行う。
- Safari 専用ではなく WebExtension 経由で DOM を直接操作するモードを追加する。
- 設定ファイルを JSON 以外 (YAML 等) や GUI から編集できるようにする。

## 開発メモ

- リポジトリはまだ初期化段階です。`git switch -c initial-setup` などでブランチを作成し、PR 経由で `main` にマージしてください。
- 追加で必要なファイルやテンプレートがあれば指示を頂ければ反映します。
