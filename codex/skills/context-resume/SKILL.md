---
name: context-resume
description: Traceary / git / PR / Issue から作業状態を復元し、手書き handoff に頼らず Codex が current orchestrator / worker として継続する。multi-AI workspace、再起動後、別 agent からの継続、Claude/Antigravity/Codex の調査失敗後に使う。
---

# Context Resume

## 目的

手書きの「Claude → Codex handoff」を標準にせず、Traceary と repository state から現在地を復元して、自律的に次の作業へ進む。

## 使う場面

- セッション再起動後に前の作業を継続する
- Claude / Antigravity / Codex のどれかが途中で失敗・timeout・quota になった
- multi-AI workspace で他 agent の変更やレビュー結果を引き継ぐ
- ユーザーが「続き」「確認できる？」「本題に戻る」など、明示 handoff なしに再開を求めた

## 復元順序

1. **Traceary**
   - active / latest session の handoff を確認する
   - recent context / command audit / durable memory pack を確認する
   - raw transcript を外部 AI にそのまま渡さず、必要な objective / decision / blocker へ蒸留する
2. **Repository state**
   - `git status --short --branch`
   - current branch / base branch / local diff / staged diff
   - open PR / issue / review comments
3. **Project instructions**
   - `AGENTS.md`
   - `CLAUDE.md` / `AGENTS.md` / project docs
   - local agent policy（`~/.config/ai-agent-policy.env`、環境変数）
4. **Validation state**
   - 直近の test / lint / typecheck 結果
   - CI / `gh pr checks`
   - 失敗した agent と classification

## 判断ルール

- 情報不足だけを理由に停止しない。安全に進められるなら Draft PR / design note / local verification へ進む。
- 破壊的操作、secret 送信、repo 外 private file、production deploy は明示承認がない限り実行しない。
- Antigravity / Claude / Codex のどれかが local policy で無効なら、skip 理由を記録して残りの agent と local verification で補完する。
- 既存の他 agent の変更を revert しない。必要なら差分を分離して conflict を明示する。

## 出力フォーマット

```json
{
  "source": "codex-context-resume",
  "objective": "",
  "current_state": "",
  "branch": "",
  "changed_files": [],
  "context_refs": [],
  "validated_commands": [],
  "results": {"passed": [], "failed": []},
  "residual_risks": [],
  "next_actions": []
}
```
