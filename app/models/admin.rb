# frozen_string_literal: true

class Admin < ApplicationRecord
  # :database_authenticatable = メール・パスワード認証
  # :recoverable = パスワードリセット
  # :rememberable = ログイン状態記憶
  # :validatable = メールとパスワードのバリデーション
  # :lockable = ログイン試行回数制限・ロック
  # :timeoutable = 一定時間操作がないセッションをタイムアウト
  # :trackable = ログイン履歴を記録
  devise :database_authenticatable, :recoverable, :rememberable,
         :validatable, :lockable, :timeoutable, :trackable

  # Deviseのデフォルトバリデーション（:validatable）に加えて
  # 独自のパスワード強度チェックを追加
  validates :password, password_strength: true, if: :password_required?

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
  def password_required?
    !persisted? || !password.nil? || !password_confirmation.nil?
  end
end
