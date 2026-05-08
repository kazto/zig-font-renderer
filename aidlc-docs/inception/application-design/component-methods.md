# Component Methods

## FontProvider (Face)
| Method | Input | Output | Purpose |
|---|---|---|---|
| `init(allocator, data)` | `Allocator`, `[]const u8` | `!Face` | フォントデータをパースしインスタンスを初期化 |
| `getGlyphId(codepoint)` | `u32` | `?u16` | UnicodeからグリフIDを取得 |
| `getHMetric(glyph_id)` | `u16` | `HMetric` | グリフの水平メトリクス（アドバンス幅等）を取得 |

## Shaper (ShapeEngine)
| Method | Input | Output | Purpose |
|---|---|---|---|
| `shape(allocator, face, text)` | `Allocator`, `*Face`, `[]const u8` | `![]GlyphInfo` | テキストをシェイピングし、配置情報を返す |
| `applyGsub(face, glyphs)` | `*Face`, `*ArrayList(u16)` | `!void` | GSUBテーブルによる置換を適用 |
| `applyGpos(face, glyphs)` | `*Face`, `[]GlyphPosition` | `!void` | GPOSテーブルによる位置調整を適用 |

## GlyphGeometry
| Method | Input | Output | Purpose |
|---|---|---|---|
| `getOutline(allocator, face, glyph_id)` | `Allocator`, `*Face`, `u16` | `!Outline` | 指定グリフのアウトラインデータを取得 |
| `scalePoints(outline, scale)` | `*Outline`, `f32` | `void` | アウトラインの座標をスケーリング |

## Renderer (SvgRenderer)
| Method | Input | Output | Purpose |
|---|---|---|---|
| `writeStart(writer)` | `AnyWriter` | `!void` | SVGのヘッダーを出力 |
| `writePath(writer, outline, x, y)` | `AnyWriter`, `Outline`, `f32`, `f32` | `!void` | グリフパスを出力 |
| `writeEnd(writer)` | `AnyWriter` | `!void` | SVGのフッターを出力 |
