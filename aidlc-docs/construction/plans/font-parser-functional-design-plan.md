# Functional Design Plan - Unit 1: Font Parser

This plan outlines the steps for the detailed functional design of the Font Parser unit.

## Execution Checklist

- [x] Define business logic for font file validation and table discovery
- [x] Model domain entities for TTF/OTF tables (head, cmap, maxp, etc.)
- [x] Specify business rules for coordinate system mapping and units
- [x] Answer clarifying questions for functional design
- [x] Obtain approval for the functional design

## Design Considerations & Questions

### 1. サポートする情報の詳細
パースする各テーブルにおいて、具体的にどの情報を「ビジネスロジック」として扱うかを明確にします。
- **cmap (Character to Glyph Index Mapping)**: どのプラットフォームID/エンコーディングIDを優先しますか？
  - A) Unicode (Platform 3, Encoding 1 または 10) を最優先する
  - B) Apple系 (Platform 0) を優先する
  - C) 見つかったものすべてを等しく扱う
[Answer]: A

- **glyf (Glyph Data)**: 複合グリフ（複数のグリフを組み合わせて1文字を作る形式）のサポートは必須ですか？
  - A) 必須（アクセント付き文字などで多用されるため）
  - B) 後回しで良い（まずは単純な単一グリフのみ）
[Answer]: B

### 2. 数値の扱い（ビジネスルール）
フォント内部の `FUnits` (Font Units) から最終的なレンダリング座標への変換ルールをどう定義しますか？
- A) フォント内部の値をそのまま返し、スケーリングは上位レイヤー（Unit 3）に任せる
- B) `Face` インスタンス初期化時に指定されたサイズに基づいて、内部でピクセル/ポイント単位に変換する
[Answer]: A

### 3. バリデーションルール
フォントファイルが「不正」であると判断する基準をどう設定しますか？
- A) Checksumの不一致、必須テーブル（head, hhea, maxp, cmap, glyf, hmtx）の欠落
- B) Checksumは無視し、データの構造が読み取れれば良しとする
- C) その他
[Answer]: B

---
## Instructions
1. `aidlc-docs/construction/plans/font-parser-functional-design-plan.md` を直接編集して、[Answer]: タグに回答を記入してください。
2. 回答が完了しましたら、その旨を教えてください。
