# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# 管理者ユーザーのシード
if Admin.count.zero?
  puts 'Creating default admin user...'

  admin = Admin.new(
    email: 'admin@example.com',
    password: 'Password1234!',  # 本番環境では変更すること
    password_confirmation: 'Password1234!',
    role: 'headquarters_admin'  # 本部管理者として作成
  )

  # 保存に失敗した場合はエラーメッセージを表示
  if admin.save
    puts 'Default admin user created successfully!'
  else
    puts 'Failed to create default admin user:'
    puts admin.errors.full_messages.join(', ')
  end
else
  puts 'Admin user already exists, skipping seed.'
end

# 検索機能テスト用の豊富なシードデータ
puts 'Creating inventory items with various conditions...'

# 管理者ユーザーを追加で作成
admin2 = Admin.find_or_create_by!(email: 'admin2@example.com') do |a|
  a.password = 'Password1234!'
  a.password_confirmation = 'Password1234!'
  a.role = 'headquarters_admin'  # 本部管理者として作成
end

admin3 = Admin.find_or_create_by!(email: 'admin3@example.com') do |a|
  a.password = 'Password1234!'
  a.password_confirmation = 'Password1234!'
  a.role = 'headquarters_admin'  # 本部管理者として作成
end

# Current.userを設定（ログ記録のため）
Current.user = Admin.first

