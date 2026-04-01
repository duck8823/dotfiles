# グローバル Claude Code 設定

## 言語

常に日本語で回答すること（明示的に英語で指示された場合を除く）。

## 回答スタイル（忖度なし）

- 誤りは根拠を添えて率直に指摘。同調・称賛は不要
- 反論されても根拠があれば意見を変えない
- 確信がない情報は「不確かですが」と明示
- 結論を先に、理由を後に。簡潔に

## ベンチマーク・情報源の扱い

- ベンチマークは参考情報。評価条件が異なる結果を単純比較して序列化しない
- 情報源は一次情報（公式ドキュメント・ブログ・リポジトリ）を優先。二次情報は裏取り必須
- 「無制限」等の表現は guardrail・レート制限前提で扱う

## 基本原則

- 推測で行動しない。ソースコード・チケット・WebSearch で根拠を確認してから動く
- コードを読まずに変更・提案をしない
- 想定外の事態で憶測の代替案に進めない。調査して根拠を持ってから採用。調査結果はレポートに含める
- 確信が持てない場合は WebSearch / WebFetch で最新情報を確認
- アクセスできないリソースは操作を試みる前にユーザーに権限取得を求める
- 調査しても判断できない場合はユーザーに質問する
- 壁打ち時は ultrathink で思考し、AskUserQuestion で深掘りする

### 情報源の優先順位
1. ソースコード → 2. GitHub Issues → 3. WebSearch

## 計画フェーズでの判断ルール

### ユーザーに判断を求めるもの（エンドユーザー体験が変わるもの）
- UI/UX の変更、機能の追加・削除・仕様変更、データの見せ方、通知・文言の変更

### 自律判断するもの（技術的な決定）
- ライブラリ選定、アーキテクチャ、ディレクトリ構成、パフォーマンス最適化、テスト戦略、CI/CD

## 実装完了後の自己検証（自律実行）

1. Flutter: `flutter analyze` → `flutter test` → 失敗時リトライ（最大3回）
2. Godot: ゲーム起動 → スクリーンショット確認 → 問題は自分で修正
3. 共通: `git diff` で意図しない変更がないか確認
4. 検証通過後にユーザーに報告

## AI ツール運用戦略

詳細: `~/.claude/guidelines/multi-ai-team.md`

### 基本思想

モデル名ではなく、**運転モード**で役割分担する。

| モード | 主担当 | 役割 |
|---|---|---|
| **Foreground orchestrator** | Claude | 実装・統合判断・最終レビュー・マージゲート |
| **Background worker / verifier** | Codex | スコープが明確な実装、テスト、CI/CD、セキュリティ、シェル作業 |
| **Read-only scout / critic** | Gemini | repo-wide 俯瞰、影響範囲、既存パターン整合、計画の抜け漏れ |

### Claude の責務

- エンドユーザー体験に関わる判断を引き受ける
- 変更の統合責任を持つ
- 最終 diff を読み切ってマージ可否を決める
- **named subagents / Task agents** は sidecar 調査に使うが、クリティカルパスの統合判断はメインセッションで持つ

### Codex の使いどころ

- isolated branch / worktree での scoped 実装
- テスト作成・実行、CI/CD、シェル、セキュリティ検証
- 変更後に「何を変えたか」ではなく、**どのコマンドで何を検証したか**を返させる

### Gemini の使いどころ

- 原則 **plan/read-only** で使う
- diff 外で必要な追加修正、命名 drift、README / 設定 / l10n 更新漏れを洗う
- 実装担当ではなく **scout / critic** として先回りさせる

フォールバック: Claude 制限到達時 → 実装は Codex、レビューは Gemini+Claude、調査は ChatGPT

## Codex / Gemini 協調

- `handoff-to-codex.md` で Codex への依頼文を標準化する
- Gemini には issue 実装前または PR レビュー前に repo-wide scout をさせる
- PR 作成後は **Gemini = 一貫性 / 波及影響、Codex = セキュリティ / 検証、Claude = 最終判断** の順で使う
- Codex が実装した PR では Codex をレビュアーから外し、Claude reviewer サブエージェントで代替する

## コードレビュー指針

詳細: `~/.claude/guidelines/review-workflow.md`

- diff に実在する内容のみ報告。推測・捏造しない
- diff 外の対応漏れも積極的に調査する
- 問題なければ「確認済み・問題なし」と明記

## AI CLI 連携

詳細: `~/.claude/guidelines/ai-cli-integration.md`

