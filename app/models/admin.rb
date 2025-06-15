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
         :omniauthable, omniauth_providers: [:github]

  # アソシエーション
  has_many :report_files, dependent: :destroy

  # Deviseのデフォルトバリデーション（:validatable）に加えて
  # 独自のパスワード強度チェックを追加（OAuthユーザーは除外）
  validates :password, password_strength: true, if: :password_required_for_validation?

  # GitHubソーシャルログイン用のクラスメソッド
  # OmniAuthプロバイダーから返される認証情報を処理
  def self.from_omniauth(auth)
    # 既存の管理者を provider + uid で検索
    admin = find_by(provider: auth.provider, uid: auth.uid)
    
    if admin
      # 既存管理者の場合、GitHubの最新情報で更新
      admin.update(
        email: auth.info.email,
        sign_in_count: admin.sign_in_count + 1,
        last_sign_in_at: Time.current,
        current_sign_in_at: Time.current,
        last_sign_in_ip: admin.current_sign_in_ip,
        current_sign_in_ip: auth.extra.raw_info.ip || "127.0.0.1"
      )
    else
      # 新規管理者の場合、GitHubアカウント情報から作成
      admin = new(
        provider: auth.provider,
        uid: auth.uid,
        email: auth.info.email,
        # OAuthユーザーはパスワード認証不要のため、ランダムパスワード設定
        password: Devise.friendly_token[0, 20],
        password_confirmation: Devise.friendly_token[0, 20],
        # トラッキング情報の初期設定
        sign_in_count: 1,
        current_sign_in_at: Time.current,
        last_sign_in_at: Time.current,
        current_sign_in_ip: auth.extra&.raw_info&.ip || "127.0.0.1"
      )
      
      # TODO: 🟡 Phase 3（中）- GitHub管理者の自動承認・権限設定
      # 優先度: 中（セキュリティ要件による）
      # 実装内容: 新規GitHub管理者の自動承認可否、デフォルト権限設定
      # 理由: セキュリティと利便性のバランス、組織のポリシー対応
      # 期待効果: 適切な権限管理による安全な管理者追加
      # 工数見積: 1日
      # 依存関係: 管理者権限レベル機能の設計
      
      admin.save
    end
    
    admin
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

  private

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
