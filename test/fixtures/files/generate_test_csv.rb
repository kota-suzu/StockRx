#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"

# テスト用の大きなCSVファイルを生成するスクリプト
rows = 10_000 # 1万行
output_file = File.join(File.dirname(__FILE__), "large_inventory.csv")

puts "#{rows}行のCSVファイルを生成中..."

CSV.open(output_file, "wb") do |csv|
  # ヘッダー行
  csv << %w[name quantity price status]

  # データ行
  rows.times do |i|
    name = "テスト商品#{i+1}"
    quantity = rand(1..1000)
    price = rand(100..10000)
    status = [ "active", "archived" ].sample

    csv << [ name, quantity, price, status ]
  end
end

file_size = File.size(output_file) / 1024.0 / 1024.0 # MB単位
puts "生成完了: #{output_file} (#{file_size.round(2)} MB)"
