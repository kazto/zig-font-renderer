# Unit of Work Story Map

## Mapping Stories to Units

### Unit 1: Font Parser
- **US-1**: TrueType/OpenTypeファイルの解析 (Pure Zig)

### Unit 2: Shaping Engine
- **US-2**: ラテン文字と日本語の基本シェイピング
- **US-3**: カーニングと合字のサポート (GSUB/GPOS)

### Unit 3: SVG Rendering & CLI
- **US-4**: テキストのアウトライン出力 (SVG Path)
- **US-5**: CLIインターフェースの提供
- **US-6**: デュアルAPI（高レベル・低レベル）の提供

## Validation
- [x] すべてのユーザーストーリーがいずれかのユニットに割り当てられている。
- [x] ユニットの境界はコンポーネント設計（Application Design）と整合している。
