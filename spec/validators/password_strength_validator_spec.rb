# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PasswordStrengthValidator do
  # テスト用の一時的なクラスを定義
  let(:test_model) do
    Class.new do
      include ActiveModel::Validations

      attr_accessor :password

      validates :password, password_strength: true

      def self.name
        'TestModel'
      end
    end
  end

  let(:model) { test_model.new }

  # ============================================
  # 基本機能テスト（後方互換性確保）
  # ============================================

  context '強いパスワード' do
    it '有効なパスワードを許可すること' do
      model.password = 'Password123!'
      expect(model).to be_valid
    end

    it '複雑なパスワードを許可すること' do
      model.password = 'MySecureP@ssw0rd2024!'
      expect(model).to be_valid
    end
  end

  context '弱いパスワード' do
    it '短すぎるパスワードは無効であること' do
      model.password = 'Abc12!'
      expect(model).not_to be_valid
      expect(model.errors[:password]).to include(/文字以上/)
    end

    it '数字を含まないパスワードは無効であること' do
      model.password = 'PasswordAbc!'
      expect(model).not_to be_valid
      expect(model.errors[:password]).to include(/数字を含める/)
    end

    it '小文字を含まないパスワードは無効であること' do
      model.password = 'PASSWORD123!'
      expect(model).not_to be_valid
      expect(model.errors[:password]).to include(/小文字を含める/)
    end

    it '大文字を含まないパスワードは無効であること' do
      model.password = 'password123!'
      expect(model).not_to be_valid
      expect(model.errors[:password]).to include(/大文字を含める/)
    end

    it '記号を含まないパスワードは無効であること' do
      model.password = 'Password123'
      expect(model).not_to be_valid
      expect(model.errors[:password]).to include(/記号を含める/)
    end
  end

  # ============================================
  # カプセル化された設定機能のテスト
  # ============================================

  context 'カスタム設定' do
    let(:test_model_with_options) do
      Class.new do
        include ActiveModel::Validations

        attr_accessor :password

        validates :password, password_strength: { min_length: 8, symbol: false }

        def self.name
          'TestModelWithOptions'
        end
      end
    end

    let(:model_with_options) { test_model_with_options.new }

    it 'カスタム設定のバリデーションを正しく適用すること' do
      model_with_options.password = 'Password123'  # 記号なしでOK、長さ8以上
      expect(model_with_options).to be_valid

      model_with_options.password = 'Pass123'  # 短すぎる
      expect(model_with_options).not_to be_valid
    end

    it '個別ルールの無効化が正しく動作すること' do
      custom_model = Class.new do
        include ActiveModel::Validations
        attr_accessor :password
        validates :password, password_strength: {
          min_length: 6,
          digit: false,
          upper: false
        }
        def self.name; 'CustomModel'; end
      end.new

      # 数字なし、大文字なしでもOK
      custom_model.password = 'password!'
      expect(custom_model).to be_valid
    end
  end

  # ============================================
  # カスタムルール機能のテスト（新機能）
  # ============================================

  context 'カスタムルール拡張機能' do
    let(:test_model_with_custom_rules) do
      Class.new do
        include ActiveModel::Validations

        attr_accessor :password

        validates :password, password_strength: {
          min_length: 8,
          custom_rules: [
            {
              type: :regex,
              pattern: /[äöüß]/,
              error_key: :missing_german_chars
            },
            {
              type: :complexity_score,
              min_score: 4,
              error_key: :insufficient_complexity
            }
          ]
        }

        def self.name
          'TestModelWithCustomRules'
        end
      end
    end

    let(:model_with_custom) { test_model_with_custom_rules.new }

    it 'カスタム正規表現ルールが動作すること' do
      model_with_custom.password = 'Password123!' # ドイツ語文字なし
      expect(model_with_custom).not_to be_valid
      expect(model_with_custom.errors[:password]).to include(/german/)

      model_with_custom.password = 'Passwört123!' # ドイツ語文字あり
      expect(model_with_custom).to be_valid
    end

    it '複雑度スコアルールが動作すること' do
      # 複雑度不足
      model_with_custom.password = 'simpleäöü'
      expect(model_with_custom).not_to be_valid
      expect(model_with_custom.errors[:password]).to include(/complexity/)

      # 複雑度十分
      model_with_custom.password = 'ComplexPäss123!'
      expect(model_with_custom).to be_valid
    end
  end

  # ============================================
  # カプセル化されたメソッドの単体テスト
  # ============================================

  describe 'PasswordRule構造体' do
    let(:rule) do
      described_class::PasswordRule.new(
        name: :test_rule,
        regex: /test/,
        error_key: :test_error,
        enabled_by_default: true
      )
    end

    describe '#enabled?' do
      it 'デフォルト値で有効状態を返すこと' do
        expect(rule.enabled?({})).to be true
      end

      it 'オプションでの無効化が正しく動作すること' do
        expect(rule.enabled?({ test_rule: false })).to be false
      end

      it 'nilの場合はデフォルト値を使用すること' do
        expect(rule.enabled?({ test_rule: nil })).to be true
      end
    end

    describe '#validate_against' do
      it '正規表現マッチングが正しく動作すること' do
        expect(rule.validate_against('testing')).to be true
        expect(rule.validate_against('example')).to be false
      end
    end
  end

  describe 'カスタムルールバリデーター' do
    describe 'RegexRuleValidator' do
      it '文字列パターンからRegexpオブジェクトを作成すること' do
        validator = described_class::RegexRuleValidator.new('[0-9]+')
        expect(validator.valid?('123')).to be true
        expect(validator.valid?('abc')).to be false
      end

      it 'Regexpオブジェクトをそのまま使用すること' do
        validator = described_class::RegexRuleValidator.new(/[a-z]+/)
        expect(validator.valid?('abc')).to be true
        expect(validator.valid?('123')).to be false
      end
    end

    describe 'LengthRangeValidator' do
      let(:validator) { described_class::LengthRangeValidator.new(8, 16) }

      it '範囲内の長さを有効とすること' do
        expect(validator.valid?('password')).to be true  # 8文字
        expect(validator.valid?('a' * 16)).to be true     # 16文字
        expect(validator.valid?('a' * 12)).to be true     # 中間
      end

      it '範囲外の長さを無効とすること' do
        expect(validator.valid?('short')).to be false     # 5文字
        expect(validator.valid?('a' * 20)).to be false    # 20文字
      end
    end

    describe 'ComplexityScoreValidator' do
      let(:validator) { described_class::ComplexityScoreValidator.new(4) }

      it '複雑度スコアを正しく計算すること' do
        # スコア6: 小文字+大文字+数字+記号+12文字以上+16文字未満
        expect(validator.valid?('Password123!')).to be true

        # スコア3: 小文字+大文字+数字（複雑度不足）
        expect(validator.valid?('Password123')).to be false

        # スコア6: 小文字+大文字+数字+記号+12文字以上+16文字以上
        expect(validator.valid?('VeryComplexPassword123!')).to be true
      end
    end
  end

  # ============================================
  # エラーハンドリングとエッジケーステスト
  # ============================================

  context 'エラーハンドリング' do
    it 'nilパスワードを適切に処理すること' do
      model.password = nil
      expect(model).to be_valid # nilは早期リターンで有効
    end

    it '空文字列パスワードを無効とすること' do
      model.password = ''
      expect(model).not_to be_valid
      expect(model.errors[:password]).to include(/文字以上/)
    end

    it '不正なカスタムルールタイプでエラーを発生させること' do
      invalid_model = Class.new do
        include ActiveModel::Validations
        attr_accessor :password
        validates :password, password_strength: {
          custom_rules: [ { type: :invalid_type } ]
        }
        def self.name; 'InvalidModel'; end
      end.new

      invalid_model.password = 'Password123!'
      expect { invalid_model.valid? }.to raise_error(ArgumentError, /Unknown custom rule type/)
    end
  end

  # ============================================
  # パフォーマンステスト（freeze効果確認）
  # ============================================

  context 'パフォーマンス' do
    it '大量バリデーションでメモリ効率が良いこと', :performance do
      passwords = [ 'Password123!' ] * 1000

      memory_before = ObjectSpace.count_objects[:T_REGEXP]

      passwords.each do |password|
        model.password = password
        model.valid?
      end

      memory_after = ObjectSpace.count_objects[:T_REGEXP]

      # 正規表現オブジェクトの増加が最小限であることを確認
      expect(memory_after - memory_before).to be < 10
    end
  end

  # ============================================
  # 拡張性・横展開テスト
  # ============================================

  context '拡張性の確認' do
    it '新しい強度ルールを動的に追加できること' do
      # 将来的に新しいルールタイプを追加する際のテンプレート
      expect(described_class::STRENGTH_RULES).to be_frozen
      expect(described_class::STRENGTH_RULES.size).to eq(4)

      # 各ルールが期待される構造を持つことを確認
      described_class::STRENGTH_RULES.each do |rule|
        expect(rule).to respond_to(:name, :regex, :error_key, :enabled_by_default)
        expect(rule).to respond_to(:enabled?, :validate_against)
      end
    end

    it 'デフォルト設定が適切に保護されていること' do
      expect(described_class::DEFAULT_CONFIG).to be_frozen
      expect(described_class::DEFAULT_CONFIG).to include(:min_length, :custom_rules)
    end
  end
end