# カテゴリごとの商品データ - 医薬品200件を含む充実したデータセット
categories = {
  "医薬品" => [
    # 解熱鎮痛薬
    { name: "アスピリン錠 100mg", price: 1200, quantity: 500, status: "active" },
    { name: "アスピリン腸溶錠 100mg", price: 1300, quantity: 300, status: "active" },
    { name: "パラセタモール錠 500mg", price: 800, quantity: 0, status: "active" },
    { name: "パラセタモール坐剤 200mg", price: 600, quantity: 150, status: "active" },
    { name: "イブプロフェン錠 200mg", price: 1500, quantity: 8, status: "active" },
    { name: "イブプロフェン顆粒 20%", price: 1800, quantity: 75, status: "active" },
    { name: "ロキソプロフェン錠 60mg", price: 1100, quantity: 400, status: "active" },
    { name: "ナプロキセン錠 100mg", price: 1400, quantity: 200, status: "active" },
    { name: "ジクロフェナク錠 25mg", price: 1200, quantity: 180, status: "active" },
    { name: "インドメタシンカプセル 25mg", price: 1600, quantity: 90, status: "active" },

    # 抗生物質
    { name: "アモキシシリンカプセル 250mg", price: 2500, quantity: 200, status: "active" },
    { name: "アモキシシリン細粒 10%", price: 2800, quantity: 120, status: "active" },
    { name: "クラリスロマイシン錠 200mg", price: 3200, quantity: 150, status: "active" },
    { name: "アジスロマイシン錠 250mg", price: 3800, quantity: 80, status: "active" },
    { name: "セフジニルカプセル 100mg", price: 3200, quantity: 150, status: "archived" },
    { name: "セフカペンピボキシル錠 100mg", price: 3600, quantity: 100, status: "active" },
    { name: "レボフロキサシン錠 250mg", price: 4200, quantity: 90, status: "active" },
    { name: "シプロフロキサシン錠 200mg", price: 4000, quantity: 70, status: "active" },
    { name: "ドキシサイクリン錠 100mg", price: 2800, quantity: 110, status: "active" },
    { name: "テトラサイクリン錠 250mg", price: 2600, quantity: 85, status: "active" },

    # 消化器系薬
    { name: "オメプラゾール錠 20mg", price: 2200, quantity: 300, status: "active" },
    { name: "ランソプラゾール錠 15mg", price: 2000, quantity: 280, status: "active" },
    { name: "エソメプラゾール錠 20mg", price: 2400, quantity: 200, status: "active" },
    { name: "ファモチジン錠 20mg", price: 1600, quantity: 350, status: "active" },
    { name: "ドンペリドン錠 10mg", price: 1400, quantity: 250, status: "active" },
    { name: "メトクロプラミド錠 5mg", price: 1200, quantity: 180, status: "active" },
    { name: "ロペラミド錠 1mg", price: 1000, quantity: 200, status: "active" },
    { name: "ビサコジル錠 5mg", price: 800, quantity: 300, status: "active" },
    { name: "センノシド錠 12mg", price: 600, quantity: 400, status: "active" },
    { name: "乳酸菌製剤カプセル", price: 1800, quantity: 150, status: "active" },

    # 循環器系薬
    { name: "アムロジピン錠 5mg", price: 1800, quantity: 400, status: "active" },
    { name: "ニフェジピン徐放錠 20mg", price: 2000, quantity: 300, status: "active" },
    { name: "リシノプリル錠 10mg", price: 2200, quantity: 250, status: "active" },
    { name: "エナラプリル錠 5mg", price: 2000, quantity: 280, status: "active" },
    { name: "ロサルタン錠 50mg", price: 2400, quantity: 200, status: "active" },
    { name: "バルサルタン錠 80mg", price: 2600, quantity: 180, status: "active" },
    { name: "アテノロール錠 50mg", price: 1600, quantity: 220, status: "active" },
    { name: "メトプロロール錠 50mg", price: 1800, quantity: 200, status: "active" },
    { name: "フロセミド錠 40mg", price: 1200, quantity: 300, status: "active" },
    { name: "スピロノラクトン錠 25mg", price: 1400, quantity: 180, status: "active" },

    # 呼吸器系薬
    { name: "サルブタモール錠 2mg", price: 1600, quantity: 200, status: "active" },
    { name: "テオフィリン錠 100mg", price: 1400, quantity: 250, status: "active" },
    { name: "プレドニゾロン錠 5mg", price: 2000, quantity: 300, status: "active" },
    { name: "デキサメタゾン錠 0.5mg", price: 1800, quantity: 150, status: "active" },
    { name: "モンテルカスト錠 10mg", price: 3200, quantity: 100, status: "active" },
    { name: "カルボシステイン錠 250mg", price: 1200, quantity: 400, status: "active" },
    { name: "アンブロキソール錠 15mg", price: 1000, quantity: 350, status: "active" },
    { name: "コデインリン酸塩錠 20mg", price: 1800, quantity: 120, status: "active" },
    { name: "デキストロメトルファン錠 15mg", price: 1200, quantity: 200, status: "active" },
    { name: "グアイフェネシン錠 200mg", price: 1000, quantity: 180, status: "active" },

    # 中枢神経系薬
    { name: "ロラゼパム錠 0.5mg", price: 2200, quantity: 100, status: "active" },
    { name: "ジアゼパム錠 2mg", price: 2000, quantity: 120, status: "active" },
    { name: "アルプラゾラム錠 0.4mg", price: 2400, quantity: 80, status: "active" },
    { name: "ゾルピデム錠 5mg", price: 2600, quantity: 90, status: "active" },
    { name: "トリアゾラム錠 0.25mg", price: 2800, quantity: 70, status: "active" },
    { name: "フルニトラゼパム錠 1mg", price: 3000, quantity: 60, status: "active" },
    { name: "カルバマゼピン錠 200mg", price: 2200, quantity: 150, status: "active" },
    { name: "フェニトイン錠 100mg", price: 2000, quantity: 130, status: "active" },
    { name: "バルプロ酸ナトリウム錠 200mg", price: 2400, quantity: 110, status: "active" },
    { name: "レベチラセタム錠 250mg", price: 3500, quantity: 80, status: "active" },

    # 糖尿病治療薬
    { name: "メトホルミン錠 250mg", price: 1800, quantity: 300, status: "active" },
    { name: "グリクラジド錠 40mg", price: 2000, quantity: 200, status: "active" },
    { name: "グリベンクラミド錠 1.25mg", price: 1600, quantity: 250, status: "active" },
    { name: "インスリン グラルギン 300単位", price: 8000, quantity: 50, status: "active" },
    { name: "インスリン アスパルト 300単位", price: 7500, quantity: 60, status: "active" },
    { name: "シタグリプチン錠 50mg", price: 4200, quantity: 80, status: "active" },
    { name: "エンパグリフロジン錠 10mg", price: 4800, quantity: 70, status: "active" },
    { name: "リナグリプチン錠 5mg", price: 4000, quantity: 90, status: "active" },
    { name: "アカルボース錠 100mg", price: 2800, quantity: 120, status: "active" },
    { name: "ミグリトール錠 50mg", price: 3000, quantity: 100, status: "active" },

    # 精神科薬
    { name: "セルトラリン錠 25mg", price: 3200, quantity: 100, status: "active" },
    { name: "パロキセチン錠 10mg", price: 3000, quantity: 120, status: "active" },
    { name: "フルオキセチン錠 10mg", price: 3400, quantity: 90, status: "active" },
    { name: "エスシタロプラム錠 10mg", price: 3600, quantity: 80, status: "active" },
    { name: "ミルタザピン錠 15mg", price: 3800, quantity: 70, status: "active" },
    { name: "アミトリプチリン錠 10mg", price: 2400, quantity: 150, status: "active" },
    { name: "ハロペリドール錠 1mg", price: 2200, quantity: 100, status: "active" },
    { name: "リスペリドン錠 1mg", price: 3200, quantity: 90, status: "active" },
    { name: "オランザピン錠 2.5mg", price: 4000, quantity: 60, status: "active" },
    { name: "クエチアピン錠 25mg", price: 3600, quantity: 80, status: "active" },

    # 皮膚科薬
    { name: "ベタメタゾン軟膏 0.05%", price: 1800, quantity: 200, status: "active" },
    { name: "ヒドロコルチゾン軟膏 1%", price: 1200, quantity: 300, status: "active" },
    { name: "フルオシノロンアセトニド軟膏", price: 2000, quantity: 150, status: "active" },
    { name: "クロトリマゾール軟膏 1%", price: 1600, quantity: 180, status: "active" },
    { name: "ケトコナゾール軟膏 2%", price: 2200, quantity: 120, status: "active" },
    { name: "ミコナゾール軟膏 1%", price: 1800, quantity: 160, status: "active" },
    { name: "アクリノール液 0.1%", price: 800, quantity: 400, status: "active" },
    { name: "ポビドンヨード液 10%", price: 1000, quantity: 350, status: "active" },
    { name: "白色ワセリン", price: 600, quantity: 500, status: "active" },
    { name: "尿素軟膏 20%", price: 1400, quantity: 200, status: "active" },

    # 眼科薬
    { name: "ラタノプロスト点眼液 0.005%", price: 4200, quantity: 80, status: "active" },
    { name: "ブリモニジン点眼液 0.1%", price: 3800, quantity: 90, status: "active" },
    { name: "チモロール点眼液 0.5%", price: 3200, quantity: 120, status: "active" },
    { name: "フルオロメトロン点眼液 0.1%", price: 2800, quantity: 150, status: "active" },
    { name: "ベタメタゾン点眼液 0.1%", price: 3000, quantity: 130, status: "active" },
    { name: "クロラムフェニコール点眼液", price: 2200, quantity: 180, status: "active" },
    { name: "人工涙液点眼", price: 800, quantity: 400, status: "active" },
    { name: "ヒアルロン酸点眼液 0.1%", price: 1800, quantity: 250, status: "active" },
    { name: "アトロピン点眼液 1%", price: 2000, quantity: 100, status: "active" },
    { name: "トロピカミド点眼液 1%", price: 1600, quantity: 120, status: "active" },

    # 耳鼻科薬
    { name: "オキシメタゾリン点鼻液", price: 1200, quantity: 200, status: "active" },
    { name: "キシロメタゾリン点鼻液", price: 1000, quantity: 250, status: "active" },
    { name: "クロルフェニラミン錠 4mg", price: 800, quantity: 400, status: "active" },
    { name: "ロラタジン錠 10mg", price: 2000, quantity: 200, status: "active" },
    { name: "セチリジン錠 10mg", price: 1800, quantity: 220, status: "active" },
    { name: "フェキソフェナジン錠 60mg", price: 2200, quantity: 180, status: "active" },
    { name: "デスロラタジン錠 5mg", price: 2400, quantity: 150, status: "active" },
    { name: "モンテルカスト顆粒 4mg", price: 3000, quantity: 100, status: "active" },
    { name: "ベクロメタゾン点鼻液", price: 2800, quantity: 120, status: "active" },
    { name: "フルチカゾン点鼻液", price: 3200, quantity: 100, status: "active" },

    # 産婦人科薬
    { name: "エチニルエストラジオール錠", price: 2800, quantity: 100, status: "active" },
    { name: "レボノルゲストレル錠", price: 3200, quantity: 80, status: "active" },
    { name: "プロゲステロン膣座薬", price: 4000, quantity: 60, status: "active" },
    { name: "クロミフェン錠 50mg", price: 3600, quantity: 70, status: "active" },
    { name: "メトロニダゾール膣錠", price: 2400, quantity: 120, status: "active" },
    { name: "ミコナゾール膣錠", price: 2000, quantity: 150, status: "active" },
    { name: "葉酸錠 5mg", price: 1200, quantity: 300, status: "active" },
    { name: "鉄剤錠 100mg", price: 1400, quantity: 250, status: "active" },
    { name: "ドンペリドン坐剤 30mg", price: 1600, quantity: 180, status: "active" },
    { name: "オキシトシン注射液", price: 5000, quantity: 40, status: "active" },

    # 泌尿器科薬
    { name: "タムスロシン錠 0.2mg", price: 2800, quantity: 150, status: "active" },
    { name: "デュタステリド錠 0.5mg", price: 4200, quantity: 80, status: "active" },
    { name: "フィナステリド錠 1mg", price: 3800, quantity: 90, status: "active" },
    { name: "シルデナフィル錠 50mg", price: 5000, quantity: 60, status: "active" },
    { name: "トルテロジン錠 2mg", price: 3200, quantity: 120, status: "active" },
    { name: "ミラベグロン錠 50mg", price: 4000, quantity: 70, status: "active" },
    { name: "アルファカルシドール錠", price: 2400, quantity: 180, status: "active" },
    { name: "炭酸カルシウム錠 500mg", price: 1200, quantity: 300, status: "active" },
    { name: "アロプリノール錠 100mg", price: 1600, quantity: 200, status: "active" },
    { name: "フェブキソスタット錠 10mg", price: 3000, quantity: 100, status: "active" },

    # 小児科薬
    { name: "アセトアミノフェン細粒 20%", price: 1000, quantity: 300, status: "active" },
    { name: "イブプロフェン細粒 20%", price: 1200, quantity: 250, status: "active" },
    { name: "アモキシシリン細粒 10%", price: 2000, quantity: 200, status: "active" },
    { name: "クラリスロマイシン細粒 10%", price: 2400, quantity: 150, status: "active" },
    { name: "セフジニル細粒 10%", price: 2600, quantity: 130, status: "active" },
    { name: "プレドニゾロン細粒 1%", price: 1800, quantity: 180, status: "active" },
    { name: "整腸剤細粒", price: 1400, quantity: 250, status: "active" },
    { name: "ビタミンB1シロップ", price: 1600, quantity: 200, status: "active" },
    { name: "総合感冒薬シロップ", price: 1200, quantity: 300, status: "active" },
    { name: "去痰薬シロップ", price: 1000, quantity: 350, status: "active" },

    # 整形外科薬
    { name: "セレコキシブ錠 100mg", price: 3200, quantity: 120, status: "active" },
    { name: "メロキシカム錠 10mg", price: 2800, quantity: 150, status: "active" },
    { name: "エトドラク錠 200mg", price: 2400, quantity: 180, status: "active" },
    { name: "ジクロフェナクナトリウム錠", price: 2000, quantity: 200, status: "active" },
    { name: "インドメタシン坐剤 25mg", price: 1800, quantity: 150, status: "active" },
    { name: "ケトプロフェンテープ 20mg", price: 2200, quantity: 180, status: "active" },
    { name: "フェルビナクテープ 35mg", price: 2000, quantity: 200, status: "active" },
    { name: "インドメタシンクリーム 1%", price: 1600, quantity: 220, status: "active" },
    { name: "メントール配合外用剤", price: 1200, quantity: 300, status: "active" },
    { name: "温湿布", price: 800, quantity: 400, status: "active" },

    # 外科薬
    { name: "ポビドンヨード軟膏 10%", price: 1800, quantity: 200, status: "active" },
    { name: "ゲンタマイシン軟膏 0.1%", price: 2200, quantity: 150, status: "active" },
    { name: "フラジオマイシン軟膏", price: 2000, quantity: 180, status: "active" },
    { name: "ベタジン軟膏", price: 1600, quantity: 250, status: "active" },
    { name: "メチルプレドニゾロン軟膏", price: 2400, quantity: 120, status: "active" },
    { name: "リドカインゼリー 2%", price: 1400, quantity: 200, status: "active" },
    { name: "止血剤パウダー", price: 3000, quantity: 80, status: "active" },
    { name: "創傷治癒促進剤", price: 2800, quantity: 100, status: "active" },
    { name: "抗真菌クリーム", price: 2200, quantity: 150, status: "active" },
    { name: "抗菌石鹸液", price: 1200, quantity: 300, status: "active" },

    # 漢方薬
    { name: "葛根湯エキス顆粒", price: 2000, quantity: 200, status: "active" },
    { name: "小青竜湯エキス顆粒", price: 2200, quantity: 180, status: "active" },
    { name: "桂枝茯苓丸エキス顆粒", price: 2400, quantity: 150, status: "active" },
    { name: "当帰芍薬散エキス顆粒", price: 2600, quantity: 130, status: "active" },
    { name: "加味逍遙散エキス顆粒", price: 2800, quantity: 120, status: "active" },
    { name: "六君子湯エキス顆粒", price: 2400, quantity: 140, status: "active" },
    { name: "補中益気湯エキス顆粒", price: 2600, quantity: 130, status: "active" },
    { name: "半夏厚朴湯エキス顆粒", price: 2200, quantity: 160, status: "active" },
    { name: "大建中湯エキス顆粒", price: 2400, quantity: 140, status: "active" },
    { name: "真武湯エキス顆粒", price: 2000, quantity: 170, status: "active" }
  ],
  "医療機器" => [
    { name: "血圧計 デジタル式", price: 12000, quantity: 25, status: "active" },
    { name: "体温計 非接触式", price: 8500, quantity: 0, status: "active" },
    { name: "パルスオキシメーター", price: 15000, quantity: 5, status: "active" },
    { name: "聴診器 カーディオロジー", price: 25000, quantity: 12, status: "active" },
    { name: "血糖値測定器", price: 18000, quantity: 0, status: "archived" }
  ],
  "消耗品" => [
    { name: "サージカルマスク 50枚入", price: 500, quantity: 1000, status: "active" },
    { name: "ニトリル手袋 Mサイズ 100枚", price: 1200, quantity: 2000, status: "active" },
    { name: "消毒用アルコール 500ml", price: 800, quantity: 3, status: "active" },
    { name: "ガーゼ 滅菌済み 10cm×10cm", price: 300, quantity: 5000, status: "active" },
    { name: "注射針 23G 100本入", price: 2000, quantity: 0, status: "active" }
  ],
  "サプリメント" => [
    { name: "ビタミンC 1000mg 60錠", price: 2500, quantity: 100, status: "active" },
    { name: "マルチビタミン 90錠", price: 3500, quantity: 80, status: "active" },
    { name: "オメガ3 フィッシュオイル", price: 4200, quantity: 7, status: "active" },
    { name: "プロバイオティクス 30カプセル", price: 3800, quantity: 0, status: "active" },
    { name: "ビタミンD3 5000IU", price: 2800, quantity: 120, status: "archived" }
  ]
}

