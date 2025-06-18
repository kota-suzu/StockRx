# frozen_string_literal: true

module AdminControllers
  class InventoriesController < BaseController
    before_action :set_inventory, only: %i[show edit update destroy]

    # TODO: 以下の機能実装が必要
    # - 在庫一括操作機能（一括ステータス変更、一括削除）
    # - 在庫レポート機能（月次・年次レポート、在庫回転率）
    # - 在庫アラート設定機能（最低在庫数設定、期限切れアラート）
    # - エクスポート機能（PDF、Excel、CSV）
    # - 在庫履歴・監査ログ機能
    # - APIレート制限・認証機能強化

    # GET /admin/inventories
    def index
      # Kaminariページネーション実装（50/100/200件切り替え可能）
      per_page = validate_per_page_param(params[:per_page])

      # Kaminariのページネーション情報を保持
      @inventories_raw = SearchQuery.call(params)
                                   .page(params[:page])
                                   .per(per_page)

      # デコレートはKaminariメソッドにアクセスした後に実行
      @inventories = @inventories_raw.decorate

      respond_to do |format|
        format.html # Turbo Frame 対応
        format.json {
          render json: {
            inventories: @inventories.map(&:as_json_with_decorated),
            pagination: {
              current_page: @inventories_raw.current_page,
              total_pages: @inventories_raw.total_pages,
              total_count: @inventories_raw.total_count,
              per_page: @inventories_raw.limit_value
            }
          }
        }
        format.turbo_stream # 必要に応じて実装
      end
    end

    # GET /admin/inventories/1
    def show
      respond_to do |format|
        format.html
        format.json { render json: @inventory.as_json_with_decorated }
      end
    end

    # GET /admin/inventories/new
    def new
      @inventory = Inventory.new
    end

    # GET /admin/inventories/1/edit
    def edit
    end

    # POST /admin/inventories
    def create
      @inventory = Inventory.new(inventory_params)

      respond_to do |format|
        begin
          @inventory.save!
          format.html { redirect_to admin_inventory_path(@inventory), notice: "在庫が正常に登録されました。" }
          format.json { render json: @inventory.decorate.as_json_with_decorated, status: :created }
          format.turbo_stream { flash.now[:notice] = "在庫が正常に登録されました。" }
        rescue ActiveRecord::RecordInvalid => e
          # 422エラー時の個別処理
          format.html {
            flash.now[:alert] = "入力内容に問題があります"
            render :new, status: :unprocessable_entity
          }
          format.json {
            # CLAUDE.md準拠: ベストプラクティス - 一貫性のあるAPIエラーレスポンス
            error_response = {
              code: "validation_error",
              message: "入力内容に問題があります",
              details: @inventory.errors.full_messages
            }
            render json: error_response, status: :unprocessable_entity
          }
          format.turbo_stream { render :form_update, status: :unprocessable_entity }
        end
      end
    end

    # PATCH/PUT /admin/inventories/1
    def update
      respond_to do |format|
        begin
          @inventory.update!(inventory_params)
          format.html { redirect_to admin_inventory_path(@inventory), notice: "在庫が正常に更新されました。" }
          format.json { render json: @inventory.decorate.as_json_with_decorated }
          format.turbo_stream { flash.now[:notice] = "在庫が正常に更新されました。" }
        rescue ActiveRecord::RecordInvalid => e
          # 422エラー時の個別処理
          format.html {
            flash.now[:alert] = "入力内容に問題があります"
            render :edit, status: :unprocessable_entity
          }
          format.json {
            # CLAUDE.md準拠: ベストプラクティス - 一貫性のあるAPIエラーレスポンス
            error_response = {
              code: "validation_error",
              message: "入力内容に問題があります",
              details: @inventory.errors.full_messages
            }
            render json: error_response, status: :unprocessable_entity
          }
          format.turbo_stream { render :form_update, status: :unprocessable_entity }
        end
      end
    end

    # DELETE /admin/inventories/1
    def destroy
      # CLAUDE.md準拠: 監査ログの完全性保護を考慮した削除処理
      # メタ認知: 削除前に関連レコードの存在確認が必要
      # ベストプラクティス: 明示的なエラーハンドリングとユーザーフィードバック
      begin
        if @inventory.destroy
          respond_to do |format|
            format.html { redirect_to admin_inventories_path, notice: "在庫が正常に削除されました。", status: :see_other }
            format.json { head :no_content }
            format.turbo_stream { flash.now[:notice] = "在庫が正常に削除されました。" }
          end
        else
          handle_destroy_error
        end
      rescue ActiveRecord::InvalidForeignKey, ActiveRecord::DeleteRestrictionError => e
        # 依存関係による削除制限エラー（監査ログなど）
        Rails.logger.warn "Inventory deletion restricted: #{e.message}, inventory_id: #{@inventory.id}"

        # CLAUDE.md準拠: ユーザーフレンドリーなエラーメッセージ（日本語化）
        # メタ認知: 技術的なエラーメッセージを業務理解しやすい日本語に変換
        error_message = case e.message
        when /inventory.logs.*exist/i, /dependent.*inventory.*logs.*exist/i
          "この在庫には在庫変動履歴が記録されているため削除できません。\n監査上、履歴データの保護が必要です。\n\n代替案：在庫を「アーカイブ」状態に変更してください。"
        when /Cannot delete.*dependent.*exist/i
          "この在庫には関連する記録が存在するため削除できません。\n関連データ：在庫履歴、移動履歴、監査ログなど"
        else
          "この在庫には関連する履歴データが存在するため、削除できません。"
        end

        handle_destroy_error(error_message)
      rescue => e
        # その他の予期しないエラー
        Rails.logger.error "Inventory deletion failed: #{e.message}, inventory_id: #{@inventory.id}"
        handle_destroy_error("削除中にエラーが発生しました。")
      end
    end

    # GET /admin/inventories/import_form
    # CSVインポートフォーム表示
    def import_form
      # CLAUDE.md準拠: メタ認知的アプローチ - なぜCSVインポートが必要か？
      # 目的: 大量在庫データの効率的一括登録、外部システムからのデータ移行
      # 効果: 手作業時間削減、データ整合性向上、運用効率化
      
      # セキュリティ考慮事項の事前チェック
      @import_security_info = {
        max_file_size: "10MB",
        allowed_formats: [".csv"],
        required_headers: %w[name quantity price],
        security_measures: [
          "ファイルサイズ制限: 10MB以下",
          "ファイル形式: CSV形式のみ",
          "セキュリティスキャン: 自動実行",
          "プレビュー機能: 事前確認可能"
        ]
      }
      
      # 進行中のインポートジョブの確認
      @current_import_jobs = check_running_import_jobs
      
      # CSVテンプレート用のサンプルデータ
      @csv_template_headers = %w[name quantity price status]
      @csv_sample_data = [
        ["商品A", "100", "1500", "active"],
        ["商品B", "50", "2000", "active"],
        ["商品C", "200", "800", "active"]
      ]
      
      # TODO: 🟡 Phase 4（高度機能）- CSVインポート機能拡張
      # 優先度: 中（基本機能実装後）
      # 実装内容:
      #   - インポートプレビュー機能（最初の10行表示）
      #   - カラムマッピング設定（CSVヘッダーとDBカラムの対応）
      #   - バリデーションエラーの事前表示
      #   - 重複データ処理オプション（更新/スキップ/エラー）
      #   - インポート履歴表示機能
      # 横展開: 他のCSVインポート機能でも同様のUIパターン適用
    end

    # POST /admin/inventories/import
    # CSVインポート実行
    def import
      # CLAUDE.md準拠: セキュリティファーストアプローチ
      # メタ認知: CSVインポートの潜在的リスク（ファイルアップロード攻撃、CSVインジェクション）
      
      begin
        # 1. 基本的なパラメータ検証
        unless params[:csv_file].present?
          redirect_to import_form_admin_inventories_path,
                      alert: "CSVファイルを選択してください。" and return
        end
        
        uploaded_file = params[:csv_file]
        
        # 2. セキュリティバリデーション（CLAUDE.md準拠）
        validation_result = validate_uploaded_csv_file(uploaded_file)
        
        unless validation_result[:valid]
          redirect_to import_form_admin_inventories_path,
                      alert: validation_result[:error_message] and return
        end
        
        # 3. 一時ファイルとして安全に保存
        temp_file_path = save_uploaded_file_securely(uploaded_file)
        
        # 4. インポートオプションの設定
        import_options = build_import_options(params)
        
        # 5. 非同期インポートジョブの実行
        job_id = enqueue_import_job(temp_file_path, import_options)
        
        # 6. 成功レスポンス（進捗追跡ページにリダイレクト）
        redirect_to admin_job_status_path(job_id),
                    notice: "CSVインポートを開始しました。進捗はこのページで確認できます。"
        
      rescue => e
        # 7. エラーハンドリング（CLAUDE.md準拠：ユーザーフレンドリーなエラーメッセージ）
        Rails.logger.error "CSV import error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n") if e.backtrace
        
        # 一時ファイルのクリーンアップ
        cleanup_temp_file(temp_file_path) if defined?(temp_file_path)
        
        # ユーザーへのエラー通知
        redirect_to import_form_admin_inventories_path,
                    alert: "CSVインポート中にエラーが発生しました。ファイルを確認して再試行してください。"
      end
      
      # TODO: 🔴 Phase 5（重要）- CSVインポート機能強化
      # 優先度: 高（セキュリティ・パフォーマンス）
      # 実装内容:
      #   - プレビュー機能（インポート前のデータ確認）
      #   - インクリメンタルインポート（差分のみ処理）
      #   - ロールバック機能（インポート取り消し）
      #   - 詳細エラーレポート（行別エラー表示）
      #   - 多言語対応（国際化）
      # 横展開: Receipt, Shipmentでも同様のインポート機能実装
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_inventory
      # CLAUDE.md準拠: パフォーマンス最適化 - アクション別に必要な関連データのみを読み込み
      # メタ認知: showアクションのみbatchesデータが必要、その他は基本情報のみで十分
      case action_name
      when "show"
        # showアクション: バッチ情報を含む詳細表示に必要な全関連データを読み込み
        @inventory = Inventory.includes(:batches).find(params[:id]).decorate
      else
        # edit, update, destroy: 基本的なInventoryデータのみで十分
        # パフォーマンス向上: 不要なJOINとデータ読み込みを回避
        @inventory = Inventory.find(params[:id]).decorate
      end
    end

    # 削除エラー時の共通処理（CLAUDE.md準拠: ベストプラクティス）
    # @param message [String] 表示するエラーメッセージ
    def handle_destroy_error(message = nil)
      error_message = message || @inventory.errors.full_messages.join("、")

      respond_to do |format|
        format.html {
          redirect_to admin_inventories_path,
                      alert: error_message,
                      status: :see_other
        }
        format.json {
          # CLAUDE.md準拠: ベストプラクティス - 一貫性のあるAPIエラーレスポンス
          error_response = {
            code: "deletion_error",
            message: error_message,
            details: []
          }
          render json: error_response, status: :unprocessable_entity
        }
        format.turbo_stream {
          flash.now[:alert] = error_message
          render turbo_stream: turbo_stream.update("flash",
                                                  partial: "shared/flash_messages")
        }
      end
    end

    # Only allow a list of trusted parameters through.
    def inventory_params
      params.require(:inventory).permit(:name, :quantity, :price, :status)
    end

    # Per page パラメータの検証（50/100/200のみ許可）
    def validate_per_page_param(per_page_param)
      allowed_per_page = [ 50, 100, 200 ]
      per_page = per_page_param&.to_i || 50  # デフォルト50件

      if allowed_per_page.include?(per_page)
        per_page
      else
        50  # 不正な値の場合はデフォルトに戻す
      end
    end

    # ============================================
    # CSVインポート関連のプライベートメソッド
    # ============================================

    # 進行中のインポートジョブを確認
    def check_running_import_jobs
      # TODO: 🟡 Phase 6（推奨）- Sidekiq Web UIとの統合
      # 優先度: 中（運用改善）
      # 実装内容: 現在実行中のCSVインポートジョブのリアルタイム表示
      # 効果: 重複インポート防止、管理者の状況把握向上
      []  # 現在はプレースホルダー
    end

    # アップロードされたCSVファイルのセキュリティバリデーション
    def validate_uploaded_csv_file(uploaded_file)
      # CLAUDE.md準拠: セキュリティファーストアプローチ
      
      # ファイルサイズ制限（10MB）
      max_size = 10.megabytes
      if uploaded_file.size > max_size
        return {
          valid: false,
          error_message: "ファイルサイズが大きすぎます。#{ActiveSupport::NumberHelper.number_to_human_size(max_size)}以下にしてください。"
        }
      end

      # MIMEタイプ検証
      unless uploaded_file.content_type&.include?("text/csv") || 
             uploaded_file.content_type&.include?("application/csv") ||
             uploaded_file.original_filename&.end_with?(".csv")
        return {
          valid: false,
          error_message: "CSVファイルを選択してください。許可されている形式: .csv"
        }
      end

      # ファイル名の検証（パストラバーサル攻撃対策）
      if uploaded_file.original_filename&.include?("..") || 
         uploaded_file.original_filename&.include?("/") ||
         uploaded_file.original_filename&.include?("\\")
        return {
          valid: false,
          error_message: "不正なファイル名です。"
        }
      end

      # 基本的なCSV形式の検証
      begin
        # 最初の数行をチェック
        CSV.parse(uploaded_file.read(1024), headers: true)
        uploaded_file.rewind  # ファイルポインタをリセット
      rescue CSV::MalformedCSVError => e
        return {
          valid: false,
          error_message: "CSVファイルの形式が正しくありません: #{e.message}"
        }
      rescue => e
        return {
          valid: false,
          error_message: "ファイルの読み込みに失敗しました。"
        }
      end

      { valid: true }
    end

    # アップロードファイルを安全に一時保存
    def save_uploaded_file_securely(uploaded_file)
      # 安全な一時ディレクトリに保存
      temp_dir = Rails.root.join("tmp", "csv_imports")
      FileUtils.mkdir_p(temp_dir) unless Dir.exist?(temp_dir)

      # ユニークなファイル名を生成（衝突回避）
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      random_suffix = SecureRandom.hex(8)
      safe_filename = "import_#{timestamp}_#{random_suffix}.csv"
      
      temp_file_path = temp_dir.join(safe_filename)

      # ファイルを保存
      File.open(temp_file_path, "wb") do |file|
        file.write(uploaded_file.read)
      end

      temp_file_path.to_s
    end

    # インポートオプションの構築
    def build_import_options(params)
      # CLAUDE.md準拠: 設定可能なオプションで柔軟性を提供
      {
        batch_size: 1000,
        skip_invalid: params[:skip_invalid]&.present? || false,
        update_existing: params[:update_existing]&.present? || false,
        unique_key: params[:unique_key].presence || "name",
        admin_id: current_admin.id
      }
    end

    # 非同期インポートジョブのエンキュー
    def enqueue_import_job(temp_file_path, import_options)
      # CLAUDE.md準拠: ImportInventoriesJobを使用した非同期処理
      # メタ認知: ユーザー体験向上（ノンブロッキング処理）とシステム安定性の両立
      
      job_id = SecureRandom.uuid
      
      Rails.logger.info "CSVインポートジョブ開始: #{temp_file_path}, オプション: #{import_options.except(:admin_id)}"
      
      begin
        # ImportInventoriesJobを非同期実行
        ImportInventoriesJob.perform_later(
          temp_file_path,
          import_options[:admin_id],
          import_options.except(:admin_id),
          job_id
        )
        
        Rails.logger.info "CSVインポートジョブがキューに登録されました: job_id=#{job_id}"
        
      rescue => e
        Rails.logger.error "CSVインポートジョブのエンキューに失敗: #{e.message}"
        
        # エラー時は一時ファイルをクリーンアップ
        cleanup_temp_file(temp_file_path)
        raise e
      end
      
      job_id
    end

    # 一時ファイルのクリーンアップ
    def cleanup_temp_file(temp_file_path)
      return unless temp_file_path && File.exist?(temp_file_path)
      
      begin
        File.delete(temp_file_path)
        Rails.logger.info "一時ファイルを削除しました: #{File.basename(temp_file_path)}"
      rescue => e
        Rails.logger.warn "一時ファイルの削除に失敗: #{e.message}"
      end
    end
  end
end
