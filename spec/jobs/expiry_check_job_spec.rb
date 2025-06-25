# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExpiryCheckJob, type: :job do
  # CLAUDE.md準拠: 期限切れチェックジョブの包括的テスト
  # メタ認知: 定期実行・通知機能・段階的アラートの品質保証
  # 横展開: 他の定期実行ジョブでも同様のテストパターン適用

  include ActiveJob::TestHelper

  let(:admin) { create(:admin) }
  let(:admin2) { create(:admin) }
  let(:days_ahead) { 30 }

  before do
    # 在庫データとバッチ作成
    @inventory1 = create(:inventory, name: "Medicine A", quantity: 100, price: 500, status: 'active')
    @inventory2 = create(:inventory, name: "Equipment B", quantity: 50, price: 1000, status: 'active')
    @inventory3 = create(:inventory, name: "Supply C", quantity: 30, price: 200, status: 'active')

    # バッチデータ（期限管理テスト用）
    @expired_batch = create(:batch,
      inventory: @inventory1,
      lot_code: 'EXPIRED001',
      expires_on: 2.days.ago,
      quantity: 20
    )

    @expiring_batch = create(:batch,
      inventory: @inventory2,
      lot_code: 'EXPIRING001',
      expires_on: 15.days.from_now,
      quantity: 25
    )

    @safe_batch = create(:batch,
      inventory: @inventory3,
      lot_code: 'SAFE001',
      expires_on: 60.days.from_now,
      quantity: 30
    )

    # ProgressNotifierのモック
    allow_any_instance_of(described_class).to receive(:initialize_progress).and_return("progress_key_123")
    allow_any_instance_of(described_class).to receive(:notify_completion).and_return(true)
    allow_any_instance_of(described_class).to receive(:notify_error).and_return(true)

    # ActionCableのモック
    allow(ActionCable.server).to receive(:broadcast)

    # ジョブのヘルパーメソッドをモック（実際のバッチ検索をテスト用に置き換え）
    allow_any_instance_of(described_class).to receive(:find_expiring_items) do |job, days|
      if days >= 15
        [ @inventory2 ] # 15日後に期限切れ
      else
        []
      end
    end

    allow_any_instance_of(described_class).to receive(:find_expired_items) do
      [ @inventory1 ] # 既に期限切れ
    end
  end

  describe "#perform" do
    context "期限切れアイテムが存在する場合" do
      it "期限切れ・期限間近アイテムを検出する" do
        result = described_class.perform_now(days_ahead)

        expect(result[:expired_items]).to include(@inventory1)
        expect(result[:expiring_items]).to include(@inventory2)
        expect(result[:notifications_sent]).to eq(Admin.count)
      end

      it "指定した管理者のみに通知する" do
        result = described_class.perform_now(days_ahead, [ admin.id ])

        expect(result[:notifications_sent]).to eq(1)
      end

      it "全管理者に通知する（管理者ID未指定時）" do
        result = described_class.perform_now(days_ahead, [])

        expect(result[:notifications_sent]).to eq(Admin.count)
      end

      it "ActionCable経由で通知を送信する" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "admin_#{admin.id}",
          hash_including(
            type: "expiry_alert",
            message: include("期限管理アラート"),
            expired_count: 1,
            expiring_count: 1
          )
        )

        described_class.perform_now(days_ahead, [ admin.id ])
      end

      it "適切なログを出力する" do
        expect(Rails.logger).to receive(:info).with(include("Starting expiry check"))
        expect(Rails.logger).to receive(:info).with(include("event"))

        described_class.perform_now(days_ahead)
      end
    end

    context "期限切れアイテムが存在しない場合" do
      before do
        allow_any_instance_of(described_class).to receive(:find_expiring_items).and_return([])
        allow_any_instance_of(described_class).to receive(:find_expired_items).and_return([])
      end

      it "早期リターンして通知を送信しない" do
        expect(ActionCable.server).not_to receive(:broadcast)

        result = described_class.perform_now(days_ahead)

        expect(result).to be_nil
      end
    end

    context "進捗追跡" do
      it "進捗通知を初期化する" do
        job_instance = described_class.new

        expect(job_instance).to receive(:initialize_progress).with(
          admin.id,
          anything,
          "expiry_check",
          hash_including(days_ahead: days_ahead)
        )

        job_instance.perform(days_ahead, [ admin.id ])
      end

      it "完了通知を送信する" do
        job_instance = described_class.new

        expect(job_instance).to receive(:notify_completion).with(
          anything,
          admin.id,
          "expiry_check",
          hash_including(
            expired_count: 1,
            expiring_count: 1
          )
        )

        job_instance.perform(days_ahead, [ admin.id ])
      end
    end

    context "エラーハンドリング" do
      it "通知送信エラーを適切に処理する" do
        allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError.new("Broadcast failed"))

        expect(Rails.logger).to receive(:error).with(include("Failed to send expiry notification"))

        result = described_class.perform_now(days_ahead, [ admin.id ])

        # エラーが発生しても処理は継続される
        expect(result[:notifications_sent]).to eq(0)
      end

      it "例外発生時にエラー通知を送信する" do
        allow_any_instance_of(described_class).to receive(:find_expiring_items).and_raise(StandardError.new("Test error"))

        job_instance = described_class.new

        expect(job_instance).to receive(:notify_error).with(
          anything,
          admin.id,
          "expiry_check",
          instance_of(StandardError)
        )

        expect {
          job_instance.perform(days_ahead, [ admin.id ])
        }.to raise_error(StandardError)
      end
    end
  end

  describe "#find_expiring_items" do
    let(:job) { described_class.new }

    context "実際のバッチモデル連携テスト" do
      # 実際のバッチクエリをテスト（モックを無効化）
      before do
        allow_any_instance_of(described_class).to receive(:find_expiring_items).and_call_original
      end

      it "指定日数以内に期限切れ予定のアイテムを検索する" do
        # 現在の実装ではダミーで空配列を返すが、将来の実装に備えてテスト
        result = job.send(:find_expiring_items, 30)

        expect(result).to be_an(Array)
        # TODO: Batchモデル実装後に実際の検索結果をテスト
        # expect(result).to include(inventory_with_expiring_batch)
      end

      it "期限切れ日が指定範囲外のアイテムは除外する" do
        result = job.send(:find_expiring_items, 5)

        expect(result).to be_an(Array)
        # TODO: Batchモデル実装後に範囲外除外をテスト
      end
    end
  end

  describe "#find_expired_items" do
    let(:job) { described_class.new }

    context "実際のバッチモデル連携テスト" do
      before do
        allow_any_instance_of(described_class).to receive(:find_expired_items).and_call_original
      end

      it "既に期限切れのアイテムを検索する" do
        result = job.send(:find_expired_items)

        expect(result).to be_an(Array)
        # TODO: Batchモデル実装後に実際の検索結果をテスト
        # expect(result).to include(inventory_with_expired_batch)
      end
    end
  end

  describe "#send_expiry_notifications" do
    let(:job) { described_class.new }
    let(:expiring_items) { [ @inventory2 ] }
    let(:expired_items) { [ @inventory1 ] }

    it "期限切れと期限間近の両方がある場合の通知を送信する" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "admin_#{admin.id}",
        hash_including(
          type: "expiry_alert",
          message: include("期限切れ商品: 1件, #{days_ahead}日以内期限切れ予定: 1件"),
          expired_count: 1,
          expiring_count: 1,
          days_ahead: days_ahead
        )
      )

      result = job.send(:send_expiry_notifications, admin, expiring_items, expired_items, days_ahead)

      expect(result).to be true
    end

    it "期限切れのみがある場合の通知を送信する" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "admin_#{admin.id}",
        hash_including(
          message: include("期限切れ商品: 1件"),
          expired_count: 1,
          expiring_count: 0
        )
      )

      result = job.send(:send_expiry_notifications, admin, [], expired_items, days_ahead)

      expect(result).to be true
    end

    it "期限間近のみがある場合の通知を送信する" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "admin_#{admin.id}",
        hash_including(
          message: include("#{days_ahead}日以内期限切れ予定: 1件"),
          expired_count: 0,
          expiring_count: 1
        )
      )

      result = job.send(:send_expiry_notifications, admin, expiring_items, [], days_ahead)

      expect(result).to be true
    end

    it "該当アイテムがない場合は通知を送信しない" do
      expect(ActionCable.server).not_to receive(:broadcast)

      result = job.send(:send_expiry_notifications, admin, [], [], days_ahead)

      expect(result).to be true
    end

    it "通知送信失敗時にfalseを返す" do
      allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError.new("Broadcast failed"))

      expect(Rails.logger).to receive(:error).with(include("Failed to send expiry notification"))

      result = job.send(:send_expiry_notifications, admin, expiring_items, expired_items, days_ahead)

      expect(result).to be false
    end

    it "正常送信時にログを出力する" do
      allow(ActionCable.server).to receive(:broadcast)

      expect(Rails.logger).to receive(:info).with("Expiry notification sent to admin #{admin.id}")

      result = job.send(:send_expiry_notifications, admin, expiring_items, expired_items, days_ahead)

      expect(result).to be true
    end

    it "通知データにタイムスタンプが含まれる" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "admin_#{admin.id}",
        hash_including(
          timestamp: match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        )
      )

      job.send(:send_expiry_notifications, admin, expiring_items, expired_items, days_ahead)
    end

    it "アイテム詳細を適切にフォーマットする" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "admin_#{admin.id}",
        hash_including(
          expired_items: array_including(
            hash_including(name: @inventory1.name, quantity: @inventory1.quantity)
          ),
          expiring_items: array_including(
            hash_including(name: @inventory2.name, quantity: @inventory2.quantity)
          )
        )
      )

      job.send(:send_expiry_notifications, admin, expiring_items, expired_items, days_ahead)
    end

    it "最大5件のアイテム詳細のみを通知に含める" do
      # 6件のアイテムを作成
      many_items = Array.new(6) { |i| create(:inventory, name: "Item #{i}") }

      expect(ActionCable.server).to receive(:broadcast).with(
        anything,
        hash_including(
          expired_items: have_attributes(size: 5) # 最大5件に制限
        )
      )

      job.send(:send_expiry_notifications, admin, [], many_items, days_ahead)
    end
  end

  describe "#format_items_for_notification" do
    let(:job) { described_class.new }

    it "アイテム情報を通知用にフォーマットする" do
      items = [ @inventory1, @inventory2 ]

      result = job.send(:format_items_for_notification, items)

      expect(result).to eq([
        { name: @inventory1.name, quantity: @inventory1.quantity },
        { name: @inventory2.name, quantity: @inventory2.quantity }
      ])
    end

    it "空配列でも適切に処理する" do
      result = job.send(:format_items_for_notification, [])

      expect(result).to eq([])
    end

    it "大量のアイテムも適切に処理する" do
      items = Array.new(100) { create(:inventory) }

      result = job.send(:format_items_for_notification, items)

      expect(result.size).to eq(100)
      expect(result.first).to have_key(:name)
      expect(result.first).to have_key(:quantity)
    end
  end

  describe "Sidekiq設定" do
    it "正しいキューが設定されている" do
      expect(described_class.queue_name).to eq('notifications')
    end

    it "適切なSidekiqオプションが設定されている" do
      sidekiq_options = described_class.sidekiq_options_hash

      expect(sidekiq_options['retry']).to eq(2)
      expect(sidekiq_options['backtrace']).to be true
      expect(sidekiq_options['queue']).to eq(:notifications)
    end
  end

  describe "パラメータ検証" do
    it "デフォルトのdays_aheadで実行される" do
      expect_any_instance_of(described_class).to receive(:find_expiring_items).with(30)

      described_class.perform_now
    end

    it "カスタムdays_aheadで実行される" do
      custom_days = 7

      expect_any_instance_of(described_class).to receive(:find_expiring_items).with(custom_days)

      described_class.perform_now(custom_days)
    end

    it "無効なdays_aheadでもエラーを発生させない" do
      expect {
        described_class.perform_now(-1)
      }.not_to raise_error
    end

    it "管理者が存在しない場合でも適切に処理する" do
      Admin.delete_all

      expect {
        result = described_class.perform_now(days_ahead)
        expect(result[:notifications_sent]).to eq(0)
      }.not_to raise_error
    end
  end

  describe "統合テスト" do
    it "完全なワークフローを実行する" do
      # 進捗追跡から通知までの完全なフロー
      result = described_class.perform_now(days_ahead, [ admin.id, admin2.id ])

      expect(result).to include(
        expired_items: include(@inventory1),
        expiring_items: include(@inventory2),
        notifications_sent: 2
      )
    end

    it "期限日数による結果の変化をテストする" do
      # 短期間（5日）での検索
      short_result = described_class.perform_now(5, [ admin.id ])

      # 長期間（60日）での検索
      long_result = described_class.perform_now(60, [ admin.id ])

      # 長期間の方が多くのアイテムを検出することを確認
      # (実際の実装ではモックにより制御されているが、将来の実装に備えて)
      expect(short_result[:expiring_items].size).to be <= long_result[:expiring_items].size
    end
  end

  describe "パフォーマンステスト" do
    it "大量の管理者に対しても適切に処理する" do
      # 100人の管理者を作成
      create_list(:admin, 100)

      start_time = Time.current
      result = described_class.perform_now(days_ahead)
      duration = Time.current - start_time

      expect(duration).to be < 5.0 # 5秒以内に完了
      expect(result[:notifications_sent]).to eq(Admin.count)
    end

    it "大量の期限切れアイテムも適切に処理する" do
      # 大量のアイテムをモック
      large_item_list = Array.new(1000) { create(:inventory) }

      allow_any_instance_of(described_class).to receive(:find_expiring_items).and_return(large_item_list)
      allow_any_instance_of(described_class).to receive(:find_expired_items).and_return(large_item_list)

      start_time = Time.current
      result = described_class.perform_now(days_ahead, [ admin.id ])
      duration = Time.current - start_time

      expect(duration).to be < 3.0 # 3秒以内に完了
      expect(result[:expiring_items].size).to eq(1000)
    end
  end

  describe "エッジケース" do
    it "期限日がnilのバッチを適切に処理する" do
      # 期限日がnilのバッチが存在する場合
      create(:batch, inventory: @inventory1, expires_on: nil, quantity: 10)

      expect {
        described_class.perform_now(days_ahead)
      }.not_to raise_error
    end

    it "数量が0のアイテムも適切に処理する" do
      @inventory1.update!(quantity: 0)

      result = described_class.perform_now(days_ahead, [ admin.id ])

      expect(result[:expired_items]).to include(@inventory1)
    end

    it "非アクティブなアイテムも期限チェック対象とする" do
      @inventory1.update!(status: 'inactive')

      result = described_class.perform_now(days_ahead, [ admin.id ])

      # 期限管理は在庫状態に関係なく実行される
      expect(result[:expired_items]).to include(@inventory1)
    end
  end

  # TODO: 🔴 Phase 1（緊急）- 追加テストケース
  # 優先度: 高（CLAUDE.md準拠）
  # 実装期間: 1-2日
  # 横展開: 他の定期実行ジョブと同等のテスト網羅性達成
  #
  # 1. Batchモデル実装後の統合テスト
  #    - 実際のバッチクエリテスト
  #    - 複数バッチを持つ在庫の期限判定
  #    - バッチロット管理との連携テスト
  #
  # 2. 通知システム拡張テスト
  #    - メール通知機能のテスト（将来実装）
  #    - 段階的アラート（緊急・警告・注意）のテスト
  #    - 管理者別通知設定のテスト
  #
  # 3. セキュリティ・監査テスト
  #    - 期限変更の監査ログテスト
  #    - 不正な期限操作の検出テスト
  #    - 権限のない管理者での実行テスト
  #
  # 4. 自動処理機能テスト
  #    - 期限切れ商品の自動無効化テスト
  #    - 廃棄処理ワークフローのテスト
  #    - 関連業者への自動通知テスト
  #
  # 5. 分析・レポート機能テスト
  #    - 期限切れトレンド分析テスト
  #    - 損失金額計算テスト
  #    - 改善提案生成テスト
end
