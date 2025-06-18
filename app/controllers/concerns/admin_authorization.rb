# frozen_string_literal: true

# Admin Authorization Concern
# ============================================
# CLAUDE.md準拠: 管理者権限チェックの標準化
# 横展開: 全AdminControllersで共通使用
# ============================================
module AdminAuthorization
  extend ActiveSupport::Concern

  # ============================================
  # 権限チェックメソッド
  # ============================================

  private

  # 本部管理者権限チェック
  # 監査ログ、システム全体設定等の最高権限が必要な機能用
  def authorize_headquarters_admin!
    unless current_admin.headquarters_admin?
      redirect_to admin_root_path,
                  alert: "この操作は本部管理者のみ実行可能です。"
    end
  end

  # 店舗管理権限チェック（特定店舗）
  # 店舗情報の編集・削除等の管理機能用
  def authorize_store_management!(store)
    unless can_manage_store?(store)
      redirect_to admin_root_path,
                  alert: "この店舗を管理する権限がありません。"
    end
  end

  # 店舗閲覧権限チェック（特定店舗）
  # 店舗情報の参照機能用
  def authorize_store_view!(store)
    unless can_view_store?(store)
      redirect_to admin_root_path,
                  alert: "この店舗を閲覧する権限がありません。"
    end
  end

  # 移動申請承認権限チェック
  # 店舗間移動の承認・却下機能用
  def authorize_transfer_approval!(transfer)
    unless current_admin.can_approve_transfers?
      redirect_to admin_root_path,
                  alert: "移動申請の承認権限がありません。"
    end
  end

  # 移動申請修正権限チェック
  # 申請内容の変更機能用
  def authorize_transfer_modification!(transfer)
    unless can_modify_transfer?(transfer)
      redirect_to admin_root_path,
                  alert: "この移動申請を修正する権限がありません。"
    end
  end

  # 移動申請取消権限チェック
  # 申請の削除・キャンセル機能用
  def authorize_transfer_cancellation!(transfer)
    unless can_cancel_transfer?(transfer)
      redirect_to admin_root_path,
                  alert: "この移動申請をキャンセルする権限がありません。"
    end
  end

  # 監査ログアクセス権限チェック
  # セキュリティ監査機能用（最高権限のみ）
  def authorize_audit_log_access!
    unless current_admin.headquarters_admin?
      redirect_to admin_root_path,
                  alert: "監査ログへのアクセス権限がありません。本部管理者権限が必要です。"
    end
  end

  # マルチストア権限チェック
  # 複数店舗管理機能用
  def ensure_multi_store_permissions
    unless current_admin.can_access_all_stores?
      redirect_to admin_root_path,
                  alert: "マルチストア機能へのアクセス権限がありません。"
    end
  end

  # ============================================
  # 権限判定ヘルパーメソッド
  # ============================================

  # 店舗管理可否判定
  def can_manage_store?(store)
    current_admin.can_manage_store?(store)
  end

  # 店舗閲覧可否判定
  def can_view_store?(store)
    current_admin.can_view_store?(store)
  end

  # 移動申請修正可否判定
  def can_modify_transfer?(transfer)
    return true if current_admin.headquarters_admin?
    return false unless transfer.pending? || transfer.approved?

    # 申請者本人または移動元店舗の管理者のみ修正可能
    transfer.requested_by == current_admin ||
      (current_admin.store_manager? && transfer.source_store == current_admin.store)
  end

  # 移動申請取消可否判定
  def can_cancel_transfer?(transfer)
    return true if current_admin.headquarters_admin?
    return false unless transfer.can_be_cancelled?

    # 申請者本人のみキャンセル可能
    transfer.requested_by == current_admin
  end

  # 在庫ログアクセス権限判定
  def can_access_inventory_logs?(inventory = nil)
    return true if current_admin.headquarters_admin?

    # 店舗スタッフは自店舗の在庫ログのみアクセス可能
    return false unless current_admin.store_id.present?

    if inventory.present?
      inventory.store_inventories.exists?(store_id: current_admin.store_id)
    else
      true # 自店舗のログ全般はアクセス可能
    end
  end
end

# ============================================
# TODO: 🟡 Phase 4 - 役割階層の将来拡張（設計文書）
# ============================================
# 優先度: 低（長期ロードマップ）
# 
# 【現在の役割システム】
# - store_user: 店舗一般ユーザー
# - pharmacist: 薬剤師
# - store_manager: 店舗管理者
# - headquarters_admin: 本部管理者
#
# 【将来の拡張案】
# 1. 🔮 地域管理者 (regional_manager)
#    - 複数店舗の管理権限
#    - 地域レベルの分析・レポート
#
# 2. 🔮 システム管理者 (system_admin)
#    - システム設定・メンテナンス
#    - ユーザー管理・権限設定
#
# 3. 🔮 監査役 (auditor)
#    - 読み取り専用の監査権限
#    - コンプライアンス・監査ログ専用
#
# 4. 🔮 API管理者 (api_manager)
#    - 外部API連携管理
#    - システム間連携設定
#
# 【実装時の考慮事項】
# - 既存権限への後方互換性維持
# - データベースマイグレーション計画
# - UIでの権限表示・管理
# - テストケースの拡張
#
# 【メタ認知ポイント】
# - 役割追加時は本concernの全メソッド見直し必須
# - Admin modelの権限メソッド群も同期更新
# - フロントエンド権限制御も連動更新
#
# ============================================