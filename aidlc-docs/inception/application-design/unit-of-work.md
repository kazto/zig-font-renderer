# Units of Work

## 1. Font Parser (Unit 1)
- **Description**: TTF/OTFファイルのバイナリ読み込みとテーブルアクセスの基盤モジュール。
- **Responsibilities**:
  - `Face` 構造体の実装。
  - `head`, `cmap`, `maxp`, `hhea`, `hmtx` テーブルのパース。
  - `glyf` および `CFF ` テーブルのバイナリデータへのアクセス提供。
  - 基本的なグリフID取得と水平メトリクスの提供。

## 2. Shaping Engine (Unit 2)
- **Description**: GSUB/GPOSテーブルの処理とテキストレイアウト。
- **Responsibilities**:
  - `ShapeEngine` 構造体の実装。
  - `GSUB` テーブルによるグリフ置換ロジック。
  - `GPOS` テーブルによる位置調整（カーニング・合字・配置）ロジック。
  - 複数文字のUnicode入力を受け取り、シェイピング済みグリフリストを生成。

## 3. SVG Rendering & CLI (Unit 3)
- **Description**: アウトライン抽出、SVG生成、およびCLIインターフェース。
- **Responsibilities**:
  - `GlyphGeometry` モジュール（アウトライン抽出・スケーリング）。
  - `Renderer` モジュール（SVGパス生成）。
  - `FontRenderingService` による全体オーケストレーション。
  - `CliOrchestrator` によるCLIの実装。