inventories = []

categories.each_with_index do |(category, items), category_index|
  items.each_with_index do |item_data, item_index|
    # SKU生成（カテゴリ別連番）
    sku = "#{category_index.to_s.rjust(2, '0')}-#{item_index.to_s.rjust(4, '0')}"

    # メーカー名をカテゴリに基づいて設定
    manufacturer = case category
    when "医薬品"
      %w[武田薬品 大塚製薬 アステラス製薬 エーザイ 第一三共 中外製薬 田辺三菱製薬].sample
    when "医療機器"
      %w[オムロン テルモ 日本光電 島津製作所 富士フイルム].sample
    when "消耗品"
      %w[ユニ・チャーム 花王 ライオン 大王製紙 エリエール].sample
    when "サプリメント"
      %w[DHC ファンケル ディアナチュラ ネイチャーメイド 大塚製薬].sample
    else
      "汎用メーカー"
    end

    # 単位を商品名に基づいて設定
    unit = case item_data[:name]
    when /錠|カプセル|坐剤/
      "piece"  # 錠剤は piece として扱う
    when /ml|液|シロップ/
      "ml"
    when /g|軟膏|クリーム|細粒|顆粒/
      "g"
    when /本|注射/
      "bottle"  # 注射は bottle として扱う
    when /袋|包/
      "pack"    # 袋は pack として扱う
    when /個|マスク|手袋/
      "piece"   # 個は piece として扱う
    else
      "piece"
    end

    inventory = Inventory.create!(
      name: item_data[:name],
      sku: sku,
      manufacturer: manufacturer,
      unit: unit,
      price: item_data[:price],
      quantity: item_data[:quantity],
      status: item_data[:status],
      created_at: rand(90).days.ago,
      updated_at: rand(30).days.ago
    )
    inventories << inventory
  end
