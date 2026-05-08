# Unit of Work Dependency

## Dependency Matrix
| Unit | Depends On | Reason |
|---|---|---|
| **Unit 1: Font Parser** | - | 最下位レイヤー（フォント解析） |
| **Unit 2: Shaping Engine** | Unit 1 | GSUB/GPOSテーブル読み込みとグリフID取得に必要 |
| **Unit 3: SVG Rendering & CLI** | Unit 1, Unit 2 | アウトラインデータ取得(U1)とレイアウト結果(U2)に必要 |

## Development Sequence
1. **Unit 1**: 逐次開発。まずはパース基盤を完成させる。
2. **Unit 2**: Unit 1が完了次第、シェイピングエンジンの設計と実装を開始。
3. **Unit 3**: Unit 1, 2の成果物を用いて、最終的な描画とCLIを構築。
