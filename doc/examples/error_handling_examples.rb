# ==============================================================
# StockRx エラーハンドリング実装例
# ==============================================================

# -------------------------------------------
# 例1: ActiveRecordの標準例外を活用したシンプルな実装
# -------------------------------------------

# 変更前: 手動でエラーチェックして404返却
def show
  @inventory = Inventory.find_by(id: params[:id])
  head 404 if @inventory.nil?
  # ...処理...
end

# 変更後: findメソッドの自然な例外をそのまま活用（レスキューは共通モジュールで実装済み）
def show
  @inventory = Inventory.find(params[:id])
  # ...処理...
end

# -------------------------------------------
# 例2: バリデーションエラーの処理（422ステータス）
# -------------------------------------------

# 変更前: バリデーションエラーを手動で処理
def create
  @inventory = Inventory.new(inventory_params)
  if @inventory.save
    redirect_to @inventory, notice: "在庫が作成されました"
  else
    flash.now[:alert] = "入力エラーがあります"
    render :new, status: :unprocessable_entity
  end
end

# 変更後: save!で例外を発生させ、共通エラーハンドラでキャッチ
def create
  @inventory = Inventory.new(inventory_params)
  @inventory.save!  # バリデーションエラーでActiveRecord::RecordInvalidが発生
  redirect_to @inventory, notice: "在庫が作成されました"
end

# コントローラ内で422時の処理をオーバーライドする場合
def create
  @inventory = Inventory.new(inventory_params)
  begin
    @inventory.save!
    redirect_to @inventory, notice: "在庫が作成されました"
  rescue ActiveRecord::RecordInvalid => e
    # 422エラー時に特別な処理が必要な場合はここで処理
    flash.now[:alert] = "入力内容に問題があります"
    render :new, status: :unprocessable_entity
  end
end

# -------------------------------------------
# 例3: カスタムエラーの使用例（409 Conflict）
# -------------------------------------------

# 在庫更新メソッド（競合チェック付き）
def update
  @inventory = Inventory.find(params[:id])

  # バージョンチェック（楽観的ロック）
  if params[:inventory][:lock_version].to_i != @inventory.lock_version
    # 競合発生時はカスタムエラーを発生
    raise CustomError::ResourceConflict.new(
      "他のユーザーがこの在庫を更新しました。最新の情報を確認してください。",
      [ "同時編集が検出されました" ]
    )
  end

  # 更新処理
  @inventory.update!(inventory_params)
  redirect_to @inventory, notice: "在庫が更新されました"
end

# -------------------------------------------
# 例4: API実装でのエラーハンドリング
# -------------------------------------------

module Api
  module V1
    class InventoriesController < ApiController
      # 在庫取得API
      def show
        @inventory = Inventory.find(params[:id])
        render json: @inventory
      end

      # 在庫作成API
      def create
        @inventory = Inventory.new(inventory_params)

        # レート制限チェック（例）
        if rate_limited?
          raise CustomError::RateLimitExceeded.new(
            "短時間に多くのリクエストが行われました",
            [ "#{Time.current.strftime('%H:%M:%S')}から30秒間お待ちください" ]
          )
        end

        @inventory.save!
        render json: @inventory, status: :created
      end

      private

      def rate_limited?
        # 実際の実装ではRedisなどを使ってレート制限をチェック
        false
      end
    end
  end
end

# -------------------------------------------
# 例5: テスト実装例
# -------------------------------------------

# RSpec共通モジュール（spec/support/shared_examples/error_handling.rb）
RSpec.shared_examples "handles not found error" do
  it "returns 404 for non-existent resource" do
    get :show, params: { id: "non-existent-id" }
    expect(response).to have_http_status(:not_found)

    # APIモードの場合はJSONレスポンスも検証
    if request.format.json?
      json = JSON.parse(response.body)
      expect(json["code"]).to eq("resource_not_found")
    end
  end
end

# コントローラテスト例
RSpec.describe InventoriesController, type: :controller do
  describe "GET #show" do
    it_behaves_like "handles not found error"
  end
end
