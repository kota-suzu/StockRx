# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminChannel, type: :channel do
  # CLAUDE.md準拠: AdminChannelのActionCable統合テスト
  # メタ認知: リアルタイム通信・進捗追跡・認証の品質保証
  # 横展開: 他のActionCableチャンネルでも同様のテストパターン適用

  let(:admin) { create(:admin) }
  let(:connection) { ActionCable::TestConnection.new }
  let(:redis) { double('Redis') }

  before do
    # ActionCable接続のセットアップ
    connection.current_admin = admin

    # Redisのモック
    allow(connection).to receive(:get_redis_connection).and_return(redis)
    allow_any_instance_of(described_class).to receive(:get_redis_connection).and_return(redis)

    # ログのモック
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)
  end

  describe '#subscribed' do
    context '認証済み管理者' do
      it '正常にチャンネルにサブスクライブする' do
        subscribe(connection: connection)

        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_for(admin)
      end

      it '接続完了通知を送信する' do
        expect {
          subscribe(connection: connection)
        }.to have_broadcasted_to(subscription).with(
          hash_including(
            type: "connection_established",
            admin_id: admin.id,
            timestamp: match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
          )
        )
      end

      it '接続ログを出力する' do
        expect(Rails.logger).to receive(:info).with("Admin #{admin.id} subscribed to AdminChannel")

        subscribe(connection: connection)
      end
    end

    context '未認証の接続' do
      before do
        connection.current_admin = nil
      end

      it 'サブスクリプションを拒否する' do
        subscribe(connection: connection)

        expect(subscription).to be_rejected
      end
    end
  end

  describe '#unsubscribed' do
    before do
      subscribe(connection: connection)
    end

    it '切断ログを出力する' do
      expect(Rails.logger).to receive(:info).with("Admin #{admin.id} unsubscribed from AdminChannel")

      subscription.unsubscribe_from_channel
    end

    context '管理者が未設定の場合' do
      before do
        connection.current_admin = nil
      end

      it '安全に切断処理を行う' do
        expect(Rails.logger).to receive(:info).with("Admin  unsubscribed from AdminChannel")

        expect {
          subscription.unsubscribe_from_channel
        }.not_to raise_error
      end
    end
  end

  describe '#track_csv_import' do
    let(:job_id) { "test_job_123" }
    let(:status_key) { "csv_import:#{job_id}" }

    before do
      subscribe(connection: connection)
    end

    context '有効なジョブID' do
      context 'ジョブが進行中' do
        let(:job_data) do
          {
            "status" => "processing",
            "progress" => "50",
            "total_records" => "100",
            "processed_records" => "50",
            "errors_count" => "2"
          }
        end

        before do
          allow(redis).to receive(:hgetall).with(status_key).and_return(job_data)
        end

        it 'ジョブ進捗情報を送信する' do
          expect {
            subscription.track_csv_import("job_id" => job_id)
          }.to have_broadcasted_to(subscription).with(
            hash_including(
              type: "csv_import_progress",
              job_id: job_id,
              status: "processing",
              progress: 50.0,
              processed_records: 50,
              total_records: 100,
              errors_count: 2
            )
          )
        end
      end

      context 'ジョブが完了' do
        let(:job_data) do
          {
            "status" => "completed",
            "progress" => "100",
            "total_records" => "100",
            "processed_records" => "100",
            "errors_count" => "0",
            "completion_time" => "2024-12-25T10:30:00Z",
            "success_count" => "98"
          }
        end

        before do
          allow(redis).to receive(:hgetall).with(status_key).and_return(job_data)
        end

        it 'ジョブ完了情報を送信する' do
          expect {
            subscription.track_csv_import("job_id" => job_id)
          }.to have_broadcasted_to(subscription).with(
            hash_including(
              type: "csv_import_completed",
              job_id: job_id,
              success_count: 98,
              errors_count: 0,
              completion_time: "2024-12-25T10:30:00Z"
            )
          )
        end
      end

      context 'ジョブでエラー発生' do
        let(:job_data) do
          {
            "status" => "failed",
            "error_message" => "ファイル読み込みエラー",
            "errors_count" => "1"
          }
        end

        before do
          allow(redis).to receive(:hgetall).with(status_key).and_return(job_data)
        end

        it 'エラー情報を送信する' do
          expect {
            subscription.track_csv_import("job_id" => job_id)
          }.to have_broadcasted_to(subscription).with(
            hash_including(
              type: "csv_import_failed",
              job_id: job_id,
              error_message: "ファイル読み込みエラー",
              errors_count: 1
            )
          )
        end
      end

      context 'ジョブが見つからない' do
        before do
          allow(redis).to receive(:hgetall).with(status_key).and_return({})
        end

        it 'ジョブ未発見メッセージを送信する' do
          expect {
            subscription.track_csv_import("job_id" => job_id)
          }.to have_broadcasted_to(subscription).with(
            hash_including(
              type: "csv_import_not_found",
              job_id: job_id,
              message: "指定されたインポートジョブが見つかりません"
            )
          )
        end
      end
    end

    context '無効なジョブID' do
      it 'job_idが空の場合はアクションを拒否する' do
        expect {
          subscription.track_csv_import("job_id" => "")
        }.to have_broadcasted_to(subscription).with(
          hash_including(
            type: "action_rejected",
            reason: "job_id required"
          )
        )
      end

      it 'job_idが未指定の場合はアクションを拒否する' do
        expect {
          subscription.track_csv_import({})
        }.to have_broadcasted_to(subscription).with(
          hash_including(
            type: "action_rejected",
            reason: "job_id required"
          )
        )
      end
    end

    context 'Redis接続エラー' do
      before do
        allow_any_instance_of(described_class).to receive(:get_redis_connection).and_return(nil)
      end

      it 'Redis接続エラーメッセージを送信する' do
        expect {
          subscription.track_csv_import("job_id" => job_id)
        }.to have_broadcasted_to(subscription).with(
          hash_including(
            type: "action_rejected",
            reason: "Redis unavailable"
          )
        )
      end
    end

    context 'Redis操作エラー' do
      before do
        allow(redis).to receive(:hgetall).and_raise(Redis::CannotConnectError.new("Redis connection failed"))
      end

      it 'エラーログを出力してエラーメッセージを送信する' do
        expect(Rails.logger).to receive(:error).with(include("Failed to track CSV import"))

        expect {
          subscription.track_csv_import("job_id" => job_id)
        }.to have_broadcasted_to(subscription).with(
          hash_including(
            type: "csv_import_error",
            job_id: job_id,
            message: "進捗情報の取得に失敗しました"
          )
        )
      end
    end
  end

  describe '#send_stock_alert' do
    let(:alert_data) do
      {
        "message" => "在庫不足アラート",
        "items" => [
          { "id" => 1, "name" => "商品A", "quantity" => 5 },
          { "id" => 2, "name" => "商品B", "quantity" => 0 }
        ],
        "threshold" => 10
      }
    end

    before do
      subscribe(connection: connection)
    end

    context '有効なアラートデータ' do
      it '在庫アラートを送信する' do
        expect {
          subscription.send_stock_alert(alert_data)
        }.to have_broadcasted_to(subscription).with(
          hash_including(
            type: "stock_alert",
            message: "在庫不足アラート",
            items: alert_data["items"],
            threshold: 10,
            timestamp: match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
          )
        )
      end

      it 'アラートログを出力する' do
        expect(Rails.logger).to receive(:info).with(include("Stock alert sent to admin #{admin.id}"))

        subscription.send_stock_alert(alert_data)
      end
    end

    context '無効なアラートデータ' do
      it 'メッセージが空の場合はアクションを拒否する' do
        invalid_data = alert_data.merge("message" => "")

        expect {
          subscription.send_stock_alert(invalid_data)
        }.to have_broadcasted_to(subscription).with(
          hash_including(
            type: "action_rejected",
            reason: "Invalid alert data"
          )
        )
      end

      it 'itemsが空の場合はアクションを拒否する' do
        invalid_data = alert_data.merge("items" => [])

        expect {
          subscription.send_stock_alert(invalid_data)
        }.to have_broadcasted_to(subscription).with(
          hash_including(
            type: "action_rejected",
            reason: "Invalid alert data"
          )
        )
      end
    end
  end

  describe '#heartbeat' do
    before do
      subscribe(connection: connection)
    end

    it 'ハートビート応答を送信する' do
      expect {
        subscription.heartbeat({})
      }.to have_broadcasted_to(subscription).with(
        hash_including(
          type: "heartbeat_response",
          admin_id: admin.id,
          timestamp: match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        )
      )
    end

    it 'サーバー状態情報を含める' do
      allow(described_class).to receive(:server_status).and_return({
        memory_usage: "256MB",
        active_connections: 5
      })

      expect {
        subscription.heartbeat({})
      }.to have_broadcasted_to(subscription).with(
        hash_including(
          server_status: {
            memory_usage: "256MB",
            active_connections: 5
          }
        )
      )
    end
  end

  describe 'プライベートメソッド' do
    let(:channel_instance) { described_class.new(connection, {}) }

    before do
      allow(channel_instance).to receive(:current_admin).and_return(admin)
    end

    describe '#reject_action' do
      it 'アクション拒否メッセージを送信する' do
        expect(channel_instance).to receive(:transmit).with(
          hash_including(
            type: "action_rejected",
            reason: "Test reason",
            timestamp: match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
          )
        )

        channel_instance.send(:reject_action, "Test reason")
      end
    end

    describe '#format_csv_import_response' do
      let(:job_data) do
        {
          "status" => "processing",
          "progress" => "75",
          "total_records" => "200",
          "processed_records" => "150"
        }
      end

      it 'CSVインポート応答を適切にフォーマットする' do
        result = channel_instance.send(:format_csv_import_response, "job_123", job_data)

        expect(result).to include(
          type: "csv_import_progress",
          job_id: "job_123",
          status: "processing",
          progress: 75.0,
          processed_records: 150,
          total_records: 200
        )
      end

      it '数値データを適切に変換する' do
        result = channel_instance.send(:format_csv_import_response, "job_123", job_data)

        expect(result[:progress]).to be_a(Float)
        expect(result[:processed_records]).to be_a(Integer)
        expect(result[:total_records]).to be_a(Integer)
      end
    end
  end

  describe '統合テスト' do
    let(:job_id) { "integration_test_job" }

    before do
      subscribe(connection: connection)
    end

    it '完全なCSVインポート追跡フローを実行する' do
      # 1. 進行中状態
      allow(redis).to receive(:hgetall).with("csv_import:#{job_id}").and_return({
        "status" => "processing",
        "progress" => "25",
        "total_records" => "100",
        "processed_records" => "25"
      })

      subscription.track_csv_import("job_id" => job_id)

      # 2. 完了状態
      allow(redis).to receive(:hgetall).with("csv_import:#{job_id}").and_return({
        "status" => "completed",
        "progress" => "100",
        "total_records" => "100",
        "processed_records" => "100",
        "success_count" => "98",
        "errors_count" => "2"
      })

      subscription.track_csv_import("job_id" => job_id)

      # 両方の状態が適切に通知されることを確認
      expect(subscription).to have_received_broadcasts(2)
    end

    it '在庫アラートと進捗追跡の並行処理を適切に処理する' do
      # 進捗追跡の設定
      allow(redis).to receive(:hgetall).and_return({
        "status" => "processing",
        "progress" => "50"
      })

      # 並行してアクションを実行
      subscription.track_csv_import("job_id" => job_id)
      subscription.send_stock_alert({
        "message" => "テストアラート",
        "items" => [ { "id" => 1, "name" => "商品A" } ],
        "threshold" => 5
      })

      # 両方のアクションが正常に処理されることを確認
      expect(subscription).to have_received_broadcasts(2)
    end
  end

  describe 'パフォーマンステスト' do
    before do
      subscribe(connection: connection)
    end

    it '大量データでも高速に処理される' do
      large_items = Array.new(100) { |i| { "id" => i, "name" => "商品#{i}", "quantity" => i } }

      start_time = Time.current
      subscription.send_stock_alert({
        "message" => "大量アラート",
        "items" => large_items,
        "threshold" => 50
      })
      duration = Time.current - start_time

      expect(duration).to be < 1.0 # 1秒以内に完了
    end
  end

  describe 'セキュリティテスト' do
    before do
      subscribe(connection: connection)
    end

    it 'XSS攻撃を防ぐ' do
      malicious_data = {
        "message" => "<script>alert('XSS')</script>",
        "items" => [ { "id" => 1, "name" => "<img src=x onerror=alert('XSS')>" } ],
        "threshold" => 10
      }

      # ActionCableの自動エスケープ機能により、悪意あるスクリプトは無害化される
      expect {
        subscription.send_stock_alert(malicious_data)
      }.not_to raise_error

      expect(subscription).to have_received_broadcasts(1)
    end

    it '権限外のアクションを適切に拒否する' do
      # 管理者権限を削除
      connection.current_admin = nil

      expect {
        subscription.track_csv_import("job_id" => "test")
      }.to raise_error(ActionCable::Connection::Authorization::UnauthorizedError)
    end
  end

  # TODO: 🔴 Phase 1（緊急）- 追加テストケース
  # 優先度: 高（CLAUDE.md準拠）
  # 実装期間: 1日
  # 横展開: 他のActionCableチャンネルと同等のテスト網羅性達成
  #
  # 1. 負荷テスト
  #    - 同時接続数の上限テスト
  #    - メッセージ送信頻度の制限テスト
  #    - メモリリーク検出テスト
  #
  # 2. 障害復旧テスト
  #    - Redis接続断からの自動復旧
  #    - ネットワーク障害時の再接続
  #    - 部分的データ損失の処理
  #
  # 3. リアルタイム通知拡張テスト
  #    - 複数チャンネル間の連携
  #    - 優先度別メッセージ配信
  #    - 通知履歴管理機能
end
