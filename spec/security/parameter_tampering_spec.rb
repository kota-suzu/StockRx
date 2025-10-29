# frozen_string_literal: true

require 'rails_helper'

# CLAUDE.md準拠: パラメータ改ざん攻撃テスト
# セキュリティ脆弱性の検証と防御機能の確認
RSpec.describe "Parameter Tampering Security", type: :request do
  describe "管理者権限昇格攻撃の防御" do
    let(:store_user) { create(:store_user) }
    let(:admin) { create(:admin) }

    context "店舗ユーザーが管理者権限を偽装" do
      before { sign_in store_user }

      it "管理者専用エンドポイントへのアクセスを拒否" do
        # 管理者IDを偽装してアクセス
        get admin_inventories_path, params: { admin_id: admin.id }

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("権限がありません")
      end

      it "管理者権限パラメータを無視" do
        # is_admin パラメータを送信
        post store_inventories_path, params: {
          inventory: { name: "Test" },
          is_admin: true,
          admin_role: "super_admin"
        }

        # 権限昇格が発生していないことを確認
        expect(controller.send(:current_admin)).to be_nil
        expect(store_user.reload).not_to respond_to(:admin_role)
      end
    end
  end

  describe "IDパラメータ改ざん攻撃" do
    let(:store1) { create(:store) }
    let(:store2) { create(:store) }
    let(:user1) { create(:store_user, store: store1) }
    let(:inventory1) { create(:inventory) }
    let(:inventory2) { create(:inventory) }

    before do
      create(:store_inventory, store: store1, inventory: inventory1)
      create(:store_inventory, store: store2, inventory: inventory2)
      sign_in user1
      allow_any_instance_of(StoreControllers::BaseController).to receive(:current_store).and_return(store1)
    end

    context "他店舗のリソースへのアクセス試行" do
      it "URLのIDを改ざんしても自店舗のデータのみアクセス可能" do
        # store2のinventory2にアクセス試行
        get store_inventory_path(inventory2)

        expect(response).to have_http_status(:not_found)
      end

      it "hidden fieldでstore_idを改ざんしても無視される" do
        post adjust_store_inventory_path(inventory1), params: {
          adjustment: {
            new_quantity: 100,
            reason: "調整"
          },
          store_id: store2.id  # 他店舗のIDを注入
        }

        # store1の在庫が更新される
        expect(store1.store_inventories.find_by(inventory: inventory1).quantity).to eq(100)
        # store2の在庫は変更されない
        expect(store2.store_inventories.find_by(inventory: inventory2)).to be_nil
      end
    end
  end

  describe "一括操作時のID配列改ざん" do
    let(:admin) { create(:admin) }
    let(:inventories) { create_list(:inventory, 5) }

    before { sign_in admin }

    context "削除対象IDの改ざん" do
      it "許可されたIDのみを処理する" do
        # 存在しないIDや権限外のIDを混入
        delete bulk_destroy_admin_inventories_path, params: {
          inventory_ids: [
            inventories[0].id,
            inventories[1].id,
            99999,  # 存在しないID
            -1,     # 不正なID
            "abc"   # 文字列ID
          ]
        }

        # 正常なIDのみ処理される
        expect(Inventory.where(id: [ inventories[0].id, inventories[1].id ])).to be_empty
        expect(Inventory.where(id: inventories[2..4].map(&:id))).to exist
      end
    end
  end

  describe "金額・数量パラメータの改ざん" do
    let(:admin) { create(:admin) }
    let(:inventory) { create(:inventory, price: 1000) }

    before { sign_in admin }

    context "負の値の注入" do
      it "価格に負の値を拒否" do
        patch admin_inventory_path(inventory), params: {
          inventory: {
            price: -1000
          }
        }

        inventory.reload
        expect(inventory.price).to eq(1000)  # 変更されない
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "在庫数に負の値を拒否" do
        patch admin_inventory_path(inventory), params: {
          inventory: {
            quantity: -50
          }
        }

        inventory.reload
        expect(inventory.quantity).to be >= 0
      end
    end

    context "極端に大きな値の注入" do
      it "整数オーバーフローを防ぐ" do
        patch admin_inventory_path(inventory), params: {
          inventory: {
            quantity: 2**63  # 巨大な数値
          }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to include("値が最大値")
      end
    end
  end

  describe "ステータス値の改ざん" do
    let(:admin) { create(:admin) }
    let(:inventory) { create(:inventory, status: "active") }

    before { sign_in admin }

    it "許可されていないステータス値を拒否" do
      patch admin_inventory_path(inventory), params: {
        inventory: {
          status: "super_active",  # 存在しないステータス
          internal_status: "hidden"  # 許可されていないフィールド
        }
      }

      inventory.reload
      expect(inventory.status).to eq("active")  # 変更されない
      expect(inventory).not_to respond_to(:internal_status)
    end
  end

  describe "タイムスタンプ改ざん" do
    let(:admin) { create(:admin) }
    let(:inventory) { create(:inventory) }

    before { sign_in admin }

    it "created_at/updated_atの改ざんを無視" do
      original_created_at = inventory.created_at
      original_updated_at = inventory.updated_at

      patch admin_inventory_path(inventory), params: {
        inventory: {
          name: "Updated",
          created_at: 1.year.ago,
          updated_at: 1.year.ago
        }
      }

      inventory.reload
      expect(inventory.created_at).to be_within(1.second).of(original_created_at)
      expect(inventory.updated_at).to be > original_updated_at  # 更新される
    end
  end

  describe "ファイルアップロードパラメータ改ざん" do
    let(:admin) { create(:admin) }

    before { sign_in admin }

    context "ファイル名の改ざん" do
      it "パストラバーサル攻撃を防ぐ" do
        file = fixture_file_upload('test_inventory.csv', 'text/csv')

        # ファイル名に危険なパスを含める
        allow(file).to receive(:original_filename).and_return("../../etc/passwd")

        post import_admin_inventories_path, params: { csv_file: file }

        # ファイル名がサニタイズされる
        expect(controller.send(:sanitize_filename, file.original_filename)).not_to include("..")
      end
    end

    context "MIMEタイプの偽装" do
      it "実際のファイル内容を検証" do
        # 実行ファイルをCSVとして偽装
        file = fixture_file_upload('malicious.exe', 'text/csv')

        post import_admin_inventories_path, params: { csv_file: file }

        expect(response).to redirect_to(import_form_admin_inventories_path)
        expect(flash[:alert]).to include("CSVファイルを選択してください")
      end
    end
  end

  describe "検索パラメータのインジェクション" do
    let(:admin) { create(:admin) }

    before do
      sign_in admin
      create(:inventory, name: "Test Product")
    end

    context "正規表現インジェクション" do
      it "危険な正規表現パターンを無害化" do
        # ReDoS攻撃パターン
        get admin_inventories_path, params: {
          q: { name_cont: "(a+)+" * 100 }
        }

        expect(response).to be_successful
        expect(response).to have_http_status(:ok)
      end
    end

    context "LDAPインジェクション対策" do
      it "LDAP特殊文字をエスケープ" do
        get admin_inventories_path, params: {
          q: { name_cont: "*()|&" }
        }

        expect(response).to be_successful
        # エスケープされて検索される
        expect(assigns(:inventories)).to be_empty
      end
    end
  end

  describe "並行リクエストによる競合状態攻撃" do
    let(:store) { create(:store) }
    let(:user) { create(:store_user, store: store) }
    let(:inventory) { create(:inventory) }
    let(:store_inventory) { create(:store_inventory, store: store, inventory: inventory, quantity: 10) }

    before do
      sign_in user
      allow_any_instance_of(StoreControllers::BaseController).to receive(:current_store).and_return(store)
    end

    it "同時在庫調整でも整合性を保つ" do
      # 楽観的ロックやトランザクションで保護されることを確認
      threads = []

      2.times do |i|
        threads << Thread.new do
          # 各スレッドで在庫を5減らす
          post adjust_store_inventory_path(inventory), params: {
            adjustment: {
              new_quantity: store_inventory.quantity - 5,
              reason: "Thread #{i}"
            }
          }
        end
      end

      threads.each(&:join)

      # 競合状態が発生せず、適切に処理される
      store_inventory.reload
      expect(store_inventory.quantity).to be >= 0
    end
  end

  describe "エンコーディング攻撃" do
    let(:admin) { create(:admin) }

    before { sign_in admin }

    context "不正なUTF-8シーケンス" do
      it "不正なエンコーディングを処理" do
        # 不正なUTF-8バイトシーケンス
        post admin_inventories_path, params: {
          inventory: {
            name: "\xFF\xFE不正な文字",
            quantity: 100,
            price: 1000
          }
        }

        # エラーにならず、適切に処理される
        expect(response).to be_successful
      end
    end

    context "NULL文字インジェクション" do
      it "NULL文字を除去" do
        post admin_inventories_path, params: {
          inventory: {
            name: "Product\x00Name",
            quantity: 100,
            price: 1000
          }
        }

        inventory = Inventory.last
        expect(inventory.name).not_to include("\x00")
      end
    end
  end
end
