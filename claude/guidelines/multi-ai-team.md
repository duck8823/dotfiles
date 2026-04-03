# Multi-AI チーム設計

## コンセプト

同じ役割を Claude / Codex / Gemini の3AIで多重化するが、**モデル比較ではなく運転モードで分担**する。

- **Claude**: foreground orchestrator
- **Codex**: background worker / verifier
- **Gemini**: read-only scout / critic

## 運転モード別ルーティング

| タスクの形 | 主担当 | 補助 |
|---|---|---|
| ユーザー体験を変える仕様判断 | Claude | Gemini で影響範囲確認 |
| リポジトリ横断の一貫性・命名・波及影響調査 | Gemini | Codex architect |
| scoped 実装・テスト追加・CI/CD・スクリプト | Codex | Claude が統合判断 |
| テスト作成・リファクタリング | Codex | Claude がレビュー |
| セキュリティ・エッジケース・再現確認 | Codex | Claude reviewer |
| コード調査・ドキュメント調査 | Codex | Gemini（補助） |
| 複数レイヤー統合・大規模 refactor・UI 実装 | Claude | Gemini/Codex が scout |
| マイルストーン計画・Issue 分解 | Codex + Gemini | Claude が統合 |
| レポーティング | Codex | Gemini（補助） |

### 原則

1. **Gemini を先に書かせない** — まず scout / critic として使う
2. **Codex は isolated branch / worktree 前提で書かせる**
3. **Claude は最終 diff とユーザー影響を引き受ける**
4. 迷ったら Claude を foreground、Gemini を read-only、Codex を worker として置く

## 開発フェーズ別の AI 活用

| フェーズ | Claude | Codex | Gemini |
|---|---|---|---|
| **Plan** | 統合・最終判断 | 依存分析・Wave構成・フィジビリティ・リスク | 優先度・スコープ・漏れ検出 |
| **Scout** | — | セキュリティ事前スキャン・コード調査 | repo-wide 影響範囲・一貫性 |
| **Build** | UX判断を伴う実装 | scoped 実装（isolated branch） | — |
| **Verify** | — | テスト実行・lint・セキュリティスキャン・QA | docs/config/l10n 更新漏れ |
| **Review** | 最終レビュー・統合判断 | セキュリティ・エッジケース | パターン一貫性・diff外影響 |
| **Merge** | マージゲート | — | — |

### リスク別ルーティング

| リスク | ルーティング |
|---|---|
| **Low**（定型・テスト追加等） | Codex build → Codex verify → Gemini review → Claude final |
| **Medium**（通常の機能実装） | Gemini scout → Codex build → Claude verify/integrate → multi-AI review |
| **High**（アーキテクチャ変更等） | Claude plan/build 主体、Gemini scout、Codex verifier |

### フォールバック

| 障害 | 対応 |
|---|---|
| Codex タイムアウト/失敗 | 1回リトライ → スキップ → Claude が直接実行 |
| Gemini タイムアウト/失敗 | 1回リトライ → スキップ → Codex scout で代替（一貫性精度低下を許容） |
| 部分レビュー（一部 AI のみ完了） | 完了した AI の結果で統合判断を続行。欠落を統合ログに記録 |

## タスク適性ガイド（METR RCT 2025 に基づく）

METR の RCT 研究で「経験者×馴染みのコードベースでは AI 利用で 19% 遅くなった」ことが実証された。
タスク特性に応じた使い分けが重要。

| タスク特性 | AI 活用 | 根拠 |
|---|---|---|
| ボイラープレート・テスト生成・定型コード | ◎ 積極活用 | 30-55% 高速化が一貫して確認 |
| 不慣れなコードベース・新技術の探索 | ○ 有効 | コンテキスト補完が利得 |
| 熟知したコードの小修正 | △ 任意 | 認知マップ完成済みの領域ではオーバーヘッド |
| 大規模アーキテクチャ変更 | △ 計画のみ | 実装は段階的に人間が判断 |

### 運用規則への接続

- **High risk タスクでは Claude foreground を必須**とし、Codex/Gemini は補助に留める
- **熟知したコードの小修正では AI を必須にしない**（レビューのみ任意で使用）
- タスク起票時にリスク判定を行い、上記ルーティングに従う

## 役割×AI マトリクス

