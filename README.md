# SwiftRecruitApp

リクビジョンのiOSネイティブ版です。企業、選考予定、締切、ToDoを一か所で管理し、就職活動の次の行動を忘れないための初期MVPをSwiftUIで実装しています。

## 主な機能

- Sign in with Apple / Supabase Auth
- 直近7日間の選考とToDoを表示するホーム
- 選考予定、選考締切、ToDoをまとめて確認する月間カレンダー
- 企業の追加、編集、検索、絞り込み、削除
- 企業ごとの選考タイムライン
- ToDo、完了管理、関連企業
- ESテンプレートの保存、検索、コピーによる再利用
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

## セットアップ

### 1. Xcodeプロジェクトを生成

```bash
brew install xcodegen
xcodegen generate
open SwiftRecruitApp.xcodeproj
```

新しいSupabaseプロジェクトのURLと公開可能キーは `Config/AppConfig.xcconfig` に設定済みです。別プロジェクトへ切り替える場合だけ `Config/Local.xcconfig.example` を `Config/Local.xcconfig` へコピーして上書きしてください。サービスロールキーはiOSアプリへ絶対に入れないでください。

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

`starts_on` / `deadline_on` / `due_on` を使用するアプリ版を配信する前に、必ずmigrationを本番DBへ先に反映してください。旧アプリとの移行期間は互換用のtimestamp列も同期されます。

AppleログインをSupabase Dashboardで有効化します。iOS App IDとXcode targetの両方でSign in with Apple capabilityを有効にしてください。

アカウント削除時にAppleの認可も失効するため、Apple DeveloperでSign in with Apple用のKeyを作成します。秘密値はGitやiOSアプリへ入れず、Supabase Secretsだけに保存してください。

```bash
cp supabase/.env.apple.example supabase/.env.apple
# supabase/.env.apple にApple Team ID、Key ID、Client ID、.p8秘密鍵を設定
npx supabase secrets set --env-file supabase/.env.apple
npx supabase functions deploy delete-account
```

`APPLE_CLIENT_ID` はiOSアプリのBundle ID `com.arata1202.SwiftRecruitApp` です。Apple Secretsを設定するまでは、更新後の `delete-account` Functionをデプロイしないでください。

### 3. 実機確認

```bash
xcodebuild \
  -project SwiftRecruitApp.xcodeproj \
  -scheme SwiftRecruitApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

Sign in with Appleと通知は、Apple Developerの署名を設定した実機でも確認してください。

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
