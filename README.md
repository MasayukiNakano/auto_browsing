# Auto Browsing Toolkit

Safari をアクセシビリティ経由で制御し、ニュースサイトの「次を読み込む」や無限スクロールを自動化する macOS 向けアプリです。  
Bloomberg / MarketWatch の最新記事リンクを収集し、Java 製の戦略モジュールと連携して Parquet 形式で保存します。

---

## 主な機能

- **Bloomberg クロール**
  - 任意フィード単体、または「全カテゴリ横断モード」で連続収集。
  - API レスポンスの整合チェックと自動再試行（最大回数 / 待機秒数は UI から設定）。
  - Safari から取得した記事を重複排除しつつ `.parquet` に追記。
  - プレビュー保存時に HTML/JSON を `url-sha1@v1-canonical` の ID で永続化し、`article_id`, `id_scheme`, `capturedAt` などメタデータを付与。

- **MarketWatch クロール**
  - DOM 解析で見出し・発行日時を抽出し、Bloomberg と同じフォーマットで保存。
  - 既知リンクの復元、重複検出、リトライを Bloomberg と共通挙動でサポート。

- **リンク蓄積と集計**
  - 既知リンクは `Application Support/AutoBrowsing/links-output` 以下に Parquet + `.known` キャッシュとして永続化。
  - `scripts/aggregate_links.py` でサイト単位に重複除去した集計結果を生成（dry-run や詳細ログにも対応）。

- **UI/監視**
  - SwiftUI + AppKit による macOS アプリで、キュー状況・リトライ回数・取得履歴をリアルタイム表示。
  - Safari の前面化、遷移待機、ランダムスリープ挿入など長時間運用を想定した制御を実装。

- **戦略モジュール (Java)**
  - `java-strategy` でロードモア操作判定、リンク書き込みを行う。
  - Parquet 書き込み時に既存レコードを読み戻して重複を抑止。

---

## リポジトリ構成

| パス | 説明 |
| ---- | ---- |
| `macos-app/` | SwiftUI + AppKit アプリ本体。アクセシビリティ制御、クロールロジック、Java ブリッジを含む。 |
| `java-strategy/` | Java 製ロードモア戦略サーバ。Parquet 書き込みやサイト固有戦略を担当。 |
| `scripts/` | 運用補助スクリプト。現在はリンク集計ツールを同梱。 |
| `test/` | 実験用の小規模サンドボックス (一部サンプル)。 |

---

## 動作要件

- macOS 13 Ventura 以降（Safari をアクセシビリティ経由で操作可能であること）。
- Xcode 15 以降 / Swift 5.9 以降。
- Java 17 以上（`java-strategy` 用）。
- Python 3.9 以上 + `pandas`, `pyarrow`（リンク集計スクリプト用、任意）。
- Safari のアクセシビリティ許可（システム設定 > プライバシーとセキュリティ > アクセシビリティ）。

---

## セットアップ

### 1. macOS アプリのビルド / テスト

```bash
cd macos-app
swift build          # ビルド
swift test           # ユニットテスト
swift run            # デバッグ起動 (Xcode プロジェクト生成も可)
```

初回起動時はアクセシビリティ許可を求められるので、指示に従って付与してください。
リンク保存先は既定で `~/Library/Application Support/AutoBrowsing/links-output` です。

### 2. Java 戦略サーバ

```bash
cd java-strategy
./gradlew test       # 戦略ロジックのテスト
./gradlew run        # StrategyServer を起動 (標準入出力で待機)
```

`StrategyServer` は Swift 側から JSON を受け取り、Parquet 書き込み・ロードモア指示を返します。  
`LinkParquetWriter` が Parquet + `.known` キャッシュを生成し、重複を抑制します。

### 3. Python スクリプト (任意)

```bash
python3 -m pip install pandas pyarrow
```

---

## アプリの使い方

1. Swift アプリを起動し、「設定」タブでフォーカス再取得回数・スリープ間隔・自動再開回数などを調整。
2. Bloomberg / MarketWatch タブで対象フィードや開始オフセット・ページ数を選択。
   - Bloomberg は「全カテゴリを順番に取得」をオンにすると、Markets → Economics … の順で重複検出まで巡回します。
