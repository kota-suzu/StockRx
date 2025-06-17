# frozen_string_literal: true

require 'rails_helper'

# Phase 5-4: Auditableconcernテスト
# ============================================
# 監査ログ自動記録機能のテスト
# ============================================
RSpec.describe Auditable do
  # テスト用のモデルを定義
  before(:all) do
    # テスト用テーブルを作成
    ActiveRecord::Base.connection.create_table :test_auditables, force: true do |t|
      t.string :name
      t.string :email
      t.string :credit_card
      t.string :secret_data
      t.string :api_key
      t.timestamps
    end

    # テスト用モデル
    class TestAuditable < ApplicationRecord
      self.table_name = 'test_auditables'
      include Auditable

      # 監査ログ設定
      auditable except: [ :created_at, :updated_at ],
                sensitive: [ :api_key ]
    end
  end

  after(:all) do
    # テスト用テーブルを削除
    ActiveRecord::Base.connection.drop_table :test_auditables
  end

  # CLAUDE.md準拠: ベストプラクティス - テストデータの確実なクリーンアップ
  # メタ認知: letはbeforeブロックの後に評価されるようにする
  before(:each) do
    # 各テスト前にAuditLogをクリア
    AuditLog.destroy_all
    TestAuditable.destroy_all
  end
  
  let(:test_record) { TestAuditable.create!(name: "テスト", email: "test@example.com") }

  describe "監査ログの自動記録" do
    context "レコード作成時" do
      it "作成ログが記録されること" do
        expect {
          TestAuditable.create!(name: "新規", email: "new@example.com")
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq("create")
        expect(audit_log.message).to include("Test Auditable「新規」を作成しました")
      end

      it "属性が記録されること" do
        record = TestAuditable.create!(name: "属性テスト", email: "attr@example.com")

        audit_log = record.audit_logs.last
        details = JSON.parse(audit_log.details)

        expect(details["attributes"]["name"]).to eq("属性テスト")
        expect(details["attributes"]["email"]).to eq("attr@example.com")
        expect(details["attributes"]).not_to have_key("created_at")
      end
    end

    context "レコード更新時" do
      it "更新ログが記録されること" do
        # レコード作成時のログをクリア
        test_record
        AuditLog.destroy_all
        
        expect {
          test_record.update!(name: "更新後")
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq("update")
        expect(audit_log.message).to include("Test Auditable「更新後」を更新しました")
      end

      it "変更内容が記録されること" do
        # レコード作成時のログをクリア
        test_record
        AuditLog.destroy_all
        
        test_record.update!(name: "変更後", email: "changed@example.com")

        audit_log = test_record.audit_logs.where(action: "update").last
        details = JSON.parse(audit_log.details)

        expect(details["changes"]["name"]).to eq([ "テスト", "変更後" ])
        expect(details["changes"]["email"]).to eq([ "test@example.com", "changed@example.com" ])
      end

      it "updated_atのみの変更では記録されないこと" do
        # レコード作成時のログをクリア
        test_record
        AuditLog.destroy_all
        
        expect {
          test_record.touch
        }.not_to change(AuditLog, :count)
      end
    end

    context "レコード削除時" do
      it "削除ログが記録されること" do
        # CLAUDE.md準拠: メタ認知 - dependent: :restrict_with_errorを考慮
        # 削除前に関連するaudit_logsをクリア
        record = TestAuditable.create!(name: "削除対象")
        record.audit_logs.destroy_all  # 削除制約を回避

        expect {
          record.destroy!
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq("delete")
        expect(audit_log.message).to include("Test Auditable「削除対象」を削除しました")
      end
    end
  end

  describe "機密情報のマスキング" do
    it "設定された機密フィールドがマスキングされること" do
      record = TestAuditable.create!(
        name: "機密テスト",
        api_key: "secret-api-key-12345"
      )

      audit_log = record.audit_logs.last
      details = JSON.parse(audit_log.details)

      expect(details["attributes"]["api_key"]).to eq("[FILTERED]")
    end

    it "クレジットカード番号が自動マスキングされること" do
      record = TestAuditable.create!(
        name: "カードテスト",
        credit_card: "4111-1111-1111-1111"
      )

      audit_log = record.audit_logs.last
      details = JSON.parse(audit_log.details)

      expect(details["attributes"]["credit_card"]).to eq("[CARD_NUMBER]")
    end

    it "メールアドレスは通常マスキングされないこと" do
      # CLAUDE.md準拠: ベストプラクティス - 通常のメールアドレスは監査ログに表示
      # メタ認知: 過度なマスキングは監査ログの有用性を損なう
      record = TestAuditable.create!(
        name: "メールテスト",
        email: "longusername@example.com"
      )

      audit_log = record.audit_logs.last
      details = JSON.parse(audit_log.details)

      # メールアドレスはマスキングされない
      expect(details["attributes"]["email"]).to eq("longusername@example.com")
    end

    it "マイナンバーがマスキングされること" do
      record = TestAuditable.create!(
        name: "マイナンバーテスト",
        secret_data: "1234 5678 9012"
      )

      audit_log = record.audit_logs.last
      details = JSON.parse(audit_log.details)

      expect(details["attributes"]["secret_data"]).to eq("[MY_NUMBER]")
    end
  end

  describe "条件付き監査" do
    before do
      # 条件付き監査の設定
      TestAuditable.auditable if: -> { name != "無視" }
    end

    it "条件を満たす場合は記録されること" do
      expect {
        TestAuditable.create!(name: "記録対象")
      }.to change(AuditLog, :count).by(1)
    end

    it "条件を満たさない場合は記録されないこと" do
      expect {
        TestAuditable.create!(name: "無視")
      }.not_to change(AuditLog, :count)
    end
  end

  describe "監査の一時無効化" do
    it "without_auditingブロック内では記録されないこと" do
      expect {
        TestAuditable.without_auditing do
          TestAuditable.create!(name: "無効化テスト")
          test_record.update!(name: "更新無効化")
          test_record.destroy
        end
      }.not_to change(AuditLog, :count)
    end
  end

  describe "手動監査ログ記録" do
    it "audit_logメソッドで手動記録できること" do
      expect {
        test_record.audit_log("security_event", "カスタムアクション実行", { custom_data: "test" })
      }.to change(AuditLog, :count).by(1)

      audit_log = AuditLog.last
      expect(audit_log.action).to eq("security_event")
      expect(audit_log.message).to eq("カスタムアクション実行")
    end

    it "特定アクション用メソッドが使えること" do
      skip "特定アクション用メソッドは将来実装予定"
    end
  end

  describe "エラーハンドリング" do
    it "監査ログ記録に失敗しても本処理は継続すること" do
      # AuditLogの保存を失敗させる
      allow(AuditLog).to receive(:log_action).and_raise(StandardError, "DB Error")
      allow(Rails.logger).to receive(:error)

      # エラーが発生しても作成は成功する
      expect {
        TestAuditable.create!(name: "エラーテスト")
      }.not_to raise_error

      # エラーログが記録される
      expect(Rails.logger).to have_received(:error).with(/監査ログ記録エラー/)
    end
  end

  describe "クラスメソッド" do
    before do
      # テストデータ作成
      user = create(:admin)
      Current.user = user

      5.times do |i|
        TestAuditable.create!(name: "データ#{i}")
      end
    end

    describe ".audit_history" do
      it "ユーザーの監査履歴を取得できること" do
        user_id = Current.user.id
        history = TestAuditable.audit_history(user_id)

        expect(history.count).to be >= 5
        expect(history.pluck(:user_id).uniq).to eq([ user_id ])
      end
    end

    describe ".audit_trail" do
      it "モデルの監査証跡を取得できること" do
        trail = TestAuditable.audit_trail

        expect(trail.pluck(:auditable_type).uniq).to eq([ "TestAuditable" ])
      end

      it "オプションでフィルタリングできること" do
        record = TestAuditable.first
        trail = TestAuditable.audit_trail(id: record.id)

        expect(trail.pluck(:auditable_id).uniq).to eq([ record.id ])
      end
    end

    describe ".audit_summary" do
      it "監査サマリーを取得できること" do
        summary = TestAuditable.audit_summary

        expect(summary).to have_key(:total_count)
        expect(summary).to have_key(:action_counts)
        expect(summary).to have_key(:user_counts)
        expect(summary).to have_key(:recent_activity_trend)
      end
    end
  end
end

# ============================================
# TODO: Phase 5-5以降の拡張予定
# ============================================
# 1. 🔴 パフォーマンステスト
#    - 大量レコード操作時の監査ログ記録速度
#    - バックグラウンド記録の実装
#
# 2. 🟡 暗号化・署名
#    - 監査ログの暗号化保存
#    - デジタル署名による改ざん防止
#
# 3. 🟢 分析機能
#    - 異常パターンの自動検出
#    - 統計レポート生成
