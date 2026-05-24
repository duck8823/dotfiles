# Multi-AI agent operations

この文書は、Claude / Codex / Gemini の skill・agent・subagent 定義を共通化するときの source of truth です。
各ツール固有の `CLAUDE.md`、`codex/agents/*.toml`、`gemini/agents/*.md`、`SKILL.md` は、この役割表を投影したものとして扱います。

## 共通ロール

| ロール | 主担当 | 権限 | 成果物 |
|---|---|---|---|
| Foreground orchestrator | Claude / Codex メインセッション | 最終統合、採否判断、ユーザー確認、PR ゲート | 方針、採否理由、統合コメント |
| Background implementation worker | Codex | scoped worktree / feature branch の write | 変更ファイル、実行コマンド、結果、残リスク |
| Read-only scout | Gemini | 原則 read-only / plan | 既存パターン逸脱、命名 drift、diff 外影響 |
| Security / verification reviewer | Codex | test / lint / 静的解析、セキュリティ観点 | `validated_commands` 付き findings |
| Call-chain reviewer | Claude subagent | Read / Grep / 必要最小の test | 呼び出し元からのバグ・エラー処理・テスト漏れ |
| Structure reviewer | Claude / Codex / Gemini | read-heavy、必要なら設計メモ | 責務配置、境界/IF、振る舞いテスト不足 |
| Planner / spec writer | Codex / Gemini | issue・コード調査 | wave、依存、担当、検証計画 |

## 共通 schema

外部 AI / subagent / worker へ渡す依頼は、ツールに関係なく次の項目を含めます。

```json
{
  "objective": "",
  "scope": [],
  "allowed_write_scope": [],
  "forbidden_actions": [],
  "required_validation": [],
  "output_format": {
    "changed_files": [],
    "validated_commands": [],
    "results": {"passed": [], "failed": []},
    "residual_risks": [],
    "findings": []
  }
}
```

- read-only scout では `allowed_write_scope` を空にし、書き込み禁止を明示する。
- write worker では ticket / branch / worktree / 変更可能ファイルを明示する。
- reviewer では author と利益相反を明示する。Codex authored PR では Codex verifier を独立最終レビュー扱いにしない。
- `validated_commands` が空の verifier 出力は「未検証」として扱う。

## 共通化の方針

1. **抽象は role / responsibility / schema に置く**
   モデル名、CLI フラグ、ツール名は各ツール固有ファイルに置く。
2. **skill は workflow、agent は観点、hook は決定論的 gate**
   skill に恒久制約を埋め込まない。恒久制約は global instruction / rule / policy に置く。
3. **local subagent を優先し、remote agent は明確な境界がある場合だけ使う**
   同一ワークスペース内の並列調査は local subagent / worktree で十分。別サービス・別チーム・別 framework と連携する場合だけ A2A を検討する。
4. **handoff では履歴を削る**
   外部 AI へは PR diff、関連 Issue、必要ソース、テスト出力だけを渡す。shell history、`.env*`、認証情報、無関係な repo 外ファイルは渡さない。
5. **パーソナライズ情報はそのまま運用ルールにしない**
   Gemini / Google Lens / 個人記憶から得た示唆は、出典・再現性・適用条件を確認してから dotfiles に蒸留する。スクリーンショットや個人データの raw dump は PR review / external AI prompt に含めない。

## 2026-05 時点の採用知見

- Claude / Gemini とも subagent は「専門ロール + 独立 context + tool 制限」で安定する。万能 agent を増やすより、role / schema を共通化し、各 CLI の agent 定義へ薄く投影する。
- Handoff は会話履歴を丸ごと渡すのではなく、objective / scope / forbidden_actions / required_validation / output_format を明示した packet に落とす。
- Guardrail / hook は LLM 判断ではなく、決定論的な policy gate・secret 除外・CI 判定・failure classification に寄せる。
- Tracing / memory / session audit は便利だが、prompt / tool payload / function output が sensitive data を含む可能性があるため、include sensitive data は明示 opt-in とする。
- MCP / external connector は per-client consent・scope 表示・redirect/token 検証を前提にし、token passthrough や broad external upload を禁止する。

## Claude / Gemini / Codex research 協調

Claude / Gemini / Codex の協調調査は `scripts/multi-ai-research.sh` を使う。install 後は `~/.local/bin/multi-ai-research.sh` から呼び出せる。
git repository 内では、secret / private data を除外した同一 workspace context packet を Claude / Gemini / Codex に共有する。
Gemini など prompt 内 `@...` を file reference と解釈する CLI では、送信直前に `@` を `\u0040` として transport-escape する場合がある。この場合も source packet は同一で、監査は `packet_sha256` と engine 別 prompt hash の両方で行う。

```bash
rtk proxy ./scripts/multi-ai-research.sh \
  --topic "調査したいテーマ" \
  --mode auto
```

- `auto`: git repository では `workspace`、それ以外では `general` として動く。
- `workspace`: git status / diff / source files から sanitized packet を生成し、同じ packet hash を各 engine に渡す。engine 別 transport escape がある場合は prompt hash も併記する。
- `general`: repo と無関係な外部動向調査だけに使う。
- `packet`: workspace packet に含まれない repo 外 artifact / 追加資料を渡すときに使う。
- 結果は `summary.md` として出力され、各 engine の `classification`（`ok` / `trust_failed` / `auth_prompt` / `quota_or_capacity` / `policy_or_permission_denied` / `prompt_file_reference_expansion` / `process_oom` / `timeout` / `command_failed` / `empty_output`）を残す。

## Traceary memory の扱い

- `candidate` / `extracted` / low-confidence memory は、そのまま global instruction に昇格しない。
- durable memory へ昇格する前に、source、confidence、evidence、重複、期限を確認する。
- `traceary doctor` の memory activation warning は「受け入れ済み memory がない」状態でも出るため、0 accepted memories の場合は即修正ではなく review 対象として扱う。
- workspace 指定は Traceary の正規 workspace（例: `github.com/duck8823/dotfiles`）を優先する。絶対パス指定では検索結果が空になる場合がある。

## 参考一次情報

- Claude Code subagents: <https://code.claude.com/docs/en/sub-agents>
- Claude Code hooks: <https://code.claude.com/docs/en/hooks>
- Gemini CLI subagents: <https://github.com/google-gemini/gemini-cli/blob/main/docs/core/subagents.md>
- Gemini CLI hooks: <https://github.com/google-gemini/gemini-cli/blob/main/docs/hooks/writing-hooks.md>
- OpenAI Agents SDK handoffs: <https://openai.github.io/openai-agents-python/handoffs/>
- Google ADK / A2A: <https://adk.dev/a2a/intro/>
