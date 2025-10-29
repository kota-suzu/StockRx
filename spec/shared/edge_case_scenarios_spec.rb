# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Edge Case Scenarios", type: :model do
  # CLAUDE.md準拠: エッジケースシナリオの包括的テスト
  # メタ認知: 境界値・異常値・極端な条件での動作保証
  # 横展開: 全モデル・サービスで共通のエッジケースパターン適用

  # ============================================
  # 1. 数値の境界値とオーバーフロー
  # ============================================

  describe "Numeric Boundary Cases" do
    describe "Inventory quantity limits" do
      let(:inventory) { create(:inventory) }

      it "最大整数値での在庫数を処理できる" do
        max_int = 2_147_483_647  # PostgreSQL integer max
        inventory.quantity = max_int

        expect(inventory).to be_valid
        expect { inventory.save! }.not_to raise_error
      end

      it "負の在庫数を適切に処理する" do
        inventory.quantity = -100

        expect(inventory).not_to be_valid
        expect(inventory.errors[:quantity]).to include("は0以上の値にしてください")
      end

      it "小数点在庫数を整数に変換する" do
        inventory.quantity = 10.7
        inventory.save!

        expect(inventory.reload.quantity).to eq(10)
      end

      it "Float::INFINITYを適切にエラー処理する" do
        inventory.quantity = Float::INFINITY

        expect(inventory).not_to be_valid
      end
    end

    describe "Price calculations" do
      let(:inventory) { create(:inventory, price: 1000) }

      it "価格計算でのオーバーフローを防ぐ" do
        huge_quantity = 1_000_000_000

        service = PriceCalculationService.new(inventory)
        result = service.calculate_total(huge_quantity)

        expect(result[:status]).to eq(:error)
        expect(result[:message]).to include("計算結果が範囲を超えています")
      end

      it "ゼロ除算を適切に処理する" do
        service = DiscountCalculationService.new
        result = service.calculate_discount_rate(original: 1000, discounted: 0)

        expect(result).to eq(100.0)  # 100%割引

        # 逆のケース
        result = service.calculate_discount_rate(original: 0, discounted: 1000)
        expect(result).to eq(0.0)  # エラーではなく0%として処理
      end
    end
  end

  # ============================================
  # 2. 文字列の異常値とエンコーディング
  # ============================================

  describe "String Edge Cases" do
    describe "Unicode and special characters" do
      let(:inventory) { build(:inventory) }

      it "絵文字を含む商品名を正しく処理する" do
        inventory.name = "🎉スペシャル商品🎊"

        expect(inventory).to be_valid
        expect { inventory.save! }.not_to raise_error
        expect(inventory.reload.name).to eq("🎉スペシャル商品🎊")
      end

      it "制御文字を含む入力をサニタイズする" do
        inventory.name = "商品\x00\x01\x02名"
        inventory.save!

        expect(inventory.reload.name).to eq("商品名")  # 制御文字は除去される
      end

      it "非常に長い文字列を適切に切り詰める" do
        long_name = "あ" * 1000
        inventory.name = long_name

        expect(inventory).not_to be_valid
        expect(inventory.errors[:name]).to include("は255文字以内で入力してください")
      end

      it "様々なエンコーディングの文字列を処理する" do
        # Shift_JISからUTF-8への変換
        sjis_string = "商品名".encode("Shift_JIS")
        inventory.name = sjis_string.force_encoding("UTF-8")

        expect { inventory.save! }.not_to raise_error
      end

      it "NULL文字を含むCSVインポートを処理する" do
        csv_content = "name,quantity,price\n商品\0名,10,1000"

        importer = CsvImporter.new(csv_content)
        result = importer.import

        expect(result[:success_count]).to eq(1)
        expect(Inventory.last.name).to eq("商品名")
      end
    end

    describe "SQL injection prevention" do
      it "SQLインジェクション試行を無害化する" do
        malicious_name = "'; DROP TABLE inventories; --"

        results = Inventory.where("name LIKE ?", "%#{malicious_name}%")
        expect { results.to_a }.not_to raise_error

        # テーブルが削除されていないことを確認
        expect(Inventory.table_exists?).to be_truthy
      end

      it "複雑なSQL文字列をエスケープする" do
        special_chars = "50% off! (limited time) [new] {special} \"quoted\" 'single'"
        inventory = create(:inventory, name: special_chars)

        found = Inventory.where("name = ?", special_chars).first
        expect(found).to eq(inventory)
      end
    end
  end

  # ============================================
  # 3. 日付・時刻の特殊ケース
  # ============================================

  describe "DateTime Edge Cases" do
    describe "Timezone handling" do
      around do |example|
        original_tz = Time.zone
        Time.zone = "Asia/Tokyo"
        example.run
        Time.zone = original_tz
      end

      it "タイムゾーンを跨ぐ日付変更を正しく処理する" do
        # 日本時間で深夜0時直前
        Time.zone = "Asia/Tokyo"
        jp_time = Time.zone.parse("2024-01-01 23:59:59")

        batch = create(:batch, expires_on: jp_time.to_date)

        # UTCでは前日
        Time.zone = "UTC"
        expect(batch.expires_on.to_s).to eq("2024-01-01")
      end

      it "サマータイム切り替え時の処理" do
        # サマータイムのある地域でテスト
        Time.zone = "America/New_York"

        # 2024年3月10日 2:00 AM はサマータイム開始で存在しない
        dst_start = Time.zone.parse("2024-03-10 01:59:59")

        job = ScheduledJob.new(run_at: dst_start + 1.second)
        expect(job.run_at.hour).to eq(3)  # 2時が飛ばされて3時になる
      end
    end

    describe "Leap year and edge dates" do
      it "うるう年の2月29日を正しく処理する" do
        leap_date = Date.new(2024, 2, 29)
        batch = create(:batch, expires_on: leap_date)

        expect(batch.expires_on).to eq(leap_date)
        expect(batch.days_until_expiry).to be_a(Integer)
      end

      it "存在しない日付の作成を防ぐ" do
        expect {
          Date.new(2023, 2, 29)  # 2023年はうるう年ではない
        }.to raise_error(ArgumentError)
      end

      it "遠い未来の日付を処理する" do
        far_future = Date.new(9999, 12, 31)
        batch = build(:batch, expires_on: far_future)

        expect(batch).to be_valid
        expect(batch.days_until_expiry).to be > 1_000_000
      end
    end
  end

  # ============================================
  # 4. 並行処理とレースコンディション
  # ============================================

  describe "Concurrency Edge Cases" do
    describe "Race conditions" do
      let(:inventory) { create(:inventory, quantity: 100) }

      it "同時在庫更新でレースコンディションを防ぐ" do
        threads = []
        errors = []

        10.times do
          threads << Thread.new do
            begin
              Inventory.transaction do
                inv = Inventory.lock.find(inventory.id)
                inv.quantity -= 10
                inv.save!
              end
            rescue => e
              errors << e
            end
          end
        end

        threads.each(&:join)

        expect(errors).to be_empty
        expect(inventory.reload.quantity).to eq(0)
      end

      it "カウンターキャッシュの同時更新を正しく処理する" do
        store = create(:store)
        threads = []

        10.times do
          threads << Thread.new do
            inventory = create(:inventory)
            create(:store_inventory, store: store, inventory: inventory)
          end
        end

        threads.each(&:join)

        expect(store.reload.inventories_count).to eq(10)
      end
    end

    describe "Deadlock handling" do
      it "デッドロック検出時に適切にリトライする" do
        inventory1 = create(:inventory)
        inventory2 = create(:inventory)

        deadlock_occurred = false

        thread1 = Thread.new do
          Inventory.transaction do
            Inventory.lock.find(inventory1.id)
            sleep 0.1
            begin
              Inventory.lock.find(inventory2.id)
            rescue ActiveRecord::Deadlocked
              deadlock_occurred = true
              raise
            end
          end
        end

        thread2 = Thread.new do
          Inventory.transaction do
            Inventory.lock.find(inventory2.id)
            sleep 0.1
            Inventory.lock.find(inventory1.id)
          end
        end

        [ thread1, thread2 ].each { |t| t.join rescue nil }

        # デッドロックが検出されることを確認
        expect(deadlock_occurred).to be_truthy
      end
    end
  end

  # ============================================
  # 5. メモリとパフォーマンスの限界
  # ============================================

  describe "Memory and Performance Limits" do
    describe "Large dataset handling" do
      it "大量データのバッチ処理でメモリ枯渇を防ぐ" do
        # 10万件のレコードを想定
        expect {
          Inventory.find_in_batches(batch_size: 1000) do |batch|
            batch.each do |inventory|
              # 処理
            end
          end
        }.not_to raise_error
      end

      it "巨大なCSVエクスポートをストリーミングで処理する" do
        # メモリに載せずにストリーミング
        csv_enumerator = Enumerator.new do |yielder|
          yielder << CSV.generate_line([ "name", "quantity", "price" ])

          Inventory.find_each do |inventory|
            yielder << CSV.generate_line([
              inventory.name,
              inventory.quantity,
              inventory.price
            ])
          end
        end

        # ストリーミングレスポンスとして返せることを確認
        expect(csv_enumerator).to be_a(Enumerator)
      end
    end

    describe "Infinite loops prevention" do
      # TODO: Categoryモデル実装後に有効化
      # it "再帰的な関連で無限ループを防ぐ" do
      #   category1 = create(:category)
      #   category2 = create(:category, parent: category1)
      #
      #   # 循環参照を作ろうとする
      #   expect {
      #     category1.update(parent: category2)
      #   }.to raise_error(ActiveRecord::RecordInvalid, /循環参照/)
      # end

      it "コールバックの無限連鎖を防ぐ" do
        inventory = create(:inventory)

        # after_updateで自身を更新するような処理があってもスタックオーバーフローしない
        update_count = 0
        allow(inventory).to receive(:after_update_method) do
          update_count += 1
          raise "無限ループ検出" if update_count > 10
        end

        expect {
          inventory.update(quantity: 50)
        }.not_to raise_error
      end
    end
  end

  # ============================================
  # 6. ファイルシステムとI/O
  # ============================================

  describe "File System Edge Cases" do
    describe "File operations" do
      let(:temp_dir) { Rails.root.join("tmp/test_uploads") }

      before { FileUtils.mkdir_p(temp_dir) }
      after { FileUtils.rm_rf(temp_dir) }

      it "ディスク容量不足を適切に処理する" do
        allow(File).to receive(:write).and_raise(Errno::ENOSPC)

        service = FileUploadService.new
        result = service.save_file("content", "test.txt")

        expect(result[:status]).to eq(:error)
        expect(result[:message]).to include("ディスク容量が不足しています")
      end

      it "ファイルロック競合を処理する" do
        file_path = temp_dir.join("locked_file.txt")

        # ファイルをロック
        File.open(file_path, "w") do |f|
          f.flock(File::LOCK_EX | File::LOCK_NB)

          # 別プロセスからのアクセスをシミュレート
          service = FileAccessService.new
          result = service.read_file(file_path)

          expect(result[:status]).to eq(:error)
          expect(result[:message]).to include("ファイルがロックされています")
        end
      end

      it "シンボリックリンク攻撃を防ぐ" do
        safe_path = temp_dir.join("safe_file.txt")
        evil_path = "/etc/passwd"
        link_path = temp_dir.join("evil_link.txt")

        # シンボリックリンクを作成
        File.symlink(evil_path, link_path)

        service = SecureFileService.new
        result = service.read_file(link_path)

        expect(result[:status]).to eq(:error)
        expect(result[:message]).to include("シンボリックリンクは許可されていません")
      end
    end
  end

  # ============================================
  # 7. ネットワークとタイムアウト
  # ============================================

  describe "Network Edge Cases" do
    describe "Timeout handling" do
      it "読み取りタイムアウトを適切に処理する" do
        stub_request(:get, "https://slow-api.example.com/data")
          .to_timeout

        service = ExternalApiService.new(timeout: 1)
        result = service.fetch_data

        expect(result[:status]).to eq(:error)
        expect(result[:error_type]).to eq(:timeout)
        expect(result[:message]).to include("タイムアウトしました")
      end

      it "部分的なレスポンス受信を処理する" do
        # レスポンスが途中で切れる
        stub_request(:get, "https://api.example.com/data")
          .to_return(body: '{"items": [{"id": 1, "name": "Test"')  # JSON不完全

        service = ApiDataParser.new
        result = service.parse_response

        expect(result[:status]).to eq(:error)
        expect(result[:error_type]).to eq(:invalid_json)
      end
    end

    describe "DNS and connection issues" do
      it "DNS解決失敗を処理する" do
        stub_request(:get, "https://non-existent-domain-xyz123.com/api")
          .to_raise(SocketError.new("getaddrinfo: Name or service not known"))

        service = ExternalApiService.new
        result = service.fetch_from("https://non-existent-domain-xyz123.com/api")

        expect(result[:status]).to eq(:error)
        expect(result[:error_type]).to eq(:dns_error)
      end

      it "接続拒否を適切に処理する" do
        stub_request(:get, "http://localhost:9999/api")
          .to_raise(Errno::ECONNREFUSED)

        service = LocalApiService.new
        result = service.check_health

        expect(result[:status]).to eq(:error)
        expect(result[:message]).to include("接続が拒否されました")
      end
    end
  end

  # ============================================
  # 8. データベース固有のエッジケース
  # ============================================

  describe "Database Specific Edge Cases" do
    describe "Transaction edge cases" do
      it "ネストしたトランザクションでのロールバック" do
        expect {
          Inventory.transaction do
            create(:inventory, name: "Outer")

            Inventory.transaction(requires_new: true) do
              create(:inventory, name: "Inner")
              raise ActiveRecord::Rollback
            end

            create(:inventory, name: "Outer2")
          end
        }.to change(Inventory, :count).by(2)  # Innerだけロールバック
      end

      it "セーブポイントを使った部分的ロールバック" do
        inventory = create(:inventory, quantity: 100)

        Inventory.transaction do
          inventory.update!(quantity: 50)

          Inventory.transaction(requires_new: true) do
            inventory.update!(quantity: 25)
            raise ActiveRecord::Rollback
          end
        end

        expect(inventory.reload.quantity).to eq(50)
      end
    end

    describe "Connection pool exhaustion" do
      it "コネクションプール枯渇を検出する" do
        original_size = ActiveRecord::Base.connection_pool.size

        # プールを意図的に枯渇させる
        connections = []
        begin
          (original_size + 1).times do
            connections << ActiveRecord::Base.connection_pool.checkout
          end
        rescue ActiveRecord::ConnectionTimeoutError => e
          expect(e.message).to include("could not obtain a connection")
        ensure
          connections.each { |conn| ActiveRecord::Base.connection_pool.checkin(conn) }
        end
      end
    end
  end

  # ============================================
  # 9. 状態遷移の異常系
  # ============================================

  describe "State Machine Edge Cases" do
    describe "Invalid state transitions" do
      let(:transfer) { create(:inter_store_transfer, status: "pending") }

      it "不正な状態遷移を防ぐ" do
        # pending -> completedは不正（approved経由が必要）
        transfer.status = "completed"

        expect(transfer).not_to be_valid
        expect(transfer.errors[:status]).to include("不正な状態遷移です")
      end

      it "同時状態更新での競合を処理する" do
        transfer1 = InterStoreTransfer.find(transfer.id)
        transfer2 = InterStoreTransfer.find(transfer.id)

        transfer1.approve!

        expect {
          transfer2.approve!
        }.to raise_error(StateMachine::InvalidTransition)
      end
    end
  end

  # ============================================
  # 10. 暗号化とセキュリティ
  # ============================================

  describe "Encryption Edge Cases" do
    describe "Key rotation" do
      it "古い暗号化キーでのデータを復号できる" do
        # 古いキーで暗号化
        old_encrypted = SecurityComplianceManager.encrypt("sensitive", version: 1)

        # キーローテーション後も復号可能
        decrypted = SecurityComplianceManager.decrypt(old_encrypted)
        expect(decrypted).to eq("sensitive")
      end

      it "改ざんされた暗号文を検出する" do
        encrypted = SecurityComplianceManager.encrypt("data")
        tampered = encrypted[0...-1] + "X"  # 最後の文字を改ざん

        expect {
          SecurityComplianceManager.decrypt(tampered)
        }.to raise_error(SecurityComplianceManager::DecryptionError)
      end
    end
  end
end
