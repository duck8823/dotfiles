# Multi-AI チーム設計

## コンセプト

同じ役割を Claude / Codex / Antigravity の3AIで多重化するが、**モデル比較ではなく運転モードとローカルポリシーで分担**する。Orchestrator は固定 AI 名ではなく role であり、現状は Codex が担うことが多いだけと扱う。

- **Codex**: current orchestrator candidate / worker / verifier
- **Claude**: foreground specialist / orchestrator candidate / integrator
- **Gemini**: policy-controlled scout / critic / optional worker

共有 dotfiles は安全側のデフォルトを配るだけで、Antigravity を恒久的に read-only 固定しない。各マシン・各リポジトリでは `conventions/ai/local-agent-policy.md` に従い、Antigravity の無効化・approval mode・write 可否を上書きできる。

## モデル世代と Dynamic Workflows（2026-05 更新）

役割をモデル比較で決めない原則は不変。**primary orchestrator は現状 Codex（GPT-5.5）を維持**する。Claude Code Opus 4.8（2026-05-28 / `claude-opus-4-8` / Claude Code v2.1.154+）で次が利用可能になった。

- **effort**: low / medium / high（既定）/ xhigh / max。`auto` は独立段階ではなくモデル既定への reset。max・ultracode は settings に固定不可（セッション指定）。
- **Dynamic Workflows**（research preview）: Claude が orchestration script（JS）を書き、会話と隔離された runtime が subagent 群を実行する。**同時最大 16 / 1 run 総計 1,000 agent 上限 / 同一セッション内のみ resumable**。「数百並列」はマーケ表現で、実態は「上限 1,000 を最大 16 並列で消化」。
- **ultracode**: xhigh 送信 + 実質タスク毎に workflow を自動編成（理解→変更→検証を別 workflow に分割）。

### 棲み分け（追加指針）

- **ローカルで再実行可能・検証収束型**（敵対的検証で findings を絞る、context 汚染を避けて多数 subagent を回す、codify した orchestration）→ **Claude Code ultracode / Dynamic Workflows**
- **cloud VM 隔離の並列実行・長時間 long-horizon 自律・実データ接続（SSH）** → **Codex（GPT-5.5）**

### 役割委任の更新ルール

- 新モデル発表時は **委任先モデルだけ更新**し、役割の枠組み（current orchestrator = role）は維持する。
- **スコア序列だけで orchestrator / verifier を入れ替えない**。ベンチは評価条件差・汚染・loophole があり単純序列化しない（例: SWE-bench Pro は Claude 系の `.git` loophole 悪用が報告され、汚染耐性の DeepSWE では GPT-5.5 が Opus を逆転）。比較は SWE-bench Pro を参照しつつ、得意領域の差（Opus=SWE-bench Pro / tool 協調 / HLE、GPT-5.5=Terminal 自律 / 長時間 / 数学 / 長文脈）として扱う。
- アーキテクチャ設計・責務境界・公開 API 追加実装は最も高能力な Claude Opus tier（現状 Opus 4.8）へ委任、Codex はオーケストレーション・レビュー・検証を主担当（Traceary durable memory と整合）。

## 相互協調ポリシー

multi-AI 協業は一方向の handoff ではなく、Traceary / git / PR / Issue から context を復元し、現在の orchestrator が次の agent を選ぶ。現在の orchestrator は Codex に固定しない。

- **Current orchestrator**: 全体進行、実装、検証、レビュー反映、PR コメント集約を担当する
- **Claude specialist**: UX・仕様・大きめの統合判断、Claude Code 固有の作業、最終説明を担当する
- **Antigravity scout / worker**: repo-wide consistency、計画漏れ、diff 外影響、local policy が許す scoped task を担当する
- **Traceary**: 手書き引き継ぎの代替。session handoff / recent context / durable memory / command audit から resume packet を作る

`multi-ai-review` / `context-resume` / `Claude Code` / `Gemini` / `Codex` が明示され、かつ `~/.codex/config.toml` の `[auto_review].policy` を満たす場合、対象リポジトリの PR diff・関連 Issue・レビューコメント・該当ソース・テストログは configured external AI CLI に渡してよい。secrets・認証情報・repo 外 private file・本番/個人データ raw dump は毎回追加確認または policy deny とする。

## 運転モード別ルーティング

| タスクの形 | 標準担当 | 補助 |
|---|---|---|
| 自律的な Issue/PR 進行 | Current orchestrator（現状は Codex が多い） | Claude / Antigravity / Codex |
| scoped 実装・テスト追加・CI/CD・スクリプト | Codex | Antigravity / Claude review |
| セキュリティ・エッジケース・再現確認 | Codex verifier | Claude reviewer |
| コード調査・ドキュメント調査 | Codex | Antigravity / Claude |
| リポジトリ横断の一貫性・命名・波及影響調査 | Gemini または Codex scout | Claude / Codex integrator |
| ユーザー体験を変える仕様判断 | Claude | Codex / Antigravity が影響範囲確認 |
| 複数レイヤー統合・大規模 refactor | Codex + Claude | Antigravity scout |
| マイルストーン計画・Issue 分解 | Codex + Gemini | Claude が必要時に統合 |

### 原則

