# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PasswordRules::RegexRuleValidator do
  describe '初期化' do
    context '正規表現を直接指定した場合' do
      let(:validator) { described_class.new(/\d/, "数字が必要です") }

      it '正しく初期化されること' do
        expect(validator.pattern).to eq(/\d/)
        expect(validator.error_message).to eq("数字が必要です")
      end
    end

    context '文字列パターンを指定した場合' do
      let(:validator) { described_class.new('\d+', "数字が必要です") }

      it '正規表現に変換されること' do
        expect(validator.pattern).to be_a(Regexp)
        expect(validator.pattern.source).to eq('\d+')
      end
    end

    context 'シンボルパターンを指定した場合' do
      let(:validator) { described_class.new(:digit, "数字が必要です") }

      it '事前定義パターンが使用されること' do
        expect(validator.pattern).to eq(described_class::DIGIT_REGEX)
      end
    end

    context '複数パターンの配列を指定した場合' do
      let(:patterns) { [ /\d/, /[a-z]/ ] }
      let(:validator) { described_class.new(patterns, "数字と小文字が必要です") }

      it '配列として保存されること' do
        expect(validator.pattern).to eq(patterns)
      end
    end

    context '無効なパターンを指定した場合' do
      it 'ArgumentErrorが発生すること' do
        expect { described_class.new(123, "エラー") }.to raise_error(ArgumentError, /Pattern must be/)
      end
    end

    context '未知のシンボルパターンを指定した場合' do
      it 'ArgumentErrorが発生すること' do
        expect { described_class.new(:unknown_pattern, "エラー") }.to raise_error(ArgumentError, /Unknown pattern/)
      end
    end
  end

  describe '事前定義正規表現定数' do
    it 'DIGIT_REGEXが数字にマッチすること' do
      expect("123".match?(described_class::DIGIT_REGEX)).to be true
      expect("abc".match?(described_class::DIGIT_REGEX)).to be false
    end

    it 'LOWER_CASE_REGEXが小文字にマッチすること' do
      expect("abc".match?(described_class::LOWER_CASE_REGEX)).to be true
      expect("ABC".match?(described_class::LOWER_CASE_REGEX)).to be false
    end

    it 'UPPER_CASE_REGEXが大文字にマッチすること' do
      expect("ABC".match?(described_class::UPPER_CASE_REGEX)).to be true
      expect("abc".match?(described_class::UPPER_CASE_REGEX)).to be false
    end

    it 'SPECIAL_CHAR_REGEXが特殊文字にマッチすること' do
      expect("!@#".match?(described_class::SPECIAL_CHAR_REGEX)).to be true
      expect("abc123".match?(described_class::SPECIAL_CHAR_REGEX)).to be false
    end
  end

  describe '#valid?' do
    context '単一正規表現パターンの場合' do
      let(:validator) { described_class.new(/\d/, "数字が必要です") }

      it '一致する値でtrueを返すこと' do
        expect(validator.valid?("abc123")).to be true
      end

      it '一致しない値でfalseを返すこと' do
        expect(validator.valid?("abcdef")).to be false
      end

      it '空値でfalseを返すこと' do
        expect(validator.valid?("")).to be false
        expect(validator.valid?(nil)).to be false
      end
    end

    context '複数パターンのAND条件の場合' do
      let(:patterns) { [ /\d/, /[a-z]/, /[A-Z]/ ] }
      let(:validator) { described_class.new(patterns, "数字、小文字、大文字が必要です") }

      it 'すべてのパターンに一致する場合にtrueを返すこと' do
        expect(validator.valid?("Password123")).to be true
      end

      it '一部のパターンのみ一致する場合にfalseを返すこと' do
        expect(validator.valid?("password123")).to be false  # 大文字なし
        expect(validator.valid?("PASSWORD123")).to be false  # 小文字なし
        expect(validator.valid?("Password")).to be false     # 数字なし
      end
    end
  end

  describe 'ファクトリーメソッド' do
    describe '.digit' do
      let(:validator) { described_class.digit }

      it '数字パターンのバリデーターを作成すること' do
        expect(validator.valid?("test123")).to be true
        expect(validator.valid?("testonly")).to be false
      end

      it 'カスタムエラーメッセージを設定できること' do
        custom_validator = described_class.digit("カスタムエラー")
        expect(custom_validator.error_message).to eq("カスタムエラー")
      end
    end

    describe '.lowercase' do
      let(:validator) { described_class.lowercase }

      it '小文字パターンのバリデーターを作成すること' do
        expect(validator.valid?("Test")).to be true
        expect(validator.valid?("TEST")).to be false
      end
    end

    describe '.uppercase' do
      let(:validator) { described_class.uppercase }

      it '大文字パターンのバリデーターを作成すること' do
        expect(validator.valid?("Test")).to be true
        expect(validator.valid?("test")).to be false
      end
    end

    describe '.special_char' do
      let(:validator) { described_class.special_char }

      it '特殊文字パターンのバリデーターを作成すること' do
        expect(validator.valid?("test!")).to be true
        expect(validator.valid?("test123")).to be false
      end
    end
  end

  describe '複合パターンファクトリーメソッド' do
    describe '.any_of' do
      let(:validator) { described_class.any_of(/\d/, /[!@#]/, error_message: "数字または特殊文字が必要") }

      it 'いずれかのパターンに一致する場合にtrueを返すこと' do
        expect(validator.valid?("test123")).to be true    # 数字あり
        expect(validator.valid?("test!")).to be true      # 特殊文字あり
        expect(validator.valid?("test")).to be false      # どちらもなし
      end

      it 'カスタムエラーメッセージが設定されること' do
        expect(validator.error_message).to eq("数字または特殊文字が必要")
      end
    end

    describe '.all_of' do
      let(:validator) { described_class.all_of(/\d/, /[a-z]/, /[A-Z]/, error_message: "すべての文字種が必要") }

      it 'すべてのパターンに一致する場合にtrueを返すこと' do
        expect(validator.valid?("Password123")).to be true
        expect(validator.valid?("password123")).to be false  # 大文字なし
      end
    end
  end

  describe '#inspect' do
    let(:validator) { described_class.new(/\d/, "数字が必要です") }

    it 'クラス名とパターン情報を含む文字列を返すこと' do
      result = validator.inspect
      expect(result).to match(/RegexRuleValidator/)
      expect(result).to include("pattern=")
    end
  end

  describe 'エラーメッセージ' do
    context 'カスタムメッセージが指定された場合' do
      let(:validator) { described_class.new(/\d/, "カスタムエラーメッセージ") }

      it 'カスタムメッセージを返すこと' do
        expect(validator.error_message).to eq("カスタムエラーメッセージ")
      end
    end

    context 'カスタムメッセージが指定されない場合' do
      let(:validator) { described_class.new(/\d/) }

      it 'デフォルトメッセージを返すこと' do
        expect(validator.error_message).to eq("パスワードが必要な形式に一致していません")
      end
    end
  end

  describe 'パフォーマンステスト' do
    let(:validator) { described_class.new(/\d/) }
    let(:test_password) { "Password123!" }

    it '大量実行でもメモリリークしないこと' do
      # GC前の正規表現オブジェクト数を記録
      GC.start
      initial_regex_count = ObjectSpace.count_objects[:T_REGEXP]

      # 大量バリデーション実行
      10000.times { validator.valid?(test_password) }

      # GC後の正規表現オブジェクト数を確認
      GC.start
      final_regex_count = ObjectSpace.count_objects[:T_REGEXP]

      # 新規作成された正規表現オブジェクトが少ないことを確認（freeze効果）
      new_regex_objects = final_regex_count - initial_regex_count
      expect(new_regex_objects).to be < 100  # 許容範囲内
    end
  end

  describe 'エッジケース' do
    let(:validator) { described_class.new(/\d/) }

    it 'マルチバイト文字を含む文字列を正しく処理すること' do
      expect(validator.valid?("パスワード123")).to be true
      expect(validator.valid?("パスワード")).to be false
    end

    it '非常に長い文字列を正しく処理すること' do
      long_string = "a" * 10000 + "1"
      expect(validator.valid?(long_string)).to be true
    end

    it '改行文字を含む文字列を正しく処理すること' do
      expect(validator.valid?("test\n123")).to be true
    end
  end
end
