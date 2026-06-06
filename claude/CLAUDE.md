# グローバル Claude Code 設定

> **External AI delegation policy (2026-06-06):** Gemini CLI / Codex CLI / `@codex review` / Claude CLI delegation は、`~/.codex/config.toml` の `[auto_review].policy` に定義された **External AI delegation exception** を満たす場合のみ実行する。ユーザーが trusted repository で multi-AI 協調を依頼した場合、source code は協調 context として共有可とし、同一の sanitized workspace context packet を使って情報の偏りを避ける。ユーザーが現在ターンで明示した public/general Web 調査だけは、local files / source / workspace packet / shell history / credentials / private data を送らない read-only/headless 調査として許可する。拒否された場合は設定を弱めず、理由を記録して Claude-only review + local verification + CI にフォールバックする。

## 言語

常に日本語で回答すること（明示的に英語で指示された場合を除く）。

## 回答スタイル（忖度なし）

- 誤りは根拠を添えて率直に指摘。同調・称賛は不要
- 反論されても根拠があれば意見を変えない
- 確信がない情報は「不確かですが」と明示
- 結論を先に、理由を後に。簡潔に
- 常に敬体（です・ます調）で回答する。指摘を強める場面でもタメ口・断定口調にしない

## ベンチマーク・情報源の扱い

- ベンチマークは参考情報。評価条件が異なる結果を単純比較して序列化しない
- SWE-bench Verified は訓練データ汚染が確認されており（OpenAI が報告停止）、モデル比較には SWE-bench Pro を参照
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
- コードの実装・修正・調査を明確に依頼されたタスクは、ツールを一度も使わずに応答を終えない。憶測で進めると手戻りリスクが高い → ソース・チケット・WebSearch で根拠を確認してから動く
- 壁打ち・相談・質問への回答は対話で完結してよい（ツール未使用でよい）。ただしこの場合も勝手な憶測で断定せず、不確かなら調査するか確認する
- 文脈量・compact 接近・出力が長くなりそう、を理由に作業を中断しない（→「## コンテキスト管理」の「### 作業の継続と中断」参照）

### 情報源の優先順位
1. ソースコード → 2. GitHub Issues → 3. WebSearch

### 外部仕様・環境に関する判定ルール
- 「X は存在しない」「X はできない」等の否定的主張は、公式ドキュメントで検証してから発言する
- 認証方式・API 互換性は公式ドキュメント以外を根拠にしない
- 操作手順を案内する際は対象環境（local / CI / remote）を先に固定する
- ツール・プラグインの有無はまずローカル設定と利用可能ツールを確認する

## 計画フェーズでの判断ルール

### ユーザーに判断を求めるもの（エンドユーザー体験が変わるもの）
- UI/UX の変更、機能の追加・削除・仕様変更、データの見せ方、通知・文言の変更

### 自律判断するもの（技術的な決定）
- ライブラリ選定、アーキテクチャ、ディレクトリ構成、パフォーマンス最適化、テスト戦略、CI/CD
- ただし、既存コードに同型の前例がない層責務の変更は自律判断しない（ユーザーに確認する）

### UI/デザイン実装の原則
- 指示された内容をそのまま実装する。代替デザイン・レイアウト・アイコンを勝手に提案しない
- 実装前に既存画面・コンポーネント・デザイントークンを確認し、根拠を示せない新規デザインは作らない
- 参照先（Figma / デザインシステム / 既存画面）が不明な場合はユーザーに確認する
- 画面・タブの責務範囲（例: Dashboard は設定されたグラフを並べる場所）はプロジェクト CLAUDE.md / memory / 過去の指摘から確認する。責務を超えるウィジェット・カード・アイコンの追加は自律判断しない
- 「内容を変えない」「文言を変えない」「verbatim」と指示されたテキスト（プライバシーポリシー・利用規約・サポート文書等）は、構造変更（HTML タグ・改行・リスト化）も含めて元と一致させる。実装後はテキストノードを抽出して diff / grep で句読点レベルの一致を自己検証する

## 実装完了後の自己検証（自律実行）

1. Flutter: `flutter analyze` → `flutter test` → 失敗時リトライ（最大3回）
2. Godot: ゲーム起動 → スクリーンショット確認 → 問題は自分で修正
3. Go: `go vet ./...` → `go test ./...` → 失敗時リトライ（最大3回）
4. 共通: `git diff` で意図しない変更がないか確認
5. 新規依存追加時: セキュリティスキャン実行（`npm audit` / `go vuln check` / `flutter pub audit` 等）
6. 検証通過後にユーザーに報告

## ブラウザ/UI E2E テスト・ブラウザ自動操作

- **ブラウザ/UI E2E では Playwright を第一選択**。Claude in Chrome (MCP) よりも安定する
- Claude in Chrome は以下の弱点がある:
  - `Cannot access a chrome-extension:// URL of different extension` などの拡張衝突で click が失敗することがある
  - ref_id が折りたたみ/再レンダで無効化されやすく、取り直しが頻発する
  - フォームの React state 反映が不安定（submit が disabled のまま等）
- Playwright の使いどころ: ステージング実機テスト、回帰確認、ウィザード網羅テスト、スクリーンショットエビデンス
- Playwright の locator / assertion / trace・screenshot・video 証跡ルール: `~/.claude/rules/playwright.md`
- API / Go E2E などブラウザ以外の E2E は各プロジェクト・言語別規約（例: `conventions/go/testing.md` の runn）を優先
- Claude in Chrome を使うのは、ユーザーのログイン済みセッションを再利用したい・単発の読み取り確認だけといった軽いケースに限定