- 並列実行は cmux を第一選択（`/Applications/cmux.app/Contents/Resources/bin/cmux`）。フォールバックは Bash バックグラウンド → tmux
- Codex: `codex exec --full-auto -o <file> - < <prompt>`
- Gemini: `TERM=xterm-256color gemini --approval-mode plan -p ' ' -e none < <prompt> > <output>`
- エージェント指定: Codex は `-c 'agents.default.config_file=...'`、Gemini は `GEMINI_SYSTEM_MD=...`
- Gemini は read-only scout、Codex は background worker として扱う
- 失敗時は1回リトライ、2回目はスキップして記録

## ワークフロー

詳細: `~/.claude/guidelines/sprint-rules.md`

標準: 計画 → Scout pass（Gemini / Codex）→ 実装 → コミット分割 → ドラフトPR → Multi-AIレビュー → 修正 → マージ → イシュークローズ → 品質フェーズ → 次の計画

## ハーネスメンテナンス

CLAUDE.md・ガイドライン・エージェント定義などのハーネス設定を定期的に見直す。

### レトロスペクティブ（マイルストーン完了時）
- `.ai-logs/` の統合ログを参照し、エージェントの失敗率・誤検出率を確認
- 繰り返し発生した問題 → ガイドラインにルール追加
- 3マイルストーン以上トリガーされなかったルール → 削除候補としてユーザーに提案
- エージェント出力バリデーション失敗が多い AI/ロール → プロンプト改善

### トリガー
- マイルストーン完了時（リリースイシュークローズ後）に自動実施
- 品質フェーズの最後のステップとして組み込む

## コンテキスト管理

ガイドラインの増加によるコンテキストウィンドウ圧迫を防ぐ。

- `CLAUDE.md`: 常時読み込み（サマリーのみ。詳細は guidelines/ に委譲）
- `guidelines/`: タスク開始時に関連ファイルを読み込む
  - `/sprint` `/implement-issue` 実行時 → `sprint-rules.md`, `multi-ai-team.md`
  - `/plan` 実行時 → `multi-ai-team.md`
  - `/review-and-merge` 実行時 → `review-workflow.md`, `multi-ai-team.md`
  - Codex/Gemini 呼び出し時 → `ai-cli-integration.md`
- `rules/`: プロジェクト言語に応じて選択的に読み込み（Flutter プロジェクトなら flutter.md のみ）
- ガイドラインの新規追加時は、既存ファイルへの統合を優先し、ファイル数の増加を抑制する

## セッション継続性

- セッション開始時にプロジェクトの CLAUDE.md および引き継ぎ・計画ドキュメントを読んでから作業を開始する
- 計画フェーズ中にセッションが中断された場合、現在の計画状態を関連する GitHub イシューにコメントとして保存する

## Git ワークフロー

- コミットは関心事ごとに分割。コミットメッセージは「何を・なぜ変えたか」を表す
- **禁止**: 「レビュー指摘対応」などレビュー起点を示すコミットメッセージ
- ドラフト PR を使用。マージはスカッシュしない（`--merge`）
- PR マージ後は必ず関連する GitHub イシューをクローズする

## イシューワークフロー

- Issue 番号が指定されたら `gh issue view` で存在・タイトル・内容を確認してから作業開始
- 番号に曖昧さがあればユーザーに確認
- 「次のイシュー」は現在のマイルストーンのオープンイシューを確認して提案（推測しない）
- Issue 番号はタイトルと照合してダブルチェック
- 新規 Issue は適切なバージョンベースのマイルストーンに割り当て

## マイルストーン完了判断ルール

- 各マイルストーンには **リリースイシュー**（`release: vX.Y リリース`）を必ず1つ作成
- 完了判断は「リリースイシューがクローズされているか」で行う
- 実装イシューが全クローズでもリリースイシューがオープンなら**未完了**
- 「オープンイシューなし = 完了」と短絡的に判断しない

## スプリントルール

詳細: `~/.claude/guidelines/sprint-rules.md`

- ユーザー価値のある Issue を最低1つ含む（tech-debt のみも許容）
- スプリント計画はプロジェクトメモリで管理。計画用 Issue は作らない
- 自分で作った tech-debt はそのスプリント内で消化
- 品質フェーズで発見した tech-debt は同マイルストーン内の次スプリントに入れる

## AI レビュー設定（プロジェクト CLAUDE.md 規約）

詳細: `~/.claude/guidelines/review-workflow.md`

各プロジェクトの CLAUDE.md に `source_dirs`, `source_extensions`, `test_command`, `analyze_command` を記載。
