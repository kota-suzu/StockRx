# Rails 7.2 凍結配列問題対策 (シンプル版)
# 
# このファイルは、Rails 7.2で導入された配列の凍結による問題を回避するための
# 最小限の対策を提供します。複雑なモンキーパッチを避け、必要な部分だけを
# 安全に修正します。

# 環境変数で有効化を制御
if ENV['RAILS_AVOID_FREEZING_ARRAYS'] == 'true' || ENV['RAILS_AVOID_FREEZING_ARRAYS'] == '1'
  begin
    puts "Rails 7.2用の凍結配列対策（シンプル版）を適用します..."

    # autoload_pathsの凍結対策
    if Rails.application.config.autoload_paths.frozen?
      puts "- autoload_paths の凍結を解除します"
      Rails.application.config.autoload_paths = Rails.application.config.autoload_paths.dup
    end

    # eager_load_pathsの凍結対策
    if Rails.application.config.eager_load_paths.frozen?
      puts "- eager_load_paths の凍結を解除します"
      Rails.application.config.eager_load_paths = Rails.application.config.eager_load_paths.dup
    end

    # helpers_pathsの凍結対策
    if Rails.application.config.respond_to?(:helpers_paths) && 
       Rails.application.config.helpers_paths.frozen?
      puts "- helpers_paths の凍結を解除します"
      Rails.application.config.helpers_paths = Rails.application.config.helpers_paths.dup
    end

    puts "凍結配列対策の適用が完了しました"
  rescue => e
    puts "凍結配列対策の適用中にエラーが発生しました: #{e.message}"
  end
end

# Rails 8.0対応のためのTODO:
# このファイルはRails 7.2での一時的な対策です。
# Rails 8.0へのアップグレード時には、アプリケーション内の配列操作を
# 非破壊的な方法（+=演算子の使用など）に修正し、この初期化ファイルを削除してください。
