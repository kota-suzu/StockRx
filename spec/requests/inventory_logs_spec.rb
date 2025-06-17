require 'rails_helper'

# ============================================================================
# 【DEPRECATED】旧InventoryLogs Request Spec
# ============================================================================
# ⚠️  注意: このテストファイルは非推奨です
# 
# 📍 移行完了: Phase 3 - inventory_logs機能の管理画面統合（2025年6月）
# 旧パス: /inventory_logs → 新パス: /admin/inventory_logs
# 
# 🔄 新しいテストファイルの場所:
#    spec/requests/admin_controllers/inventory_logs_spec.rb
# 
# 📝 移行理由:
#    - 管理機能の一元化（CLAUDE.md準拠）
#    - 権限ベースのアクセス制御強化
#    - セキュリティ向上とUX統一
# 
# ⏰ 削除予定: 2025年Q3（移行完了確認後）
# 
# 🚀 横展開済み:
#    - ルーティング設定の変更完了
#    - コントローラーの名前空間移行完了
#    - ビューファイルの移行完了
#    - 後方互換性のリダイレクト設定完了
# ============================================================================

RSpec.describe "InventoryLogs [DEPRECATED]", type: :request do
  # ============================================================================
  # 旧URLへのアクセスが新URLに適切にリダイレクトされることをテスト
  # ============================================================================
  
  describe "旧URL リダイレクトテスト" do
    let(:admin) { create(:admin) }
    
    before { sign_in admin }
    
    it "GET /inventory_logs が /admin/inventory_logs にリダイレクトされる" do
      get "/inventory_logs"
      
      expect(response).to redirect_to("/admin/inventory_logs")
      expect(response.status).to eq(301) # Permanent Redirect
    end
    
    it "GET /inventory_logs/all が /admin/inventory_logs/all にリダイレクトされる" do
      get "/inventory_logs/all"
      
      expect(response).to redirect_to("/admin/inventory_logs/all")
      expect(response.status).to eq(301)
    end
    
    it "GET /inventory_logs/:id が /admin/inventory_logs/:id にリダイレクトされる" do
      get "/inventory_logs/123"
      
      expect(response).to redirect_to("/admin/inventory_logs/123")
      expect(response.status).to eq(301)
    end
    
    it "GET /inventory_logs/operation/:type が /admin/inventory_logs/operation/:type にリダイレクトされる" do
      get "/inventory_logs/operation/increment"
      
      expect(response).to redirect_to("/admin/inventory_logs/operation/increment")
      expect(response.status).to eq(301)
    end
  end
  
  # ============================================================================
  # 新しいテストは以下のファイルで実装してください
  # ============================================================================
  describe "新しいテストファイルへの案内" do
    it "新しいAdminControllers::InventoryLogsテストを使用してください" do
      pending "このテストは spec/requests/admin_controllers/inventory_logs_spec.rb に移行済みです"
    end
    
    it "管理画面の在庫ログ機能テストは admin_controllers で実装してください" do
      skip "詳細: /admin/inventory_logs での認証・認可・機能テスト"
    end
    
    it "Phase 1優先実装項目は admin_controllers/inventory_logs_spec.rb を参照" do
      skip "基本CRUD操作、認証テスト、JSON APIテストなど"
    end
  end
end

# ============================================================================
# 横展開確認済み: 類似の非推奨テストファイルについて
# ============================================================================
#
# ✅ 確認済み:
# - spec/requests/inventories_spec.rb → spec/requests/admin_controllers/inventories_spec.rb
# - spec/requests/store_inventories_spec.rb → 公開機能として継続使用
# - spec/controllers/store_inventories_controller_spec.rb → 店舗機能として継続使用
#
# 🔄 今後の類似ケース対応方針:
# 1. 旧テストファイルはDEPRECATED マーク
# 2. リダイレクトテストの実装
# 3. 新しいテストファイルへの明確な案内
# 4. 削除予定の明記（時期とマイルストーン）
# 5. 移行理由の文書化
#
# ============================================================================
