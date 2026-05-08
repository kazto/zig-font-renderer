# NFR Design Plan - Unit 1: Font Parser

This plan outlines the steps for incorporating Non-Functional Requirements into the design of the Font Parser unit.

## Execution Checklist

- [x] Design performance patterns for glyph lookup and data extraction
- [x] Design security mechanisms for binary data bounds checking
- [x] Identify logical components for memory management and parsing abstractions
- [x] Answer clarifying questions for NFR design
- [x] Obtain approval for the NFR design

## Design Considerations & Questions

### 1. グリフ情報のキャッシュ戦略 (Performance)
一度パースしたグリフのアドバンス幅やアウトラインデータをキャッシュしますか？
- A) `Face` 構造体内部に単純なキャッシュ（例: `std.AutoHashMap`）を持ち、再パースを防ぐ
- B) キャッシュは行わず、毎回バイナリからパースする（メモリ消費を最小化する。Lazy Loadingが十分速いと仮定）
- C) キャッシュの管理はライブラリ利用者（Unit 3等）に任せ、Parserはステートレスな抽出に徹する
[Answer]: C

### 2. バイナリ読み込みの抽象化 (Security & Performance)
Zig 0.15.2の機能を活かした安全な読み込み手法としてどちらを優先しますか？
- A) `std.mem.readIntBig` をラップした専用の `SafeReader` を作成し、すべての読み込みで境界チェックを強制する（安全重視）
- B) 基本的にスライスへのポインタアクセス（`@ptrCast` 等）を用い、クリティカルな箇所でのみ手動で境界チェックを行う（速度重視）
[Answer]: B

### 3. スレッドセーフ性
リアルタイムレンダリングにおいて、複数のスレッドから同一の `Face` インスタンスにアクセスする可能性がありますか？
- A) スレッドセーフにする（内部で Mutex 等を使用するか、不変な設計にする）
- B) スレッドセーフ性は考慮しない（呼び出し側の責任とする。ライブラリ自体はシンプルに保つ）
[Answer]: B

### 4. ゼロコピー指向
パース結果を返す際、元のバイナリデータへの参照（スライス）を返す「ゼロコピー」をどの程度追求しますか？
- A) 可能な限りゼロコピーで行う（高速だが、元データの生存期間管理が複雑になる）
- B) 必要に応じてデータをコピーして返す（安全で使いやすいが、アロケーションが発生する）
[Answer]: Aで行きたいが、どれくらい複雑になるか次第

---
## Instructions
1. `aidlc-docs/construction/plans/font-parser-nfr-design-plan.md` を直接編集して、[Answer]: タグに回答を記入してください。
2. 回答が完了しましたら、その旨を教えてください。
