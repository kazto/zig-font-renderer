# Library and Wrapper Executable Build Plan

## 目的

既存の単一実行ファイル中心のビルド成果物を、公開ライブラリ artifact と CLI ラッパ実行ファイル artifact に分離する。ライブラリ artifact は静的ライブラリと共有ライブラリの両方を生成する。

## 対象

- `build.zig`
- `src/root.zig`
- `src/main.zig`
- `aidlc-docs/construction/build-and-test/`

## 実施ステップ

- [x] Step 1: 既存の `src/root.zig` 公開 API と `src/main.zig` CLI ラッパの分離状態を確認する。
- [x] Step 2: `build.zig` に `zig_font_renderer` 静的ライブラリ artifact を追加する。
- [x] Step 3: `build.zig` に `zig_font_renderer` 共有ライブラリ artifact を追加する。
- [x] Step 4: デフォルト `zig build` で静的ライブラリ、共有ライブラリ、ラッパ実行ファイルをインストールする。
- [x] Step 5: `zig build lib` で静的ライブラリと共有ライブラリ artifact を明示的にビルドできるステップを追加する。
- [x] Step 6: 既存の `zig build run`、`zig build test`、`zig build perf` の動作を維持する。
- [x] Step 7: AIDLC Build and Test 文書に成果物分離を反映する。

## 受け入れ条件

- `zig build` が成功し、`zig-out/lib/libzig_font_renderer.a` を生成する。
- `zig build` が成功し、Linux では `zig-out/lib/libzig_font_renderer.so` を生成する。
- `zig build` が成功し、`zig-out/bin/zig_font_renderer` を生成する。
- `zig build lib` が成功する。
- `zig build test` が成功する。
- `zig build run -- --help` が成功する。
