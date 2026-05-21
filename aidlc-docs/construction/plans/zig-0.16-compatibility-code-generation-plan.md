# Zig 0.16.0 互換性対応 Code Generation Plan

## 目的

本リポジトリを Zig 0.15.2 前提から Zig 0.16.0 でビルド・テストできる状態へ移行する。

## 対象

- `src/main.zig`
- `src/perf_smoke.zig`
- `src/font_rendering_service.zig`
- `src/svg_renderer.zig`
- `src/svg_glyph.zig`
- `src/cff_outline.zig`
- `src/cff_types.zig`
- `src/type2_charstring.zig`
- `src/type2_path_ops.zig`
- `aidlc-docs/construction/build-and-test/`

## 実施ステップ

- [x] Step 1: Zig 0.16.0 の `zig build test` で既存コンパイルエラーを確認する。
- [x] Step 2: `std.fs.File` / `std.fs.cwd()` 参照を `std.Io.File` / `std.Io.Dir` API へ移行する。
- [x] Step 3: `std.ArrayList(u8).writer` 利用箇所を `std.Io.Writer.Allocating` / `*std.Io.Writer` へ移行する。
- [x] Step 4: `std.heap.GeneralPurposeAllocator` を `std.heap.DebugAllocator` へ移行する。
- [x] Step 5: `std.process.argsAlloc` を `std.process.Init` と `std.process.Args.Iterator` ベースへ移行する。
- [x] Step 6: optional performance smoke の `std.time.Timer` 利用を `std.Io.Timestamp` ベースへ移行する。
- [x] Step 7: `zig fmt`、`zig build test`、`zig build`、CLI smoke、`zig build perf` で検証する。
- [x] Step 8: AIDLC Build and Test 文書を Zig 0.16.0 対応として更新する。

## 受け入れ条件

- `zig version` が `0.16.0` の環境で `zig build test` が成功する。
- `zig version` が `0.16.0` の環境で `zig build` が成功する。
- CLI の基本実行が成功する。
- `zig build perf` が成功または代表フォント未存在時に skip として正常終了する。
