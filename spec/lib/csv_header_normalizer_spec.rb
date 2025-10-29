# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CsvHeaderNormalizer do
  # CLAUDE.md準拠: CSVヘッダー正規化ユーティリティの包括的テスト
  # メタ認知: 多言語対応・キャッシュ・パフォーマンスの品質保証
  # 横展開: 他のCSV処理ユーティリティでも同様のテストパターン適用

  before do
    # I18nテスト用の設定
    I18n.backend.store_translations(:en, {
      csv: {
        header_mappings: {
          inventory: {
            "商品名" => "name",
            "価格" => "price",
            "数量" => "quantity",
            "在庫数" => "quantity",
            "説明" => "description",
            "カテゴリ" => "category",
            "Product Name" => "name",
            "Price" => "price",
            "Quantity" => "quantity",
            "Description" => "description"
          },
          user: {
            "ユーザー名" => "username",
            "メールアドレス" => "email",
            "名前" => "name",
            "User Name" => "username",
            "Email" => "email"
          }
        }
      }
    })

    # キャッシュクリア
    described_class.instance_variable_set(:@mapping_cache, {})
  end

  describe '.normalize' do
    let(:mapping_key) { 'inventory' }

    context '正常なヘッダー処理' do
      it '日本語ヘッダーを英語に正規化する' do
        raw_headers = [ "商品名", "価格", "数量", "説明" ]
        expected = [ "name", "price", "quantity", "description" ]

        result = described_class.normalize(raw_headers, mapping_key)
        expect(result).to eq(expected)
      end

      it '英語ヘッダーをそのまま正規化する' do
        raw_headers = [ "Product Name", "Price", "Quantity" ]
        expected = [ "name", "price", "quantity" ]

        result = described_class.normalize(raw_headers, mapping_key)
        expect(result).to eq(expected)
      end

      it '混合言語ヘッダーを適切に処理する' do
        raw_headers = [ "商品名", "Price", "数量", "Description" ]
        expected = [ "name", "price", "quantity", "description" ]

        result = described_class.normalize(raw_headers, mapping_key)
        expect(result).to eq(expected)
      end

      it '大文字小文字を無視してマッピングする' do
        raw_headers = [ "PRICE", "quantity", "Description" ]
        expected = [ "price", "quantity", "description" ]

        result = described_class.normalize(raw_headers, mapping_key)
        expect(result).to eq(expected)
      end

      it '前後の空白を除去する' do
        raw_headers = [ " 商品名 ", "  価格", "数量  " ]
        expected = [ "name", "price", "quantity" ]

        result = described_class.normalize(raw_headers, mapping_key)
        expect(result).to eq(expected)
      end

      it '重複したヘッダーを除去する' do
        raw_headers = [ "商品名", "Product Name", "価格", "Price" ]
        expected = [ "name", "price" ]

        result = described_class.normalize(raw_headers, mapping_key)
        expect(result).to eq(expected)
      end
    end

    context '必須ヘッダーフィルタリング' do
      let(:required_headers) { [ "name", "price", "quantity" ] }

      it '必須ヘッダーのみを返す' do
        raw_headers = [ "商品名", "価格", "数量", "説明", "カテゴリ" ]

        result = described_class.normalize(raw_headers, mapping_key, required_headers)
        expect(result).to match_array([ "name", "price", "quantity" ])
      end

      it '不足する必須ヘッダーがある場合は該当分のみを返す' do
        raw_headers = [ "商品名", "説明" ] # priceとquantityが不足

        result = described_class.normalize(raw_headers, mapping_key, required_headers)
        expect(result).to eq([ "name" ])
      end

      it '必須ヘッダーが全て不足している場合は空配列を返す' do
        raw_headers = [ "説明", "カテゴリ", "備考" ]

        result = described_class.normalize(raw_headers, mapping_key, required_headers)
        expect(result).to be_empty
      end
    end

    context 'エッジケースの処理' do
      it 'nilやemptyなヘッダーを除去する' do
        raw_headers = [ "商品名", nil, "", "  ", "価格" ]
        expected = [ "name", "price" ]

        result = described_class.normalize(raw_headers, mapping_key)
        expect(result).to eq(expected)
      end

      it '空の配列を適切に処理する' do
        result = described_class.normalize([], mapping_key)
        expect(result).to be_empty
      end

      it 'マッピングされないヘッダーは小文字に変換される' do
        raw_headers = [ "UnknownHeader", "AnotherHeader" ]
        expected = [ "unknownheader", "anotherheader" ]

        result = described_class.normalize(raw_headers, mapping_key)
        expect(result).to eq(expected)
      end

      it '存在しないmapping_keyでも安全に処理する' do
        raw_headers = [ "Header1", "Header2" ]
        expected = [ "header1", "header2" ]

        result = described_class.normalize(raw_headers, 'nonexistent')
        expect(result).to eq(expected)
      end
    end

    context '別名マッピングの処理' do
      it '同じカラムに対する複数の別名を適切に処理する' do
        raw_headers = [ "数量", "在庫数" ] # どちらもquantityにマップ
        expected = [ "quantity" ] # 重複除去される

        result = described_class.normalize(raw_headers, mapping_key)
        expect(result).to eq(expected)
      end
    end
  end

  describe '.missing_headers' do
    let(:mapping_key) { 'inventory' }
    let(:required_headers) { [ "name", "price", "quantity" ] }

    it '不足している必須ヘッダーを正しく検出する' do
      raw_headers = [ "商品名", "説明" ] # priceとquantityが不足

      missing = described_class.missing_headers(raw_headers, mapping_key, required_headers)
      expect(missing).to match_array([ "price", "quantity" ])
    end

    it '全ての必須ヘッダーが揃っている場合は空配列を返す' do
      raw_headers = [ "商品名", "価格", "数量", "説明" ]

      missing = described_class.missing_headers(raw_headers, mapping_key, required_headers)
      expect(missing).to be_empty
    end

    it '全ての必須ヘッダーが不足している場合は全て返す' do
      raw_headers = [ "説明", "カテゴリ" ]

      missing = described_class.missing_headers(raw_headers, mapping_key, required_headers)
      expect(missing).to match_array(required_headers)
    end
  end

  describe '.detailed_error_message' do
    let(:mapping_key) { 'inventory' }
    let(:required_headers) { [ "name", "price", "quantity" ] }

    it '詳細なエラーメッセージを生成する' do
      raw_headers = [ "商品名", "説明" ]

      message = described_class.detailed_error_message(raw_headers, mapping_key, required_headers)

      expect(message).to include("Missing required headers: price, quantity")
      expect(message).to include("Available headers: 商品名, 説明")
      expect(message).to include("Please ensure your CSV has columns for: name, price, quantity")
      expect(message).to include("Supported Japanese headers:")
    end

    it '空のヘッダーを適切に除外してメッセージを生成する' do
      raw_headers = [ "商品名", nil, "", "  ", "説明" ]

      message = described_class.detailed_error_message(raw_headers, mapping_key, required_headers)

      expect(message).to include("Available headers: 商品名, 説明")
      expect(message).not_to include("nil")
      expect(message).not_to include('""')
    end

    it '日本語ヘッダーの例を適切に含める' do
      message = described_class.detailed_error_message([], mapping_key, required_headers)

      expect(message).to include("Supported Japanese headers:")
      # 実際の日本語ヘッダーが含まれていることを確認（順序は問わない）
      expect(message).to match(/[商品名価格数量在庫数説明カテゴリ]/)
    end
  end

  describe 'キャッシュ機能' do
    let(:mapping_key) { 'inventory' }

    it 'ヘッダーマッピングをキャッシュする' do
      # 初回呼び出し
      expect(I18n).to receive(:t).with('csv.header_mappings.inventory', default: {}).once.and_call_original
      described_class.normalize([ "商品名" ], mapping_key)

      # 2回目の呼び出しではI18n.tが呼ばれない（キャッシュされている）
      described_class.normalize([ "価格" ], mapping_key)
    end

    it 'キャッシュクリア後は再度I18n設定を読み込む' do
      # 初回キャッシュ
      described_class.normalize([ "商品名" ], mapping_key)

      # キャッシュクリア
      described_class.instance_variable_set(:@mapping_cache, {})

      # 再度I18n.tが呼ばれる
      expect(I18n).to receive(:t).with('csv.header_mappings.inventory', default: {}).once.and_call_original
      described_class.normalize([ "価格" ], mapping_key)
    end

    it '異なるmapping_keyは別々にキャッシュされる' do
      expect(I18n).to receive(:t).with('csv.header_mappings.inventory', default: {}).once.and_call_original
      expect(I18n).to receive(:t).with('csv.header_mappings.user', default: {}).once.and_call_original

      described_class.normalize([ "商品名" ], 'inventory')
      described_class.normalize([ "ユーザー名" ], 'user')
    end
  end

  describe 'プライベートメソッド' do
    describe '.get_cached_mapping' do
      it 'I18n設定のシンボルキーを文字列キーに変換する' do
        mapping = described_class.send(:get_cached_mapping, 'inventory')

        expect(mapping).to be_a(Hash)
        expect(mapping.keys).to all(be_a(String))
        expect(mapping["商品名"]).to eq("name")
      end

      it '存在しない設定キーでは空のハッシュを返す' do
        mapping = described_class.send(:get_cached_mapping, 'nonexistent')

        expect(mapping).to eq({})
      end
    end

    describe '.japanese_header_examples' do
      it '日本語ヘッダーの例を抽出する' do
        examples = described_class.send(:japanese_header_examples, 'inventory')

        expect(examples).to be_a(String)
        expect(examples).to match(/[商品名価格数量在庫数説明カテゴリ]/)
      end

      it '最大3件の例を返す' do
        examples = described_class.send(:japanese_header_examples, 'inventory')
        example_count = examples.split(", ").length

        expect(example_count).to be <= 3
      end

      it '日本語が含まれないマッピングでは空文字列を返す' do
        # 英語のみのマッピングを作成
        allow(described_class).to receive(:get_cached_mapping).and_return({
          "Product Name" => "name",
          "Price" => "price"
        })

        examples = described_class.send(:japanese_header_examples, 'english_only')
        expect(examples).to eq("")
      end
    end
  end

  describe 'パフォーマンステスト' do
    let(:mapping_key) { 'inventory' }

    it '大量のヘッダーを高速に処理する' do
      large_headers = Array.new(1000) { |i| "Header#{i}" }

      start_time = Time.current
      described_class.normalize(large_headers, mapping_key)
      duration = Time.current - start_time

      expect(duration).to be < 0.5 # 0.5秒以内に完了
    end

    it 'キャッシュにより2回目以降の処理が高速化される' do
      headers = [ "商品名", "価格", "数量" ]

      # 初回実行（キャッシュなし）
      start_time = Time.current
      described_class.normalize(headers, mapping_key)
      first_duration = Time.current - start_time

      # 2回目実行（キャッシュあり）
      start_time = Time.current
      described_class.normalize(headers, mapping_key)
      second_duration = Time.current - start_time

      # 2回目の方が高速（ただし非常に高速なため差が出ない可能性もある）
      expect(second_duration).to be <= first_duration
    end
  end

  describe '国際化対応' do
    context '異なるロケール' do
      around do |example|
        original_locale = I18n.locale
        I18n.locale = :ja
        example.run
        I18n.locale = original_locale
      end

      it '日本語ロケールでも正常に動作する' do
        raw_headers = [ "商品名", "価格", "数量" ]
        expected = [ "name", "price", "quantity" ]

        result = described_class.normalize(raw_headers, 'inventory')
        expect(result).to eq(expected)
      end
    end

    it 'Unicode文字を適切に処理する' do
      # ひらがな・カタカナ・漢字が混在するヘッダー
      raw_headers = [ "しょうひんめい", "カテゴリー", "漢字商品名" ]

      expect {
        described_class.normalize(raw_headers, 'inventory')
      }.not_to raise_error
    end
  end

  describe 'エラーハンドリング' do
    it 'I18n設定エラーを適切に処理する' do
      allow(I18n).to receive(:t).and_raise(I18n::MissingTranslationData.new("en", "missing.key"))

      expect {
        described_class.normalize([ "Header" ], 'inventory')
      }.not_to raise_error
    end

    it '無効な文字を含むヘッダーを安全に処理する' do
      invalid_headers = [ "\x00invalid\x01", "valid_header" ]

      expect {
        result = described_class.normalize(invalid_headers, 'inventory')
        expect(result).to include("valid_header")
      }.not_to raise_error
    end

    it 'メモリ不足状況を想定したテスト' do
      # 極端に長いヘッダーでメモリ効率をテスト
      very_long_header = "a" * 10000

      expect {
        described_class.normalize([ very_long_header ], 'inventory')
      }.not_to raise_error
    end
  end

  describe '実際のCSVファイル形式のテスト' do
    it 'Excelで出力されたCSVヘッダーを適切に処理する' do
      # Excelでよく見られるBOM付きヘッダー
      excel_headers = [ "\xEF\xBB\xBF商品名", "価格", "数量" ]

      result = described_class.normalize(excel_headers, 'inventory')
      # BOMが除去されて正常にマッピングされる
      expect(result).to include("name")
    end

    it 'Google Sheetsエクスポート形式を適切に処理する' do
      # Google Sheetsでよく見られる形式
      sheets_headers = [ "Product Name", "Price (¥)", "Stock Quantity" ]

      result = described_class.normalize(sheets_headers, 'inventory')
      expect(result).to include("name", "price")
    end
  end

  # TODO: 🔴 Phase 1（緊急）- 追加テストケース
  # 優先度: 高（CLAUDE.md準拠）
  # 実装期間: 1日
  # 横展開: 他のCSV処理ユーティリティと同等のテスト網羅性達成
  #
  # 1. 複雑な多言語対応テスト
  #    - 中国語・韓国語ヘッダー対応
  #    - 右から左へ書く言語（アラビア語等）
  #    - 文字正規化（Unicode NFC/NFD）
  #
  # 2. CSVフォーマット互換性テスト
  #    - RFC 4180準拠の厳密テスト
  #    - 異なるエンコーディング（Shift_JIS等）
  #    - 区切り文字・引用符の変種対応
  #
  # 3. 大規模データ対応テスト
  #    - 10万行以上のCSVヘッダー処理
  #    - メモリ使用量の監視
  #    - ガベージコレクション効率化
  #
  # 4. セキュリティ強化テスト
  #    - CSVインジェクション対策
  #    - ファイルサイズ制限
  #    - 悪意あるヘッダーの無害化
end