end

puts "Created #{inventories.count} inventory items"

# バッチ（ロット）情報の追加
puts 'Creating batches with various expiry dates...'

inventories.each do |inventory|
  # アクティブな商品にはバッチを作成
  if inventory.status == "active" && inventory.quantity > 0
    # 複数バッチを持つ商品
    if rand(100) < 50
      # バッチ1: 期限切れ間近
      Batch.create!(
        inventory: inventory,
        lot_code: "LOT#{inventory.id}A#{rand(1000..9999)}",
        quantity: inventory.quantity / 2,
        expires_on: rand(1..30).days.from_now,
        created_at: 2.months.ago
      )

      # バッチ2: 余裕のある期限
      Batch.create!(
        inventory: inventory,
        lot_code: "LOT#{inventory.id}B#{rand(1000..9999)}",
        quantity: inventory.quantity / 2,
        expires_on: rand(60..180).days.from_now,
        created_at: 1.month.ago
      )
    else
      # 単一バッチ
      expiry_date = case rand(100)
      when 0..20 then rand(1..14).days.from_now # 期限切れ間近
      when 21..40 then rand(15..30).days.from_now # やや期限が近い
      when 41..60 then rand(31..90).days.from_now # 通常
      else rand(91..365).days.from_now # 期限に余裕
      end

      Batch.create!(
        inventory: inventory,
        lot_code: "LOT#{inventory.id}#{rand(10000..99999)}",
        quantity: inventory.quantity,
        expires_on: expiry_date,
        created_at: rand(60).days.ago
      )
    end
  end

  # 期限切れバッチも一部作成
  if rand(100) < 20
    Batch.create!(
      inventory: inventory,
      lot_code: "EXPIRED#{inventory.id}#{rand(1000..9999)}",
      quantity: rand(1..10),
      expires_on: rand(1..30).days.ago,
      created_at: 3.months.ago
    )
  end
