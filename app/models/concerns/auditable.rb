# frozen_string_literal: true

module Auditable
  extend ActiveSupport::Concern

  included do
    has_many :audit_logs, as: :auditable, dependent: :destroy
  end

  # インスタンスメソッド
  
  # 監査ログを記録するメソッド
  def audit_log(action, details = {})
    audit_logs.create!(
      user_id: defined?(Current) && Current.respond_to?(:user) ? Current.user&.id : nil,
      action: action,
      details: details,
      ip_address: defined?(Current) && Current.respond_to?(:ip_address) ? Current.ip_address : nil,
      user_agent: defined?(Current) && Current.respond_to?(:user_agent) ? Current.user_agent : nil
    )
  end
  
  # 操作タイプごとの監査メソッド
  def audit_create(details = {})
    audit_log('create', details)
  end
  
  def audit_update(details = {})
    audit_log('update', details)
  end
  
  def audit_delete(details = {})
    audit_log('delete', details)
  end
  
  def audit_view(details = {})
    audit_log('view', details)
  end
  
  def audit_export(details = {})
    audit_log('export', details)
  end
  
  def audit_import(details = {})
    audit_log('import', details)
  end
  
  def audit_login(details = {})
    audit_log('login', details)
  end
  
  def audit_logout(details = {})
    audit_log('logout', details)
  end
  
  # クラスメソッド
  module ClassMethods
    # ユーザーの監査履歴を取得
    def audit_history(user_id, start_date = nil, end_date = nil)
      query = AuditLog.where(user_id: user_id)
      
      if start_date
        query = query.where('created_at >= ?', start_date.beginning_of_day)
      end
      
      if end_date
        query = query.where('created_at <= ?', end_date.end_of_day)
      end
      
      query.order(created_at: :desc)
    end
    
    # 全ての監査ログをエクスポート
    def export_audit_logs(start_date = nil, end_date = nil)
      query = AuditLog.all
      
      if start_date
        query = query.where('created_at >= ?', start_date.beginning_of_day)
      end
      
      if end_date
        query = query.where('created_at <= ?', end_date.end_of_day)
      end
      
      query.order(created_at: :desc)
    end
  end
end
