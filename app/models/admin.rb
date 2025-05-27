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

  # 将来的に追加したい機能:
  # 1. Userモデルとの連携（ユーザーの作成・管理権限）
  # 2. 2要素認証（devise-two-factor）
  # 3. 権限レベル（admin/super_admin）による機能制限

  private

  # パスワードが必要なケースかどうかを判定
  # Devise内部の同名メソッドをオーバーライド
  def password_required?
    !persisted? || !password.nil? || !password_confirmation.nil?
  end
end
