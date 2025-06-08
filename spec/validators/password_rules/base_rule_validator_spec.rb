# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PasswordRules::BaseRuleValidator do
  # テスト用の具象クラスを作成
  let(:test_validator_class) do
    Class.new(described_class) do
      def initialize(expected_value = "test", error_msg = "Test error")
        @expected_value = expected_value
        @error_msg = error_msg
      end

      def valid?(value)
        value == @expected_value
      end

      def error_message
        @error_msg
      end
    end
  end

  let(:validator) { test_validator_class.new }

  describe 'インターフェース要求' do
    context '基底クラスを直接インスタンス化した場合' do
      let(:base_validator) { described_class.new }

      it 'valid?メソッドでNotImplementedErrorが発生すること' do
        expect { base_validator.valid?("test") }.to raise_error(NotImplementedError, /valid\? must be implemented/)
      end

      it 'error_messageメソッドでNotImplementedErrorが発生すること' do
        expect { base_validator.error_message }.to raise_error(NotImplementedError, /error_message must be implemented/)
      end
    end
  end

  describe 'ユーティリティメソッド' do
    describe '#blank_value?' do
      it 'nilの場合にtrueを返すこと' do
        expect(validator.send(:blank_value?, nil)).to be true
      end

      it '空文字の場合にtrueを返すこと' do
        expect(validator.send(:blank_value?, "")).to be true
      end

      it '文字列がある場合にfalseを返すこと' do
        expect(validator.send(:blank_value?, "test")).to be false
      end

      it 'スペースのみの文字列の場合にfalseを返すこと' do
        expect(validator.send(:blank_value?, "   ")).to be false
      end
    end

    describe '#numeric_value?' do
      it '整数文字列の場合にtrueを返すこと' do
        expect(validator.send(:numeric_value?, "123")).to be true
      end

      it '小数文字列の場合にtrueを返すこと' do
        expect(validator.send(:numeric_value?, "123.45")).to be true
      end

      it '負数の場合にfalseを返すこと' do
        expect(validator.send(:numeric_value?, "-123")).to be false
      end

      it '文字が含まれる場合にfalseを返すこと' do
        expect(validator.send(:numeric_value?, "123abc")).to be false
      end

      it '空文字の場合にfalseを返すこと' do
        expect(validator.send(:numeric_value?, "")).to be false
      end
    end

    describe '#validate_options!' do
      it '必須キーがすべて存在する場合に例外が発生しないこと' do
        options = { key1: "value1", key2: "value2" }
        required_keys = [ :key1, :key2 ]

        expect { validator.send(:validate_options!, options, required_keys) }.not_to raise_error
      end

      it '必須キーが不足している場合にArgumentErrorが発生すること' do
        options = { key1: "value1" }
        required_keys = [ :key1, :key2, :key3 ]

        expect { validator.send(:validate_options!, options, required_keys) }
          .to raise_error(ArgumentError, /Missing required options: key2, key3/)
      end

      it '空のオプションで必須キーがある場合にArgumentErrorが発生すること' do
        options = {}
        required_keys = [ :key1 ]

        expect { validator.send(:validate_options!, options, required_keys) }
          .to raise_error(ArgumentError, /Missing required options: key1/)
      end
    end
  end

  describe '#inspect' do
    it 'クラス名とオブジェクトIDを含む文字列を返すこと' do
      result = validator.inspect
      expect(result).to match(/^#<.*:0x[0-9a-f]+>$/)
      # 動的クラスの場合はAnonymousClassが使用される
      expected_class_name = validator.class.name || "AnonymousClass"
      expect(result).to include(expected_class_name)
    end
  end

  describe 'ログ機能' do
    let(:logger) { instance_double(Logger) }

    before do
      allow(Rails).to receive(:logger).and_return(logger)
    end

    it 'バリデーション結果をログ出力すること' do
      expect(logger).to receive(:debug).with(/value=.*valid=/)

      # private メソッドなので、テスト用のパブリックラッパーを作成
      test_class = Class.new(test_validator_class) do
        def test_log_validation_result(value, result)
          log_validation_result(value, result)
        end
      end

      test_validator = test_class.new
      test_validator.test_log_validation_result("test_value", true)
    end
  end

  describe '具象クラスでの動作' do
    let(:custom_validator) { test_validator_class.new("expected", "Custom error message") }

    it '正しい値でvalid?がtrueを返すこと' do
      expect(custom_validator.valid?("expected")).to be true
    end

    it '間違った値でvalid?がfalseを返すこと' do
      expect(custom_validator.valid?("wrong")).to be false
    end

    it 'error_messageが設定されたメッセージを返すこと' do
      expect(custom_validator.error_message).to eq("Custom error message")
    end
  end

  describe '継承クラスの実装要求' do
    context '不完全な実装の場合' do
      let(:incomplete_class) do
        Class.new(described_class) do
          def valid?(value)
            true
          end
          # error_messageメソッドを実装しない
        end
      end

      it 'error_messageでNotImplementedErrorが発生すること' do
        validator = incomplete_class.new
        expect { validator.error_message }.to raise_error(NotImplementedError)
      end
    end
  end
end
