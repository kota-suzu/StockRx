# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PasswordRules::ComplexityScoreValidator do
  describe '初期化' do
    context '最小スコアのみ指定した場合' do
      let(:validator) { described_class.new(4) }

      it '正しく初期化されること' do
        expect(validator.min_score).to eq(4)
        expect(validator.custom_scoring).to be_a(Hash)
        expect(validator.custom_scoring[:enabled]).to be true
      end
    end

    context 'カスタムエラーメッセージを指定した場合' do
      let(:validator) { described_class.new(4, "カスタムエラー") }

      it 'カスタムメッセージが設定されること' do
        expect(validator.error_message).to eq("カスタムエラー")
      end
    end

    context 'カスタムスコアリング設定を指定した場合' do
      let(:custom_scoring) { { enabled: true, lowercase: 2, uppercase: 2 } }
      let(:validator) { described_class.new(4, nil, custom_scoring: custom_scoring) }

      it 'カスタム設定が反映されること' do
        expect(validator.custom_scoring[:lowercase]).to eq(2)
        expect(validator.custom_scoring[:uppercase]).to eq(2)
      end
    end

    context '無効な最小スコアを指定した場合' do
      it 'ArgumentErrorが発生すること' do
        expect { described_class.new(-1) }.to raise_error(ArgumentError, /must be a non-negative integer/)
        expect { described_class.new("invalid") }.to raise_error(ArgumentError, /must be a non-negative integer/)
      end
    end
  end

  describe '正規表現定数' do
    it '各文字種の正規表現が正しく定義されていること' do
      expect("abc".match?(described_class::LOWER_CASE_REGEX)).to be true
      expect("ABC".match?(described_class::UPPER_CASE_REGEX)).to be true
      expect("123".match?(described_class::DIGIT_REGEX)).to be true
      expect("!@#".match?(described_class::SYMBOL_REGEX)).to be true
    end
  end

  describe 'セキュリティレベル定数' do
    it 'セキュリティレベルが正しく定義されていること' do
      expect(described_class::SECURITY_LEVELS[:very_weak]).to eq(0..1)
      expect(described_class::SECURITY_LEVELS[:weak]).to eq(2..3)
      expect(described_class::SECURITY_LEVELS[:moderate]).to eq(4..5)
      expect(described_class::SECURITY_LEVELS[:strong]).to eq(6..7)
      expect(described_class::SECURITY_LEVELS[:very_strong]).to eq(8..Float::INFINITY)
    end
  end

  describe '#calculate_complexity_score' do
    let(:validator) { described_class.new(4) }

    context '文字種スコア計算' do
      it '各文字種に対して1ポイントずつ加算すること' do
        expect(validator.calculate_complexity_score("abc")).to eq(1)        # 小文字のみ
        expect(validator.calculate_complexity_score("ABC")).to eq(1)        # 大文字のみ
        expect(validator.calculate_complexity_score("123")).to eq(1)        # 数字のみ
        expect(validator.calculate_complexity_score("!@#")).to eq(1)        # 記号のみ
      end

      it '複数文字種の組み合わせで正しくスコア計算すること' do
        expect(validator.calculate_complexity_score("Abc")).to eq(2)        # 大文字+小文字
        expect(validator.calculate_complexity_score("Abc1")).to eq(3)       # 大文字+小文字+数字
        expect(validator.calculate_complexity_score("Abc1!")).to eq(4)      # 全文字種
      end
    end

    context '長さボーナススコア計算' do
      it '長さに応じてボーナスポイントが加算されること' do
        # 基本4ポイント（全文字種） + 長さボーナス
        expect(validator.calculate_complexity_score("Abc1!234")).to eq(5)      # 8文字: +1
        expect(validator.calculate_complexity_score("Abc1!2345678")).to eq(6)   # 12文字: +2
        expect(validator.calculate_complexity_score("Abc1!23456789012")).to eq(7) # 16文字: +3
        expect(validator.calculate_complexity_score("Abc1!2345678901234567")).to eq(8) # 20文字: +4
      end
    end

    context '空値の場合' do
      it '0を返すこと' do
        expect(validator.calculate_complexity_score("")).to eq(0)
        expect(validator.calculate_complexity_score(nil)).to eq(0)
      end
    end
  end

  describe '#valid?' do
    context 'スコア4を要求する場合' do
      let(:validator) { described_class.new(4) }

      it '要求スコア以上の場合にtrueを返すこと' do
        expect(validator.valid?("Abc1!")).to be true        # スコア4
        expect(validator.valid?("Abc1!234")).to be true     # スコア5
      end

      it '要求スコア未満の場合にfalseを返すこと' do
        expect(validator.valid?("Abc1")).to be false        # スコア3
        expect(validator.valid?("abc")).to be false         # スコア1
      end

      it '空値の場合にfalseを返すこと' do
        expect(validator.valid?("")).to be false
        expect(validator.valid?(nil)).to be false
      end
    end
  end

  describe 'ファクトリーメソッド' do
    describe '.weak' do
      let(:validator) { described_class.weak }

      it '最小スコア2のバリデーターを作成すること' do
        expect(validator.min_score).to eq(2)
        expect(validator.valid?("Ab")).to be true   # スコア2
        expect(validator.valid?("a")).to be false   # スコア1
      end
    end

    describe '.moderate' do
      let(:validator) { described_class.moderate }

      it '最小スコア4のバリデーターを作成すること' do
        expect(validator.min_score).to eq(4)
        expect(validator.valid?("Ab1!")).to be true  # スコア4
        expect(validator.valid?("Ab1")).to be false  # スコア3
      end
    end

    describe '.strong' do
      let(:validator) { described_class.strong }

      it '最小スコア6のバリデーターを作成すること' do
        expect(validator.min_score).to eq(6)
        expect(validator.valid?("ABc1!234567890123")).to be true  # 大文字(1)+小文字(1)+数字(1)+記号(1)+長さボーナス16文字(2) = 6
        expect(validator.valid?("Ab1!2345")).to be false         # A(1)+b(1)+12345(1)+!(1)+長さボーナス(1) = 5 < 6
      end
    end

    describe '.very_strong' do
      let(:validator) { described_class.very_strong }

      it '最小スコア8のバリデーターを作成すること' do
        expect(validator.min_score).to eq(8)
        expect(validator.valid?("Ab1!2345678901234567")).to be true  # スコア8
        expect(validator.valid?("Ab1!2345678")).to be false          # スコア6
      end
    end
  end

  describe '#complexity_breakdown' do
    let(:validator) { described_class.new(4) }
    let(:password) { "Password123!" }

    it '複雑度の詳細分析を返すこと' do
      breakdown = validator.complexity_breakdown(password)

      expect(breakdown).to include(
        :character_types,
        :length_bonus,
        :custom_score,
        :total_score,
        :security_level,
        :meets_requirement
      )

      expect(breakdown[:character_types][:lowercase]).to be true
      expect(breakdown[:character_types][:uppercase]).to be true
      expect(breakdown[:character_types][:digit]).to be true
      expect(breakdown[:character_types][:symbol]).to be true
      expect(breakdown[:total_score]).to be > 4
      expect(breakdown[:meets_requirement]).to be true
    end

    it '空値の場合に空ハッシュを返すこと' do
      expect(validator.complexity_breakdown("")).to eq({})
      expect(validator.complexity_breakdown(nil)).to eq({})
    end
  end

  describe '#security_level' do
    let(:validator) { described_class.new(0) }

    it '各スコアに対して正しいセキュリティレベルを返すこと' do
      expect(validator.security_level("a")).to eq(:very_weak)    # スコア1
      expect(validator.security_level("Ab")).to eq(:weak)        # スコア2
      expect(validator.security_level("Ab1!")).to eq(:moderate)  # スコア4
      expect(validator.security_level("Ab1!23")).to eq(:moderate)# スコア4（6文字、長さボーナスなし）
      expect(validator.security_level("Ab1!234567890123")).to eq(:strong) # 大文字(1)+小文字(1)+数字(1)+記号(1)+長さボーナス16文字(2)=6
    end
  end

  describe 'エラーメッセージ生成' do
    context 'セキュリティレベルに対応するスコアの場合' do
      let(:validator) { described_class.new(4) }  # moderate レベル

      it 'セキュリティレベルを含むメッセージを生成すること' do
        expect(validator.error_message).to include("moderate")
        expect(validator.error_message).to include("4")
      end
    end

    context '最高レベルのスコアの場合' do
      let(:validator) { described_class.new(9) }  # very_strongレベル

      it 'レベル名とスコアを含むメッセージを生成すること' do
        expect(validator.error_message).to include("very_strong")
        expect(validator.error_message).to include("9")
      end
    end
  end

  describe '#inspect' do
    let(:validator) { described_class.new(4) }

    it 'クラス名と最小スコア情報を含む文字列を返すこと' do
      result = validator.inspect
      expect(result).to match(/ComplexityScoreValidator/)
      expect(result).to include("min_score=4")
    end
  end

  describe 'カスタムスコアリング' do
    let(:custom_scoring) do
      {
        enabled: true,
        lowercase: 2,      # 小文字で2ポイント
        uppercase: 2,      # 大文字で2ポイント
        digit: 1,          # 数字で1ポイント
        symbol: 3,         # 記号で3ポイント
        length_bonus: false  # 長さボーナス無効
      }
    end
    let(:validator) { described_class.new(4, nil, custom_scoring: custom_scoring) }

    it 'カスタムスコアで計算されること' do
      expect(validator.calculate_complexity_score("a")).to eq(2)       # 小文字のみ
      expect(validator.calculate_complexity_score("A")).to eq(2)       # 大文字のみ
      expect(validator.calculate_complexity_score("1")).to eq(1)       # 数字のみ
      expect(validator.calculate_complexity_score("!")).to eq(3)       # 記号のみ
      expect(validator.calculate_complexity_score("Aa1!")).to eq(8)    # 全文字種

      # 長さボーナスが無効なので追加されない
      expect(validator.calculate_complexity_score("Aa1!1234567890")).to eq(8)
    end
  end

  describe 'パフォーマンステスト' do
    let(:validator) { described_class.new(4) }
    let(:test_password) { "Password123!" }

    it '大量実行でもメモリリークしないこと' do
      # GC前の正規表現オブジェクト数を記録
      GC.start
      initial_regex_count = ObjectSpace.count_objects[:T_REGEXP]

      # 大量バリデーション実行
      5000.times { validator.calculate_complexity_score(test_password) }

      # GC後の正規表現オブジェクト数を確認
      GC.start
      final_regex_count = ObjectSpace.count_objects[:T_REGEXP]

      # 新規作成された正規表現オブジェクトが少ないことを確認（freeze効果）
      new_regex_objects = final_regex_count - initial_regex_count
      expect(new_regex_objects).to be < 50  # 許容範囲内
    end

    it '複雑な計算でも高速に処理すること' do
      long_password = "A" * 1000 + "a" * 1000 + "1" * 1000 + "!" * 1000

      start_time = Time.current
      score = validator.calculate_complexity_score(long_password)
      end_time = Time.current

      expect(score).to be > 4
      expect(end_time - start_time).to be < 0.01  # 10ms以内
    end
  end

  describe 'エッジケース' do
    let(:validator) { described_class.new(4) }

    it 'マルチバイト文字を正しく処理すること' do
      # 日本語文字は記号として扱われること
      expect(validator.calculate_complexity_score("あいう")).to eq(1)  # 記号スコア
      expect(validator.calculate_complexity_score("Abc123あいう")).to eq(5)  # 基本文字種+記号+長さボーナス(8文字)
    end

    it '絵文字を正しく処理すること' do
      # 絵文字は記号として扱われること
      expect(validator.calculate_complexity_score("🔒🔑")).to eq(1)  # 記号スコア
      expect(validator.calculate_complexity_score("Abc123🔒")).to eq(4)  # 基本文字種+記号
    end

    it '制御文字を含む文字列を正しく処理すること' do
      password_with_control = "Abc123\t\n!"
      score = validator.calculate_complexity_score(password_with_control)
      expect(score).to be >= 4  # 基本文字種は最低4ポイント
    end

    it '同じ文字の繰り返しでも正しく処理すること' do
      # 同じ文字でも文字種は評価される
      expect(validator.calculate_complexity_score("AAAA")).to eq(1)     # 大文字のみ
      expect(validator.calculate_complexity_score("aaaa")).to eq(1)     # 小文字のみ
      expect(validator.calculate_complexity_score("1111")).to eq(1)     # 数字のみ
      expect(validator.calculate_complexity_score("!!!!")).to eq(1)     # 記号のみ
    end
  end

  describe '境界値テスト' do
    let(:validator) { described_class.new(4) }

    it '最小スコア境界で正しく動作すること' do
      # スコア3（要求未満）
      expect(validator.valid?("Abc1")).to be false  # A(1) + bc(1) + 1(1) = 3

      # スコア4（要求通り）
      expect(validator.valid?("Abc1!")).to be true  # A(1) + bc(1) + 1(1) + !(1) = 4

      # スコア5（要求以上）
      expect(validator.valid?("Abc12345!")).to be true  # A(1) + bc(1) + 12345(1) + !(1) + 長さボーナス9文字(1) = 5
    end
  end
end
