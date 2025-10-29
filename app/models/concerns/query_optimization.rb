# frozen_string_literal: true

# モデルレベルのクエリ最適化機能
# ============================================
# CLAUDE.md準拠: パフォーマンス最適化 - 効率的なクエリパターン
# メタ認知: モデル全体で一貫したクエリ最適化
# ============================================
module QueryOptimization
  extend ActiveSupport::Concern

  included do
    # デフォルトスコープの最適化（慎重に使用）
    # default_scope { includes(:necessary_association) }

    # スコープ定義
    scope :with_associations, ->(associations) {
      associations.present? ? includes(associations) : all
    }

    scope :optimized_for_index, -> {
      # インデックス画面用の最適化
      select(column_names - unnecessary_columns_for_index)
    }

    scope :optimized_for_show, -> {
      # 詳細画面用の最適化（全カラム・全関連）
      includes(all_associations_for_show)
    }

    scope :recent, ->(limit = 10) {
      order(created_at: :desc).limit(limit)
    }

    scope :by_ids, ->(ids) {
      where(id: ids).index_by(&:id)
    }
  end

  class_methods do
    # 不要なカラムの定義
    def unnecessary_columns_for_index
      # サブクラスでオーバーライド可能
      []
    end

    # 詳細画面で必要な関連
    def all_associations_for_show
      # サブクラスでオーバーライド可能
      reflect_on_all_associations.map(&:name)
    end

    # バッチ更新の最適化
    def update_all_in_batches(updates, batch_size: 1000)
      transaction do
        find_in_batches(batch_size: batch_size) do |batch|
          where(id: batch.map(&:id)).update_all(updates)
        end
      end
    end

    # 効率的な存在チェック
    def exists_with_cache?(id)
      Rails.cache.fetch("#{table_name}/exists/#{id}", expires_in: 1.hour) do
        exists?(id)
      end
    end

    # プリロード付きfind
    def find_with_preload(id, associations = [])
      includes(associations).find(id)
    end

    # 統計情報の取得（キャッシュ付き）
    def cached_stats(cache_key = nil)
      cache_key ||= "#{table_name}/stats/#{Date.current}"

      Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        {
          total_count: count,
          created_today: where(created_at: Date.current.all_day).count,
          updated_today: where(updated_at: Date.current.all_day).count
        }
      end
    end

    # 複雑なクエリのExplain
    def explain_query(scope)
      # CLAUDE.md準拠: 開発環境でのクエリ分析
      return unless Rails.env.development?

      explanation = scope.explain
      Rails.logger.debug("Query Explanation:\n#{explanation}")

      # インデックス未使用の警告
      if explanation.include?("Using filesort") || explanation.include?("Using temporary")
        Rails.logger.warn("Potential performance issue detected in query")
      end

      explanation
    end

    # SQLクエリの最適化提案
    def optimization_suggestions(scope)
      suggestions = []

      # N+1の可能性をチェック
      if scope.to_sql.scan(/LEFT OUTER JOIN/).count > 3
        suggestions << "Consider using preload instead of includes for better performance"
      end

      # 大量データの可能性をチェック
      estimated_count = scope.count
      if estimated_count > 10000
        suggestions << "Consider using find_in_batches for large datasets"
      end

      # インデックスの確認
      if scope.to_sql.include?("WHERE") && !scope.to_sql.include?("INDEX")
        suggestions << "Ensure proper indexes exist for WHERE conditions"
      end

      suggestions
    end
  end

  # インスタンスメソッド

  # 関連データの遅延読み込み
  def load_association_if_needed(association_name)
    # すでに読み込まれている場合はスキップ
    return send(association_name) if association(association_name).loaded?

    # 必要な場合のみ読み込み
    ActiveRecord::Associations::Preloader.new(
      records: [ self ],
      associations: association_name
    ).call

    send(association_name)
  end

  # メモ化パターン
  def memoized_expensive_calculation
    @expensive_calculation ||= begin
      # 重い計算処理
      perform_expensive_calculation
    end
  end

  # キャッシュキーの生成
  def cache_key_with_associations(*associations)
    if associations.any?
      association_stamps = associations.map { |assoc|
        records = send(assoc)
        if records.respond_to?(:maximum)
          records.maximum(:updated_at)&.to_i || 0
        else
          records&.updated_at&.to_i || 0
        end
      }
      "#{cache_key}/associations/#{association_stamps.join('-')}"
    else
      cache_key
    end
  end

  private

  def perform_expensive_calculation
    # 実際の重い計算処理
    # サブクラスでオーバーライド
    nil
  end
end
