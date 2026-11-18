<div align="right">

[![CI](https://img.shields.io/github/actions/workflow/status/Arata1202/SwiftRecruitApp/ios-ci.yml?branch=main)](https://github.com/Arata1202/SwiftRecruitApp/actions/workflows/ios-ci.yml)
[![MIT License](https://img.shields.io/github/license/Arata1202/SwiftRecruitApp?cache=public)](LICENSE)

</div>

# SwiftRecruitApp

リクビジョンのiOSネイティブ版です。企業、選考予定、締切、ToDoを一か所で管理し、就職活動の次の行動を忘れないための初期MVPをSwiftUIで実装しています。

[App Storeでダウンロード](https://apps.apple.com/jp/app/id6789862900)

## 主な機能

- Sign in with Apple / Supabase Auth
- 直近7日間の選考とToDoを表示するホーム
- 選考予定、選考締切、ToDoをまとめて確認する月間カレンダー
- 企業の追加、編集、検索、絞り込み、削除
- 企業ごとの選考タイムライン
- 企業ごとの企業研究、志望理由、面接記録、逆質問、自由項目
- ToDo、完了管理、関連企業
- `UserNotifications` によるローカル通知
- 通知タップから対象画面への遷移
- アプリ内アカウント削除

詳しい範囲は [docs/MVP.md](docs/MVP.md) を参照してください。

## 技術構成

- SwiftUI / Swift Concurrency
- Supabase Swift SDK
- Supabase Auth / PostgreSQL / Row Level Security
- Supabase Edge Functions
- UserNotifications
- XcodeGen

Supabase Swift SDKは、再現可能なビルドのため `2.46.0` に固定しています。更新時は実機確認とテストを行ってから `project.yml` のバージョンを変更してください。

## ディレクトリ構成

```text
SwiftRecruitApp/       アプリ本体
SwiftRecruitAppTests/  ユニットテスト
Config/                アプリの接続設定
supabase/              DBのマイグレーション・Edge Function
docs/                  仕様などのドキュメント
project.yml            XcodeGenのプロジェクト定義
```

## 開発環境

- macOSとXcode、XcodeGen
- 対応OS: iOS 17以降
- Supabase CLIとDocker（ローカルDBでの検証時）

## セットアップ

### 1. Xcodeプロジェクトを生成

```bash
git clone https://github.com/Arata1202/SwiftRecruitApp.git
cd SwiftRecruitApp
brew install xcodegen
xcodegen generate
open SwiftRecruitApp.xcodeproj
```

`Config/AppConfig.xcconfig` には既定の接続先が設定されています。開発や検証では `Config/Local.xcconfig.example` を `Config/Local.xcconfig` へコピーし、自分のSupabaseプロジェクトのURLと公開可能キーに変更してください。サービスロールキーはiOSアプリへ絶対に入れないでください。

### 2. Supabase

```bash
# ローカルDBを起動してmigrationを検証
npx supabase start
npx supabase db reset

# 新しく作成したSupabaseプロジェクトへ反映
npx supabase link --project-ref <PROJECT_REF>
npx supabase db push --dry-run
npx supabase db push
```

DB定義は `supabase/migrations` のSQLだけを正とします。Supabase Dashboardで直接テーブルを変更せず、変更時は `supabase migration new <name>` で新しいmigrationを追加してください。

新しいテーブルやカラムを使用するアプリ版を配信する前に、必ずmigrationを本番DBへ先に反映してください。現在のアプリは `starts_on` / `deadline_on` / `due_on`、`company_information_items` に依存します。旧アプリとの移行期間は互換用のtimestamp列も同期されます。

AppleログインをSupabase Dashboardで有効化します。iOS App IDとXcode targetの両方でSign in with Apple capabilityを有効にしてください。

アカウント削除時にAppleの認可も失効するため、Apple DeveloperでSign in with Apple用のKeyを作成します。秘密値はGitやiOSアプリへ入れず、Supabase Secretsだけに保存してください。

```bash
cp supabase/.env.apple.example supabase/.env.apple
# supabase/.env.apple にApple Team ID、Key ID、Client ID、.p8秘密鍵を設定
npx supabase secrets set --env-file supabase/.env.apple
npx supabase functions deploy delete-account
```

`APPLE_CLIENT_ID` はiOSアプリのBundle ID `com.arata1202.SwiftRecruitApp` です。Apple Secretsを設定するまでは、更新後の `delete-account` Functionをデプロイしないでください。

## テスト

```bash
xcodebuild \
  -project SwiftRecruitApp.xcodeproj \
  -scheme SwiftRecruitApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

利用可能なシミュレーターは `xcodebuild -project SwiftRecruitApp.xcodeproj -scheme SwiftRecruitApp -showdestinations` で確認できます。CIでもシミュレーター向けビルドとテストを実行します。

Sign in with Appleと通知は、Apple Developerの署名を設定した実機でも確認してください。

### CIと非本番でのテスト

[`.github/workflows/ios-ci.yml`](.github/workflows/ios-ci.yml) はpush / pull requestで、macOS 15・Xcode 16.4・iPhone 16（iOS 18.5）Simulatorの署名不要ビルドと `SwiftRecruitAppTests` のXCTestを実行します。GitHub Actionsの有効化とmacOS runnerの利用枠、Homebrew / Swift Package取得用のネットワーク接続が必要です。Secrets、Apple Developerの署名、本番SupabaseやDB変更は不要です。

CIは一時的なxcconfigを `-xcconfig` で適用し、既存の `Config/` を変更せずに接続先とキーを未設定扱いのダミー値へ上書きします。アプリ起動時にもSupabaseクライアントは生成しません。Swift言語モードは `project.yml` の `SWIFT_VERSION: "5"` に統一し、通常のローカルビルドとCIで同じ設定を使用します。Supabase SDKの固定バージョン `2.46.0` は変更しません。

同じ非本番設定でローカル検証する場合は、Xcode 16.4 / iOS 18.5 SimulatorとXcodeGenを用意して、リポジトリ直下で実行してください。

```bash
(
  export DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer
  ci_config="$(mktemp)"
  trap 'rm -f "$ci_config"' EXIT
  cat > "$ci_config" <<'XCCONFIG'
SUPABASE_URL = https:/$()/YOUR_PROJECT_REF.invalid
SUPABASE_PUBLISHABLE_KEY = YOUR_PUBLISHABLE_KEY
XCCONFIG
  xcodegen generate && xcodebuild \
    -project SwiftRecruitApp.xcodeproj \
    -scheme SwiftRecruitApp \
    -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
    -xcconfig "$ci_config" \
    CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= \
    build test
)
```

CIの成功はAppleログイン・実サービスとの通信・通知やカレンダーの実機動作を保証しないため、上記の実機確認も別途行ってください。新規workflowの初回はActionsの `iOS build and tests` → `Simulator build and XCTest` でビルド結果とテスト件数を確認してください。

## 公開前チェック

- App Storeスクリーンショットを追加
- `https://realunivlog.com/privacy` にリクビジョン固有のデータ取扱いを追記
- サポート、プライバシーポリシー、Apple標準EULAのリンク切れがないことを確認
- App Store Connectのプライバシー回答をPrivacy Manifestと一致させる
- アカウント削除と関連データの削除を実機で確認
- Appleログインの設定と失効時の挙動を確認
- 通知の予約、更新、取消、通知タップ遷移を確認

## セキュリティ

- すべての業務テーブルでRLSを有効化
- `auth.uid() = user_id` のデータだけ操作可能
- 企業と関連データは複合外部キーで所有者を一致
- アカウント削除時はAppleで再認証し、Apple認可の失効後に認証必須のEdge Functionで削除
- 広告、分析、追跡SDKは不使用

## コントリビューション

不具合報告や改善提案、プルリクエストを歓迎します。開発時の注意事項は[CONTRIBUTING.md](CONTRIBUTING.md)をご覧ください。セキュリティ上の問題は公開Issueではなく、[SECURITY.md](SECURITY.md)に記載の方法で報告してください。

開発・検証には自分のSupabaseプロジェクトを使用してください。既定の接続先を開発・検証に使わないよう、`Config/Local.xcconfig`で接続先を変更し、実ユーザーのデータを使わないようにしてください。

## ライセンス

このプロジェクトのライセンスはMITです。詳細は[LICENSE](LICENSE)を参照してください。

Toolsの撤去・保存データ・復元元は [docs/tools-retirement.md](docs/tools-retirement.md) を参照してください。
このDraftではESテンプレートのみ復元します。`es_templates` と既存RLSに依存します。
