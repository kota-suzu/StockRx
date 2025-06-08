# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PasswordRules::LengthRangeValidator do
  describe '初期化' do
    context '最小長のみ指定した場合' do
      let(:validator) { described_class.new(8) }

      it '正しく初期化されること' do
        expect(validator.min_length).to eq(8)
        expect(validator.max_length).to be_nil
      end
    end

    context '最小長と最大長を指定した場合' do
      let(:validator) { described_class.new(8, 128) }

      it '正しく初期化されること' do
        expect(validator.min_length).to eq(8)
        expect(validator.max_length).to eq(128)
      end
    end

    context 'カスタムエラーメッセージを指定した場合' do
      let(:validator) { described_class.new(8, 128, "カスタムエラー") }

      it 'カスタムメッセージが設定されること' do
        expect(validator.error_message).to eq("カスタムエラー")
      end
    end

    context '無効な最小長を指定した場合' do
      it 'ArgumentErrorが発生すること' do
        expect { described_class.new(-1) }.to raise_error(ArgumentError, /must be a non-negative integer/)
        expect { described_class.new("invalid") }.to raise_error(ArgumentError, /must be a non-negative integer/)
      end
    end

    context '無効な最大長を指定した場合' do
      it 'ArgumentErrorが発生すること' do
        expect { described_class.new(8, -1) }.to raise_error(ArgumentError, /must be a non-negative integer/)
        expect { described_class.new(8, "invalid") }.to raise_error(ArgumentError, /must be a non-negative integer/)
      end
    end

    context '最小長が最大長より大きい場合' do
      it 'ArgumentErrorが発生すること' do
        expect { described_class.new(128, 8) }.to raise_error(ArgumentError, /cannot be greater than max_length/)
      end
    end
  end

  describe 'セキュリティ定数' do
    it 'NIST推奨値が正しく定義されていること' do
      expect(described_class::MIN_SECURE_LENGTH).to eq(8)
      expect(described_class::MAX_SECURE_LENGTH).to eq(128)
      expect(described_class::RECOMMENDED_MIN_LENGTH).to eq(12)
    end
  end

  describe '#valid?' do
    context '最小長のみ指定した場合' do
      let(:validator) { described_class.new(8) }

      it '最小長以上の場合にtrueを返すこと' do
        expect(validator.valid?("12345678")).to be true    # 8文字
        expect(validator.valid?("123456789")).to be true   # 9文字
        expect(validator.valid?("a" * 100)).to be true     # 100文字
      end

      it '最小長未満の場合にfalseを返すこと' do
        expect(validator.valid?("1234567")).to be false   # 7文字
        expect(validator.valid?("")).to be false          # 0文字
      end
    end

    context '最大長のみ指定した場合' do
      let(:validator) { described_class.new(0, 10) }

      it '最大長以下の場合にtrueを返すこと' do
        expect(validator.valid?("")).to be true           # 0文字
        expect(validator.valid?("12345")).to be true      # 5文字
        expect(validator.valid?("1234567890")).to be true # 10文字
      end

      it '最大長超過の場合にfalseを返すこと' do
        expect(validator.valid?("12345678901")).to be false # 11文字
      end
    end

    context '最小長と最大長を指定した場合' do
      let(:validator) { described_class.new(8, 16) }

      it '範囲内の場合にtrueを返すこと' do
        expect(validator.valid?("12345678")).to be true    # 8文字
        expect(validator.valid?("123456789012")).to be true # 12文字
        expect(validator.valid?("1234567890123456")).to be true # 16文字
      end

      it '範囲外の場合にfalseを返すこと' do
        expect(validator.valid?("1234567")).to be false    # 7文字（最小未満）
        expect(validator.valid?("12345678901234567")).to be false # 17文字（最大超過）
      end
    end

    context '空値の場合' do
      let(:validator) { described_class.new(8) }

      it 'falseを返すこと' do
        expect(validator.valid?(nil)).to be false
        expect(validator.valid?("")).to be false
      end
    end
  end

  describe 'ファクトリーメソッド' do
    describe '.minimum' do
      let(:validator) { described_class.minimum(10) }

      it '最小長バリデーターを作成すること' do
        expect(validator.min_length).to eq(10)
        expect(validator.max_length).to be_nil
        expect(validator.valid?("1234567890")).to be true  # 10文字
        expect(validator.valid?("123456789")).to be false  # 9文字
      end
    end

    describe '.maximum' do
      let(:validator) { described_class.maximum(20) }

      it '最大長バリデーターを作成すること' do
        expect(validator.min_length).to eq(0)
        expect(validator.max_length).to eq(20)
        expect(validator.valid?("a" * 20)).to be true     # 20文字
        expect(validator.valid?("a" * 21)).to be false    # 21文字
      end
    end

    describe '.exact' do
      let(:validator) { described_class.exact(12) }

      it '固定長バリデーターを作成すること' do
        expect(validator.min_length).to eq(12)
        expect(validator.max_length).to eq(12)
        expect(validator.valid?("123456789012")).to be true  # 12文字
        expect(validator.valid?("12345678901")).to be false  # 11文字
        expect(validator.valid?("1234567890123")).to be false # 13文字
      end
    end

    describe '.secure' do
      let(:validator) { described_class.secure }

      it 'セキュアなバリデーターを作成すること' do
        expect(validator.min_length).to eq(described_class::RECOMMENDED_MIN_LENGTH)
        expect(validator.max_length).to eq(described_class::MAX_SECURE_LENGTH)
      end
    end

    describe '.nist_compliant' do
      let(:validator) { described_class.nist_compliant }

      it 'NIST準拠バリデーターを作成すること' do
        expect(validator.min_length).to eq(described_class::MIN_SECURE_LENGTH)
        expect(validator.max_length).to eq(described_class::MAX_SECURE_LENGTH)
      end
    end
  end

  describe '#range_description' do
    it '範囲の説明を正しく生成すること' do
      expect(described_class.new(8, 16).range_description).to eq("8〜16文字")
      expect(described_class.new(8).range_description).to eq("8文字以上")
      expect(described_class.new(0, 16).range_description).to eq("16文字以下")
      expect(described_class.new(12, 12).range_description).to eq("12文字")
    end
  end

  describe '#security_level' do
    it 'セキュリティレベルを正しく判定すること' do
      expect(described_class.new(4).security_level).to eq(:weak)
      expect(described_class.new(8).security_level).to eq(:moderate)
      expect(described_class.new(12).security_level).to eq(:strong)
      expect(described_class.new(16).security_level).to eq(:strong)
    end

    it '最小長が設定されていない場合はunknownを返すこと' do
      expect(described_class.new(0, 10).security_level).to eq(:unknown)
    end
  end

  describe 'エラーメッセージ生成' do
    context '範囲指定の場合' do
      let(:validator) { described_class.new(8, 16) }

      it '範囲を示すメッセージを生成すること' do
        expect(validator.error_message).to eq("パスワードは8〜16文字である必要があります")
      end
    end

    context '最小長のみの場合' do
      let(:validator) { described_class.new(8) }

      it '最小長を示すメッセージを生成すること' do
        expect(validator.error_message).to eq("パスワードは8文字以上である必要があります")
      end
    end

    context '最大長のみの場合' do
      let(:validator) { described_class.new(0, 16) }

      it '最大長を示すメッセージを生成すること' do
        expect(validator.error_message).to eq("パスワードは16文字以下である必要があります")
      end
    end

    context '固定長の場合' do
      let(:validator) { described_class.new(12, 12) }

      it '固定長を示すメッセージを生成すること' do
        expect(validator.error_message).to eq("パスワードは12文字である必要があります")
      end
    end
  end

  describe '#inspect' do
    let(:validator) { described_class.new(8, 16) }

    it 'クラス名と範囲情報を含む文字列を返すこと' do
      result = validator.inspect
      expect(result).to match(/LengthRangeValidator/)
      expect(result).to include("range=8〜16文字")
    end
  end

  describe 'エッジケース' do
    let(:validator) { described_class.new(8, 16) }

    it 'マルチバイト文字を正しく処理すること' do
      expect(validator.valid?("あいうえおかきく")).to be true   # 8文字
      expect(validator.valid?("あいうえお")).to be false       # 5文字
    end

    it '絵文字を正しく処理すること' do
      # 絵文字は文字数として正しくカウントされること
      emoji_string = "🔒🔑🛡️⚡💻🚀✨🎯"  # 8文字
      expect(validator.valid?(emoji_string)).to be true
    end

    it '制御文字を含む文字列を正しく処理すること' do
      string_with_control = "test\t\n\r123"  # タブ、改行、復帰文字を含む
      expect(validator.valid?(string_with_control)).to be true  # 8文字
    end
  end

  describe 'パフォーマンステスト' do
    let(:validator) { described_class.new(8, 128) }

    it '非常に長い文字列でも高速に処理すること' do
      very_long_string = "a" * 100000

      start_time = Time.current
      result = validator.valid?(very_long_string)
      end_time = Time.current

      expect(result).to be false  # 最大長超過
      expect(end_time - start_time).to be < 0.1  # 100ms以内
    end
  end

  describe '境界値テスト' do
    let(:validator) { described_class.new(8, 16) }

    it '境界値で正しく動作すること' do
      # 最小長境界
      expect(validator.valid?("a" * 7)).to be false   # 最小長-1
      expect(validator.valid?("a" * 8)).to be true    # 最小長
      expect(validator.valid?("a" * 9)).to be true    # 最小長+1

      # 最大長境界
      expect(validator.valid?("a" * 15)).to be true   # 最大長-1
      expect(validator.valid?("a" * 16)).to be true   # 最大長
      expect(validator.valid?("a" * 17)).to be false  # 最大長+1
    end
  end
end
