# Components

## 1. FontProvider
- **Purpose**: TTF/OTFファイルの読み込み、テーブルの検索、および基本データの抽出を担当する。
- **Responsibilities**:
  - フォントファイルのバリデーション。
  - `head`, `cmap`, `glyf`, `hmtx` などの必須テーブルのバイナリパース。
  - UnicodeからグリフIDへのマッピング。
- **Interfaces**:
  - `Face`: フォント1つのインスタンスを表す構造体。

## 2. Shaper
- **Purpose**: テキスト（Unicode文字列）を、フォントの高度なレイアウト規則（GSUB/GPOS）に従ってグリフの並びに変換する。
- **Responsibilities**:
  - `GSUB` テーブルによるグリフ置換（合字など）。
  - `GPOS` テーブルによる位置調整（カーニングなど）。
  - 各グリフの最終的な座標計算。
- **Interfaces**:
  - `ShapeEngine`: シェイピングロジックを保持する。

## 3. GlyphGeometry
- **Purpose**: 個々のグリフの幾何学的なアウトライン情報を抽出する。
- **Responsibilities**:
  - `glyf` または `CFF ` テーブルからアウトライン（直線、2次/3次ベジェ曲線）を抽出。
  - ポイントデータのスケーリングと座標変換。
- **Interfaces**:
  - `Outline`: 1つのグリフのパスデータを保持する。

## 4. Renderer
- **Purpose**: シェイピングされたグリフ群を最終的な出力形式（まずはSVG）に変換する。
- **Responsibilities**:
  - `GlyphGeometry` から得られたアウトラインをSVGの `<path>` 要素に変換。
  - SVGドキュメント全体の構築。
- **Interfaces**:
  - `SvgRenderer`: SVG生成を担当する。
