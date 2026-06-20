# Autonomous development preflight and retry reduction

この文書は Codex / Claude / Antigravity が current orchestrator として自律開発を進める前に、回り道・待ち・手戻りを減らすための共通 guard をまとめる。品質 gate は下げず、**事前確認・出力の再利用・失敗分類・証跡化**で無駄を減らす。

## Structure-Behavior Design Note

### Requirement summary
- 目的: branch 衝突、sandbox write 失敗、`rtk find` 再試行、Codex config load 不備、review 待機の手作業、`gh pr checks` 重複確認を減らす。
- 現状: 各失敗は個別に回避できるが、作業開始時・PR gate 時の定型が分散している。
- 期待する振る舞い: 新規 agent 作業時に preflight を実行し、PR gate では待機秒数・失敗分類・コメントテンプレート・checks 証跡を再利用する。
- 非対象: Traceary 本体の workspace attribution / 重複記録修正、各アプリ repo 固有のビルド改善。

### Conceptual model
| Concept | State | Behavior | Constraint / Invariant |
|---|---|---|---|
| Work target | repo path / branch / writable roots | branch と sandbox write 条件を事前確認する | main 直 push はしない |
| Review wait | pending / no_response / fallbackable / auth_required | 待機・分類・コメントを定型化する | `auth_prompt` は fallback しない |
| Evidence cache | checks / validation / review | 同一 head の証跡を再利用する | head が変わったら取り直す |
| Friction report | avoided / occurred | 最終報告へ手戻り情報を残す | 感想ではなく再利用可能な改善点を書く |

### Responsibility assignment
| Responsibility | Owner | Reason to change | Not owner / reason |
|---|---|---|---|
| branch / sandbox preflight | `scripts/agent-work-preflight.sh` | repo / branch / writable roots を deterministic に確認できる | GitHub API や PR gate は扱わない |
| Codex config validation | `scripts/validate-codex-config-template.sh` | temp `CODEX_HOME` で template と instructions を同時検証する | live user config は変更しない |
| review fallback comment | `scripts/render-pr-review-fallback-comment.sh` | no response / timeout / auth 等の分類文を定型化する | 実際の `gh pr comment` 投稿は orchestrator |
| process rule source | this document / `claude/guidelines/git-workflow.md` | 人間と agent が読む運用ルール | hook/script の実装詳細を増やしすぎない |

### Behavior tests
| Behavior | Given | When | Then | Level |
|---|---|---|---|---|
| branch prefix collision | local branch `chore` exists | preflight branch `chore/foo` | non-zero, `prefix_collision`, slashless suggestion | script |
| writable root outside | repo outside provided root | preflight | `git_write_requires_escalation: true` | script |
| Codex config check | repo template | validate helper | rendered TOML parses and instructions exists | script |
| auth fallback comment | classification `auth_prompt` | render template | `Do not fallback` appears | script |
| docs drift | policy text test | run lightweight tests | required guard phrases remain | test |

## 作業開始 preflight

1. 対象 repo / Issue / PR を確認する。
2. 作業 branch 候補を決める前に branch prefix collision を見る。

   ```bash
   rtk scripts/agent-work-preflight.sh \
     --repo /path/to/repo \
     --branch maintenance/my-task \
     --writable-root /path/to/writable/root
   ```

   dotfiles repo 外から使う場合は install 後の `rtk ~/.local/bin/agent-work-preflight.sh ...` を使う。

3. `git_write_requires_escalation: true` の場合、`git switch`, `git worktree add`, `git pull`, `git reset`, `git commit`, `git push` など git write 系は最初から sandbox escalation を使う。失敗してから同じコマンドを再実行しない。
4. branch status が `prefix_collision` / `leaf_collision` / `exists` なら、slash を避けた名前や別 prefix に切り替える。例: `chore/foo` が `chore` branch と衝突する場合は `chore-foo` へ変える。

## `rtk` wrapper constraints

- すべての shell command は `rtk` prefix を付ける。
- 単純な `git`, `python`, `bash`, `grep`, `sed`, `jq` は `rtk <cmd>` を使う。
- 複雑な `find` predicate、`-print0`、複数 `-o` 条件、`-exec`、raw diff 全量が必要な場合は wrapper の要約で情報が落ちることがある。次のように明示する。

  ```bash
  rtk /usr/bin/find . -type f \( -name '*.md' -o -name '*.sh' \) -print
  rtk proxy git diff origin/main...HEAD --unified=30
  ```

- 長い stdout は `rtk` で削減できても、MCP connector payload は削減できない。connector-heavy 調査は `conventions/ai/token-budget.md` を優先する。

## Codex config template validation

`codex/config.toml.template` を触ったら、temp `CODEX_HOME` で `{{HOME}}` 展開と `model_instructions_file` を同時に確認する。

```bash
rtk scripts/validate-codex-config-template.sh --repo .
```

dotfiles repo 外から使う場合は install 後の `rtk ~/.local/bin/validate-codex-config-template.sh --repo /path/to/dotfiles` を使う。

この helper は次を行う。

- temp `CODEX_HOME` 作成
- `config.toml.template` の `{{HOME}}` 展開
- `codex/instructions.md` を temp `CODEX_HOME/instructions.md` にコピー
- Python `tomllib` による TOML load check
- `model_instructions_file` の存在確認

## PR review wait / fallback

- 既定待機秒数は `CODEX_REVIEW_POLL_SECONDS=180`。
- `@codex review` / external reviewer の no response は、指定秒数待ってから分類する。
- 分類:
  - `no_response`, `timeout`, `quota_or_capacity`, `empty_output`, `environment_unavailable`: local verification + 別 reviewer の証跡で補完可能。
  - `policy_or_permission_denied`, `local_policy_disabled`: policy を弱めず、欠落理由を記録して補完可能。
  - `auth_prompt`: fallback 禁止。ブラウザ認証を開かず、ユーザーに CLI 認証修正を依頼する。

コメントは helper で作る。

```bash
CODEX_REVIEW_POLL_SECONDS=180 \
  rtk scripts/render-pr-review-fallback-comment.sh \
  --pr 123 \
  --head "$(git rev-parse --short HEAD)" \
  --classification no_response \
  --evidence-path /private/tmp/pr123-review-status.md
```

dotfiles repo 外から使う場合は install 後の `rtk ~/.local/bin/render-pr-review-fallback-comment.sh ...` を使う。

## `gh pr checks` evidence reuse

- `gh pr checks` は PR head ごとに1回取得し、結果を review / final gate comment に貼る。
- `no checks reported` は failure ではなく、CI 未設定/未報告として扱う。
- 同じ head で再確認を繰り返さない。PR head が変わったときだけ取り直す。
- 取得結果は `/private/tmp/<repo>-pr<nr>-checks.json` と `.err` に保存し、PR コメントには要約と path だけ残す。

## 最終報告の friction summary

最終報告 / PR comment / handoff には、検証結果だけでなく以下を短く残す。

```markdown
### Process friction
- avoided:
  - branch prefix collision preflight: ok / changed branch from ... to ...
  - sandbox write preflight: repo outside writable roots, escalated git write from first attempt
  - Codex config template validation: passed
  - PR checks evidence reused for head <sha>
- occurred:
  - <retry/fallback that still happened, or none>
- follow-up:
  - <shared workflow / traceary / app-specific issue, or none>
```

dotfiles 以外の repo で発生した改善も、共通運用なら dotfiles に取り込む。Traceary 本体 / plugin / MCP read surface の修正は `duck8823/traceary`、個別アプリ固有の問題はその repo に切る。