| ロール | Claude (サブエージェント) | Codex (TOML) | Gemini (MD) |
|--------|------------------------|--------------|-------------|
| **Planner** | — (メインセッションで統合) | 依存分析・Wave構成・フィジビリティ・リスク・担当判定 | 優先度・マイルストーン整合・漏れ検出 |
| **Spec** | — (メインセッションで統合) | テスト戦略・セキュリティ・検証計画・ファイルスコープ | — |
| **Architect** | 依存追跡・レイヤー違反 | 責務分離・設計分割・変更単位 | — |
| **Reviewer** | バグ・コールチェーン・エラー処理 | セキュリティ・エッジケース・テスト実行 | 一貫性・パターン準拠・docs/config drift |
| **QA** | — | 探索的テスト・テスト実行 | — |
| **Designer** | デザインシステム準拠 | — | — |

- Planner / Spec は Claude サブエージェント不要。Codex が技術分析、Gemini が俯瞰チェック、Claude メインセッションが統合
- QA は Codex に移動（テスト実行・コマンド実行は Codex の得意領域）
- Designer は Claude のみ（視覚判断・UX が必要なため）
- Gemini は reviewer + planner に集中（read-only scout として最も価値が出る領域）

## 実装担当の決め方

### Claude に寄せる条件
- UI を含む
- 仕様が曖昧でユーザー体験判断が必要
- 5ファイル超の連鎖変更
- 既存実装との差分が大きく、途中で設計を変える可能性が高い
- 最終統合責任を Claude が持つべき変更

### Codex に寄せる条件
- スコープが明確
- CLI / shell / CI / config / test が中心
- セキュリティ修正やバリデーション追加
- 既存パターンがあり、背景調査より実装・検証が主
- 背景で長く走らせたい

### Gemini に寄せる条件
- 原則として **実装担当ではなく scout**
- 実装前の impact scan、PR レビュー前の consistency scan、計画時の scope scan に使う
- 例外的にドキュメント草案や分割案だけ作らせることはあるが、コード書き込みの主担当にはしない

## レビュー構成ルール

### Claude が実装した PR
- Gemini reviewer
- Codex reviewer
- Claude final review

### Codex が実装した PR
- Gemini reviewer
- Claude reviewer（Codex 代替）
- Claude final review
- Codex reviewer は利益相反回避のためスキップ

### 外部生成パッチ / Gemini 由来の変更
- Codex reviewer
- Claude reviewer
- Claude final review
- Gemini は必要なら architect 的 scout に限定

## 連携の仕方

### Gemini の実行ポリシー
- 原則 `--approval-mode plan` の read-only で実行
- `GEMINI.md` と `agents/*.md` を使い、repo-wide scan に集中させる
- finding は「どこがズレたか」「diff 外で何を追加修正すべきか」に絞る

### Codex の実行ポリシー
- write タスクは isolated branch / worktree で実行
- 返却値には **変更ファイル / 実行コマンド / 残リスク** を含める
- security / tests / CI では、憶測ではなく実行証跡を優先する

### Claude の実行ポリシー
- blocking な統合判断はメインセッションで持つ
- sidecar 調査は named subagents / Task agents に分離する
- ユーザー体験を変える最終判断は常に Claude が行う

## 開発 artifact 規約

各フェーズの中間成果物をプロジェクトルートの `.ai/` に保存する。
フェーズ間の引き継ぎに使い、PR マージ後に削除する。

```text
project/
├── .ai/
│   ├── plan/<issue番号>.md      # Plan フェーズ: Wave構成・依存・リスク
│   ├── spec/<issue番号>.md      # Spec フェーズ: 実装手順・テストケース・完了条件
│   ├── verify/<issue番号>.json  # Verify フェーズ: 実行コマンド・結果・残リスク
│   └── review/<pr番号>.json     # Review フェーズ: 統合レビュー結果
├── .ai-logs/                    # 観測可能性ログ（.gitignore 対象）
├── .claude/agents/
├── .codex/agents/
├── .gemini/agents/
└── AGENTS.md
```

### ルール

- `.ai/` は**バージョン管理に含める**（レビュー対象にするため）
- PR マージ後に該当 Issue/PR の artifact を削除する
- `.ai-logs/` は**バージョン管理に含めない**（`.gitignore` 対象）
- 既存の `.spec/` を使っているプロジェクトは `.ai/spec/` に移行する

### artifact の所有者

| artifact | 生成者 | 消費者 |
|---|---|---|
| `plan/` | Claude メインセッション（Codex/Gemini planner の統合結果） | 実装担当（Claude or Codex） |
| `spec/` | `/spec-driven` スキル（3AI統合） | 実装担当 |
| `verify/` | Codex verifier | Claude（最終レビュー時に参照） |
| `review/` | `/multi-ai-review` スキル（multi-AI 統合） | Claude（マージ判断時に参照） |

