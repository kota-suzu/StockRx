# frozen_string_literal: true

# 機密情報対応ログフォーマッター
# ============================================
# QAレビュー指摘事項対応: Critical Issue #2
# ログでの機密情報マスキング完全実装
# Rails標準ログフォーマッターの拡張
# ============================================
class SensitiveLogFormatter < ActiveSupport::Logger::SimpleFormatter
  def initialize
    super
    @tags = []
  end

  # フォーマット処理（機密情報フィルタリング付き）
  def call(severity, time, progname, msg)
    # 機密情報をフィルタリング
    filtered_msg = SensitiveDataFilter.filter_log_message(msg.to_s)

    # 標準フォーマットを適用
    super(severity, time, progname, filtered_msg)
  end

  # Tagged logging support methods
  def push_tags(*tags)
    @tags.concat(tags.flatten)
  end

  def pop_tags(count = 1)
    @tags.pop(count)
  end

  def clear_tags!
    @tags.clear
  end

  def current_tags
    @tags.dup
  end

  # Tagged logging compatibility for Rails 8
  def tagged(*tags)
    push_tags(*tags)
    yield
  ensure
    pop_tags(tags.size)
  end

  private

  def tags_text
    return "" if @tags.empty?
    "[#{@tags.join("][")}] "
  end
end
