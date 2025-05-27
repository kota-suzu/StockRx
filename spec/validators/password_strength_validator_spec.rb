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

  context '強いパスワード' do
    it '有効なパスワードを許可すること' do
      model.password = 'Password123!'
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
  end
end