1. **現在の orchestrator role を明示する** — 多くの作業では現状 Codex が主導するが、能力・可用性・local policy に応じて Claude / Antigravity / Codex のいずれにも切り替えられる。
2. **agent の可否は local policy で決める** — Gemini 禁止環境では無理に起動せず `local_policy_disabled` として記録する。
3. **write は branch / worktree gate を通す** — Antigravity でも Claude でも Codex でも、write は main/master 直下で実行しない。
4. **記録と代替（ただし認証は停止）** — quota / capacity / timeout / policy deny / disabled は理由を残し、別 agent / local verification / CI へ進む。**login / 認証失敗だけは fallback せず停止し、ユーザーに認証修正を促す**（暗黙の engine 代替は設定不備を隠す）。

## 開発フェーズ別の AI 活用

| フェーズ | Codex | Claude | Gemini |
|---|---|---|---|
| **Plan** | 依存分析・Wave構成・フィジビリティ・リスク・統合 | UX/仕様判断が必要な論点の整理 | 優先度・スコープ・漏れ検出 |
| **Scout** | セキュリティ事前スキャン・コード調査・Structure-Behavior risk 分類 | structure-behavior design note 統合 | repo-wide 影響範囲・一貫性・構造 drift |
| **Build** | scoped 実装（isolated branch） | UX判断を伴う実装 | local policy が許す scoped task |
| **Verify** | テスト実行・lint・セキュリティスキャン・QA | 失敗解釈・追加確認 | docs/config/l10n 更新漏れ |
| **Review** | セキュリティ・エッジケース・構造レビュー・PR コメント集約 | 変更意図とユーザー影響 | パターン一貫性・diff外影響・構造 drift |
| **Merge** | PR gate / review 収束 | 必要時の最終説明・ユーザー確認 | — |

### リスク別ルーティング

| リスク | ルーティング |
|---|---|
| **Low**（定型・テスト追加等） | Codex build → Codex verify → optional Gemini/Claude review |
| **Medium**（通常の機能実装） | structure-behavior design note → Codex build → multi-AI review → Codex integrate |
| **High**（アーキテクチャ変更等） | structure-behavior design note + 分割PR案 → Codex/Claude で設計判断 → scoped PR → multi-AI review |

### フォールバック

| 障害 | 対応 |
|---|---|
| 認証 / ログイン失敗 | **fallback せず停止**しユーザーに認証修正を依頼（別 agent へ暗黙代替しない） |
| local policy disabled | 起動せず `local_policy_disabled` として記録。残りの agent で補完 |
| Codex タイムアウト / capacity 失敗 | 1回リトライ → Claude / local shell verification で補完 |
| Gemini タイムアウト / capacity 失敗 | 1回リトライ → Codex scout / Claude reviewer で代替 |
| Claude headless 失敗 | Codex が repo context と Traceary を読んで継続 |
| 部分レビュー（一部 AI のみ完了） | 完了した AI の結果で統合判断を続行。欠落を統合ログに記録 |

> **fallback でレビューを代替する場合、代替レビュアーは実装に使ったモデルと同等以下にしない**（実装より上位モデル、または上位 effort で行う）。詳細は `conventions/ai/quality-gates.md` を参照。

## 役割×AI マトリクス

| ロール | Codex | Claude | Gemini |
|--------|-------|--------|--------|
| **Orchestrator** | 現状の標準候補 | 必要時・能力次第 | local policy 次第 |
| **Planner** | 依存分析・Wave構成・フィジビリティ | 統合・仕様論点 | 優先度・マイルストーン整合・漏れ検出 |
| **Spec** | テスト戦略・セキュリティ・検証計画・ファイルスコープ | UX/仕様の補足 | 既存パターン・影響範囲 |
| **Architect** | 責務分離・設計分割・変更単位 | 依存追跡・レイヤー違反 | 構造 drift |
| **Structure Reviewer** | 手続き化・責務配置・振る舞いテスト | 手続き化・責務配置・境界/IF | 構造 drift・diff外影響 |
| **Reviewer** | セキュリティ・エッジケース・テスト実行 | バグ・コールチェーン・エラー処理 | 一貫性・パターン準拠・docs/config drift |
| **QA** | 探索的テスト・テスト実行 | UX 確認 | local policy 次第 |
| **Designer** | — | デザインシステム準拠 | — |

## Context resume

廃止済みの手書き Codex 引き継ぎコマンドではなく、以下を標準にする。

1. Traceary handoff / recent context / durable memory を確認する。
2. `git status --short --branch`、base diff、open PR / Issue を確認する。
3. objective / current_state / blockers / validation state を resume packet にまとめる。
4. 足りない情報だけ質問し、安全に進められる作業は止めない。
5. 外部 AI へ渡す場合は sanitized workspace packet に蒸留する。

## 開発 artifact 規約

各フェーズの中間成果物をプロジェクトルートの `.ai/` に保存できる。Traceary にも session / command / review context を残し、次の agent が復元できるようにする。

```text
project/
├── .ai/
│   ├── plan/<issue番号>.md      # Plan フェーズ: Wave構成・依存・リスク
│   ├── spec/<issue番号>.md      # Spec フェーズ: 実装手順・テストケース・完了条件
│   ├── verify/<issue番号>.json  # Verify フェーズ: 実行コマンド・結果・残リスク
│   └── review/<pr番号>.json     # Review フェーズ: 統合レビュー結果
├── .ai-logs/                    # 観測可能性ログ（.gitignore 対象）
├── AGENTS.md
├── CLAUDE.md
└── AGENTS.md
```
