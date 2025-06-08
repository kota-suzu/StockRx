# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PasswordStrengthV2Validator do
  # テスト用の一時的なクラスを定義
  let(:test_model) do
    Class.new do
      include ActiveModel::Validations

      attr_accessor :password

      def self.name
        'TestModel'
      end
    end
  end

  let(:model) { test_model.new }

  describe '事前定義ルールセット' do
    it 'PREDEFINED_RULE_SETSが正しく定義されていること' do
      expect(described_class::PREDEFINED_RULE_SETS).to include(:basic, :standard, :enterprise)

      # basic設定の確認
      basic = described_class::PREDEFINED_RULE_SETS[:basic]
      expect(basic[:min_length]).to eq(8)
      expect(basic[:require_symbol]).to be false

      # standard設定の確認
      standard = described_class::PREDEFINED_RULE_SETS[:standard]
      expect(standard[:min_length]).to eq(12)
      expect(standard[:require_symbol]).to be true

      # enterprise設定の確認
      enterprise = described_class::PREDEFINED_RULE_SETS[:enterprise]
      expect(enterprise[:min_length]).to eq(14)
      expect(enterprise[:max_length]).to eq(128)
    end
  end

  describe '基本的なバリデーション（デフォルト設定）' do
    before do
      test_model.validates :password, password_strength_v2: true
    end

    context '有効なパスワード' do
      it 'standard設定の要件を満たすパスワードを許可すること' do
        model.password = 'StrongPassword123!'
        expect(model).to be_valid
      end

      it '複雑なパスワードを許可すること' do
        model.password = 'MyVerySecureP@ssw0rd2024!'
        expect(model).to be_valid
      end
    end

    context '無効なパスワード' do
      it '短すぎるパスワードを拒否すること' do
        model.password = 'Short1!'
        expect(model).not_to be_valid
        expect(model.errors[:password]).to include(/文字以上/)
      end

      it '数字が含まれていないパスワードを拒否すること' do
        model.password = 'LongPasswordWithoutDigits!'
        expect(model).not_to be_valid
        expect(model.errors[:password]).to include(/数字/)
      end

      it '小文字が含まれていないパスワードを拒否すること' do
        model.password = 'ALLUPPERCASEPASSWORD123!'
        expect(model).not_to be_valid
        expect(model.errors[:password]).to include(/小文字/)
      end

      it '大文字が含まれていないパスワードを拒否すること' do
        model.password = 'alllowercasepassword123!'
        expect(model).not_to be_valid
        expect(model.errors[:password]).to include(/大文字/)
      end

      it '特殊文字が含まれていないパスワードを拒否すること' do
        model.password = 'LongPasswordWithoutSymbols123'
        expect(model).not_to be_valid
        expect(model.errors[:password]).to include(/特殊文字/)
      end

      it '複雑度が不足しているパスワードを拒否すること' do
        model.password = 'simple123'  # 要求スコア4未満 (small:1 + digit:1 + length8:1 = 3点)
        expect(model).not_to be_valid
        expect(model.errors[:password]).to include(/複雑度/)
      end
    end

    context 'nil・空値の場合' do
      it 'nilパスワードに対してバリデーションをスキップすること' do
        model.password = nil
        expect(model).to be_valid
      end
    end
  end

  describe 'ルールセット指定' do
    context 'basicルールセット' do
      let(:basic_model) do
        Class.new do
          include ActiveModel::Validations
          attr_accessor :password
          validates :password, password_strength_v2: { rule_set: :basic }

          def self.name
            'BasicTestModel'
          end
        end
      end

      let(:basic_instance) { basic_model.new }

      it 'basic要件を満たすパスワードを許可すること' do
        basic_instance.password = 'Password123'  # 記号なしでOK
        expect(basic_instance).to be_valid
      end

      it '短いパスワードでも8文字以上なら許可すること' do
        basic_instance.password = 'Pass123a'  # 8文字
        expect(basic_instance).to be_valid
      end
    end

    context 'enterpriseルールセット' do
      let(:enterprise_model) do
        Class.new do
          include ActiveModel::Validations
          attr_accessor :password
          validates :password, password_strength_v2: { rule_set: :enterprise }

          def self.name
            'EnterpriseTestModel'
          end
        end
      end

      let(:enterprise_instance) { enterprise_model.new }

      it 'enterprise要件を満たすパスワードを許可すること' do
        enterprise_instance.password = 'VeryStrongEnterprise123!'
        expect(enterprise_instance).to be_valid
      end

      it '14文字未満のパスワードを拒否すること' do
        enterprise_instance.password = 'TooShort123!'  # 13文字
        expect(enterprise_instance).not_to be_valid
        expect(enterprise_instance.errors[:password]).to include(/14〜128文字である必要があります/)
      end

      it '128文字超過のパスワードを拒否すること' do
        enterprise_instance.password = 'a' * 126 + 'A1!'  # 129文字
        expect(enterprise_instance).not_to be_valid
        expect(enterprise_instance.errors[:password]).to include(/14〜128文字である必要があります/)
      end
    end
  end

  describe 'カスタム設定オーバーライド' do
    context '個別オプション指定' do
      before do
        test_model.validates :password, password_strength_v2: {
          min_length: 10,
          require_symbol: false,
          complexity_score: 3
        }
      end

      it 'カスタム設定が適用されること' do
        model.password = 'CustomPass123'  # 記号なし、10文字、スコア3
        expect(model).to be_valid
      end
    end

    context 'ルールセット + カスタム設定' do
      before do
        test_model.validates :password, password_strength_v2: {
          rule_set: :basic,
          min_length: 10  # basicの8文字を10文字にオーバーライド
        }
      end

      it 'ルールセットにカスタム設定が上書きされること' do
        model.password = 'Pass123'  # 8文字（basicの要求は満たすが、カスタム要求未満）
        expect(model).not_to be_valid

        model.password = 'Password123'  # 10文字
        expect(model).to be_valid
      end
    end
  end

  describe 'カスタムルール拡張' do
    context '正規表現カスタムルール' do
      before do
        test_model.validates :password, password_strength_v2: {
          rule_set: :basic,
          custom_rules: [
            {
              type: :regex,
              pattern: /^[A-Za-z]/,  # 英字で始まる
              error_message: "パスワードは英字で始まる必要があります"
            }
          ]
        }
      end

      it 'カスタム正規表現ルールが適用されること' do
        model.password = '1Password123'  # 数字で始まる
        expect(model).not_to be_valid
        expect(model.errors[:password]).to include("パスワードは英字で始まる必要があります")

        model.password = 'Password123'  # 英字で始まる
        expect(model).to be_valid
      end
    end

    context '長さ範囲カスタムルール' do
      before do
        test_model.validates :password, password_strength_v2: {
          rule_set: :basic,
          custom_rules: [
            {
              type: :length_range,
              min_length: 15,
              max_length: 20,
              error_message: "パスワードは15-20文字である必要があります"
            }
          ]
        }
      end

      it 'カスタム長さ範囲ルールが適用されること' do
        model.password = 'Password123'  # 12文字（範囲外）
        expect(model).not_to be_valid
        expect(model.errors[:password]).to include("パスワードは15-20文字である必要があります")

        model.password = 'ExtendedPassword123'  # 18文字
        expect(model).to be_valid
      end
    end

    context '複雑度カスタムルール' do
      before do
        test_model.validates :password, password_strength_v2: {
          rule_set: :basic,
          custom_rules: [
            {
              type: :complexity_score,
              min_score: 6,
              error_message: "パスワードの複雑度が不十分です（最小スコア6）"
            }
          ]
        }
      end

      it 'カスタム複雑度ルールが適用されること' do
        model.password = 'Password123'  # スコア不足
        expect(model).not_to be_valid
        expect(model.errors[:password]).to include("パスワードの複雑度が不十分です（最小スコア6）")

        model.password = 'VeryComplexPassword123!'  # 高スコア
        expect(model).to be_valid
      end
    end

    context 'ラムダカスタムルール' do
      before do
        test_model.validates :password, password_strength_v2: {
          rule_set: :basic,
          custom_rules: [
            {
              type: :custom_lambda,
              lambda: ->(value) { !value.include?('password') },
              error_message: "パスワードに'password'を含めることはできません"
            }
          ]
        }
      end

      it 'ラムダカスタムルールが適用されること' do
        model.password = 'mypassword123'  # 'password'を含む
        expect(model).not_to be_valid
        expect(model.errors[:password]).to include("パスワードに'password'を含めることはできません")

        model.password = 'SecretCode123'  # 'password'を含まない
        expect(model).to be_valid
      end
    end
  end

  describe '複数エラーメッセージ' do
    before do
      test_model.validates :password, password_strength_v2: { rule_set: :standard }
    end

    it '複数の要件が満たされていない場合、すべてのエラーを表示すること' do
      model.password = 'short'  # 短い、大文字なし、数字なし、記号なし
      expect(model).not_to be_valid

      errors = model.errors[:password]
      expect(errors.length).to be > 1
      expect(errors.join(' ')).to include('文字以上')
    end
  end

  describe '不正なカスタムルール' do
    it '未知のルールタイプでログ警告が出力されること' do
      allow(Rails.logger).to receive(:warn)

      test_model.validates :password, password_strength_v2: {
        custom_rules: [
          { type: :unknown_type, some_config: "value" }
        ]
      }

      model.password = 'Password123!'
      model.valid?  # バリデーション実行

      expect(Rails.logger).to have_received(:warn).with(/Unknown custom rule type/)
    end
  end

  describe 'パフォーマンステスト' do
    before do
      test_model.validates :password, password_strength_v2: { rule_set: :enterprise }
    end

    it '大量のバリデーション実行でも高速に処理されること' do
      test_passwords = [
        'ValidPassword123!',
        'AnotherSecurePass456#',
        'ThirdComplexPassword789$'
      ]

      start_time = Time.current

      1000.times do |i|
        model.password = test_passwords[i % 3]
        model.valid?
      end

      end_time = Time.current
      duration = end_time - start_time

      expect(duration).to be < 1.0  # 1秒以内
      puts "1000回バリデーション実行時間: #{(duration * 1000).round(2)}ms"
    end
  end

  describe 'メモリ使用量テスト' do
    before do
      test_model.validates :password, password_strength_v2: { rule_set: :standard }
    end

    it 'メモリリークが発生しないこと' do
      GC.start
      initial_objects = ObjectSpace.count_objects

      5000.times do |i|
        model.password = "TestPassword#{i}!"
        model.valid?
      end

      GC.start
      final_objects = ObjectSpace.count_objects

      # オブジェクト増加量が合理的な範囲内であることを確認
      object_increase = final_objects[:T_OBJECT] - initial_objects[:T_OBJECT]
      expect(object_increase).to be < 1000
    end
  end

  describe '国際化対応' do
    before do
      test_model.validates :password, password_strength_v2: { rule_set: :standard }
    end

    it 'マルチバイト文字を含むパスワードを正しく処理すること' do
      model.password = 'パスワードabc123A!'  # 日本語+英小文字+英大文字+数字+記号
      expect(model).to be_valid
    end

    it '絵文字を含むパスワードを正しく処理すること' do
      model.password = 'SecurePass123!🔒'  # 絵文字含む
      expect(model).to be_valid
    end
  end

  describe 'エッジケース' do
    before do
      test_model.validates :password, password_strength_v2: { rule_set: :standard }
    end

    it '非常に長いパスワードを正しく処理すること' do
      long_password = 'A' * 1000 + 'a' * 1000 + '1' * 1000 + '!' * 1000
      model.password = long_password
      expect(model).to be_valid
    end

    it '制御文字を含むパスワードを正しく処理すること' do
      model.password = "Password123!\t\n\r"
      expect(model).to be_valid
    end

    it 'Unicode文字を含むパスワードを正しく処理すること' do
      model.password = 'Pässwörd123!çñüé'
      expect(model).to be_valid
    end
  end

  describe '境界値テスト' do
    before do
      test_model.validates :password, password_strength_v2: { min_length: 12, max_length: 128 }
    end

    it '境界値で正しく動作すること' do
      # 最小長-1
      model.password = 'Password12!'  # 11文字
      expect(model).not_to be_valid

      # 最小長
      model.password = 'Password123!'  # 12文字
      expect(model).to be_valid

      # 最大長
      model.password = 'A' * 125 + 'a1!'  # 128文字
      expect(model).to be_valid

      # 最大長+1
      model.password = 'A' * 126 + 'a1!'  # 129文字
      expect(model).not_to be_valid
    end
  end
end