end

puts "Created batches for inventory items"

# 在庫ログの作成
puts 'Creating inventory logs with various actions...'

inventories.each do |inventory|
  # 各商品に対して複数のログを作成
  rand(3..8).times do
    user = [ Admin.first, admin2, admin3 ].sample
    operation_type = [ "add", "remove", "adjust", "ship", "receive" ].sample

    # 操作タイプに応じて適切な変化量を設定
    current_stock = inventory.quantity || 0 # nilの場合は0とする

    delta = case operation_type
    when "add" then rand(1..50)
    when "remove" then current_stock > 0 ? -rand(1..[ current_stock, 20 ].min) : 0
    when "adjust" then [ -5, -3, -1, 1, 3, 5 ].sample
    when "ship" then current_stock > 0 ? -rand(1..[ current_stock, 10 ].min) : 0
    when "receive" then rand(10..100)
    else 0
    end

    # previous_quantity は current_quantity - delta で計算
    current_quantity = current_stock
    previous_quantity = [ current_quantity - delta, 0 ].max # 0以下にならないように

    InventoryLog.create!(
      inventory: inventory,
      user_id: user.id,
      operation_type: operation_type,
      delta: delta,
      previous_quantity: previous_quantity,
      current_quantity: current_quantity,
      note: [ "定期補充", "緊急対応", "顧客要求", "品質問題", nil ].sample,
      created_at: rand(60).days.ago
    )
  end
end

puts "Created inventory logs"

# 出荷情報の作成
puts 'Creating shipment records...'

# アクティブな商品から出荷を作成
active_inventories = inventories.select { |i| i.status == "active" }
active_inventories.sample(10).each do |inventory|
  rand(1..3).times do
    shipment_status = [ "pending", "processing", "shipped", "delivered", "returned", "cancelled" ].sample

    shipment = Shipment.create!(
      inventory: inventory,
      quantity: rand(1..20),
      destination: [ "東京都千代田区", "大阪府大阪市", "愛知県名古屋市", "北海道札幌市",
                   "福岡県福岡市", "宮城県仙台市", "広島県広島市", "京都府京都市" ].sample,
      shipment_status: shipment_status,
      scheduled_date: case shipment_status
                      when "pending", "processing" then rand(1..14).days.from_now
                      when "shipped" then rand(1..7).days.ago
                      when "delivered", "returned" then rand(7..30).days.ago
                      else Date.current
                      end,
      tracking_number: shipment_status == "shipped" || shipment_status == "delivered" ? "TRACK#{rand(100000..999999)}" : nil,
      notes: [ "特急配送", "通常配送", "冷蔵配送", nil ].sample,
      created_at: rand(30).days.ago
    )
  end
