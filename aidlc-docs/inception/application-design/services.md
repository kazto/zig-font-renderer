# Services

## 1. FontRenderingService (Library Entry Point)
- **Purpose**: 各コンポーネントをオーケストレーションし、一貫したレンダリングパイプラインを提供する。
- **Responsibilities**:
  - `FontProvider` を使用してフォントをロード。
  - `Shaper` を呼び出してテキストをレイアウト。
  - `GlyphGeometry` からパスを取得し、`Renderer` で出力。
- **Interaction**:
  - クライアントコードからの要求を受け取り、内部コンポーネントを適切な順序で呼び出す。

## 2. CliOrchestrator
- **Purpose**: コマンドライン引数を解釈し、`FontRenderingService` を呼び出して結果を出力する。
- **Responsibilities**:
  - 引数のバリデーション。
  - ファイル入出力（フォント読み込み、SVG書き出し）の管理。
  - エラーの標準エラー出力へのフォーマット。
