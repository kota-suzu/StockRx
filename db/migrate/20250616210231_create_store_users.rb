# frozen_string_literal: true

class CreateStoreUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :store_users do |t|
      # 所属店舗（必須）
      t.references :store, null: false, foreign_key: true

      # Devise認証フィールド
      t.string :email, null: false
      t.string :encrypted_password, null: false

      # 役割（staff: 一般スタッフ, manager: 店舗マネージャー）
      t.string :role, null: false, default: 'staff'
      t.boolean :active, null: false, default: true

      # Deviseトラッキングフィールド
      t.datetime :last_sign_in_at
      t.datetime :current_sign_in_at
      t.string :last_sign_in_ip
      t.string :current_sign_in_ip
      t.integer :sign_in_count, default: 0, null: false

      # Deviseロック機能
      t.integer :failed_attempts, default: 0, null: false
      t.datetime :locked_at
      t.string :unlock_token

      # Deviseパスワードリセット
      t.string :reset_password_token
      t.datetime :reset_password_sent_at

      # Devise記憶機能
      t.datetime :remember_created_at

      # 追加のセキュリティフィールド
      t.string :name, null: false
      t.string :employee_code  # 従業員コード（オプション）
      t.datetime :password_changed_at  # パスワード有効期限管理用
      t.boolean :must_change_password, default: false, null: false

      t.timestamps
    end

    # インデックス設定（パフォーマンスとセキュリティ考慮）
    add_index :store_users, :email
    add_index :store_users, [ :store_id, :email ], unique: true  # 店舗内でのメール一意性
    add_index :store_users, :reset_password_token, unique: true
    add_index :store_users, :unlock_token, unique: true
    add_index :store_users, [ :store_id, :employee_code ], unique: true, where: "employee_code IS NOT NULL"
    add_index :store_users, :role
    add_index :store_users, :active
  end
end