end

puts "Created shipment records"

# 入荷情報の作成
puts 'Creating receipt records...'

inventories.sample(12).each do |inventory|
  rand(1..2).times do
    receipt_status = [ "expected", "partial", "completed", "rejected", "delayed" ].sample
    receipt_date = case receipt_status
    when "expected", "delayed" then rand(1..14).days.from_now
    when "partial", "completed" then rand(1..30).days.ago
    when "rejected" then rand(7..60).days.ago
    else Date.current
    end

    Receipt.create!(
      inventory: inventory,
      quantity: rand(50..500),
      source: [ "Supplier A - 東京", "Supplier B - 大阪", "Supplier C - 名古屋",
               "海外サプライヤー X", "海外サプライヤー Y", "製薬会社直送" ].sample,
      receipt_status: receipt_status,
      receipt_date: receipt_date,
      cost_per_unit: inventory.price * rand(0.5..0.8),
      purchase_order: "PO#{Date.current.strftime('%Y%m')}#{rand(1000..9999)}",
      notes: [ "定期発注", "緊急補充", "新規取引", "品質検査要", nil ].sample,
      created_at: receipt_date || Date.current
    )
  end
end

puts "Created receipt records"

# 監査ログの作成（ポリモーフィック）
puts 'Creating audit logs...'

inventories.each do |inventory|
  # 在庫の監査ログ
  rand(2..5).times do
    AuditLog.create!(
      auditable: inventory,
      user_id: [ Admin.first, admin2, admin3 ].sample.id,
      action: [ "create", "update", "delete" ].sample,
      message: "在庫情報が更新されました",
      details: [ "quantity", "price", "status", "name" ].sample(rand(1..2)).to_json,
      ip_address: [ "192.168.1.#{rand(1..255)}", "10.0.0.#{rand(1..255)}" ].sample,
      user_agent: [ "Mozilla/5.0", "Chrome/91.0", "Safari/14.0" ].sample,
      created_at: rand(90).days.ago
    )
  end
end

# 管理者の監査ログも作成
[ Admin.first, admin2, admin3 ].each do |admin|
  rand(3..6).times do
    AuditLog.create!(
      auditable: admin,
      user_id: [ Admin.first, admin2, admin3 ].sample.id,
      action: [ "login", "logout", "update", "view" ].sample,
      message: "管理者アカウントの操作が実行されました",
      details: [ "last_sign_in_at", "password", "email" ].sample(1).to_json,
      ip_address: [ "192.168.1.#{rand(1..255)}", "10.0.0.#{rand(1..255)}" ].sample,
      user_agent: [ "Mozilla/5.0", "Chrome/91.0", "Safari/14.0" ].sample,
      created_at: rand(30).days.ago
    )
  end
end

puts "Created audit logs"

# 統計情報の表示
puts "\n=== Seed Data Summary ==="
puts "Total Inventories: #{Inventory.count}"
puts "- Active: #{Inventory.active.count}"
puts "- Archived: #{Inventory.archived.count}"
puts "- Out of Stock: #{Inventory.where(quantity: 0).count}"
puts "- Low Stock (≤10): #{Inventory.where('quantity > 0 AND quantity <= 10').count}"
puts "\nTotal Batches: #{Batch.count}"
puts "- Expiring Soon (≤30 days): #{Batch.where('expires_on <= ?', 30.days.from_now).count}"
puts "- Expired: #{Batch.where('expires_on < ?', Date.current).count}"
puts "\nTotal Logs: #{InventoryLog.count}"
puts "Total Shipments: #{Shipment.count}"
puts "Total Receipts: #{Receipt.count}"
puts "Total Audit Logs: #{AuditLog.count}"
puts "\nAdmins: #{Admin.count}"
puts "===================="

puts "\nSeed data created successfully!"
puts "\nYou can now test the advanced search features with:"
puts "- Various inventory statuses (active/archived)"
puts "- Stock levels (out of stock, low stock, in stock)"
puts "- Price ranges (¥300 - ¥25,000)"
puts "- Expiring items (some expire within 14 days)"
puts "- Batch/Lot searches (LOT prefixed codes)"
puts "- Shipment destinations (various Japanese cities)"
puts "- Receipt sources (multiple suppliers)"
puts "- User activity logs (3 different admin users)"
puts "- Date range searches (items created over last 90 days)"

# ============================================
# 🏪 Phase 2: Multi-Store Management Seeds
# ============================================

puts "\n=== Creating Multi-Store Management Data ==="

# 店舗データの作成
puts 'Creating stores...'

