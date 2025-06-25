# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StockAlertJob, type: :job do
  # CLAUDE.md準拠: 在庫アラートジョブの包括的テスト
  # メタ認知: 在庫管理・閾値判定・多重通知機能の品質保証
  # 横展開: 他のアラート系ジョブでも同様のテストパターン適用

  include ActiveJob::TestHelper

  let(:admin) { create(:admin) }
  let(:admin2) { create(:admin) }
  let(:threshold) { 10 }

  before do
    # 在庫データ作成（様々な在庫レベル）
    @high_stock_item = create(:inventory, name: "High Stock Medicine", quantity: 100, price: 500, status: 'active')
    @low_stock_item = create(:inventory, name: "Low Stock Equipment", quantity: 5, price: 1000, status: 'active')
    @out_of_stock_item = create(:inventory, name: "Out of Stock Supply", quantity: 0, price: 200, status: 'active')
    @threshold_item = create(:inventory, name: "Threshold Item", quantity: 10, price: 300, status: 'active')

    # ProgressNotifierのモック
    allow_any_instance_of(described_class).to receive(:initialize_progress).and_return("progress_key_123")
    allow_any_instance_of(described_class).to receive(:notify_completion).and_return(true)
    allow_any_instance_of(described_class).to receive(:notify_error).and_return(true)

    # ActionCableのモック
    allow(ActionCable.server).to receive(:broadcast)

    # AdminMailerのモック
    allow(AdminMailer).to receive_message_chain(:stock_alert, :deliver_now)

    # I18nのモック
    allow(I18n).to receive(:t).with("jobs.stock_alert.message", anything).and_return("在庫アラート")
  end

  describe "#perform" do
    context "在庫不足アイテムが存在する場合" do
      it "低在庫・在庫切れアイテムを検出する" do
        result = described_class.perform_now(threshold)

        expect(result[:low_stock_items]).to include(@low_stock_item, @threshold_item)
        expect(result[:out_of_stock_items]).to include(@out_of_stock_item)
        expect(result[:notifications_sent]).to eq(Admin.count)
        expect(result[:threshold]).to eq(threshold)
      end

      it "指定した管理者のみに通知する" do
        result = described_class.perform_now(threshold, [ admin.id ])

        expect(result[:notifications_sent]).to eq(1)
      end

      it "全管理者に通知する（管理者ID未指定時）" do
        result = described_class.perform_now(threshold, [])

        expect(result[:notifications_sent]).to eq(Admin.count)
      end

      it "ActionCable経由で通知を送信する" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "admin_#{admin.id}",
          hash_including(
            type: "stock_alert",
            message: include("在庫アラート"),
            total_count: 3, # low_stock: 2, out_of_stock: 1
            threshold: threshold
          )
        )

        described_class.perform_now(threshold, [ admin.id ])
      end

      it "適切なログを出力する" do
        expect(Rails.logger).to receive(:info).with(include("Starting stock alert check"))
        expect(Rails.logger).to receive(:info).with(include("stock_alert_completed"))

        described_class.perform_now(threshold)
      end
    end

    context "在庫不足アイテムが存在しない場合" do
      before do
        # 全ての在庫を十分な数量に設定
        Inventory.update_all(quantity: 100)
      end

      it "早期リターンして通知を送信しない" do
        expect(ActionCable.server).not_to receive(:broadcast)

        result = described_class.perform_now(threshold)

        expect(result).to be_nil
      end
    end

    context "メール通知機能" do
      it "メール通知が有効な場合にメールを送信する" do
        expect(AdminMailer).to receive(:stock_alert).and_call_original

        described_class.perform_now(threshold, [ admin.id ], true)
      end

      it "メール通知が無効な場合にメールを送信しない" do
        expect(AdminMailer).not_to receive(:stock_alert)

        described_class.perform_now(threshold, [ admin.id ], false)
      end

      it "メール送信失敗時でも通知は成功とする" do
        allow(AdminMailer).to receive_message_chain(:stock_alert, :deliver_now).and_raise(StandardError.new("Mail failed"))

        expect(Rails.logger).to receive(:warn).with(include("Failed to send email notification"))

        result = described_class.perform_now(threshold, [ admin.id ], true)

        expect(result[:notifications_sent]).to eq(1)
      end
    end

    context "進捗追跡" do
      it "進捗通知を初期化する" do
        job_instance = described_class.new

        expect(job_instance).to receive(:initialize_progress).with(
          admin.id,
          anything,
          "stock_alert",
          hash_including(
            threshold: threshold,
            enable_email: false
          )
        )

        job_instance.perform(threshold, [ admin.id ], false)
      end

      it "完了通知を送信する" do
        job_instance = described_class.new

        expect(job_instance).to receive(:notify_completion).with(
          anything,
          admin.id,
          "stock_alert",
          hash_including(
            low_stock_count: 2,
            out_of_stock_count: 1,
            notifications_sent: 1
          )
        )

        job_instance.perform(threshold, [ admin.id ], false)
      end
    end

    context "エラーハンドリング" do
      it "通知送信エラーを適切に処理する" do
        allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError.new("Broadcast failed"))

        expect(Rails.logger).to receive(:error).with(include("Failed to send stock alert"))

        result = described_class.perform_now(threshold, [ admin.id ])

        # エラーが発生しても処理は継続される
        expect(result[:notifications_sent]).to eq(0)
      end

      it "例外発生時にエラー通知を送信する" do
        allow_any_instance_of(described_class).to receive(:find_low_stock_items).and_raise(StandardError.new("Test error"))

        job_instance = described_class.new

        expect(job_instance).to receive(:notify_error) if job_instance.respond_to?(:notify_error)

        expect {
          job_instance.perform(threshold, [ admin.id ])
        }.to raise_error(StandardError)
      end
    end
  end

  describe "#find_low_stock_items" do
    let(:job) { described_class.new }

    it "指定閾値以下のアイテムを検索する" do
      result = job.send(:find_low_stock_items, 10)

      expect(result).to include(@low_stock_item, @threshold_item)
      expect(result).not_to include(@high_stock_item, @out_of_stock_item)
    end

    it "在庫0のアイテムは除外する" do
      result = job.send(:find_low_stock_items, 10)

      expect(result).not_to include(@out_of_stock_item)
    end

    it "数量で昇順ソートされる" do
      result = job.send(:find_low_stock_items, 10).to_a

      expect(result.first.quantity).to be <= result.last.quantity
    end

    it "異なる閾値で適切にフィルタリングする" do
      result_5 = job.send(:find_low_stock_items, 5)
      result_15 = job.send(:find_low_stock_items, 15)

      expect(result_5.count).to be <= result_15.count
    end
  end

  describe "#find_out_of_stock_items" do
    let(:job) { described_class.new }

    it "在庫0のアイテムのみを検索する" do
      result = job.send(:find_out_of_stock_items)

      expect(result).to include(@out_of_stock_item)
      expect(result).not_to include(@high_stock_item, @low_stock_item, @threshold_item)
    end

    it "名前で昇順ソートされる" do
      # 追加の在庫切れアイテムを作成
      out_of_stock_a = create(:inventory, name: "A Product", quantity: 0)
      out_of_stock_z = create(:inventory, name: "Z Product", quantity: 0)

      result = job.send(:find_out_of_stock_items).to_a

      names = result.map(&:name)
      expect(names).to eq(names.sort)
    end
  end

  describe "#send_stock_alert" do
    let(:job) { described_class.new }
    let(:low_stock_items) { [ @low_stock_item, @threshold_item ] }
    let(:out_of_stock_items) { [ @out_of_stock_item ] }

    it "リアルタイム通知とメール通知を両方送信する" do
      expect(job).to receive(:send_realtime_notification).with(admin, low_stock_items, out_of_stock_items, threshold)
      expect(job).to receive(:send_email_notification).with(admin, low_stock_items, out_of_stock_items, threshold)

      result = job.send(:send_stock_alert, admin, low_stock_items, out_of_stock_items, threshold, true)

      expect(result).to be true
    end

    it "メール無効時はリアルタイム通知のみ送信する" do
      expect(job).to receive(:send_realtime_notification)
      expect(job).not_to receive(:send_email_notification)

      result = job.send(:send_stock_alert, admin, low_stock_items, out_of_stock_items, threshold, false)

      expect(result).to be true
    end

    it "正常送信時にログを出力する" do
      allow(job).to receive(:send_realtime_notification)

      expect(Rails.logger).to receive(:info).with(include("Stock alert sent to admin #{admin.id}"))

      result = job.send(:send_stock_alert, admin, low_stock_items, out_of_stock_items, threshold, false)

      expect(result).to be true
    end

    it "例外発生時にfalseを返す" do
      allow(job).to receive(:send_realtime_notification).and_raise(StandardError.new("Test error"))

      expect(Rails.logger).to receive(:error).with(include("Failed to send stock alert"))

      result = job.send(:send_stock_alert, admin, low_stock_items, out_of_stock_items, threshold, false)

      expect(result).to be false
    end
  end

  describe "#send_realtime_notification" do
    let(:job) { described_class.new }
    let(:low_stock_items) { [ @low_stock_item ] }
    let(:out_of_stock_items) { [ @out_of_stock_item ] }

    it "ActionCable経由で適切な通知データを送信する" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "admin_#{admin.id}",
        hash_including(
          type: "stock_alert",
          message: include("在庫アラート"),
          total_count: 2,
          threshold: threshold,
          timestamp: match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        )
      )

      job.send(:send_realtime_notification, admin, low_stock_items, out_of_stock_items, threshold)
    end

    it "アイテム詳細を適切にフォーマットして含める" do
      expect(ActionCable.server).to receive(:broadcast).with(
        anything,
        hash_including(
          items: array_including(
            hash_including(
              id: @low_stock_item.id,
              name: @low_stock_item.name,
              quantity: @low_stock_item.quantity,
              status: "critical"
            )
          )
        )
      )

      job.send(:send_realtime_notification, admin, low_stock_items, out_of_stock_items, threshold)
    end

    it "最大10件のアイテム詳細のみを通知に含める" do
      many_items = Array.new(15) { create(:inventory, quantity: 5) }

      expect(ActionCable.server).to receive(:broadcast).with(
        anything,
        hash_including(
          items: have_attributes(size: 10) # 5件 + 5件の制限
        )
      )

      job.send(:send_realtime_notification, admin, many_items.first(5), many_items.last(5), threshold)
    end
  end

  describe "#send_email_notification" do
    let(:job) { described_class.new }
    let(:low_stock_items) { [ @low_stock_item ] }
    let(:out_of_stock_items) { [ @out_of_stock_item ] }

    it "AdminMailerを使ってメールを送信する" do
      mailer_double = double('AdminMailer')
      allow(AdminMailer).to receive(:stock_alert).with(admin, low_stock_items, out_of_stock_items, threshold).and_return(mailer_double)
      expect(mailer_double).to receive(:deliver_now)

      job.send(:send_email_notification, admin, low_stock_items, out_of_stock_items, threshold)
    end

    it "メール送信失敗時に警告ログを出力する" do
      allow(AdminMailer).to receive_message_chain(:stock_alert, :deliver_now).and_raise(StandardError.new("Mail error"))

      expect(Rails.logger).to receive(:warn).with(include("Failed to send email notification"))

      job.send(:send_email_notification, admin, low_stock_items, out_of_stock_items, threshold)
    end
  end

  describe "#format_items_for_notification" do
    let(:job) { described_class.new }

    it "アイテム情報を通知用にフォーマットする" do
      items = [ @low_stock_item, @out_of_stock_item ]

      result = job.send(:format_items_for_notification, items)

      expect(result).to contain_exactly(
        {
          id: @low_stock_item.id,
          name: @low_stock_item.name,
          quantity: @low_stock_item.quantity,
          price: @low_stock_item.price,
          status: "critical"
        },
        {
          id: @out_of_stock_item.id,
          name: @out_of_stock_item.name,
          quantity: @out_of_stock_item.quantity,
          price: @out_of_stock_item.price,
          status: "out_of_stock"
        }
      )
    end

    it "空配列でも適切に処理する" do
      result = job.send(:format_items_for_notification, [])

      expect(result).to eq([])
    end
  end

  describe "#determine_stock_status" do
    let(:job) { described_class.new }

    it "数量に応じて適切なステータスを返す" do
      expect(job.send(:determine_stock_status, 0)).to eq("out_of_stock")
      expect(job.send(:determine_stock_status, 3)).to eq("critical")
      expect(job.send(:determine_stock_status, 8)).to eq("low")
      expect(job.send(:determine_stock_status, 15)).to eq("normal")
    end

    it "境界値を適切に処理する" do
      expect(job.send(:determine_stock_status, 1)).to eq("critical")
      expect(job.send(:determine_stock_status, 5)).to eq("critical")
      expect(job.send(:determine_stock_status, 6)).to eq("low")
      expect(job.send(:determine_stock_status, 10)).to eq("low")
      expect(job.send(:determine_stock_status, 11)).to eq("normal")
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
    it "デフォルトの閾値で実行される" do
      result = described_class.perform_now

      expect(result[:threshold]).to eq(10)
    end

    it "カスタム閾値で実行される" do
      custom_threshold = 5

      result = described_class.perform_now(custom_threshold)

      expect(result[:threshold]).to eq(custom_threshold)
    end

    it "無効な閾値でもエラーを発生させない" do
      expect {
        described_class.perform_now(-1)
      }.not_to raise_error
    end

    it "管理者が存在しない場合でも適切に処理する" do
      Admin.delete_all

      expect {
        result = described_class.perform_now(threshold)
        expect(result[:notifications_sent]).to eq(0)
      }.not_to raise_error
    end
  end

  describe "統合テスト" do
    it "完全なワークフローを実行する" do
      # 進捗追跡から通知までの完全なフロー
      result = described_class.perform_now(threshold, [ admin.id, admin2.id ], true)

      expect(result).to include(
        low_stock_items: include(@low_stock_item, @threshold_item),
        out_of_stock_items: include(@out_of_stock_item),
        notifications_sent: 2,
        threshold: threshold
      )
    end

    it "閾値による結果の変化をテストする" do
      # 低い閾値（3）での検索
      low_result = described_class.perform_now(3, [ admin.id ])

      # 高い閾値（15）での検索
      high_result = described_class.perform_now(15, [ admin.id ])

      # 高い閾値の方が多くのアイテムを検出する
      expect(low_result[:low_stock_items].size).to be <= high_result[:low_stock_items].size
    end
  end

  describe "パフォーマンステスト" do
    it "大量の管理者に対しても適切に処理する" do
      # 100人の管理者を作成
      create_list(:admin, 100)

      start_time = Time.current
      result = described_class.perform_now(threshold)
      duration = Time.current - start_time

      expect(duration).to be < 10.0 # 10秒以内に完了
      expect(result[:notifications_sent]).to eq(Admin.count)
    end

    it "大量の在庫不足アイテムも適切に処理する" do
      # 1000件の低在庫アイテムを作成
      create_list(:inventory, 1000, quantity: 5)

      start_time = Time.current
      result = described_class.perform_now(threshold, [ admin.id ])
      duration = Time.current - start_time

      expect(duration).to be < 5.0 # 5秒以内に完了
      expect(result[:low_stock_items].size).to be >= 1000
    end
  end

  describe "エッジケース" do
    it "アーカイブ済みアイテムも対象とする" do
      archived_item = create(:inventory, name: "Archived Item", quantity: 5, status: 'archived')

      result = described_class.perform_now(threshold, [ admin.id ])

      expect(result[:low_stock_items]).to include(archived_item)
    end

    it "価格が0のアイテムも適切に処理する" do
      free_item = create(:inventory, name: "Free Item", quantity: 5, price: 0)

      result = described_class.perform_now(threshold, [ admin.id ])

      expect(result[:low_stock_items]).to include(free_item)
    end

    it "名前が特殊文字を含むアイテムも適切に処理する" do
      special_item = create(:inventory, name: "特殊文字<>&'\"商品", quantity: 5)

      expect {
        described_class.perform_now(threshold, [ admin.id ])
      }.not_to raise_error
    end

    it "同じ数量のアイテムが複数ある場合も適切にソートする" do
      item_a = create(:inventory, name: "A Item", quantity: 5)
      item_z = create(:inventory, name: "Z Item", quantity: 5)

      result = described_class.perform_now(threshold, [ admin.id ])

      items = result[:low_stock_items].to_a
      expect(items.index(item_a)).to be < items.index(item_z)
    end
  end

  describe "機密情報保護" do
    it "機密情報フィルタリング設定が定義されている" do
      expect(described_class::SENSITIVE_ALERT_PARAMS).to include(
        'notification_tokens', 'push_tokens', 'user_contacts'
      )
    end

    it "通知データ保護レベルが設定されている" do
      expect(described_class::NOTIFICATION_PROTECTION_LEVEL).to eq(:standard)
    end
  end

  # TODO: 🔴 Phase 1（緊急）- 追加テストケース
  # 優先度: 高（CLAUDE.md準拠）
  # 実装期間: 1-2日
  # 横展開: 他のアラート系ジョブと同等のテスト網羅性達成
  #
  # 1. 高度なアラート設定テスト
  #    - 商品カテゴリ別閾値設定のテスト
  #    - 重要度別通知チャンネル選択のテスト
  #    - 通知頻度制御・重複防止のテスト
  #    - VIP商品優先アラート機能のテスト
  #
  # 2. 予測アラート機能テスト
  #    - 在庫減少トレンド分析のテスト
  #    - 発注タイミング提案のテスト
  #    - 季節性考慮在庫予測のテスト
  #    - 需要予測アルゴリズムのテスト
  #
  # 3. 外部連携機能テスト
  #    - Slack/Teams通知のテスト
  #    - SMS緊急通知のテスト
  #    - 発注システム自動連携のテスト
  #    - POSシステム連携のテスト
  #
  # 4. 分析・レポート機能テスト
  #    - 在庫切れ頻度分析のテスト
  #    - アラート効果測定のテスト
  #    - 発注最適化提案のテスト
  #    - コスト影響分析のテスト
  #
  # 5. 自動化・ワークフローテスト
  #    - 段階的アラートエスカレーションのテスト
  #    - 承認ワークフロー自動化のテスト
  #    - 緊急時自動対応のテスト
  #    - 監査ログ強化のテスト
end