## エージェント自律性の境界線（AGENTS.md Guardrails）

各プロジェクトの `AGENTS.md` に以下を明記すること。

```markdown
## Guardrails

### 自律実行を許可する範囲
- ファイルの読み取り・検索
- テスト・lint・静的解析の実行
- .ai/ artifact の生成・更新
- ドラフト PR の作成

### 人間の承認が必要な範囲
- PR のマージ
- 本番環境への操作
- 外部サービスへの書き込み（Slack, メール等）
- セキュリティに関わる設定変更
- ユーザー体験を変える仕様判断

### 禁止事項
- main への直接 push
- シークレット・認証情報のコミット
- .gitignore 対象ファイルのコミット
```

## エージェント定義の配置

```text
project/
├── .claude/agents/     # Claude サブエージェント
├── .codex/agents/      # Codex エージェント
├── .gemini/agents/     # Gemini エージェント
└── AGENTS.md           # クロスツール共通コンテキスト + Guardrails
```

## 共通出力形式（Reviewer / Architect ロール）

```json
{
  "source": "<ai>-<role>",
  "findings": [
    {"severity": "CRITICAL|HIGH", "file": "path:line", "issue": "...", "fix": "..."}
  ],
  "summary": "問題なし"
}
```

必要に応じて `evidence`, `impacted_files`, `validated_commands` 等の補助フィールドを追加してよい。

## 観測可能性（エージェント実行ログ）

Multi-AI 実行の結果と統合判断を構造化ログとして保存し、ハーネス改善の材料にする。

### ログ保存ルール
- 各エージェントの結果 JSON をプロジェクトルートの `.ai-logs/{YYYY-MM-DD}-{role}-{ai}.json` に保存
- 統合判断時に各指摘の「採用/棄却」理由を統合ログ `{date}-integration.json` に記録
- 失敗・スキップしたエージェントは理由を統合ログに含め、`gh pr comment` にも記載

### 統合ログ形式
```json
{
  "date": "2026-04-02",
  "pr": "#123",
  "agents": [
    {"source": "codex-reviewer", "status": "success", "findings_count": 2},
    {"source": "gemini-architect", "status": "skipped", "reason": "timeout after retry"}
  ],
  "decisions": [
    {"file": "path:line", "adopted": true, "agreed_by": ["codex-reviewer", "claude-reviewer"], "reason": "2AI一致"},
    {"file": "path:line", "adopted": false, "agreed_by": ["gemini-architect"], "reason": "repo 実読で誤検出"}
  ]
}
```

### ログの活用
- `.ai-logs/` はバージョン管理に含めない（`.gitignore` に追加）
- マイルストーン完了時のハーネスレトロスペクティブで参照する

## 出力バリデーション

| 状況 | 対応 |
|---|---|
| JSON パース失敗 | 1回リトライ、2回目失敗 → スキップ＋統合ログに記録 |
| `findings` 要素に `file` / `severity` / `issue` が欠落 | 該当エントリを除外、残りは処理続行 |
| `source` フィールドが期待値と不一致 | 警告付きで処理続行 |
| 出力が空 or `findings` が空配列 | 正常（指摘なし）として扱う |

## 統合判断ルール（Claude メイン）

1. 各ロールの結果を読み込む
2. 同じファイル:行に対する指摘を統合（2AI以上 → 高信頼）
3. 1AIのみの指摘 → ソースコード実読で誤検出フィルタ
4. CRITICAL は無条件採用
5. PR コメントに統合結果を投稿
6. Critical / High があれば修正して再レビュー

## 契約プラン

| サービス | プラン | 主な役割 |
|---|---|---|
| Claude | Max / Pro | 実装・最終レビュー・統合判断・Computer Use |
| ChatGPT | Pro / Plus | Codex で worker / verifier / research |
| Google AI | Pro / Free | Gemini CLI で scout / critic / planning |

## Claude 制限到達時のフォールバック

1. 実装タスク → Codex に scoped handoff（Codex が主力のため影響小）
2. レビュー → Gemini + Codex で継続（Claude は最終判断のみ）
3. 調査 → Codex（コード・ドキュメント）/ Gemini（俯瞰チェック）
4. 対話 → ChatGPT / WebSearch を併用

Claude の制限到達リスクを下げるため、日常的に以下を Codex に委譲する:
- テスト作成・リファクタリング
- コード調査・ドキュメント調査
- レポーティング
- スコープが明確な実装
