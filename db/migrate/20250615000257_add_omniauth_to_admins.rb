class AddOmniauthToAdmins < ActiveRecord::Migration[8.0]
  def change
    add_column :admins, :provider, :string
    add_column :admins, :uid, :string
<<<<<<< HEAD

    # セキュリティとパフォーマンス向上のためのインデックス追加
    # provider + uid の組み合わせはユニークである必要がある
    add_index :admins, [ :provider, :uid ], unique: true,
              name: 'index_admins_on_provider_and_uid'

    # provider単体でも検索するためのインデックス
    add_index :admins, :provider, name: 'index_admins_on_provider'

=======
    
    # セキュリティとパフォーマンス向上のためのインデックス追加
    # provider + uid の組み合わせはユニークである必要がある
    add_index :admins, [:provider, :uid], unique: true, 
              name: 'index_admins_on_provider_and_uid'
    
    # provider単体でも検索するためのインデックス
    add_index :admins, :provider, name: 'index_admins_on_provider'
    
>>>>>>> a8e5e1a (🟠 Phase 2: Adminモデル拡張完了 - OmniAuth対応)
    # TODO: 🟡 Phase 3（中）- OAuth専用管理者とパスワード認証管理者の共存バリデーション
    # 優先度: 中（OAuth認証フロー実装後）
    # 実装内容: provider/uid必須バリデーションとemail/password任意化の両立
    # 理由: OAuthユーザーはパスワード不要、従来管理者は引き続きパスワード必須
    # 期待効果: 柔軟な認証方式の共存、管理者の利便性向上
    # 工数見積: 1日
    # 依存関係: OAuth認証フロー完成後
  end
end
