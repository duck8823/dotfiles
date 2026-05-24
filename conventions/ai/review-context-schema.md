# Review context packet schema

この文書は、PR レビュー前に reviewer / verifier / integrator が共有する最小 context packet を定義する。
目的は diff だけのレビューを避け、Issue / PR intent / docs / conventions / prior reviews / test evidence を同じ形で扱うこと。

## Scope

- 対象: PR / local branch / review request の context 収集
- 非対象: packet generator script の実装、外部 AI 送信 policy の変更、既存 `multi-ai-review` の実装変更
- 正本: schema と出力例はこの文書、実行手順は `claude/guidelines/review-workflow.md`、quality gate は `conventions/ai/quality-gates.md`

## Safety policy

Packet にはレビューに必要な最小情報だけを含める。

含めない:

- `.env*`, credentials, tokens, private keys, shell history
- unrelated repository / home directory dump
- raw transcript や個人データの dump
- binary artifact の中身そのもの
- secret-looking added content

外部 AI に共有する場合は、sanitized workspace context packet と External AI delegation policy gate を使う。artifact は必要に応じて path / URL / summary だけを渡す。

## Minimal packet

```jsonc
{
  "schema_version": "review-context.v1",
  "generated_at_utc": "2026-05-24T00:00:00Z",
  "packet_sha256": "sha256 of sanitized packet",
  "repository": {
    "name_with_owner": "owner/repo",
    "base_ref": "main",
    "head_ref": "feature-branch",
    "head_sha": "..."
  },
  "risk_lane": "docs-only-light|policy-docs|low|medium|high",
  "pr": {
    "number": 0,
    "title": "",
    "body": "",
    "url": "",
    "author": "",
    "is_draft": true
  },
  "tickets": [
    {
      "system": "github|jira|other",
      "id": "#54",
      "title": "",
      "url": "",
      "body_excerpt": "",
      "acceptance_criteria": []
    }
  ],
  "diff": {
    "files": [],
    "stat": "",
    "unified_excerpt": "",
    "generated_files": []
  },
  "context_refs": {
    "docs": [
      {"path_or_url": "README.md", "reason": "user-facing behavior"}
    ],
    "conventions": [
      {"path_or_url": "conventions/ai/quality-gates.md", "reason": "quality gate"}
    ],
    "codebase": [
      {"path": "src/example.ts", "reason": "caller / existing pattern"}
    ],
    "prior_reviews": [
      {"source": "github-review|comment|traceary", "summary": ""}
    ]
  },
  "test_evidence": [
    {
      "command": "git diff --check",
      "exit_code": 0,
      "summary": "pass",
      "artifact_uri": ""
    }
  ],
  "known_gaps": [
    {
      "kind": "missing_context|skipped_engine|unavailable_ci|manual_validation",
      "reason": "",
      "fallback": ""
    }
  ]
}
```

## Required fields

| Field | Required | Notes |
|---|---:|---|
| `schema_version` | yes | Versioned for future generator compatibility |
| `packet_sha256` | yes | Same source packet should be auditable across engines |
| `generated_at_utc` | yes | UTC timestamp for freshness and auditability |
| `repository.base_ref` / `head_ref` / `head_sha` | yes | Prevents stale review results |
| `risk_lane` | yes | Uses kebab-case values mapped from `conventions/ai/quality-gates.md` lanes |
| `tickets` | yes | Review must understand acceptance criteria |
| `pr.title` / `pr.body` | conditional | Required when a PR exists; local branch reviews must record missing PR context in `known_gaps` |
| `pr.number` / `pr.url` / `pr.author` / `pr.is_draft` | conditional | Required when a PR exists; optional for local branch reviews before PR creation |
| `diff.files` / `diff.stat` | yes | File list and summary are always required |
| `diff.unified_excerpt` | conditional | Required when findings depend on exact changed lines; can be excerpted when large |
| `diff.generated_files` | yes | Empty array allowed; generated files are reviewed through generator / schema / template / build config |
| `context_refs.docs` | conditional | Required when user-facing behavior, docs, or workflow guidance changes |
| `context_refs.conventions` | conditional | Required when policy / workflow / architecture / coding convention changes |
| `context_refs.codebase` | conditional | Required when diff affects callers, public behavior, or existing patterns |
| `context_refs.prior_reviews` | conditional | Required when PR has previous review comments |
| `test_evidence` | yes | Can be lightweight for docs-only light |
| `known_gaps` | yes | Empty array allowed; missing context must be explicit |

Minimal packet example fields not listed above may be empty strings or empty arrays, but missing review-relevant context must be recorded in `known_gaps`.

## Reviewer output: `required_context_checked`

Every reviewer result should include what it actually checked. If a required source was unavailable, the reviewer must say so instead of guessing.

```jsonc
{
  "source": "role-or-engine-name",
  "verdict": "APPROVE|REQUEST_CHANGES|INSUFFICIENT_CONTEXT",
  "required_context_checked": {
    "tickets": ["#54"],
    "pr_intent": "review context packet schema only; generator is out of scope",
    "docs": ["conventions/ai/quality-gates.md"],
    "conventions": ["claude/guidelines/review-workflow.md"],
    "codebase": [],
    "prior_reviews": [],
    "test_evidence": ["git diff --check", "python3 tests/test_agent_policy_scripts.py"]
  },
  "missing_context": [],
  "findings": [
    {
      "severity": "MUST|SHOULD|NIT",
      "file": "path:line",
      "issue": "",
      "fix": ""
    }
  ],
  "residual_risks": []
}
```

## `INSUFFICIENT_CONTEXT`

Use `INSUFFICIENT_CONTEXT` when a reviewer cannot validate the PR because required packet fields are missing.

Examples:

- Ticket acceptance criteria are missing for a behavior change
- Policy docs change but related hook / workflow documents were not included
- UI change lacks Playwright evidence, screenshot, or manual validation note
- Prior review comments exist but were not included

`INSUFFICIENT_CONTEXT` is not a finding by itself. The integrator role decides whether to add context, narrow scope, or block the gate.

## Related documents

- `conventions/ai/quality-gates.md`
- `conventions/ai/multi-ai-agent-operations.md`
- `conventions/ai/agent-hooks-observability.md`
- `claude/guidelines/review-workflow.md`
