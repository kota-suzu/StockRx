# Rails 7.2.2向けの特別パッチ: 凍結配列問題対策
# このファイルはRails 7.2での凍結配列エラーを解決するための一時的なパッチです
# TODO: Rails 7.3以降にアップグレードした際にはこのファイルは不要になる可能性があります（2025年7月まで保持）

# CI環境で自動的に読み込まれるようにする
if Rails.env.test? && Rails.version.start_with?("7.2")
  puts "Applying Rails 7.2 frozen array patch for CI environment..."

  # Railtieのパスオーバーライド: 凍結配列問題対策
  module Rails
    class Engine
      class << self
        alias_method :original_inherited, :inherited

        def inherited(klass)
          # エンジン初期化時の凍結配列エラーを回避
          begin
            paths = []
            klass.instance_variable_set(:@_all_autoload_paths, paths.dup)
            klass.instance_variable_set(:@_all_load_paths, paths.dup)
            original_inherited(klass)
          rescue => e
            puts "Warning: Rails Engine patch failed: #{e.message}"
            # オリジナルの処理を試す
            original_inherited(klass)
          end
        end
      end
    end
  end

  # Bootsnapのオーバーライド: キャッシュによる凍結配列問題対策
  begin
    module Bootsnap
      class << self
        def setup_with_safety(*args)
          ENV["DISABLE_BOOTSNAP"] = "1" if Rails.env.test?
          setup_without_safety(*args)
        end

        alias_method :setup_without_safety, :setup
        alias_method :setup, :setup_with_safety
      end
    end
  rescue => e
    puts "Warning: Bootsnap patch failed: #{e.message}"
  end
end
