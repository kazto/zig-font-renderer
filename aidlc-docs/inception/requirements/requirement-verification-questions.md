# Requirement Verification Questions

Please provide answers to the following questions to help clarify the requirements for the Zig Font Renderer project. You can fill in the [Answer]: tags directly.

## Functional Requirements

1. **サポートするフォント形式について**
   TrueType (.ttf) と OpenType (.otf) 以外にサポートが必要な形式はありますか？（例: WOFF, WOFF2, TTCなど）
   - A) TTF/OTFのみで十分
   - B) WOFF/WOFF2も必要
   - C) その他
   [Answer]: A

2. **レンダリングの出力形式について**
   SVGと「任意の画像」とのことですが、具体的にどの画像フォーマットを優先しますか？
   - A) PNG
   - B) BMP
   - C) JPEG
   - D) 生のピクセルデータ（RGBAなど）のみ提供し、エンコードは呼び出し側に任せる
   - E) その他
   [Answer]: E 訂正。まずはSVGのみ対応でよい。

3. **テキストレイアウト（Shaping）機能の範囲**
   複雑なスクリプト（アラビア語、デーヴァナーガリーなど）やカーニング、合字（リガチャ）のサポートは必要ですか？
   - A) 単純な左から右への配置のみで良い（ASCII/日本語の基本的な並び）
   - B) カーニングと合字のサポートが必要
   - C) HarfBuzzのような本格的なシェイピングエンジンとの統合、または同等の機能が必要
   - D) その他
   [Answer]: C

4. **SVG出力の詳細**
   SVGとして出力する際、どのような形式を想定していますか？
   - A) `<path>` 要素としてアウトラインを出力
   - B) `<text>` 要素として（フォント参照を保持したまま）出力
   - C) その他
   [Answer]: A

## Non-Functional Requirements

5. **依存関係の制限**
   外部のCライブラリ（FreeType, HarfBuzz, libpngなど）への依存は許容されますか？それとも純粋なZig（Pure Zig）での実装を希望しますか？
   - A) Pure Zigでの実装を希望（外部依存なし）
   - B) 共有ライブラリとしての依存は許容する
   - C) ビルド時に静的リンクされるなら許容する
   - D) その他
   [Answer]: A 純粋なZigでの再実装を行いたい

6. **パフォーマンスとメモリ**
   想定される主な利用シーンはどれですか？
   - A) 大量のテキストを高速にバッチ処理する
   - B) リアルタイムレンダリング（ゲームやGUIなど）で使用する
   - C) 組み込み環境などのメモリ制限の厳しい環境で使用する
   - D) その他
   [Answer]: どちらかというとB

## 拡張機能のオプトイン (Extensions Opt-In)

現在、利用可能な拡張機能はありません。

---
質問は以上です。回答をお待ちしております。
