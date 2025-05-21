namespace :bootsnap do
  desc "Clear Bootsnap cache"
  task clear: :environment do
    require "bootsnap"
    cache_dir = Rails.root.join("tmp/cache")
    
    # bootsnapのキャッシュをより包括的にクリア
    bootsnap_dirs = [
      "bootsnap",
      "bootsnap-compile-cache",
      "bootsnap-load-path-cache"
    ]
    
    bootsnap_dirs.each do |dir|
      target_dir = File.join(cache_dir, dir)
      if Dir.exist?(target_dir)
        puts "Clearing #{target_dir}..."
        # ディレクトリ内の全ファイルを削除
        Dir.glob(File.join(target_dir, "**/*")).each do |cache_file|
          File.delete(cache_file) if File.file?(cache_file)
        end
      end
    end
    
    # Zeitwerkの再起動をサポート
    if defined?(Rails.autoloaders)
      if Rails.autoloaders.respond_to?(:main)
        puts "Reloading Zeitwerk autoloader..."
        Rails.autoloaders.main.reload rescue nil
      end
    end
    
    # Rails 7.2向けの追加対応
    restart_file = Rails.root.join("tmp/restart.txt")
    FileUtils.touch(restart_file) if defined?(FileUtils)
    
    puts "Bootsnap cache cleared."
  end
end
