# frozen_string_literal: true

class Admin < ApplicationRecord
  include Auditable

  # :database_authenticatable = メール・パスワード認証
  # :recoverable = パスワードリセット
  # :rememberable = ログイン状態記憶
  # :validatable = メールとパスワードのバリデーション
  # :lockable = ログイン試行回数制限・ロック
  # :timeoutable = 一定時間操作がないセッションをタイムアウト
  # :trackable = ログイン履歴を記録
  # :omniauthable = OAuthソーシャルログイン（GitHub等）
  devise :database_authenticatable, :recoverable, :rememberable,
         :validatable, :lockable, :timeoutable, :trackable,
         :omniauthable, omniauth_providers: [ :github ]

  # アソシエーション
  has_many :report_files, dependent: :destroy
  belongs_to :store, optional: true

  # 店舗間移動関連
  has_many :requested_transfers, class_name: "InterStoreTransfer", foreign_key: "requested_by_id", dependent: :restrict_with_error
  has_many :approved_transfers, class_name: "InterStoreTransfer", foreign_key: "approved_by_id", dependent: :restrict_with_error

  # ============================================
  # enum定義
  # ============================================
  enum :role, {
    store_user: "store_user",           # 一般店舗ユーザー
    pharmacist: "pharmacist",           # 薬剤師
    store_manager: "store_manager",     # 店舗管理者
    headquarters_admin: "headquarters_admin"  # 本部管理者
  }

  # ============================================
  # バリデーション
  # ============================================
  # Deviseのデフォルトバリデーション（:validatable）に加えて
  # 独自のパスワード強度チェックを追加（OAuthユーザーは除外）
  validates :password, password_strength: true, if: :password_required_for_validation?
  validates :role, presence: true
  validates :name, length: { maximum: 50 }, allow_blank: true
  validate :store_required_for_non_headquarters_admin
  validate :store_must_be_nil_for_headquarters_admin

  # GitHubソーシャルログイン用のクラスメソッド
  # OmniAuthプロバイダーから返される認証情報を処理
  def self.from_omniauth(auth)
    admin = find_by(provider: auth.provider, uid: auth.uid)

    if admin
      update_existing_admin(admin, auth)
    else
      create_new_admin_from_oauth(auth)
    end
  end

  # ============================================
  # 権限システム設計指針（CLAUDE.md準拠）
  # ============================================
  # 
  # 🔒 現在の権限階層（上位→下位）:
  #    headquarters_admin > store_manager > pharmacist > store_user
  #
  # 📋 各権限の責任範囲:
  #    - headquarters_admin: 全店舗管理、監査ログ、システム設定
  #    - store_manager: 担当店舗管理、移動承認、スタッフ管理
  #    - pharmacist: 薬事関連業務、在庫確認、品質管理
  #    - store_user: 基本在庫操作、日常業務
  #
  # ✅ 実装済み権限メソッド:
  #    - headquarters_admin?  # 最高権限（監査ログアクセス可能）
  #    - store_manager?       # 店舗管理権限
  #    - pharmacist?          # 薬剤師権限  
  #    - store_user?          # 基本ユーザー権限
  #    - can_access_all_stores?, can_manage_store?, can_approve_transfers?
  #
  # TODO: 認証・認可関連機能
  # 1. ユーザーモデルの実装（一般スタッフ向け）
  #    - Userモデルの作成と権限管理
  #    - 管理者によるユーザーアカウント管理機能
  # 2. 🟡 Phase 5（将来拡張）- 管理者権限レベルの細分化
  #    - super_admin権限区分の追加（システム設定・緊急対応専用）
  #    - admin権限区分の追加（本部管理者の細分化）
  #    - 画面アクセス制御の詳細化
  #    優先度: 中（現在のheadquarters_adminで要件充足）
  #    実装内容:
  #      - enum roleにsuper_admin, adminを追加
  #      - 権限階層: super_admin > admin > headquarters_admin > store_manager > pharmacist > store_user
  #    横展開: AuditLogsController等で権限チェック拡張
  #    メタ認知: 過度な権限分割を避け、必要時のみ実装（YAGNI原則）
  # 3. 2要素認証の導入
  #    - devise-two-factor gemを利用
  #    - QRコード生成とTOTPワンタイムパスワード

  # TODO: 🟡 Phase 2 - Adminモデルへのnameフィールド追加
  # 優先度: 中（UX改善）
  # 実装内容: nameカラムをadminsテーブルに追加するマイグレーション
  # 理由: ユーザー表示名として適切な名前を表示するため
  # 期待効果: 管理画面でのユーザー識別性向上
  # 工数見積: 1日（マイグレーション + 管理画面での名前入力UI追加）
  # 依存関係: 新規登録・編集画面の更新が必要

  # ============================================
  # スコープ
  # ============================================
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :by_role, ->(role) { where(role: role) }
  scope :by_store, ->(store) { where(store: store) }
  scope :headquarters, -> { where(role: "headquarters_admin") }
  scope :store_staff, -> { where(role: [ "store_user", "pharmacist", "store_manager" ]) }

  # ============================================
  # インスタンスメソッド
  # ============================================

  # 表示名を返すメソッド（nameフィールド実装済み）
  def display_name
    return name if name.present?

    # nameが未設定の場合はemailから生成（後方互換性）
    email.split("@").first
  end

  # 役割の日本語表示
  def role_text
    case role
    when "store_user" then "店舗ユーザー"
    when "pharmacist" then "薬剤師"
    when "store_manager" then "店舗管理者"
    when "headquarters_admin" then "本部管理者"
    end
  end

  # 権限チェック用メソッド
  def can_access_all_stores?
    headquarters_admin?
  end

  def can_manage_store?(target_store)
    return true if headquarters_admin?
    return false unless store_manager?

    store == target_store
  end

  def can_approve_transfers?
    store_manager? || headquarters_admin?
  end

  def can_view_store?(target_store)
    return true if headquarters_admin?

    store == target_store
  end

  # アクセス可能な店舗IDのリスト
  def accessible_store_ids
    if headquarters_admin?
      Store.active.pluck(:id)
    else
      store_id ? [ store_id ] : []
    end
  end

  # 管理可能な店舗のリスト
  def manageable_stores
    if headquarters_admin?
      Store.active
    elsif store_manager? && store
      [ store ]
    else
      []
    end
  end

  private

  # 既存管理者の情報をOAuthデータで更新
  def self.update_existing_admin(admin, auth)
    admin.update(
      email: auth.info.email,
      sign_in_count: admin.sign_in_count + 1,
      last_sign_in_at: Time.current,
      current_sign_in_at: Time.current,
      last_sign_in_ip: admin.current_sign_in_ip,
      current_sign_in_ip: extract_ip_address(auth)
    )
    admin
  end

  # 新規管理者をOAuthデータから作成
  def self.create_new_admin_from_oauth(auth)
    generated_password = Devise.friendly_token[0, 20]

    admin = new(
      provider: auth.provider,
      uid: auth.uid,
      email: auth.info.email,
      # OAuthユーザーはパスワード認証不要のため、ランダムパスワード設定
      password: generated_password,
      password_confirmation: generated_password,
      # トラッキング情報の初期設定
      sign_in_count: 1,
      current_sign_in_at: Time.current,
      last_sign_in_at: Time.current,
      current_sign_in_ip: extract_ip_address(auth),
      # TODO: GitHub認証ユーザーのデフォルト権限を本部管理者に設定
      # Phase 3で組織のポリシーに基づいて変更予定
      role: "headquarters_admin"
    )

    # TODO: 🟡 Phase 3（中）- GitHub管理者の自動承認・権限設定
    # 優先度: 中（セキュリティ要件による）
    # 実装内容: 新規GitHub管理者の自動承認可否、デフォルト権限設定
    # 理由: セキュリティと利便性のバランス、組織のポリシー対応
    # 期待効果: 適切な権限管理による安全な管理者追加
    # 工数見積: 1日
    # 依存関係: 管理者権限レベル機能の設計

    admin.save
    admin
  end

  # OAuthデータから安全にIPアドレスを取得
  def self.extract_ip_address(auth)
    auth.extra&.raw_info&.ip || "127.0.0.1"
  end

  # パスワードが必要なケースかどうかを判定
  # Devise内部の同名メソッドをオーバーライド
  # OAuthユーザー（provider/uidが存在）の場合はパスワード不要
  def password_required?
    return false if provider.present? && uid.present?
    !persisted? || !password.nil? || !password_confirmation.nil?
  end

  # パスワード強度バリデーション用の判定メソッド
  # OAuthユーザーはパスワード強度チェック不要
  def password_required_for_validation?
    return false if provider.present? && uid.present?
    password_required?
  end

  # 本部管理者以外は店舗が必須
  def store_required_for_non_headquarters_admin
    return if headquarters_admin?

    if store_id.blank?
      errors.add(:store, "本部管理者以外は店舗の指定が必要です")
    end
  end

  # 本部管理者は店舗を指定できない
  def store_must_be_nil_for_headquarters_admin
    return unless headquarters_admin?

    if store_id.present?
      errors.add(:store, "本部管理者は特定の店舗に所属できません")
    end
  end
end
