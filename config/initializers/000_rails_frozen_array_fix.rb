# Rails 7.2での凍結配列問題対策
# このイニシャライザはRailsのconfig配列が凍結されることによるエラーを防止します

# Rails設定でよく使われる配列を安全に変更するためのモンキーパッチ
module SafeArrayOperations
  def safe_append(config_name, value)
    current_value = Rails.application.config.send(config_name)
    if current_value.frozen?
      # 凍結されている場合は新しい配列を作成して代入
      Rails.application.config.send("#{config_name}=", current_value + Array(value))
    else
      # 凍結されていない場合は従来通り追加
      current_value += Array(value)
    end
  end
end

# Railsの初期化中にパスを追加する場合のセーフガード
module Rails
  class Engine
    class << self
      alias_method :original_paths, :paths

      def paths
        @paths ||= begin
          paths = original_paths
          # パスコレクションのデフォルトが凍結されているかチェック
          if paths.default.frozen?
            # 安全なコピーを作成
            new_default = paths.default.dup
            paths.instance_variable_set(:@default, new_default)
          end
          paths
        end
      end
    end
  end

  class Application
    # configオブジェクトを安全に扱うためのメソッドを追加
    def self.safe_config
      @safe_config ||= begin
        # 既存の設定をラップしたセーフバージョンを返す
        config = Rails.application.config
        # SafeArrayOperationsをextendして安全なメソッドを追加
        config.extend(SafeArrayOperations)
        config
      end
    end
  end
end

# 明示的なパッチ適用：凍結された配列を安全に扱うためのパッチ
module ArrayFreezeGuard
  def unshift(*args)
    # 凍結されている場合は、新しい配列を作成して処理
    if frozen?
      self.class.new(args + to_a)
    else
      super
    end
  end

  def <<(obj)
    # 凍結されている場合は、新しい配列を作成して処理
    if frozen?
      self.class.new(to_a + [ obj ])
    else
      super
    end
  end
end

# 初期化時に明示的に対応
if Rails.env.test? || Rails.env.development?
  puts "Rails 7.2用の凍結配列対策を有効化しています..."

  # autoload_pathsが凍結されていれば安全なコピーを作成
  if Rails.application.config.autoload_paths.frozen?
    Rails.application.config.autoload_paths = Rails.application.config.autoload_paths.dup
  end

  # eager_load_pathsが凍結されていれば安全なコピーを作成
  if Rails.application.config.eager_load_paths.frozen?
    Rails.application.config.eager_load_paths = Rails.application.config.eager_load_paths.dup
  end

  # 全ての初期化ファイルが機能する前に凍結配列対策を実施
  begin
    # パッチ適用を試みる
    Array.include(ArrayFreezeGuard) unless Array.included_modules.include?(ArrayFreezeGuard)
  rescue => e
    # エラーが発生しても処理を継続
    Rails.logger.error "凍結配列対策の適用に失敗しました: #{e.message}"
  end
end
