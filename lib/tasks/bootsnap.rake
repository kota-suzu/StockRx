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

    # 一度Bootsnapの無効化を試みる（可能であれば）
    if defined?(Bootsnap) && Bootsnap.respond_to?(:unload)
      puts "Unloading Bootsnap..."
      Bootsnap.unload rescue nil
    end

    # キャッシュディレクトリの処理
    puts "Removing all Bootsnap cache files..."
    bootsnap_dirs.each do |dir|
      target_dir = File.join(cache_dir, dir)
      if Dir.exist?(target_dir)
        puts "Clearing #{target_dir}..."
        # ディレクトリ内の全ファイルを削除
        FileUtils.rm_rf(target_dir) rescue nil
        # ディレクトリを再作成して権限を設定
        FileUtils.mkdir_p(target_dir) rescue nil
        FileUtils.chmod(0777, target_dir) rescue nil
      end
    end

    # Rails 7.2向けの追加対応：restart.txtの作成
    restart_file = Rails.root.join("tmp/restart.txt")
    FileUtils.touch(restart_file) if defined?(FileUtils)

    # Zeitwerkの再起動をサポート
    if defined?(Rails.autoloaders)
      if Rails.autoloaders.respond_to?(:main)
        puts "Reloading Zeitwerk autoloader..."
        Rails.autoloaders.main.reload rescue nil
      end
    end

    puts "Bootsnap cache cleared. Application restart recommended."

    # TODO: 2025年7月リリース後にRails 7.3以降の対応を追加
    # Zeitwerk 3.0以降とBootsnap 2.0以降の互換性向上対応
  end
end
