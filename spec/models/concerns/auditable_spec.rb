# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auditable, type: :model do
  # テスト用のInventoryモデルを使用
  let(:test_model) { build(:inventory) }
  let(:admin) { create(:admin) }

  before do
    allow(Current).to receive(:user).and_return(admin)
    allow(Current).to receive(:ip_address).and_return('127.0.0.1')
    allow(Current).to receive(:user_agent).and_return('Test Agent')
  end

  describe '#create_audit_log' do
    context '正常なケース' do
      it '監査ログが正常に作成される' do
        test_model.save!
        
        # 既存のcreateログをクリア
        AuditLog.delete_all
        
        expect {
          test_model.send(:create_audit_log, 'test_action', 'テストメッセージ')
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('test_action')
        expect(audit_log.message).to eq('テストメッセージ')
        expect(audit_log.user_id).to eq(admin.id)
      end
    end

    context 'データベースエラーが発生した場合' do
      before do
        # audit_logsアソシエーションでエラーを発生させる
        allow(test_model.audit_logs).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuditLog.new))
      end

      it '重要でないアクションではエラーが隠蔽される' do
        test_model.save!
        
        expect {
          test_model.send(:create_audit_log, 'test_action', 'テストメッセージ')
        }.not_to raise_error
      end

      it 'エラーログが出力される' do
        test_model.save!
        
        expect(Rails.logger).to receive(:error).with(a_string_matching(/audit_log_failure/))
        
        expect {
          test_model.send(:create_audit_log, 'test_action', 'テストメッセージ')
        }.not_to raise_error
      end
    end

    context '重要なアクションの場合' do
      it 'delete アクションで例外が再発生される' do
        test_model.save!
        
        allow(test_model.audit_logs).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuditLog.new))
        
        expect {
          test_model.send(:create_audit_log, 'delete', 'テスト削除')
        }.to raise_error(AuditLogCriticalError)
      end

      it 'login アクションで例外が再発生される' do
        test_model.save!
        
        allow(test_model.audit_logs).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuditLog.new))
        
        expect {
          test_model.send(:create_audit_log, 'login', 'テストログイン')
        }.to raise_error(AuditLogCriticalError)
      end
    end

    context '一般的なアクションの場合' do
      it 'view アクションではエラーが隠蔽される' do
        test_model.save!
        
        allow(test_model.audit_logs).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuditLog.new))
        
        expect {
          test_model.send(:create_audit_log, 'view', 'テスト表示')
        }.not_to raise_error
      end

      it 'update アクションではエラーが隠蔽される' do
        test_model.save!
        
        allow(test_model.audit_logs).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuditLog.new))
        
        expect {
          test_model.send(:create_audit_log, 'update', 'テスト更新')
        }.not_to raise_error
      end
    end
  end

  describe '#critical_audit_action?' do
    it 'delete アクションが重要として判定される' do
      expect(test_model.send(:critical_audit_action?, 'delete')).to be true
    end

    it 'login アクションが重要として判定される' do
      expect(test_model.send(:critical_audit_action?, 'login')).to be true
    end

    it 'view アクションが重要でないと判定される' do
      expect(test_model.send(:critical_audit_action?, 'view')).to be false
    end

    it 'update アクションが重要でないと判定される' do
      expect(test_model.send(:critical_audit_action?, 'update')).to be false
    end
  end

  describe '#max_audit_retry_count' do
    it '本番環境では3回リトライする' do
      allow(Rails.env).to receive(:production?).and_return(true)
      expect(test_model.send(:max_audit_retry_count)).to eq(3)
    end

    it 'テスト環境では1回リトライする' do
      allow(Rails.env).to receive(:production?).and_return(false)
      expect(test_model.send(:max_audit_retry_count)).to eq(1)
    end
  end

  describe '#retry_delay' do
    it '指数バックオフで遅延時間が計算される' do
      expect(test_model.send(:retry_delay, 0)).to eq(0.1)
      expect(test_model.send(:retry_delay, 1)).to eq(0.2)
      expect(test_model.send(:retry_delay, 2)).to eq(0.4)
    end

    it '最大遅延時間が2秒に制限される' do
      expect(test_model.send(:retry_delay, 10)).to eq(2.0)
    end
  end

  describe '#audit_failure_context' do
    it '適切なコンテキスト情報が返される' do
      context = test_model.send(:audit_failure_context)
      
      expect(context[:user_id]).to eq(admin.id)
      expect(context[:ip_address]).to eq('127.0.0.1')
      expect(context[:user_agent]).to eq('Test Agent')
    end

    it 'Current が設定されていない場合は nil が返される' do
      allow(Current).to receive(:user).and_return(nil)
      allow(Current).to receive(:ip_address).and_return(nil)
      
      context = test_model.send(:audit_failure_context)
      
      expect(context[:user_id]).to be_nil
      expect(context[:ip_address]).to be_nil
    end
  end

  describe 'リトライメカニズム' do
    let(:saved_model) { test_model.tap(&:save!) }

    context 'データベース接続エラーの場合' do
      it '指定回数リトライしてから例外を発生させる' do
        retry_count = 0
        allow(saved_model.audit_logs).to receive(:create!) do
          retry_count += 1
          raise ActiveRecord::ConnectionNotEstablished.new('DB connection failed')
        end

        expect {
          saved_model.send(:create_audit_log, 'delete', 'テスト削除')
        }.to raise_error(AuditLogCriticalError)

        # リトライ回数 + 初回実行 = 2回実行される（テスト環境）
        expect(retry_count).to eq(2)
      end
    end

    context 'バリデーションエラーの場合' do
      it '指定回数リトライしてから例外を発生させる' do
        retry_count = 0
        allow(saved_model.audit_logs).to receive(:create!) do
          retry_count += 1
          raise ActiveRecord::RecordInvalid.new(AuditLog.new)
        end

        expect {
          saved_model.send(:create_audit_log, 'delete', 'テスト削除')
        }.to raise_error(AuditLogCriticalError)

        expect(retry_count).to eq(2) # 初回 + 1回リトライ
      end
    end
  end

  describe '既存の機能の動作確認' do
    it 'audit_log メソッドが正常に動作する' do
      test_model.save!
      AuditLog.delete_all # 既存ログをクリア
      
      expect {
        test_model.audit_log('view', { key: 'value' })
      }.to change(AuditLog, :count).by(1)

      audit_log = AuditLog.last
      expect(audit_log.action).to eq('view')
      expect(audit_log.details).to eq({ 'key' => 'value' })
    end

    it 'log_create_action が自動的に呼ばれる' do
      expect {
        test_model.save!
      }.to change(AuditLog, :count).by(1)

      audit_log = AuditLog.last
      expect(audit_log.action).to eq('create')
      expect(audit_log.message).to eq('レコードを作成しました')
    end

    it 'log_update_action が自動的に呼ばれる' do
      test_model.save!
      
      expect {
        test_model.update!(name: '更新されたテスト')
      }.to change(AuditLog, :count).by(1)

      audit_log = AuditLog.last
      expect(audit_log.action).to eq('update')
      expect(audit_log.message).to eq('レコードを更新しました')
    end
  end
end