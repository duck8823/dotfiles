# Issue #97: Gemini CLI 連携を Antigravity CLI へ移行する

## Structure-Behavior Design Note

### Requirement summary
- 目的: dotfiles の Gemini CLI 前提を Antigravity CLI (`agy`) 前提へ移し、multi-AI 調査・監査・インストール・安全フックを新しい CLI 表面に合わせる。
- 現状: Gemini CLI 用の `~/.gemini/settings.json`、`gemini/agents/*.md`、`gemini --approval-mode plan` 実行、Traceary Gemini hook 前提が複数箇所に残っている。
- 期待する振る舞い: 共有既定は `claude,antigravity,codex` になり、Antigravity 設定は `~/.gemini/antigravity-cli/settings.json` に同期される。既存 Gemini 設定は managed なら掃除し、local override は保持する。
- 非対象: Traceary 側の Antigravity hook/package 実装そのもの。v0.21.0 の doctor 警告どおり、公開 hook contract がない間はキャプチャ未対応として扱う。

### Conceptual model
| Concept | State | Behavior | Constraint / Invariant |
|---|---|---|---|
| Antigravity engine | `agy` CLI, headless print | sanitized prompt を stdin で受け、結果を bundle に保存する | repo 直接読みに戻さず、packet sha256 で監査する |
| Legacy Gemini | 明示指定時だけ使う旧 engine | 既存の失敗分類・skip を維持する | default engine にはしない |
| Managed settings | managed hash 追跡 | unedited は自動更新/廃止掃除、edited は保持 | local override を破壊しない |
| Traceary Antigravity diagnostic | doctor-only | `traceary doctor --client antigravity` を監査する | `hooks print --client antigravity` は呼ばない |

### Responsibility assignment
| Responsibility | Owner | Reason to change | Not owner / reason |
|---|---|---|---|
| CLI 実行・失敗分類 | `scripts/multi-ai-research.sh` | headless engine の境界と evidence を一元化 | README は説明のみ |
| ローカル設定同期 | `install.sh` | dotfiles 管理ファイルの生成・移行・cleanup の責務 | tests は観測可能な振る舞いのみ |
| 安全ブロック | `claude/hooks/check-codex-worktree.sh` | write-capable CLI の main/worktree gate | multi-ai script は per-run 安全設定のみ |
| Traceary/CLI 監査 | `scripts/audit-agent-observability.sh` | 現在の hook/doctor 状態を bundle 化 | install は診断しない |

### Boundaries / interfaces
| Boundary or interface | Consumer | Hidden detail | Error contract |
|---|---|---|---|
| `--engines claude,antigravity,codex` | Claude/Codex commands, user | `agy --print --sandbox` の呼び出し詳細 | `classification` と exit code を status に残す |
| `~/.gemini/antigravity-cli/settings.json` | Antigravity CLI | managed hash / candidate file | local edit 衝突時は `.dotfiles-new` |
| `MULTI_AI_ANTIGRAVITY_*` | local policy | allowlist parser | 未許可 key は無視 |
| Traceary antigravity doctor | audit script | hook unsupported detail | doctor warn は evidence として保存 |

### Behavior tests
| Behavior | Given | When | Then | Level |
|---|---|---|---|---|
| default engine migration | policy unset | multi-ai dry-run | `engines_effective: claude,antigravity` | script test |
| Antigravity settings sync | clean HOME | install.sh | `~/.gemini/antigravity-cli/settings.json` と hash が作られる | install test |
| legacy cleanup safety | old managed Gemini files | install.sh | managed 旧ファイルは消え、local override は保持 | install test |
| main branch write gate | `agy` write command | hook | `MULTI_AI_ANTIGRAVITY_ALLOW_WRITE` なしなら block | hook test |
| audit diagnostic | traceary installed | audit script | antigravity doctor を保存し hooks print は skip | shell/smoke |

### TDD plan
| Behavior | Red | Green | Refactor target |
|---|---|---|---|
| settings path migration | test_install_sync の `.gemini/settings` 期待を Antigravity path に変更 | install.sh Antigravity section 実装 | cleanup helper の managed hash 判定を分離 |
| engine migration | tests が `gemini` default を期待して失敗 | multi-ai script と policy allowlist を更新 | legacy Gemini run を明示 engine に隔離 |
| hook safety | hook tests が `agy` を見ない | Antigravity command/write detection 追加 | Codex/Gemini/Antigravity の共通 command classifier 抽出は見送り |

### Risks / rollback
- 手続き化リスク: shell script 内に engine 別分岐が増える。今回は Antigravity と legacy Gemini を明示分岐し、共通化は過剰抽象として見送る。
- premature abstraction リスク: provider 共通 runner 化はまだ variation が少ないため行わない。
- migration / compatibility: `gemini` engine は明示指定時だけ legacy として残し、既存ワークフローの緊急回避を可能にする。
- rollback trigger: `agy --print` が headless で安定しない、または Antigravity settings schema が変わった場合は default engine を local policy で `claude,codex` に絞る。
