# C API Header and Shared Library Export Plan

## 目的

`libzig_font_renderer.so` を C 言語から利用できるように、C ABI のエクスポート関数と対応するヘッダファイルを追加する。

## 対象

- `src/c_api.zig`
- `src/root.zig`
- `include/zig_font_renderer.h`
- `build.zig`
- `aidlc-docs/construction/build-and-test/`

## 実施ステップ

- [x] Step 1: C から安全に扱える最小 API を定義する。
- [x] Step 2: `zfr_render_svg_file` でフォントファイルと UTF-8 テキストから SVG 文字列を生成する。
- [x] Step 3: `zfr_free_string` で Zig 側が確保した SVG 文字列を解放できるようにする。
- [x] Step 4: `zfr_default_render_options` と `zfr_status_message` を追加する。
- [x] Step 5: `include/zig_font_renderer.h` を作成する。
- [x] Step 6: `zig build` / `zig build lib` でヘッダを `zig-out/include/zig_font_renderer.h` にインストールする。
- [x] Step 7: `nm -D` で `zfr_*` シンボルが共有ライブラリから公開されることを確認する。
- [x] Step 8: C smoke test でヘッダと `libzig_font_renderer.so` をリンクし、SVG 生成を確認する。

## 受け入れ条件

- `zig-out/include/zig_font_renderer.h` が生成される。
- `libzig_font_renderer.so` が `zfr_default_render_options`、`zfr_render_svg_file`、`zfr_free_string`、`zfr_status_message` を export する。
- C プログラムから `zfr_render_svg_file` を呼び出し、SVG 文字列を受け取って `zfr_free_string` で解放できる。