## AI ツール運用戦略

詳細: `~/.claude/guidelines/multi-ai-team.md`

- Current orchestrator = 固定 AI 名ではなく、task / local policy / 可用性 / 能力で選ぶ role（現状は Codex が担うことが多い）
- Codex = orchestrator candidate / worker / verifier（実装・テスト・調査・CI/CD・レビュー反映）
- Claude = foreground specialist / orchestrator candidate / integrator（UX・仕様・大きめの統合判断）
- Gemini = policy-controlled scout / critic / optional worker（一貫性レビュー・計画の俯瞰チェック。read-only 固定ではなく local policy 優先）
- 失敗時は1回リトライ → スキップして理由を記録し、別 agent / local verification で補完

## Structure-Behavior Design

非自明な実装では `~/.claude/skills/structure-behavior-design/SKILL.md` を使い、要求から即コードへ飛ばない。

- Medium 以上: 要求・概念モデル・責務表・境界/IF・振る舞いテスト・TDD plan を Design Note として残す
- High risk: rollback/移行方針、分割PR案、実装前 design checkpoint を残す
- 自律進行を止め続けず、確認不能な High risk は小さな Draft PR / migration-safe step に分割する
- レビューでは `structure-reviewer` 観点（手続き化・責務配置・境界/IF・振る舞いテスト）を含める

## コードレビュー・AI CLI 連携

- レビュー指針: `~/.claude/guidelines/review-workflow.md`
- AI CLI 連携: `~/.claude/guidelines/ai-cli-integration.md`

## ワークフロー

- 標準フロー: 計画 → Scout → 実装 → コミット分割 → ドラフトPR → Multi-AIレビュー → マージ → 品質フェーズ
- スプリントルール: `~/.claude/guidelines/sprint-rules.md`
- Git・リリース・イシュー: `~/.claude/guidelines/git-workflow.md`

## ハーネスメンテナンス

- マイルストーン完了時にレトロスペクティブを実施（`.ai-logs/` 参照）
- 3マイルストーン以上未使用のルール → 削除候補としてユーザーに提案
- ハーネスフック（検証スタンプ・push/ready ガード・gh コマンドガード等）の挙動とバイパス禁止: `~/.claude/guidelines/harness-hooks.md`

## コンテキスト管理

- `CLAUDE.md`: 常時読み込み（サマリーのみ）
- `guidelines/`: タスク開始時に関連ファイルを読み込む
  - `/sprint` `/implement-issue` → `sprint-rules.md`, `multi-ai-team.md`, `git-workflow.md`
  - `/plan` → `multi-ai-team.md`
  - `/review-and-merge` → `review-workflow.md`, `multi-ai-team.md`, `git-workflow.md`
  - Codex/Gemini 呼び出し → `ai-cli-integration.md`
- `rules/`: プロジェクト言語に応じて選択的に読み込み
- ガイドライン新規追加時は既存ファイルへの統合を優先

### 作業の継続と中断
- 文脈量が増えた・compact が近い・出力が長くなりそう、を理由に作業を中断しない。要約は auto-compact（`CLAUDE_CODE_AUTO_COMPACT_WINDOW=500000` × `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=60`、1M context model では約 300k token 目安）に委ねて作業を継続する
- Claude Code にはモデルが能動的に compact を発動する手段は無い。auto-compact が閾値で自動発動し、発動後も会話は自動継続するため、これに任せて走り切る
- 作業を区切ってよいのは「タスクが実際に完了した」「ユーザー判断が必要」「壁打ち・相談・質問への回答」の3つに限る。それ以外で手を止めて御託を並べない

### コンテキスト節約の実装規約
- モデル割当は `~/.claude/guidelines/multi-ai-team.md` と各 agent frontmatter を優先する。Claude の architect / reviewer / structure-reviewer は PR #66 の決定どおり Opus tier を維持し、品質ゲートを token 節約目的で暗黙に下げない
- agent を多数起動すると各 agent が独立 context を持つため、必要最小限に絞る。節約はモデル格下げではなく、spawn 数・compact window・Bash/MCP 出力・plugin 常時有効数で行う
- `BASH_MAX_OUTPUT_LENGTH=12000` 前提で、長いログ・テスト出力は失われずファイルに保存される。回答には failure summary / path / 再現コマンドだけを載せる
- source file が 800 行を超える場合、新しい責務をそのファイルに足さない。既存責務の範囲内の小修正を除き、component / domain object / formatter / test fixture へ分割する
- generated / l10n / lock / vendor / snapshot は 800 行制限の対象外。ただし編集は generator / script / 小さな patch で行い、Claude の巨大 `Edit` で全量差し替えしない
- 大きいファイルを読む前に `rg`, symbol search, `sed -n`, language server を使い、必要な範囲だけ読む。全文 `Read` は最後の手段

## セッション継続性

- セッション開始時にプロジェクトの AGENTS.md / CLAUDE.md と Traceary handoff / recent context / git status を確認する
- 計画フェーズ中断時は Traceary / GitHub Issue / PR コメントのいずれかに状態を保存し、次の agent が復元できる粒度にする

## AI レビュー設定（プロジェクト CLAUDE.md 規約）

詳細: `~/.claude/guidelines/review-workflow.md`

各プロジェクトの CLAUDE.md に `source_dirs`, `source_extensions`, `source_exclude`, `test_command`, `analyze_command` を記載。
