# 旧機能のデータ互換性

現在のアプリには自己分析・モチベーショングラフ・ESテンプレートの画面や読み書き処理はありません。既存データと旧クライアントとの互換性のため、以下のテーブルと適用済みmigrationは保持しています。

| テーブル | 定義元 |
| --- | --- |
| `public.es_templates` | `20260720213004_add_es_templates.sql` |
| `public.self_analysis_answers` | `20260720220539_add_self_analysis.sql` |
| `public.motivation_points` | `20260720220539_add_self_analysis.sql` |

各テーブルのRLS・制約・インデックス・更新トリガーは維持しています。共有関数 `set_updated_at()` と `increment_record_version()` は他の機能でも使うため、旧画面がないことを理由に削除しないでください。アカウント削除時は既存の外部キーによって関連データも削除されます。

## 2026-11-19 本番撤去の事前確認

本番プロジェクトの識別情報を照合し、RLSを迂回するDBロール（`rolbypassrls = true`）で `count(*)` を実行した結果、上記3テーブルはいずれも0件でした。migration台帳はリポジトリの既存12件と一致し、未適用の既存migrationはありません。カタログ上は対象テーブル自身の制約・索引・ポリシー・トリガー等のみが依存し、公開スキーマの関数本文から対象名の参照は検出されませんでした。これは任意の外部クライアントや動的SQLの不存在を保証しません。

**本番DROPは未実行です。** 旧版（Tools撤去前の `0f593b9`）は `RecruitStore.reload()` でESテンプレート取得を企業・選考・ToDo取得と同じthrowing tupleに含めています。したがって `es_templates` を削除すると、旧版ではTools画面だけでなく初回の主要データ読み込み全体が失敗する可能性があります。自己分析画面も残り2テーブルに依存します。

撤去migration `20261118160000_drop_empty_retired_tools.sql` を追加しています。適用先で旧版が利用されていないことが前提です。空テーブルであることだけでは、この互換性条件を代替しません。migrationは3テーブルを排他ロックし、RLSで行が隠れない設定で空を再確認した直後に `DROP TABLE ... RESTRICT` を実行します。ロック待ちは5秒で失敗し、単一のDO文として全体が原子的に処理されます。データや依存があれば全体を中止し、共有関数・主要テーブル・過去のmigrationは変更しません。

### 適用手順

対象ブランチを取得したローカル環境で、Supabase CLIにログインして正しいプロジェクトへlinkした後に実行します。PRのマージやアプリ配信はDBへの適用ではありません。

```sh
git fetch origin
git switch fix/oss-quality-cleanup
git pull --ff-only origin fix/oss-quality-cleanup
supabase login
supabase link --project-ref <PROJECT_REF>
supabase migration list --linked
supabase db push --linked --dry-run
# 新規適用予定が 20261118160000_drop_empty_retired_tools.sql の1件だけか確認
supabase db push --linked
supabase migration list --linked
```

別の未適用migrationが表示された場合は、まとめて適用せず停止してください。適用後は3テーブルの不存在とmigration台帳への追加、主要テーブルと共有関数の維持を確認します。通信失敗等で結果不明になった場合も、再実行前に台帳とテーブルの状態を確認してください。

事前確認時の対象3テーブルのスキーマカタログ（列・既定値・制約・索引・トリガー・RLS・権限）と共有関数定義は、リポジトリ外の非公開バックアップに保存しました。ユーザーデータは含めていません。バックアップはカタログJSON形式です。これとは別に隔離PostgreSQLで過去のmigrationによるスキーマ復元を検証しています。

### ローカル検証

ネットワークを無効化したPostgreSQL 17コンテナに、最小限のAuthスキーマ・ロールを用意して既存12件のmigrationを適用しました。撤去SQLのrollback付きdry-run、各テーブルの非空ガード（3ケース）、外部view依存によるRESTRICT中止、競合ロックの5秒タイムアウト、空の場合の3表のみの削除、主要4表とpublic関数の維持、過去の定義による3表の再作成を確認済みです。Supabase全サービスを含む統合テストや本番への適用試験ではありません。

## 将来のスキーマ変更

アプリから参照されなくなったテーブルでも、削除前に稼働DB・旧クライアント・外部依存を確認してください。データのバックアップと復元確認、または明示的な廃棄判断を行い、新しいmigrationとして変更します。適用済みmigrationの編集・再実行や、一括revertによる復元は避けてください。

## 外部カレンダー連携

Appleカレンダーへの書き出し・同期は廃止しています。過去に書き出した端末の予定はアプリから削除せず、そのまま残ります。アプリ内カレンダーとローカル通知は引き続き利用できます。

## 既存の選考データ

通常の選考種類で以前入力できた補足名は、現在の入力欄や一覧に表示しなくても保存データを保持しています。「その他」の名前は引き続き入力・表示できます。
