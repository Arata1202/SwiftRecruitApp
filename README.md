<div align="right">

[![CI](https://img.shields.io/github/actions/workflow/status/Arata1202/SwiftRecruitApp/ios-ci.yml?branch=main)](https://github.com/Arata1202/SwiftRecruitApp/actions/workflows/ios-ci.yml)
[![MIT License](https://img.shields.io/github/license/Arata1202/SwiftRecruitApp?cache=public)](LICENSE)

</div>

# SwiftRecruitApp

リクビジョンのiOSネイティブ版です。企業、選考予定、締切、ToDoを一か所で管理し、就職活動の次の行動を忘れないためのアプリをSwiftUIで実装しています。

[App Storeでダウンロード](https://apps.apple.com/jp/app/id6789862900)

## 主な機能

- Sign in with Apple / Supabase Auth
- 7日以内の予定と、進行中または期限を過ぎた未完了の項目を表示するホーム
- 選考予定、選考締切、ToDoをまとめて確認する月間カレンダー
- 企業の追加、編集、検索、絞り込み、削除
- 企業ごとの選考タイムライン
- 企業ごとの企業研究、志望理由、面接記録、逆質問、自由項目
- ToDo、完了管理、関連企業
- `UserNotifications` によるローカル通知
- 通知タップから対象画面への遷移
- アプリ内アカウント削除

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

### 2. 署名とアプリ識別子

実機で動かす場合は、自分のApple Developerチームと一意なBundle IDを使用してください。

- `project.yml` の `DEVELOPMENT_TEAM` と、アプリ・テストの `PRODUCT_BUNDLE_IDENTIFIER` を変更し、XcodeGenで再生成します。
- Apple Developerに同じアプリのBundle IDを登録し、Sign in with Appleを有効にします。
- Supabase AuthのApple設定と、下記の `APPLE_CLIENT_ID` にも同じアプリのBundle IDを指定します。
- 署名不要のSimulatorテストだけを行う場合は、後述の非本番テスト手順を使用できます。

### 3. Supabase

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

AppleログインをSupabase Dashboardで有効化します。iOS App IDとXcode targetの両方でSign in with Apple capabilityを有効にしてください。

アカウント削除時にAppleの認可も失効するため、Apple DeveloperでSign in with Apple用のKeyを作成します。秘密値はGitやiOSアプリへ入れず、Supabase Secretsだけに保存してください。

```bash
cp supabase/.env.apple.example supabase/.env.apple
# supabase/.env.apple にApple Team ID、Key ID、Client ID、.p8秘密鍵を設定
npx supabase secrets set --env-file supabase/.env.apple
npx supabase functions deploy delete-account
```

`APPLE_CLIENT_ID` は自分のiOSアプリのBundle IDに合わせてください。DBマイグレーションを適用し、Apple Secretsを設定してから `delete-account` Functionをデプロイしてください。

## テスト

ソース契約テストはPython標準ライブラリだけで実行できます（リポジトリ直下）。iOS CIでも同じコマンドを実行します。

```bash
python3 -m unittest discover -s SwiftRecruitAppTests -p '*_source_tests.py' -v
```

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

CIではダミーの接続設定を使い、本番のSupabaseに接続せずにテストします。

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

## リリース時の確認

- DBやEdge Functionを変更する場合は、配信中のアプリとの互換性を確認し、新版の配信前に反映
- アカウント削除、Appleログイン、通知の予約・更新・取消・タップ遷移を実機で確認
- サポート・プライバシーポリシー・利用規約と、配信先のプライバシー申告を実装に合わせて確認

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
