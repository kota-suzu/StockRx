namespace :bootsnap do
  desc "Clear Bootsnap cache"
  task clear: :environment do
    require "bootsnap"
    cache_dir = Rails.root.join("tmp/cache")

    # Bootsnap 1.18.4+では CompileCache::Store クラスが存在しないため、
    # 直接キャッシュディレクトリを操作します
    if Dir.exist?(cache_dir)
      # bootsnap キャッシュファイルをクリア
      Dir.glob(File.join(cache_dir, "bootsnap/**/*.bin")).each do |cache_file|
        File.delete(cache_file) if File.exist?(cache_file)
      end

      # bootsnap-compile-cache ディレクトリをクリア
      bootsnap_cache_dir = File.join(cache_dir, "bootsnap-compile-cache")
      if Dir.exist?(bootsnap_cache_dir)
        Dir.glob(File.join(bootsnap_cache_dir, "**/*")).each do |cache_file|
          File.delete(cache_file) if File.file?(cache_file)
        end
      end
    end

    puts "Bootsnap cache cleared."
  end
end