stores_data = [
  {
    name: "中央薬局 本店",
    code: "ST001",
    store_type: "pharmacy",
    region: "東京都",
    address: "東京都千代田区丸の内1-1-1",
    phone: "03-1234-5678",
    email: "central@example.com",
    manager_name: "田中太郎",
    active: true
  },
  {
    name: "西口薬局",
    code: "ST002",
    store_type: "pharmacy",
    region: "東京都",
    address: "東京都新宿区西新宿2-2-2",
    phone: "03-2345-6789",
    email: "west@example.com",
    manager_name: "佐藤花子",
    active: true
  },
  {
    name: "南口薬局",
    code: "ST003",
    store_type: "pharmacy",
    region: "東京都",
    address: "東京都渋谷区南平台1-1-1",
    phone: "03-3456-7890",
    email: "south@example.com",
    manager_name: "鈴木一郎",
    active: true
  },
  {
    name: "関西配送センター",
    code: "WH001",
    store_type: "warehouse",
    region: "大阪府",
    address: "大阪府大阪市北区梅田3-3-3",
    phone: "06-1234-5678",
    email: "kansai-warehouse@example.com",
    manager_name: "山田次郎",
    active: true
  },
  {
    name: "東北配送センター",
    code: "WH002",
    store_type: "warehouse",
    region: "宮城県",
    address: "宮城県仙台市青葉区本町1-1-1",
    phone: "022-123-4567",
    email: "tohoku-warehouse@example.com",
    manager_name: "高橋三郎",
    active: true
  },
  {
    name: "本部オフィス",
    code: "HQ001",
    store_type: "headquarters",
    region: "東京都",
    address: "東京都港区赤坂1-1-1",
    phone: "03-9999-0000",
    email: "headquarters@example.com",
    manager_name: "本部管理責任者",
    active: true
  }
]

created_stores = []
stores_data.each do |store_data|
  store = Store.find_or_create_by!(code: store_data[:code]) do |s|
    s.assign_attributes(store_data)
  end
  created_stores << store
  puts "  Created store: #{store.name} (#{store.code})"
end

puts "Created #{created_stores.count} stores"

# 管理者の店舗割り当て更新
puts 'Assigning admins to stores...'

# 既存の管理者を店舗管理者として割り当て
if admin2.headquarters_admin?
  admin2.update!(
    role: 'store_manager',
    store: created_stores.find { |s| s.code == 'ST001' }, # 中央薬局
    name: '田中太郎'
  )
  puts "  Assigned admin2 to #{admin2.store.name} as store manager"
end

if admin3.headquarters_admin?
  admin3.update!(
    role: 'store_manager',
    store: created_stores.find { |s| s.code == 'ST002' }, # 西口薬局
    name: '佐藤花子'
  )
  puts "  Assigned admin3 to #{admin3.store.name} as store manager"
end

# 追加の店舗管理者を作成
additional_admins = [
  {
    email: 'south-manager@example.com',
    name: '鈴木一郎',
    role: 'store_manager',
    store_code: 'ST003'
  },
  {
    email: 'warehouse-kansai@example.com',
    name: '山田次郎',
    role: 'store_manager',
    store_code: 'WH001'
  },
  {
    email: 'warehouse-tohoku@example.com',
    name: '高橋三郎',
    role: 'store_manager',
    store_code: 'WH002'
  }
]

additional_admins.each do |admin_data|
  store = created_stores.find { |s| s.code == admin_data[:store_code] }
  next unless store

  admin = Admin.find_or_create_by!(email: admin_data[:email]) do |a|
    a.password = 'Password1234!'
    a.password_confirmation = 'Password1234!'
    a.role = admin_data[:role]
    a.store = store
    a.name = admin_data[:name]
  end
  puts "  Created admin: #{admin.display_name} for #{store.name}"
end

# 店舗在庫データの作成
puts 'Creating store inventories...'

# 各店舗に在庫を分散配置
created_stores.each do |store|
  next if store.headquarters? # 本部には在庫を配置しない

  # 各在庫アイテムの一部を各店舗に配置
  sample_inventories = inventories.select { |inv| inv.status == 'active' }.sample(rand(10..15))

  sample_inventories.each do |inventory|
    # 倉庫には多めの在庫、薬局には少なめの在庫
    base_quantity = store.warehouse? ? rand(100..500) : rand(5..50)
    reserved_qty = rand(0..base_quantity/4)
    safety_level = base_quantity * 0.2

    store_inventory = StoreInventory.find_or_create_by!(
      store: store,
      inventory: inventory
    ) do |si|
      si.quantity = base_quantity
      si.reserved_quantity = reserved_qty
      si.safety_stock_level = safety_level.to_i
      si.last_updated_at = rand(30).days.ago
    end

    # TODO: 🟡 Phase 3（中）- 店舗在庫の自動補充機能
    # 優先度: 中（運用効率化）
    # 実装内容: 安全在庫レベルを下回った際の自動補充申請
    # 期待効果: 在庫切れリスク軽減、手動管理工数削減
  end

  puts "  Created #{store.store_inventories.count} inventory items for #{store.name}"
end

puts "Created store inventories for all stores"

# 店舗間移動データの作成
puts 'Creating inter-store transfers...'