3. `開始` ボタンでクロール開始。Safari が前面化し、リンクが収集されると UI に最新 10 件まで表示。
4. 取得結果は `links-output/<siteId>*.parquet` に追記されるため、必要に応じて集計スクリプトを実行。
5. 任意の URL で「Safariで開く」を押すと、専用ワーカーウィンドウで Reader を適用し、`
   links-output/` に `<article_id>.html` と `<article_id>.json`（タイトル・本文・`article_id`・`id_scheme`・`capturedAt` など）を保存。GUI の「解析済みプレビュー」で同内容を確認できます。

### 自動再開と重複検出

- エラーやキャプチャページ検出時は自動でリトライ（回数 / 待機秒数は設定タブ）。
- 重複検出をオンにすると、新規リンクが見つからなかった時点でクロールを停止し、次のフィードへ遷移 / 再開に備えます。
- Bloomberg / MarketWatch ともに `.known` キャッシュを読み込んで前回の取得状況を復元します。

---

## リンク集計スクリプト

`scripts/aggregate_links.py` は `links-output/*.parquet` を読み込み、サイト単位に重複排除した結果を `links-output/aggregated/<site>.parquet` へ出力します。

```bash
python3 scripts/aggregate_links.py \
    --base ~/Library/Application\ Support/AutoBrowsing/links-output \
    --keep-timestamp \
    --verbose
```

主なオプション:

| オプション | 説明 |
| ---------- | ---- |
| `--base PATH` | 入力ディレクトリ（既定: `links-output`）。 |
| `--output PATH` | 出力先（既定: `<base>/aggregated`）。 |
| `--keep-timestamp` | `timestampMillis` 列を保持。 |
| `--dry-run` | 書き込みを行わず処理概要のみを表示。 |
| `--verbose` | 詳細ログを出力。 |

---

## データ構造

- **Parquet カラム**: `siteId`, `pageUrl`, `href`, `text`, `publishedAt`, `timestampMillis` (オプション)。
- `.known` ファイル: `LinkParquetWriter` が既知 URL を 1 行ずつ保存するテキスト。Swift アプリはこれを読み込んで既知リンク集合を初期化します。
- 取得ログ: `~/Library/Application Support/AutoBrowsing/status-log.txt`（必要に応じて自動アーカイブ）。

---

## 開発ガイド

- Swift 側の主要クラス
  - `AppState`: UI 状態 / クロールフロー / 設定管理。
  - `SafariAccessibilityController`: アクセシビリティ API を使った Safari 操作。
  - `ScrollAutomationEngine`: Java 戦略サーバからの指示を解釈し、スクロールやボタン押下を実行。
  - `LoadMoreStrategyClient`: Java プロセス起動・JSON 通信・リンク蓄積。
- Java 側
  - `StrategyServer`: JSON リクエスト/レスポンスを処理し、リンクを Parquet に保存。
  - `BloombergStrategy` など `LoadMoreStrategy` 実装でサイト固有の「Load more」判定を記述。

テスト / フォーマット:

```bash
swift test                            # macos-app
./gradlew test                        # java-strategy
python3 scripts/aggregate_links.py --dry-run --verbose
```

---

## 今後の拡張アイデア

- Swift と Java の常時接続を確立し、ロードモア操作を戦略サーバ主導に移行。
- CAPTCHA 回避や認証状態維持のため、追加のヘルスチェック / プロンプト機構を導入。
- WebExtension / AppleScript 以外の操作モードを検討（Selenium / WebKit Automation 等）。
- 設定エクスポート・インポート、UI からの集計実行、通知連携など運用性を向上。

---

## ライセンス / コントリビューション

現時点では社内検証用プロトタイプとして開発中です。Issue / PR を歓迎しますが、機密情報や API トークンなどは含めないでください。必要な追加機能があれば、具体的なシナリオとともにフィードバックをお寄せください。
