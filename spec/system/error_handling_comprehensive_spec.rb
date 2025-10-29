# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Error Handling Comprehensive Tests", type: :system do
  # CLAUDE.md準拠: エラーハンドリングの包括的テスト
  # メタ認知: 全エラーパターンの網羅的検証と回復可能性の確保
  # 横展開: 全コントローラー・サービス・ジョブで一貫したエラー処理

  # ============================================
  # 1. コントローラー層のエラーハンドリング
  # ============================================

  describe "Controller Error Handling" do
    let(:admin) { create(:admin) }
    let(:store_user) { create(:store_user) }
    let(:store) { create(:store) }

    describe "ActiveRecord::RecordNotFound" do
      context "Admin Controllers" do
        before { sign_in admin }

        it "在庫詳細で存在しないIDアクセス時に404エラーページを表示" do
          visit admin_inventory_path(id: 999999)

          expect(page).to have_http_status(404)
          expect(page).to have_content("お探しのページは見つかりませんでした")
          expect(page).to have_link("管理画面トップへ戻る", href: admin_root_path)
        end

        it "店舗詳細で存在しないIDアクセス時に404エラーページを表示" do
          visit admin_store_path(id: 999999)

          expect(page).to have_http_status(404)
          expect(page).to have_content("お探しのページは見つかりませんでした")
        end

        it "在庫移動で存在しないIDアクセス時に404エラーページを表示" do
          visit admin_inter_store_transfer_path(id: 999999)

          expect(page).to have_http_status(404)
          expect(page).to have_content("お探しのページは見つかりませんでした")
        end
      end

      context "Store Controllers" do
        before do
          sign_in store_user
          store_user.update!(store: store)
        end

        it "店舗在庫で存在しないIDアクセス時に404エラーページを表示" do
          visit store_inventory_path(store_id: store.id, id: 999999)

          expect(page).to have_http_status(404)
          expect(page).to have_content("お探しのページは見つかりませんでした")
          expect(page).to have_link("店舗ダッシュボードへ戻る", href: store_dashboard_path(store))
        end
      end
    end

    describe "ActiveRecord::RecordInvalid" do
      context "バリデーションエラー" do
        before { sign_in admin }

        it "在庫作成で無効なデータ送信時にエラーメッセージを表示" do
          visit new_admin_inventory_path

          # 必須フィールドを空で送信
          click_button "登録"

          expect(page).to have_content("エラーが発生しました")
          expect(page).to have_content("商品名を入力してください")
          expect(page).to have_content("価格は数値で入力してください")
          expect(current_path).to eq(admin_inventories_path)
        end

        it "店舗作成で重複名称時にエラーメッセージを表示" do
          existing_store = create(:store, name: "既存店舗")

          visit new_admin_store_path
          fill_in "店舗名", with: "既存店舗"
          fill_in "店舗コード", with: "NEW001"
          select "pharmacy", from: "店舗タイプ"
          click_button "登録"

          expect(page).to have_content("店舗名はすでに存在します")
          expect(current_path).to eq(admin_stores_path)
        end
      end
    end

    describe "ActionController::ParameterMissing" do
      it "必須パラメータ欠落時に400エラーを返す" do
        page.driver.post admin_inventories_path, {}

        expect(page).to have_http_status(400)
        expect(page).to have_content("リクエストパラメータが不正です")
      end
    end

    describe "CustomError Classes" do
      context "ResourceConflict (409)" do
        it "在庫移動で同時更新競合時に適切なエラーメッセージを表示" do
          transfer = create(:inter_store_transfer, status: "pending")

          # 他のプロセスで承認されたと仮定
          transfer.update_columns(status: "approved", updated_at: 1.second.ago)

          sign_in admin
          visit edit_admin_inter_store_transfer_path(transfer)

          # フォームを編集して送信
          fill_in "備考", with: "更新テスト"
          click_button "更新"

          expect(page).to have_content("リソースが競合しています")
          expect(page).to have_content("最新の情報に更新してから再試行してください")
        end
      end

      context "Forbidden (403)" do
        it "権限のない操作実行時に403エラーを表示" do
          sign_in store_user

          # 店舗ユーザーが管理者エリアにアクセス
          visit admin_root_path

          expect(page).to have_http_status(403)
          expect(page).to have_content("この操作を行う権限がありません")
          expect(page).to have_link("ログイン画面へ", href: new_admin_session_path)
        end
      end

      context "RateLimitExceeded (429)" do
        it "レート制限超過時に429エラーを表示" do
          # レート制限をシミュレート
          allow_any_instance_of(RateLimiter).to receive(:check!).and_raise(
            CustomError::RateLimitExceeded.new
          )

          visit store_inventories_path(store)

          expect(page).to have_http_status(429)
          expect(page).to have_content("短時間に多くのリクエストが行われました")
          expect(page).to have_content("しばらく待ってから再試行してください")
        end
      end
    end

    describe "Turbo Frame Error Handling" do
      before { sign_in admin }

      it "Turboフレーム内でのエラーが適切に表示される" do
        visit admin_inventories_path

        # Turboフレーム内で無効なリクエスト
        within_frame "inventory_list" do
          click_link "削除", match: :first

          # 確認ダイアログで削除を実行（削除失敗をシミュレート）
          accept_confirm

          expect(page).to have_content("削除できませんでした")
          expect(page).to have_css(".alert-danger")
        end
      end
    end
  end

  # ============================================
  # 2. サービス層のエラーハンドリング
  # ============================================

  describe "Service Layer Error Handling" do
    describe "EmailAuthService" do
      let(:store_user) { create(:store_user) }

      context "メール送信エラー" do
        it "SMTP接続エラー時に適切なエラーメッセージを返す" do
          allow_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_now)
            .and_raise(Net::SMTPServerBusy)

          service = EmailAuthService.new(store_user)
          result = service.send_passcode

          expect(result).to be_falsey
          expect(service.errors).to include("メール送信に失敗しました。しばらく待ってから再試行してください。")
        end
      end

      context "パスコード検証エラー" do
        it "期限切れパスコード使用時にエラーを返す" do
          expired_passcode = create(:temp_password,
            store_user: store_user,
            expires_at: 1.hour.ago
          )

          service = EmailAuthService.new(store_user)
          result = service.verify_passcode(expired_passcode.password)

          expect(result).to be_falsey
          expect(service.errors).to include("パスコードの有効期限が切れています")
        end

        it "無効なパスコード使用時にエラーを返す" do
          service = EmailAuthService.new(store_user)
          result = service.verify_passcode("INVALID")

          expect(result).to be_falsey
          expect(service.errors).to include("パスコードが正しくありません")
        end
      end
    end

    describe "StockMovementService" do
      let(:inventory) { create(:inventory, quantity: 10) }

      context "在庫不足エラー" do
        it "在庫数を超える出庫時にエラーを発生させる" do
          service = StockMovementService.new(inventory)

          expect {
            service.ship(15, "過剰出庫テスト")
          }.to raise_error(StockMovementService::InsufficientStockError, "在庫が不足しています")

          # 在庫数は変更されない
          expect(inventory.reload.quantity).to eq(10)
        end
      end

      context "トランザクションロールバック" do
        it "ログ作成失敗時に在庫変更をロールバックする" do
          allow_any_instance_of(InventoryLog).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)

          service = StockMovementService.new(inventory)

          expect {
            service.receive(5, "入庫テスト")
          }.to raise_error(ActiveRecord::RecordInvalid)

          # 在庫数は変更されない
          expect(inventory.reload.quantity).to eq(10)
        end
      end
    end

    describe "RateLimiter" do
      let(:user) { create(:admin) }

      context "レート制限" do
        it "制限を超えた場合にRateLimitExceededエラーを発生させる" do
          limiter = RateLimiter.new(
            key: "test:#{user.id}",
            limit: 3,
            period: 1.minute
          )

          # 制限内のリクエスト
          3.times { expect { limiter.check! }.not_to raise_error }

          # 制限を超えるリクエスト
          expect {
            limiter.check!
          }.to raise_error(CustomError::RateLimitExceeded)
        end

        it "期間経過後はリセットされる" do
          limiter = RateLimiter.new(
            key: "test:#{user.id}",
            limit: 1,
            period: 1.second
          )

          limiter.check!

          # 即座の再リクエストは失敗
          expect { limiter.check! }.to raise_error(CustomError::RateLimitExceeded)

          # 期間経過後は成功
          sleep 1.1
          expect { limiter.check! }.not_to raise_error
        end
      end
    end
  end

  # ============================================
  # 3. ジョブ層のエラーハンドリング
  # ============================================

  describe "Job Layer Error Handling" do
    describe "ImportInventoriesJob" do
      let(:csv_file) { fixture_file_upload('inventories.csv', 'text/csv') }
      let(:job_status) { create(:job_status, job_type: 'inventory_import') }

      context "CSVパースエラー" do
        it "不正なCSV形式でエラーステータスを記録" do
          malformed_csv = StringIO.new("invalid\"csv\"format\nwithout,proper,quotes")

          expect {
            ImportInventoriesJob.perform_now(malformed_csv, job_status.id)
          }.not_to raise_error

          job_status.reload
          expect(job_status.status).to eq("failed")
          expect(job_status.error_message).to include("CSV形式が不正です")
        end
      end

      context "データ検証エラー" do
        it "無効なデータ行でエラー詳細を記録" do
          invalid_csv = StringIO.new(
            "name,quantity,price,status\n" +
            ",invalid,not_a_number,invalid_status\n" +
            "Valid Product,10,1000,active"
          )

          ImportInventoriesJob.perform_now(invalid_csv, job_status.id)

          job_status.reload
          expect(job_status.status).to eq("completed_with_errors")
          expect(job_status.error_details).to include("1行目: 商品名を入力してください")
          expect(job_status.error_details).to include("1行目: 価格は数値で入力してください")
          expect(job_status.success_count).to eq(1)
          expect(job_status.error_count).to eq(1)
        end
      end

      context "リトライ機能" do
        it "一時的なエラーで自動リトライを実行" do
          allow_any_instance_of(ImportInventoriesJob).to receive(:process_row)
            .and_raise(ActiveRecord::ConnectionNotEstablished)

          expect {
            ImportInventoriesJob.perform_now(csv_file, job_status.id)
          }.to raise_error(ActiveRecord::ConnectionNotEstablished)

          # Sidekiqのリトライキューに追加されることを確認
          expect(ImportInventoriesJob).to have_enqueued_sidekiq_job(csv_file, job_status.id)
        end
      end
    end

    describe "MonthlyReportJob" do
      let(:store) { create(:store) }

      context "レポート生成エラー" do
        it "PDF生成失敗時にエラーログを記録" do
          allow_any_instance_of(ReportPdfGenerator).to receive(:generate)
            .and_raise(Prawn::Errors::UnknownFont)

          expect {
            MonthlyReportJob.perform_now(store.id, Date.current)
          }.not_to raise_error

          # エラーログが記録される
          expect(Rails.logger).to have_received(:error).with(/レポート生成に失敗しました/)
        end
      end

      context "ファイル保存エラー" do
        it "ストレージ書き込み失敗時に通知を送信" do
          allow_any_instance_of(ReportFileStorageService).to receive(:store)
            .and_raise(Errno::ENOSPC) # ディスク容量不足

          expect {
            MonthlyReportJob.perform_now(store.id, Date.current)
          }.not_to raise_error

          # 管理者への通知が送信される
          expect(ActionMailer::Base.deliveries.last.subject).to include("レポート生成エラー")
        end
      end
    end
  end

  # ============================================
  # 4. 外部API連携のエラーハンドリング
  # ============================================

  describe "External API Error Handling" do
    describe "外部在庫同期" do
      context "ネットワークエラー" do
        it "タイムアウト時に適切なフォールバック処理を実行" do
          stub_request(:get, "https://api.external-supplier.com/inventory")
            .to_timeout

          service = ExternalInventorySyncService.new
          result = service.sync_all

          expect(result[:status]).to eq(:error)
          expect(result[:message]).to include("接続タイムアウト")
          expect(result[:fallback_executed]).to be_truthy
        end

        it "5xx エラー時に指数バックオフでリトライ" do
          retry_count = 0

          stub_request(:get, "https://api.external-supplier.com/inventory")
            .to_return(status: 503).times(2)
            .then.to_return(status: 200, body: { items: [] }.to_json)

          service = ExternalInventorySyncService.new
          result = service.sync_all

          expect(result[:status]).to eq(:success)
          expect(result[:retry_count]).to eq(2)
        end
      end

      context "認証エラー" do
        it "401エラー時にトークンを再取得して再試行" do
          stub_request(:get, "https://api.external-supplier.com/inventory")
            .to_return(status: 401).times(1)
            .then.to_return(status: 200, body: { items: [] }.to_json)

          stub_request(:post, "https://api.external-supplier.com/auth/token")
            .to_return(status: 200, body: { token: "new_token" }.to_json)

          service = ExternalInventorySyncService.new
          result = service.sync_all

          expect(result[:status]).to eq(:success)
          expect(result[:token_refreshed]).to be_truthy
        end
      end
    end
  end

  # ============================================
  # 5. データベース関連のエラーハンドリング
  # ============================================

  describe "Database Error Handling" do
    describe "デッドロック処理" do
      it "デッドロック検出時に自動リトライを実行" do
        inventory1 = create(:inventory)
        inventory2 = create(:inventory)

        # デッドロックをシミュレート
        allow_any_instance_of(Inventory).to receive(:update!)
          .and_raise(ActiveRecord::Deadlocked)
          .once
          .and_call_original

        service = InventoryTransferService.new
        result = service.transfer(
          from: inventory1,
          to: inventory2,
          quantity: 5
        )

        expect(result[:status]).to eq(:success)
        expect(result[:retry_performed]).to be_truthy
      end
    end

    describe "一意性制約違反" do
      it "重複キー挿入時に適切なエラーメッセージを返す" do
        create(:store, code: "STORE001")

        duplicate_store = build(:store, code: "STORE001")

        expect(duplicate_store.save).to be_falsey
        expect(duplicate_store.errors[:code]).to include("はすでに存在します")
      end
    end
  end

  # ============================================
  # 6. ファイルアップロードのエラーハンドリング
  # ============================================

  describe "File Upload Error Handling" do
    before { sign_in admin }

    context "ファイルサイズ制限" do
      it "10MBを超えるファイルアップロード時にエラーを表示" do
        large_file = fixture_file_upload('large_file.csv', 'text/csv')
        allow(large_file).to receive(:size).and_return(11.megabytes)

        visit new_admin_inventory_import_path
        attach_file "CSVファイル", large_file
        click_button "インポート開始"

        expect(page).to have_content("ファイルサイズは10MB以下にしてください")
      end
    end

    context "ファイル形式制限" do
      it "CSV以外のファイルアップロード時にエラーを表示" do
        invalid_file = fixture_file_upload('image.png', 'image/png')

        visit new_admin_inventory_import_path
        attach_file "CSVファイル", invalid_file
        click_button "インポート開始"

        expect(page).to have_content("CSVファイルを選択してください")
      end
    end
  end

  # ============================================
  # 7. 並行処理のエラーハンドリング
  # ============================================

  describe "Concurrent Processing Error Handling" do
    describe "楽観的ロック" do
      let(:inventory) { create(:inventory, lock_version: 0) }

      it "同時更新検出時にStaleObjectErrorを発生させる" do
        # 2つの同時セッションをシミュレート
        inventory1 = Inventory.find(inventory.id)
        inventory2 = Inventory.find(inventory.id)

        # 最初の更新は成功
        inventory1.update!(quantity: 100)

        # 2番目の更新は失敗
        expect {
          inventory2.update!(quantity: 200)
        }.to raise_error(ActiveRecord::StaleObjectError)
      end

      it "StaleObjectError時に最新データで再試行オプションを表示" do
        visit edit_admin_inventory_path(inventory)

        # 他のプロセスで更新されたと仮定
        inventory.update_columns(quantity: 999, lock_version: 1)

        fill_in "在庫数", with: 100
        click_button "更新"

        expect(page).to have_content("他のユーザーによって更新されています")
        expect(page).to have_button("最新情報を取得")
      end
    end
  end

  # ============================================
  # 8. セキュリティ関連のエラーハンドリング
  # ============================================

  describe "Security Error Handling" do
    describe "CSRF対策" do
      it "無効なCSRFトークンでエラーを表示" do
        page.driver.post admin_inventories_path, {
          inventory: { name: "Test", quantity: 10, price: 1000 }
        }, {
          "X-CSRF-Token" => "invalid_token"
        }

        expect(page).to have_http_status(422)
        expect(page).to have_content("セキュリティトークンが無効です")
      end
    end

    describe "セッションタイムアウト" do
      it "期限切れセッションでログイン画面にリダイレクト" do
        sign_in admin

        # セッションを無効化
        Capybara.reset_sessions!

        visit admin_root_path

        expect(current_path).to eq(new_admin_session_path)
        expect(page).to have_content("セッションの有効期限が切れました")
      end
    end
  end

  # ============================================
  # 9. エラー回復とフォールバック
  # ============================================

  describe "Error Recovery and Fallback" do
    describe "キャッシュフォールバック" do
      it "Redis接続エラー時にデータベースから直接取得" do
        allow(Rails.cache).to receive(:fetch).and_raise(Redis::CannotConnectError)

        visit admin_root_path

        # エラーなく表示される（DBから取得）
        expect(page).to have_content("ダッシュボード")
        expect(page).to have_css(".alert-warning", text: "キャッシュサーバーに接続できません")
      end
    end

    describe "部分的障害の処理" do
      it "外部サービス障害時も基本機能は継続" do
        # メール送信サービスの障害をシミュレート
        allow_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_later)
          .and_raise(StandardError)

        sign_in admin
        inventory = create(:inventory)

        visit edit_admin_inventory_path(inventory)
        fill_in "在庫数", with: 50
        click_button "更新"

        # 更新は成功する
        expect(page).to have_content("在庫情報を更新しました")
        # ただし通知エラーの警告を表示
        expect(page).to have_content("通知メールの送信に失敗しました")
      end
    end
  end

  # ============================================
  # 10. エラーログとモニタリング
  # ============================================

  describe "Error Logging and Monitoring" do
    describe "構造化ログ出力" do
      it "エラー発生時に必要な情報を構造化ログに記録" do
        allow(Rails.logger).to receive(:error)

        visit admin_inventory_path(id: 999999)

        expect(Rails.logger).to have_received(:error) do |&block|
          log_output = block.call
          parsed_log = JSON.parse(log_output)

          expect(parsed_log).to include(
            "status" => 404,
            "error" => "ActiveRecord::RecordNotFound",
            "request_id" => be_present,
            "path" => "/admin/inventories/999999"
          )
        end
      end
    end
  end
end
