<div align="right">

[![CI](https://img.shields.io/github/actions/workflow/status/Arata1202/SwiftRecruitApp/ios-ci.yml?branch=main)](https://github.com/Arata1202/SwiftRecruitApp/actions/workflows/ios-ci.yml)
[![MIT License](https://img.shields.io/github/license/Arata1202/SwiftRecruitApp?cache=public)](LICENSE)

</div>

# SwiftRecruitApp

リクビジョンのiOSネイティブ版です。企業、選考予定、締切、ToDoを一か所で管理し、就職活動の次の行動を忘れないためのアプリをSwiftUIで実装しています。

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

新しいテーブルやカラムを使用するアプリ版を配信する前に、必ずmigrationを本番DBへ先に反映してください。現在のアプリに必要な列・制約・関数を揃えるため、`supabase/migrations` 内の全migrationをファイル名の時系列順に適用してください。一部の列だけを手動で追加する方法はサポートしていません。旧アプリとの移行期間は互換用のtimestamp列も同期されます。

AppleログインをSupabase Dashboardで有効化します。iOS App IDとXcode targetの両方でSign in with Apple capabilityを有効にしてください。

アカウント削除時にAppleの認可も失効するため、Apple DeveloperでSign in with Apple用のKeyを作成します。秘密値はGitやiOSアプリへ入れず、Supabase Secretsだけに保存してください。

```bash
cp supabase/.env.apple.example supabase/.env.apple
# supabase/.env.apple にApple Team ID、Key ID、Client ID、.p8秘密鍵を設定
npx supabase secrets set --env-file supabase/.env.apple
npx supabase functions deploy delete-account
```

`APPLE_CLIENT_ID` は自分のiOSアプリのBundle IDに合わせてください。Apple Secretsを設定してから `delete-account` Functionをデプロイしてください。

### 通知タイミング

通知は1件です。時刻ありは「なし」「5分前」「15分前」「30分前」「1時間前」「2時間前」「1日前」「2日前」「1週間前」「1か月前」「カスタム」。日付のみは「なし」「1日前」「2日前」「1週間前」「2週間前」「1か月前」「3か月前」「6か月前」「カスタム」です。日付のみの基準時刻は端末の現地時刻9:00です。

カスタムは通知行の下に要約と数字・単位の標準ホイールを表示します。どちらも分・時間・日・週間・か月を選べます。通常のカスタムに別シートや数字の手入力はありません。数値の選択上限は全単位200です（日付のみの日は0〜200、それ以外は1〜200）。保存済みの範囲外値は現在値として保持し、無関係な保存やキャンセルで変更しません。編集中の数字・単位を保持します。数を変えずに切り替えられない単位は選択できません。変更はフォームの下書きだけに反映し、保存で確定、キャンセルで破棄確認を表示します。通常の操作では日時・経過時間・暦日といった方式の選択や独立した時刻入力を表示しません。

時刻ありの日・週は既存の経過時間形式で保存し、1日=24時間、1週=168時間です。夏時間の切替をまたぐと現地の時計時刻はずれる場合があります。日付のみの日・週は暦日を引き、その日の9:00を使います。月は暦の月を引き、月末は移動先の月末に合わせます。日付のみの分・時間は当日9:00から引きます。通知予定の年月日・時刻を画面に表示し、開始・期限の変更に追従します。予定の終了日時は通知基準にしません。日付精度を切り替えると、別々に保持した時刻あり/日付のみの設定を使用します。

既存の72時間前、任意の経過時間、特定時刻の暦日設定、絶対日時は自動変換しません。相対指定で表せない設定は現在の日時・値だけを表示し、旧方式への切替や専用編集は提供しません。既存の絶対日時は日程・精度・タイムゾーン変更でも同じ瞬間を保持します。通知オフは設定を消さず、別の通知方法の選択は現在の精度の設定と絶対日時を切り替えます。変更を取り消す場合は外側の編集画面をキャンセルします。無関係な項目の保存では通知値を変更しません。

新しく指定・変更する過去の絶対日時は保存できません。過去になった相対通知は即時配信せず、通知されない旨を表示します。既存の期限切れ通知は無関係な編集・完了・通知オフを妨げません。表示は予約計画であり到着の保証ではありません。通知許可・64件の予約上限・完了/中止/削除にも従います。アプリ停止中のタイムゾーン変更は次の前面復帰で再予約します。既存の暦日時刻では夏時間の欠落時刻は同日内の次の有効時刻、重複時刻は最初の時刻を使います。

月と日付のみの分・時間の保存には060000が必要です。200週間前の保存には050000が必要です。既存JSON形式のまま、数値制約を2,016,000分・33,600時間・1,400日まで拡張します。UIの選択上限は各単位200です。絶対日時の互換性のため040000も引き続き必要です。

先に全migrationを順番どおり、特に 20261119010000 → 20261119020000 → 20261119030000_add_custom_notification_timing.sql → 20261119040000_add_absolute_notification_timing.sql → 20261119050000_expand_notification_timing_to_200_weeks.sql → 20261119060000_add_calendar_relative_notification_units.sql の順で適用してから、アプリを更新してください。過去のmigrationは変更しません。旧版は追加設定を表示・予約できないため、利用する全端末を更新してから使用してください。旧版による矛盾するプリセット変更はDBが拒否し、同値の設定書き込みや無関係な編集は保持します。DB互換性だけでは旧版端末のローカル通知を正しい時刻にできません。

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

[`.github/workflows/ios-ci.yml`](.github/workflows/ios-ci.yml) はpush / pull requestで、macOS 15・Xcode 16.4・iPhone 16（iOS 18.5）Simulatorの署名不要ビルドと `SwiftRecruitAppTests` のXCTestを実行します。GitHub Actionsの有効化とmacOS runnerの利用枠、Homebrew / Swift Package取得用のネットワーク接続が必要です。Secrets、Apple Developerの署名、本番SupabaseやDB変更は不要です。

CIは一時的なxcconfigを `-xcconfig` で適用し、既存の `Config/` を変更せずに接続先とキーを未設定扱いのダミー値へ上書きします。アプリ起動時にもSupabaseクライアントは生成しません。Swift言語モードは `project.yml` の `SWIFT_VERSION: "5"` に統一し、通常のローカルビルドとCIで同じ設定を使用します。

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

CIの成功はAppleログイン・実サービスとの通信・通知やカレンダーの実機動作を保証しないため、上記の実機確認も別途行ってください。Actionsの `iOS build and tests` でビルド結果とテスト結果を確認できます。

## リリース時の確認

- 変更に必要なmigrationとEdge Functionを、互換性を確認してから反映
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

### 項目ごとの通知時刻

日付のみの予定・締切・ToDoでは、編集画面の「通知時刻」を直接変更できます（初期値9:00）。通知タイミングを変えても時刻を保持し、その項目の保存／キャンセルに従います。時刻ありの予定と絶対日時通知は対象外です。設定画面の端末共通時刻は撤回し、保存済みデータの時刻をそのまま使用します。分・時間前はこの時刻を基準に差し引き、通知予定日時に結果を表示します。

追加migration 20261119070000_add_per_item_notification_clock.sql を060000の後に適用してください。相対通知の個別時刻を保存するために必要です。本番DBへの適用は別途必要です。

### 時刻あり予定の日・週・月前の通知

日・週・月前を選ぶと、同じ通知時刻行で時刻を編集できます。新しく選ぶ際は9:00で、日・週・月の切替では選んだ時刻を維持します。分・時間前は予定時刻からの逆算で、時刻入力は表示しません。表示項目・メニュー順・画面構成は変更していません。
既存の経過時間設定は開くだけ・無関係な保存では変更せず、実際の通知時刻を表示します。日単位への選び直し／通知時刻の編集で暦日と時刻の指定になります。
070000の後に080000（add_timed_calendar_notification_clock）migrationを適用し、利用端末を更新してください。本番には自動適用しません。

### インターンシップ

選考の種類に「インターンシップ」を追加。専用ページ・画面名・既存データの変更はありません。
080000の後に090000（add_internship_selection_type）migrationを適用し、利用端末を更新してください。旧アプリは追加された種類を読み込めないため、端末更新前に新しい種類の登録を始めないでください。