# 移動申請のサンプルデータ
transfer_scenarios = [
  {
    reason: "低在庫補充のため",
    priority: "urgent",
    status: "pending"
  },
  {
    reason: "緊急在庫要請",
    priority: "emergency",
    status: "approved"
  },
  {
    reason: "定期在庫移動",
    priority: "normal",
    status: "completed"
  },
  {
    reason: "期限切れ間近商品の移動",
    priority: "urgent",
    status: "in_transit"
  },
  {
    reason: "過剰在庫の調整",
    priority: "normal",
    status: "rejected"
  }
]

# ランダムな移動申請を作成
15.times do
  scenario = transfer_scenarios.sample

  # 移動元・移動先をランダム選択（同じ店舗は除外）
  source_store = created_stores.sample
  destination_stores = created_stores.reject { |s| s == source_store || s.headquarters? }
  destination_store = destination_stores.sample

  next unless destination_store

  # 移動元店舗に在庫がある商品をランダム選択
  source_inventories = source_store.store_inventories.joins(:inventory).where(inventories: { status: 'active' })
  source_inventory = source_inventories.sample

  next unless source_inventory

  quantity = rand(1..10)
  available_qty = source_inventory.quantity - source_inventory.reserved_quantity
  next if available_qty < quantity

  requested_by = [ Admin.first, admin2, admin3 ].sample
  approved_by = scenario[:status].in?([ 'approved', 'completed', 'in_transit' ]) ? Admin.first : nil

  requested_at = rand(30).days.ago
  completed_at = scenario[:status] == 'completed' ? requested_at + rand(1..7).days : nil

  transfer = InterStoreTransfer.create!(
    source_store: source_store,
    destination_store: destination_store,
    inventory: source_inventory.inventory,
    quantity: quantity,
    reason: scenario[:reason],
    priority: scenario[:priority],
    status: scenario[:status],
    requested_by: requested_by,
    approved_by: approved_by,
    requested_at: requested_at,
    completed_at: completed_at
  )

  puts "  Created transfer: #{transfer.transfer_summary} (#{transfer.status})"
end

puts "Created inter-store transfer records"

# 統計情報の表示（更新版）
puts "\n=== Multi-Store Management Summary ==="
puts "Total Stores: #{Store.count}"
puts "- Pharmacies: #{Store.pharmacy.count}"
puts "- Warehouses: #{Store.warehouse.count}"
puts "- Headquarters: #{Store.headquarters.count}"
puts "\nTotal Store Inventories: #{StoreInventory.count}"
puts "Total Inter-Store Transfers: #{InterStoreTransfer.count}"
puts "- Pending: #{InterStoreTransfer.pending.count}"
puts "- Approved: #{InterStoreTransfer.approved.count}"
puts "- Completed: #{InterStoreTransfer.completed.count}"
puts "\nAdmins by Role:"
puts "- Headquarters Admins: #{Admin.headquarters.count}"
puts "- Store Managers: #{Admin.where(role: 'store_manager').count}"
puts "- Store Users: #{Admin.where(role: 'store_user').count}"
puts "- Pharmacists: #{Admin.where(role: 'pharmacist').count}"
puts "===================="

# ============================================
# Phase 4: 店舗ユーザーデータの作成
# ============================================
puts "\n=== Creating Store Users ==="

store_users_data = [
  # 中央薬局 本店
  {
    store_code: "ST001",
    users: [
      { name: "山田花子", email: "yamada@central.example.com", role: "manager", employee_code: "EMP001" },
      { name: "鈴木一郎", email: "suzuki@central.example.com", role: "staff", employee_code: "EMP002" }
    ]
  },
  # 西口薬局
  {
    store_code: "ST002",
    users: [
      { name: "佐藤次郎", email: "sato@west.example.com", role: "manager", employee_code: "EMP003" },
      { name: "伊藤美咲", email: "ito@west.example.com", role: "staff", employee_code: "EMP004" }
    ]
  },
  # 東京倉庫
  {
    store_code: "WH001",
    users: [
      { name: "中村健一", email: "nakamura@warehouse.example.com", role: "manager", employee_code: "EMP005" }
    ]
  }
]

store_users_data.each do |store_data|
  store = Store.find_by(code: store_data[:store_code])
  next unless store

  store_data[:users].each do |user_data|
    store_user = StoreUser.find_or_create_by!(
      email: user_data[:email],
      store: store
    ) do |su|
      su.name = user_data[:name]
      su.password = 'StoreUser123!'
      su.password_confirmation = 'StoreUser123!'
      su.role = user_data[:role]
      su.employee_code = user_data[:employee_code]
      su.active = true
      su.password_changed_at = Time.current
    end
    puts "  Created store user: #{store_user.name} (#{store_user.role}) for #{store.name}"
  end
end

puts "\n=== Store Users Summary ==="
puts "Total Store Users: #{StoreUser.count}"
puts "- Managers: #{StoreUser.managers.count}"
puts "- Staff: #{StoreUser.staff.count}"
puts "===================="

puts "\n📌 Test Credentials:"
puts "Admin: admin@example.com / Password1234!"
puts "Store User: yamada@central.example.com / StoreUser123!"
puts "Store Selection: http://localhost:3000/store"
puts "Admin Login: http://localhost:3000/admin/sign_in"

# 最後にCurrent.userをクリア
Current.user = nil
