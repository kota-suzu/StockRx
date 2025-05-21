namespace :bootsnap do
  desc "Clear Bootsnap cache"
  task clear: :environment do
    require "bootsnap"
    cache_dir = Rails.root.join("tmp/cache")
    Bootsnap::CompileCache::Store.new(cache_dir: cache_dir).clear
    puts "Bootsnap cache cleared."
  end
end
