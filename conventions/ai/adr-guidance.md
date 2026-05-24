# ADR guidance for high-risk changes

この文書は、AI agent が high-risk な設計判断を会話履歴だけに閉じず、リポジトリ上で追跡できる Architecture Decision Record (ADR) として残すための最小規約です。

## When to write an ADR

ADR は乱発しない。原則として `conventions/ai/quality-gates.md` の High risk lane に該当し、後から判断根拠を追う必要がある変更に限定する。

必須対象:

- public API / external contract の破壊的変更または新設
- DB schema / migration / data backfill / data retention の変更
- auth / authz / permission / identity / session / token handling の変更
- billing / pricing / payment / quota / entitlement の変更
- irreversible migration、rollback が難しい運用変更
- cross-module architecture、新しい module boundary、shared abstraction の導入
- security / privacy / compliance に影響するデータ境界の変更

ADR が不要な例:

- typo / formatting / docs-only light
- 既存パターンに沿った小さな bug fix
- private helper の局所 refactor
- 実験 branch 内だけで破棄可能な spike
- 既存 ADR / design note の範囲内で判断が変わらない実装詳細

## Required content

ADR は短くてよいが、最低限以下を含める。

- Status: `Proposed` / `Accepted` / `Superseded` / `Deprecated`
- Date
- Decision owner and reviewers / reviewing roles
- Context: 何が問題で、どの制約があるか
- Decision: 何を採用するか
- Alternatives considered: 主要な代替案と不採用理由
- Consequences: 利点・コスト・運用影響
- Rollback / migration safety: 戻し方、段階移行、feature flag、data recovery
- Validation plan: test / migration check / monitoring / rollout gate
- References: Issue / PR / spec / incident / prior ADR

## File placement

各プロジェクトの既存規約を優先する。規約がない場合は以下を推奨する。

- `docs/adr/YYYY-MM-DD-short-title.md`
- title は kebab-case
- 既存 ADR を置き換える場合は削除せず、古い ADR を `Superseded` にして新 ADR へリンクする
- この dotfiles リポジトリ自身の AI 運用判断で ADR が必要な場合は `conventions/ai/adr/YYYY-MM-DD-short-title.md` を推奨する

## Review gate

High risk lane で ADR が必要な場合、PR ready 前に reviewer / integrator が以下を確認する。

- 変更が High risk 条件に該当する理由
- ADR が PR から参照されていること
- rollback / migration-safe plan が ADR または PR にあること
- test / verification / monitoring plan があること
- 未決定事項が `known_gaps` または follow-up Issue として明示されていること

ADR がない場合でも、変更を Low / Medium に分割できるなら ADR 必須にせず、分割 PR と Design Note で進めてよい。

## Template

ADR template は `conventions/ai/templates/adr.md` を使う。
