---
name: structure-behavior-design
description: 非自明な実装で、要求・概念モデル・責務分離・境界/IF・振る舞いテスト・TDD・構造レビューを軽量に通す。AI が手続き的実装に飛びつくリスクを抑えたいときに使う。
---
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- Adapted from the structure-behavior-design knowledge pack in https://github.com/theoden9014/ai-knowledge-base. Changes: condensed, translated to Japanese, and integrated with duck8823/dotfiles multi-AI roles/policy gates. -->

# Structure-Behavior Design

Canonical content is maintained in this file and mirrored to
`claude/skills/structure-behavior-design/SKILL.md` for Claude Code
installation. Keep both files synchronized until a neutral knowledge
source/build step is introduced.

## 目的

AI が要件からそのまま実装へ飛び、肥大 usecase / handler / service、transaction script、data-only model、実装詳細テストを作るリスクを下げる。  
非自明な変更では、**構造設計（概念・責務・境界）**と**振る舞い設計（テスト仕様・TDD）**を短く明文化してから実装する。

## 使う条件

使う:
- 新機能、振る舞い変更、状態遷移、API / usecase / domain / application logic の変更
- 認証・認可・課金・契約・DB schema / migration・cache・設定・batch・workflow など事故影響が大きい変更
- 複数ファイル・複数モジュールにまたがる変更
- 責務・境界・依存方向を変える refactor

フル適用しない:
- typo / comment / formatting のみ
- 既存パターンの完全な横展開で設計判断がない小変更
- docs-only で実装構造に影響しない変更

## リスク別ゲート

| リスク | 条件 | 実装前に必要なもの |
|---|---|---|
| Low | 既存設計に沿う小変更 | 要求要約、振る舞いテスト、TDD plan、セルフレビュー |
| Medium | 新しい振る舞い・IF・複数ファイル変更 | Low + 概念モデル、責務表、境界/IF案、手続き化リスク |
| High | public API、DB、auth/authz、billing、契約、migration、cross-module architecture | Medium + rollback/移行方針、分割PR案、実装前 design checkpoint |

High risk でもユーザー確認だけで停止し続けない。確認不能なら、破壊的変更を避けて小さな Draft PR / design note / migration-safe step に分割する。

## 実装前 Design Note

Medium 以上では、production code を書く前に以下を短く残す。`.ai/spec/<issue>.md` がある場合はそこへ統合する。

```markdown
## Structure-Behavior Design Note

### Requirement summary
- 目的:
- 現状:
- 期待する振る舞い:
- 非対象:

### Conceptual model
| Concept | State | Behavior | Constraint / Invariant |
|---|---|---|---|

### Responsibility assignment
| Responsibility | Owner | Reason to change | Not owner / reason |
|---|---|---|---|

### Boundaries / interfaces
| Boundary or interface | Consumer | Hidden detail | Error contract |
|---|---|---|---|

### Behavior tests
| Behavior | Given | When | Then | Level |
|---|---|---|---|---|

### TDD plan
| Behavior | Red | Green | Refactor target |
|---|---|---|---|

### Risks / rollback
- 手続き化リスク:
- premature abstraction リスク:
- migration / compatibility:
- rollback trigger:
```

## 設計ルール

- 概念・状態・不変条件を先に見つける。usecase / handler / script だけを設計単位にしない。
- SRP は「1 action 1 class」ではなく「変更理由」で分ける。
- 実在しない variation のために Strategy / Factory / Plugin を作らない。
- Core behavior へ DB / HTTP / SDK DTO を漏らさない。
- IF は consumer-oriented に小さくし、boolean flag や primitive parameter の山を避ける。
- テストは private method や内部 call order ではなく、観測可能な振る舞い・状態遷移・エラー・境界値を書く。
- Green 後の refactor では、振る舞いを state / invariant を持つ owner へ寄せる。

## Multi-AI での使い分け

- **Claude foreground**: 要求・UX・統合判断・最終設計 note の責任を持つ。
- **Codex worker/verifier**: scoped 実装、TDD、検証コマンド、security / edge case、構造レビュー証跡を返す。
- **Gemini scout**: read-only で既存パターン、命名 drift、diff 外影響、docs/config 更新漏れ、構造 drift を見る。

外部 AI に diff / source を渡すときは既存の External AI delegation policy gate を優先する。

## 実装後レビュー

必ず確認する:
- rules / decisions が handler・controller・application service に滞留していないか
- usecase / service が orchestration を超えて core behavior を所有していないか
- data-only model と primitive obsession が残っていないか
- hidden side effect、IO と意思決定の混在、infra leakage がないか
- IF が大きすぎないか、consumer が使わない method に依存していないか
- テストが振る舞いではなく実装形状を固定していないか

## Attribution

This skill adapts ideas from the `structure-behavior-design` knowledge pack in `theoden9014/ai-knowledge-base`, licensed under CC BY-SA 4.0. See repository `NOTICE.md`.
