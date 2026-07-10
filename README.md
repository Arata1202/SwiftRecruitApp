# SwiftRecruitApp

リクビジョンのiOSネイティブ版です。企業、選考予定、締切、ToDoを一か所で管理し、就職活動の次の行動を忘れないための初期MVPをSwiftUIで実装しています。

## 主な機能

- Sign in with Apple / Supabase Auth
- 直近7日間の選考とToDoを表示するホーム
- 企業の追加、編集、検索、絞り込み、削除
- 企業ごとの選考タイムライン
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

## セットアップ

### 1. Xcodeプロジェクトを生成

```bash
brew install xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig
xcodegen generate
open SwiftRecruitApp.xcodeproj
```

`Config/Local.xcconfig` にSupabase URLと公開可能キーを設定してください。サービスロールキーはiOSアプリへ絶対に入れないでください。

### 2. Supabase

```bash
supabase link --project-ref <PROJECT_REF>
supabase db push
supabase functions deploy delete-account
```

AppleログインをSupabase Dashboardで有効化します。iOS App IDとXcode targetの両方でSign in with Apple capabilityを有効にしてください。

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

- App IconとApp Storeスクリーンショットを追加
- アプリ内のプライバシーポリシーと利用規約を正式版へ更新
- App Store Connectのプライバシー回答をPrivacy Manifestと一致させる
- アカウント削除と関連データの削除を実機で確認
- Appleログインの設定と失効時の挙動を確認
- 通知の予約、更新、取消、通知タップ遷移を確認

## セキュリティ

- すべての業務テーブルでRLSを有効化
- `auth.uid() = user_id` のデータだけ操作可能
- 企業と関連データは複合外部キーで所有者を一致
- アカウント削除だけを認証必須のEdge Functionで実行
- 広告、分析、追跡SDKは不使用
