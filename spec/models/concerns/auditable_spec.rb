# frozen_string_literal: true

require 'rails_helper'

# Auditable Concernの包括的テスト
# ============================================
# CLAUDE.md準拠: 監査ログ機能の完全テスト実装
# メタ認知: コールバック動作・監査ログ生成・パフォーマンスを検証
# ============================================
RSpec.describe Auditable do
  # テスト用のモデルクラスを定義
  let(:test_class) do
    Class.new(ApplicationRecord) do
      self.table_name = 'inventories'
      include Auditable

      # 監査オプションの設定
      auditable except: [ :updated_at, :created_at ],
                sensitive: [ :price ],
                if: -> { name != 'Skip Audit' }
    end
  end

  let(:test_model) { test_class.new(name: 'Test Item', price: 100, quantity: 50) }
  let(:admin) { create(:admin) }

  before do
    Current.admin = admin
  end

  after do
    Current.reset
  end

  describe '基本的な監査ログ機能' do
    describe '#log_create_action' do
      it '作成時に監査ログを記録する' do
        expect {
          test_model.save!
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('create')
        expect(audit_log.auditable).to eq(test_model)
        expect(audit_log.user_id).to eq(admin.id)
        expect(audit_log.user_type).to eq('Admin')
        expect(audit_log.message).to include('作成しました')
      end

      it '機密フィールドをマスキングする' do
        test_model.save!

        audit_log = AuditLog.last
        details = JSON.parse(audit_log.details)
        expect(details['attributes']['price']).to eq('[FILTERED]')
        expect(details['attributes']['name']).to eq('Test Item')
      end

      it '条件に応じて監査をスキップする' do
        test_model.name = 'Skip Audit'

        expect {
          test_model.save!
        }.not_to change(AuditLog, :count)
      end
    end

    describe '#log_update_action' do
      before { test_model.save! }

      it '更新時に監査ログを記録する' do
        expect {
          test_model.update!(quantity: 100)
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('update')
        expect(audit_log.message).to include('更新しました')
        expect(audit_log.message).to include('quantity')
      end

      it '変更内容を記録する' do
        test_model.update!(quantity: 100, price: 200)

        audit_log = AuditLog.last
        details = JSON.parse(audit_log.details)
        expect(details['changes']['quantity']).to eq([ 50, 100 ])
        expect(details['changes']['price']).to eq([ '[FILTERED]', '[FILTERED]' ])
      end

      it 'updated_atのみの変更は監査対象外' do
        expect {
          test_model.touch
        }.not_to change(AuditLog, :count)
      end
    end

    describe '#log_destroy_action' do
      before { test_model.save! }

      it '削除時に監査ログを記録する' do
        expect {
          test_model.destroy!
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('delete')
        expect(audit_log.message).to include('削除しました')
      end

      it '削除前の属性を保存する' do
        test_model.destroy!

        audit_log = AuditLog.last
        details = JSON.parse(audit_log.details)
        expect(details['attributes']['name']).to eq('Test Item')
        expect(details['attributes']['quantity']).to eq(50)
      end
    end
  end

  describe 'クラスメソッド' do
    describe '.auditable' do
      it 'オプションを設定できる' do
        expect(test_class.audit_options[:except]).to include(:updated_at, :created_at)
        expect(test_class.audit_options[:sensitive]).to include(:price)
      end
    end

    describe '.without_auditing' do
      it '一時的に監査を無効化できる' do
        expect {
          test_class.without_auditing do
            test_model.save!
            test_model.update!(quantity: 200)
            test_model.destroy!
          end
        }.not_to change(AuditLog, :count)
      end

      it 'ブロック実行後に監査を再有効化する' do
        test_class.without_auditing do
          test_model.save!
        end

        expect {
          test_class.create!(name: 'New Item', price: 150, quantity: 30)
        }.to change(AuditLog, :count).by(1)
      end
    end

    describe '.audit_trail' do
      before do
        3.times do |i|
          model = test_class.create!(name: "Item #{i}", price: 100 + i * 10, quantity: 50)
          model.update!(quantity: 60)
          model.destroy!
        end
      end

      it '監査ログの履歴を取得できる' do
        trail = test_class.audit_trail
        expect(trail.count).to eq(9) # 3 creates + 3 updates + 3 deletes
      end

      it 'アクションでフィルタリングできる' do
        trail = test_class.audit_trail(action: 'create')
        expect(trail.count).to eq(3)
        expect(trail.pluck(:action).uniq).to eq([ 'create' ])
      end

      it '期間でフィルタリングできる' do
        start_date = 1.hour.ago
        end_date = Time.current

        trail = test_class.audit_trail(start_date: start_date, end_date: end_date)
        expect(trail.where(created_at: start_date..end_date).count).to eq(trail.count)
      end
    end

    describe '.audit_summary' do
      before do
        5.times { test_class.create!(name: 'Item', price: 100, quantity: 50) }
        3.times { test_class.first.update!(quantity: rand(100)) }
        test_class.last.destroy!
      end

      it '監査サマリーを取得できる' do
        summary = test_class.audit_summary

        expect(summary[:total_count]).to be > 0
        expect(summary[:action_counts]).to include('create', 'update', 'delete')
        expect(summary[:recent_activity_trend]).to have_key(:current_week_count)
        expect(summary[:latest]).to respond_to(:each)
      end
    end
  end

  describe 'インスタンスメソッド' do
    before { test_model.save! }

    describe '#audit_log' do
      it '手動で監査ログを記録できる' do
        expect {
          test_model.audit_log('custom_action', 'カスタムアクションを実行しました', extra_data: 'test')
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('custom_action')
        expect(audit_log.message).to eq('カスタムアクションを実行しました')
        expect(JSON.parse(audit_log.details)['extra_data']).to eq('test')
      end
    end

    describe '#audit_view' do
      it '参照ログを記録できる' do
        viewer = create(:admin)

        expect {
          test_model.audit_view(viewer)
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('view')
        expect(JSON.parse(audit_log.details)['viewer_id']).to eq(viewer.id)
      end
    end

    describe '#audit_export' do
      it 'エクスポートログを記録できる' do
        expect {
          test_model.audit_export('csv', file_size: '1MB')
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('export')
        expect(JSON.parse(audit_log.details)['export_format']).to eq('csv')
      end
    end

    describe '#audit_security_event' do
      it 'セキュリティイベントを記録できる' do
        expect {
          test_model.audit_security_event(
            'unauthorized_access',
            '不正なアクセスを検出しました',
            ip_address: '192.168.1.1',
            severity: 'high'
          )
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        details = JSON.parse(audit_log.details)
        expect(details['security_event']).to be true
        expect(details['severity']).to eq('high')
        expect(details['ip_address']).to eq('192.168.1.1')
      end
    end
  end

  describe 'パフォーマンステスト' do
    it '監査ログ記録のオーバーヘッドが許容範囲内' do
      # 監査なしの実行時間
      time_without_audit = Benchmark.realtime do
        test_class.without_auditing do
          100.times { test_class.create!(name: 'Perf Test', price: 100, quantity: 50) }
        end
      end

      # 監査ありの実行時間
      time_with_audit = Benchmark.realtime do
        100.times { test_class.create!(name: 'Perf Test', price: 100, quantity: 50) }
      end

      # オーバーヘッドが50%以下であることを確認
      overhead_ratio = (time_with_audit - time_without_audit) / time_without_audit
      expect(overhead_ratio).to be < 0.5
    end
  end

  describe 'エラーハンドリング' do
    it '監査ログ記録に失敗しても主処理は継続する' do
      # AuditLogの保存をモックして失敗させる
      allow(AuditLog).to receive(:create!).and_raise(StandardError, 'DB Error')

      # エラーが発生してもモデルの保存は成功する
      expect {
        test_model.save!
      }.not_to raise_error

      expect(test_model).to be_persisted
    end

    it 'エラーログを出力する' do
      allow(AuditLog).to receive(:create!).and_raise(StandardError, 'DB Error')

      expect(Rails.logger).to receive(:error).with(/監査ログ記録エラー/)

      test_model.save!
    end
  end

  describe '機密情報のマスキング' do
    let(:sensitive_model) do
      Class.new(ApplicationRecord) do
        self.table_name = 'inventories'
        include Auditable

        auditable sensitive: [ :credit_card_number, :ssn, :my_number ]

        attr_accessor :credit_card_number, :ssn, :my_number, :email, :phone
      end
    end

    it 'クレジットカード番号をマスキングする' do
      model = sensitive_model.new(
        name: 'Test',
        credit_card_number: '4111-1111-1111-1111',
        price: 100,
        quantity: 50
      )
      model.save!

      audit_log = AuditLog.last
      details = JSON.parse(audit_log.details)
      expect(details['attributes']['credit_card_number']).to eq('[FILTERED]')
    end

    it 'パターンマッチングで機密情報を検出してマスキングする' do
      model = sensitive_model.new(
        name: 'Test with card 4111-1111-1111-1111 and SSN 123-45-6789',
        price: 100,
        quantity: 50
      )

      # secret_dataフィールドでのマスキングテスト
      model.instance_eval do
        def attributes
          super.merge('secret_data' => 'Card: 4111-1111-1111-1111, SSN: 123-45-6789')
        end
      end

      model.save!

      audit_log = AuditLog.last
      details = JSON.parse(audit_log.details)

      # secret_dataフィールドの内容がマスキングされていることを確認
      expect(details['attributes']['secret_data']).to include('[CARD_NUMBER]')
      expect(details['attributes']['secret_data']).to include('[SSN]')
    end
  end

  describe '関連レコードの削除制限' do
    before { test_model.save! }

    it '監査ログが存在する場合、レコードを削除できない' do
      # 監査ログが作成されている
      expect(test_model.audit_logs.count).to be > 0

      # restrict_with_errorにより削除が制限される
      expect {
        test_model.destroy
      }.not_to change { test_class.count }

      expect(test_model.errors[:base]).to include(/関連するレコードが存在/)
    end
  end
end
