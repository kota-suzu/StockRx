# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditLogCriticalError do
  let(:error_message) { 'Test audit log error' }
  let(:action) { 'delete' }
  let(:context) { { user_id: 1, ip_address: '127.0.0.1' } }

  describe '#initialize' do
    it 'メッセージが正しく設定される' do
      error = described_class.new(error_message)
      expect(error.message).to eq(error_message)
    end

    it 'アクションとコンテキストが正しく設定される' do
      error = described_class.new(error_message, action: action, context: context)
      expect(error.action).to eq(action)
      expect(error.context).to eq(context)
    end

    it 'アクションとコンテキストは省略可能' do
      error = described_class.new(error_message)
      expect(error.action).to be_nil
      expect(error.context).to eq({})
    end
  end

  describe '#to_h' do
    let(:error) { described_class.new(error_message, action: action, context: context) }

    it '構造化されたエラー情報を返す' do
      result = error.to_h

      expect(result[:error_class]).to eq('AuditLogCriticalError')
      expect(result[:message]).to eq(error_message)
      expect(result[:action]).to eq(action)
      expect(result[:context]).to eq(context)
      expect(result[:severity]).to eq('critical')
      expect(result[:timestamp]).to be_present
    end

    it 'タイムスタンプがISO8601形式である' do
      result = error.to_h
      expect { Time.iso8601(result[:timestamp]) }.not_to raise_error
    end
  end

  describe '#to_json' do
    let(:error) { described_class.new(error_message, action: action, context: context) }

    it 'JSON形式で出力される' do
      json_result = error.to_json
      parsed = JSON.parse(json_result)

      expect(parsed['error_class']).to eq('AuditLogCriticalError')
      expect(parsed['message']).to eq(error_message)
      expect(parsed['action']).to eq(action)
      expect(parsed['context']).to eq(context.stringify_keys)
      expect(parsed['severity']).to eq('critical')
    end
  end

  describe 'StandardErrorの継承' do
    it 'StandardErrorを継承している' do
      expect(described_class.ancestors).to include(StandardError)
    end

    it '例外として発生させることができる' do
      expect {
        raise described_class.new(error_message)
      }.to raise_error(described_class, error_message)
    end
  end
end