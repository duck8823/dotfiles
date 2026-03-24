---
name: sprint
description: スプリント内のIssueを自律的に順次実装しPR作成まで完了する
---

# スプリント自律実行

## 前提
- `/plan` でスプリントが構成済み
- プロジェクトメモリにスプリント状態が保存済み

## メインループ

### 各 Wave に対して:

Wave 内の Issue は順次実行（Agent Teams が有効なら並列も可）。

### 各 Issue に対して:

#### 1. 準備
```bash
gh issue view <番号>
```
- Issue タイトルとの照合（ダブルチェック）
- ブランチ作成: `feature/<内容>` or `fix/<内容>` or `maintenance/<内容>`

#### 2. 仕様書生成（3AI多重）
`spec-driven` スキルを呼び出し:
- Claude / Codex / Gemini の spec-writer を並列起動
- 統合して `.spec/<issue番号>.md` 生成

#### 3. 実装
- .spec に基づいて実装（Claude Opus メイン）
- 自己検証ループ:
  - Flutter: `flutter analyze` → `flutter test` → 失敗時リトライ（最大3回）
  - Godot: 起動 → スクリーンショット確認 → 問題は自分で修正
  - 共通: `git diff` で意図しない変更がないか確認

#### 4. コミット分割 & PR
- 関心事ごとにコミット分割
- ドラフト PR 作成（`--draft`）

#### 5. Multi-AI レビュー（6並列）
`multi-ai-review` スキルを呼び出し:
- Architect × 3AI + Reviewer × 3AI = 6並列
- Claude Opus が結果を統合
- CRITICAL → 修正 → 再レビュー

#### 6. マージ判断
- プロジェクトメモリで「マージ前にユーザー許可が必要」と記録されているプロジェクト: ユーザーの許可を待つ
- それ以外: 全レビュー通過で Ready for Review に変更し、ユーザーに報告

#### 7. 後処理
- PR マージ後に `gh issue close <番号>`
- `.spec/<issue番号>.md` を削除
- プロジェクトメモリのスプリント状態を更新
- 次の Issue へ

### 全 Issue 完了後:

#### 品質フェーズ
`quality-phase` スキルを呼び出し。

#### ビルド & アップロード（Flutter プロジェクトのみ）
```bash
flutter clean && flutter build ipa
# App Store Connect にアップロード
```

#### 完了報告
- 消化した Issue 一覧
- 品質フェーズの結果
- 新規作成した tech-debt Issue 一覧
- 次スプリントの推奨構成

## セッション中断対策

### 中断時
1. 現在の Issue の進捗を GitHub Issue にコメント保存
2. メモリのスプリント状態を更新（どの Issue まで完了したか）
3. 未コミットの変更があれば WIP コミット

### 復帰時（「/sprint 続き」で）
1. メモリからスプリント状態を読み込み
2. 未完了の Issue から再開
3. .spec が残っていればそこから実装再開
