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

  # Deviseのデフォルトバリデーション（:validatable）に加えて
  # 独自のパスワード強度チェックを追加（OAuthユーザーは除外）
  validates :password, password_strength: true, if: :password_required_for_validation?

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

  # TODO: 認証・認可関連機能
  # 1. ユーザーモデルの実装（一般スタッフ向け）
  #    - Userモデルの作成と権限管理
  #    - 管理者によるユーザーアカウント管理機能
  # 2. 管理者権限レベルの実装
  #    - admin/super_admin権限区分の追加
  #    - 画面アクセス制御の詳細化
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

  # 表示名を返すメソッド（nameフィールドが実装されるまでの暫定対応）
  def display_name
    # GitHub認証の場合はGitHubユーザー名を使用する可能性があるが、
    # 現在はemailから生成
    email.split("@").first
  end

  # name メソッドをdisplay_nameにエイリアス
  # ビューの互換性のため
  alias_method :name, :display_name

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
      current_sign_in_ip: extract_ip_address(auth)
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
end
