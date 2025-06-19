# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  # ============================================
  # GitHubアイコン生成のテスト
  # ============================================

  describe '#github_icon' do
    it 'デフォルトCSSクラスでSVGアイコンを生成すること' do
      result = helper.github_icon

      expect(result).to include('<svg')
      expect(result).to include('class="github-icon"')
      expect(result).to include('viewBox="0 0 24 24"')
      expect(result).to include('fill="currentColor"')
      expect(result).to include('<path')
    end

    it 'カスタムCSSクラスでSVGアイコンを生成すること' do
      result = helper.github_icon(css_class: "custom-github-icon")

      expect(result).to include('class="custom-github-icon"')
      expect(result).not_to include('class="github-icon"')
    end

    it '適切なGitHubアイコンのパスを含むこと' do
      result = helper.github_icon

      # GitHubアイコンの特徴的なパス要素を確認
      expect(result).to include('M12 0c-6.626 0-12 5.373-12 12')
    end
  end

  # ============================================
  # フラッシュメッセージクラス変換のテスト
  # ============================================

  describe '#flash_class' do
    it 'notice を success に変換すること' do
      expect(helper.flash_class('notice')).to eq('success')
      expect(helper.flash_class(:notice)).to eq('success')
    end

    it 'alert を danger に変換すること' do
      expect(helper.flash_class('alert')).to eq('danger')
      expect(helper.flash_class(:alert)).to eq('danger')
    end

    it 'error を danger に変換すること' do
      expect(helper.flash_class('error')).to eq('danger')
      expect(helper.flash_class(:error)).to eq('danger')
    end

    it 'warning を warning のまま返すこと' do
      expect(helper.flash_class('warning')).to eq('warning')
      expect(helper.flash_class(:warning)).to eq('warning')
    end

    it 'info を info のまま返すこと' do
      expect(helper.flash_class('info')).to eq('info')
      expect(helper.flash_class(:info)).to eq('info')
    end

    it '未知のタイプはそのまま文字列として返すこと' do
      expect(helper.flash_class('custom')).to eq('custom')
      expect(helper.flash_class(:custom)).to eq('custom')
    end
  end

  # ============================================
  # アクティブナビゲーションクラスのテスト
  # ============================================

  describe '#active_class' do
    before do
      # current_page?をモック
      allow(helper).to receive(:current_page?)
    end

    it '現在のページの場合は "active" を返すこと' do
      allow(helper).to receive(:current_page?).with('/test').and_return(true)

      expect(helper.active_class('/test')).to eq('active')
    end

    it '現在のページでない場合は空文字を返すこと' do
      allow(helper).to receive(:current_page?).with('/test').and_return(false)

      expect(helper.active_class('/test')).to eq('')
    end
  end

  # ============================================
  # 監査ログアクション色クラスのテスト
  # ============================================

  describe '#audit_log_action_color' do
    context 'ログイン関連のアクション' do
      it 'login/signup を success として処理すること' do
        expect(helper.audit_log_action_color('login')).to eq('success')
        expect(helper.audit_log_action_color('signup')).to eq('success')
        expect(helper.audit_log_action_color(:login)).to eq('success')
      end

      it 'logout を info として処理すること' do
        expect(helper.audit_log_action_color('logout')).to eq('info')
        expect(helper.audit_log_action_color(:logout)).to eq('info')
      end

      it 'failed_login を danger として処理すること' do
        expect(helper.audit_log_action_color('failed_login')).to eq('danger')
        expect(helper.audit_log_action_color(:failed_login)).to eq('danger')
      end
    end

    context 'CRUD関連のアクション' do
      it 'create を success として処理すること' do
        expect(helper.audit_log_action_color('create')).to eq('success')
      end

      it 'update を warning として処理すること' do
        expect(helper.audit_log_action_color('update')).to eq('warning')
      end

      it 'delete/destroy を danger として処理すること' do
        expect(helper.audit_log_action_color('delete')).to eq('danger')
        expect(helper.audit_log_action_color('destroy')).to eq('danger')
      end

      it 'view/show を info として処理すること' do
        expect(helper.audit_log_action_color('view')).to eq('info')
        expect(helper.audit_log_action_color('show')).to eq('info')
      end
    end

    context 'その他のアクション' do
      it 'export を warning として処理すること' do
        expect(helper.audit_log_action_color('export')).to eq('warning')
      end

      it 'permission_change を danger として処理すること' do
        expect(helper.audit_log_action_color('permission_change')).to eq('danger')
      end

      it 'password_change を warning として処理すること' do
        expect(helper.audit_log_action_color('password_change')).to eq('warning')
      end

      it '未知のアクションを secondary として処理すること' do
        expect(helper.audit_log_action_color('unknown_action')).to eq('secondary')
      end
    end
  end

  # ============================================
  # セキュリティイベント色クラスのテスト
  # ============================================

  describe '#security_event_color' do
    context 'セキュリティ脅威' do
      it '脅威レベル高のイベントを danger として処理すること' do
        danger_events = %w[failed_login rate_limit_exceeded suspicious_activity]
        danger_events.each do |event|
          expect(helper.security_event_color(event)).to eq('danger')
          expect(helper.security_event_color(event.to_sym)).to eq('danger')
        end
      end
    end

    context 'セキュリティ成功' do
      it '成功イベントを success として処理すること' do
        success_events = %w[login_success password_changed]
        success_events.each do |event|
          expect(helper.security_event_color(event)).to eq('success')
          expect(helper.security_event_color(event.to_sym)).to eq('success')
        end
      end
    end

    context 'アクセス許可' do
      it 'アクセス許可イベントを info として処理すること' do
        info_events = %w[permission_granted access_granted]
        info_events.each do |event|
          expect(helper.security_event_color(event)).to eq('info')
          expect(helper.security_event_color(event.to_sym)).to eq('info')
        end
      end
    end

    context 'セッション関連' do
      it 'セッション期限切れを warning として処理すること' do
        expect(helper.security_event_color('session_expired')).to eq('warning')
        expect(helper.security_event_color(:session_expired)).to eq('warning')
      end
    end

    context '未知のイベント' do
      it '未知のイベントを secondary として処理すること' do
        expect(helper.security_event_color('unknown_event')).to eq('secondary')
      end
    end
  end

  # ============================================
  # カテゴリ推定機能のテスト（緊急対応）
  # ============================================

  describe '#categorize_by_name' do
    context '医薬品の分類' do
      it '錠剤系の商品を医薬品として分類すること' do
        medicine_names = [
          'アスピリン錠100mg',
          'パラセタモールカプセル',
          'ビタミンB錠',
          'インスリン注射液',
          '消毒用エタノール'
        ]

        medicine_names.each do |name|
          expect(helper.categorize_by_name(name)).to eq('医薬品')
        end
      end

      it '軟膏・点眼薬を医薬品として分類すること' do
        topical_medicines = [
          'ステロイド軟膏',
          '点眼液',
          'プレドニゾロンシロップ'
        ]

        topical_medicines.each do |name|
          expect(helper.categorize_by_name(name)).to eq('医薬品')
        end
      end
    end

    context '医療機器の分類' do
      it '測定器類を医療機器として分類すること' do
        device_names = [
          'デジタル血圧計',
          '体温計',
          'パルスオキシメーター',
          '聴診器'
        ]

        device_names.each do |name|
          expect(helper.categorize_by_name(name)).to eq('医療機器')
        end
      end
    end

    context '消耗品の分類' do
      it '使い捨て用品を消耗品として分類すること' do
        supply_names = [
          '使い捨てマスク',
          'ニトリル手袋',
          'アルコール綿',
          'ガーゼ',
          '注射針'
        ]

        supply_names.each do |name|
          expect(helper.categorize_by_name(name)).to eq('消耗品')
        end
      end
    end

    context 'サプリメントの分類' do
      it 'サプリメント類を正しく分類すること' do
        supplement_names = [
          'ビタミンCサプリ',
          'オメガ3フィッシュオイル',
          'プロバイオティクス'
        ]

        supplement_names.each do |name|
          expect(helper.categorize_by_name(name)).to eq('サプリメント')
        end
      end
    end

    context 'その他の分類' do
      it '分類不能な商品をその他として分類すること' do
        other_names = [
          '不明な商品',
          'テスト商品',
          '特殊機材ABC'
        ]

        other_names.each do |name|
          expect(helper.categorize_by_name(name)).to eq('その他')
        end
      end

      it 'blank な商品名をその他として分類すること' do
        expect(helper.categorize_by_name('')).to eq('その他')
        expect(helper.categorize_by_name(nil)).to eq('その他')
        expect(helper.categorize_by_name('   ')).to eq('その他')
      end
    end

    context 'エッジケース' do
      it '大文字小文字を区別せずに分類すること' do
        expect(helper.categorize_by_name('ASPIRIN錠')).to eq('医薬品')
        expect(helper.categorize_by_name('aspirin錠')).to eq('医薬品')
        expect(helper.categorize_by_name('Aspirin錠')).to eq('医薬品')
      end

      it '複数キーワードが含まれる場合は優先度順で分類すること' do
        # 医療機器キーワードが先にマッチする場合
        expect(helper.categorize_by_name('血圧計用ビタミン錠')).to eq('医療機器')

        # 消耗品キーワードが先にマッチする場合
        expect(helper.categorize_by_name('マスク用ビタミンスプレー')).to eq('消耗品')
      end
    end

    context 'パフォーマンステスト' do
      it '大量の商品名処理でも高速に動作すること' do
        product_names = Array.new(1000) { |i| "テスト商品#{i}号ビタミン錠" }

        start_time = Time.current
        product_names.each { |name| helper.categorize_by_name(name) }
        elapsed_time = (Time.current - start_time) * 1000 # ミリ秒に変換
        
        expect(elapsed_time).to be < 50
      end
    end
  end

  # ============================================
  # 統合テスト
  # ============================================

  describe 'integration tests' do
    it 'すべてのヘルパーメソッドがビューコンテキストで動作すること' do
      # 実際のビューコンテキストでのテスト
      expect { helper.github_icon }.not_to raise_error
      expect { helper.flash_class('notice') }.not_to raise_error
      expect { helper.audit_log_action_color('login') }.not_to raise_error
      expect { helper.security_event_color('failed_login') }.not_to raise_error
      expect { helper.categorize_by_name('アスピリン錠') }.not_to raise_error
    end
  end

  # ============================================
  # 統一フラッシュメッセージヘルパーのテスト（新機能）
  # ============================================

  describe '#flash_alert_class' do
    it 'フラッシュタイプに応じた適切なアラートクラスを返すこと' do
      expect(helper.flash_alert_class('notice')).to eq('alert-success')
      expect(helper.flash_alert_class('success')).to eq('alert-success')
      expect(helper.flash_alert_class('alert')).to eq('alert-danger')
      expect(helper.flash_alert_class('error')).to eq('alert-danger')
      expect(helper.flash_alert_class('warning')).to eq('alert-warning')
      expect(helper.flash_alert_class('info')).to eq('alert-info')
      expect(helper.flash_alert_class('unknown')).to eq('alert-info')
    end
  end

  describe '#flash_icon_class' do
    it 'フラッシュタイプに応じた適切なアイコンクラスを返すこと' do
      expect(helper.flash_icon_class('notice')).to eq('bi bi-check-circle')
      expect(helper.flash_icon_class('success')).to eq('bi bi-check-circle')
      expect(helper.flash_icon_class('alert')).to eq('bi bi-exclamation-triangle')
      expect(helper.flash_icon_class('error')).to eq('bi bi-exclamation-triangle')
      expect(helper.flash_icon_class('warning')).to eq('bi bi-exclamation-circle')
      expect(helper.flash_icon_class('info')).to eq('bi bi-info-circle')
      expect(helper.flash_icon_class('unknown')).to eq('bi bi-info-circle')
    end
  end

  describe '#flash_title_for' do
    it 'フラッシュタイプに応じた適切なタイトルを返すこと' do
      expect(helper.flash_title_for('notice')).to eq('成功')
      expect(helper.flash_title_for('success')).to eq('成功')
      expect(helper.flash_title_for('alert')).to eq('エラー')
      expect(helper.flash_title_for('error')).to eq('エラー')
      expect(helper.flash_title_for('warning')).to eq('警告')
      expect(helper.flash_title_for('info')).to eq('情報')
      expect(helper.flash_title_for('unknown')).to be_nil
    end
  end

  describe '#flash_detail_for' do
    it 'エラータイプの場合に詳細メッセージを返すこと' do
      expect(helper.flash_detail_for('alert', 'test')).to eq('エラーが解決しない場合は管理者にお問い合わせください。')
      expect(helper.flash_detail_for('error', 'test')).to eq('エラーが解決しない場合は管理者にお問い合わせください。')
      expect(helper.flash_detail_for('notice', 'test')).to be_nil
      expect(helper.flash_detail_for('info', 'test')).to be_nil
    end
  end

  # ============================================
  # 統一フッターヘルパーのテスト（新機能）
  # ============================================

  describe 'footer helpers' do
    before do
      # current_sectionをモック
      allow(helper).to receive(:current_section).and_return('admin')
    end

    describe '#footer_classes' do
      it 'セクションに応じた適切なフッタークラスを返すこと' do
        allow(helper).to receive(:current_section).and_return('admin')
        expect(helper.footer_classes).to eq('footer-admin py-4 mt-auto')

        allow(helper).to receive(:current_section).and_return('store')
        expect(helper.footer_classes).to eq('footer-store py-4 mt-auto')

        allow(helper).to receive(:current_section).and_return('public')
        expect(helper.footer_classes).to eq('footer-public bg-dark text-light py-4 mt-auto')
      end
    end

    describe '#footer_container_classes' do
      it 'セクションに応じた適切なコンテナクラスを返すこと' do
        allow(helper).to receive(:current_section).and_return('admin')
        expect(helper.footer_container_classes).to eq('container-fluid')

        allow(helper).to receive(:current_section).and_return('store')
        expect(helper.footer_container_classes).to eq('container-fluid')

        allow(helper).to receive(:current_section).and_return('public')
        expect(helper.footer_container_classes).to eq('container')
      end
    end

    describe '#footer_divider_classes' do
      it '一貫した区切り線クラスを返すこと' do
        expect(helper.footer_divider_classes).to eq('my-3 opacity-25')
      end
    end

    describe '#footer_brand_icon_class' do
      it 'セクションに応じた適切なブランドアイコンクラスを返すこと' do
        allow(helper).to receive(:current_section).and_return('admin')
        expect(helper.footer_brand_icon_class).to eq('bi bi-boxes')

        allow(helper).to receive(:current_section).and_return('store')
        expect(helper.footer_brand_icon_class).to eq('bi bi-shop')

        allow(helper).to receive(:current_section).and_return('public')
        expect(helper.footer_brand_icon_class).to eq('bi bi-boxes-stacked')
      end
    end

    describe '#footer_brand_icon_color' do
      it 'セクションに応じた適切なアイコン色を返すこと' do
        allow(helper).to receive(:current_section).and_return('admin')
        expect(helper.footer_brand_icon_color).to eq('text-primary')

        allow(helper).to receive(:current_section).and_return('store')
        expect(helper.footer_brand_icon_color).to eq('text-info')

        allow(helper).to receive(:current_section).and_return('public')
        expect(helper.footer_brand_icon_color).to eq('text-primary')
      end
    end

    describe '#footer_brand_text' do
      it 'ブランドテキストを返すこと' do
        expect(helper.footer_brand_text).to eq('StockRx')
      end
    end

    describe '#footer_default_description' do
      it 'セクションに応じた適切な説明文を返すこと' do
        allow(helper).to receive(:current_section).and_return('admin')
        expect(helper.footer_default_description).to eq('モダンな在庫管理システム - 管理者画面')

        allow(helper).to receive(:current_section).and_return('store')
        expect(helper.footer_default_description).to eq('モダンな在庫管理システム - 店舗画面')

        allow(helper).to receive(:current_section).and_return('public')
        expect(helper.footer_default_description).to eq('モダンな在庫管理システム')
      end
    end
  end

  # ============================================
  # 統一ブランディングヘルパーのテスト（新機能）
  # ============================================

  describe 'branding helpers' do
    describe '#brand_link_path' do
      context '管理者がログインしている場合' do
        before do
          admin = create(:admin)
          allow(helper).to receive(:current_admin).and_return(admin)
        end

        it '管理者ルートパスを返すこと' do
          expect(helper.brand_link_path).to eq(admin_root_path)
        end
      end

      context '店舗ユーザーがログインしている場合' do
        before do
          store_user = create(:store_user)
          allow(helper).to receive(:current_admin).and_return(nil)
          allow(helper).to receive(:current_store_user).and_return(store_user)
        end

        it '店舗ルートパスを返すこと' do
          expect(helper.brand_link_path).to eq(store_root_path)
        end
      end

      context '誰もログインしていない場合' do
        before do
          allow(helper).to receive(:current_admin).and_return(nil)
          allow(helper).to receive(:current_store_user).and_return(nil)
        end

        it 'ルートパスを返すこと' do
          expect(helper.brand_link_path).to eq(root_path)
        end
      end
    end

    describe '#current_section' do
      it 'コントローラー名から適切なセクションを判定すること' do
        # AdminControllersのテスト
        allow(helper.controller).to receive_message_chain(:class, :name).and_return('AdminControllers::DashboardController')
        expect(helper.current_section).to eq('admin')

        # StoreControllersのテスト
        allow(helper.controller).to receive_message_chain(:class, :name).and_return('StoreControllers::InventoriesController')
        expect(helper.current_section).to eq('store')

        # その他のテスト
        allow(helper.controller).to receive_message_chain(:class, :name).and_return('PublicController')
        expect(helper.current_section).to eq('public')
      end
    end

    describe '#brand_icon_class' do
      it 'セクションに応じた適切なブランドアイコンクラスを返すこと' do
        allow(helper).to receive(:current_section).and_return('admin')
        expect(helper.brand_icon_class).to eq('bi bi-boxes')

        allow(helper).to receive(:current_section).and_return('store')
        expect(helper.brand_icon_class).to eq('bi bi-shop')

        allow(helper).to receive(:current_section).and_return('public')
        expect(helper.brand_icon_class).to eq('bi bi-boxes-stacked')
      end
    end

    describe '#brand_text' do
      it 'ブランドテキストを返すこと' do
        expect(helper.brand_text).to eq('StockRx')
      end
    end

    describe '#brand_classes' do
      it 'ブランド用CSSクラスを返すこと' do
        expect(helper.brand_classes).to eq('d-flex align-items-center')
      end
    end

    describe '#brand_text_classes' do
      it 'ブランドテキスト用CSSクラスを返すこと' do
        expect(helper.brand_text_classes).to eq('fw-bold')
      end
    end

    describe '#badge_classes' do
      it 'バッジ用CSSクラスを返すこと' do
        expect(helper.badge_classes).to eq('ms-2 badge bg-light text-dark')
      end
    end
  end

  # ============================================
  # 統合テスト（新機能含む）
  # ============================================

  describe 'integration tests (extended)' do
    it '全ての新規ヘルパーメソッドがビューコンテキストで動作すること' do
      # フラッシュメッセージヘルパー
      expect { helper.flash_alert_class('notice') }.not_to raise_error
      expect { helper.flash_icon_class('error') }.not_to raise_error
      expect { helper.flash_title_for('warning') }.not_to raise_error
      expect { helper.flash_detail_for('alert', 'test') }.not_to raise_error

      # フッターヘルパー
      allow(helper).to receive(:current_section).and_return('admin')
      expect { helper.footer_classes }.not_to raise_error
      expect { helper.footer_container_classes }.not_to raise_error
      expect { helper.footer_brand_icon_class }.not_to raise_error

      # ブランディングヘルパー
      allow(helper).to receive(:current_admin).and_return(nil)
      allow(helper).to receive(:current_store_user).and_return(nil)
      expect { helper.brand_link_path }.not_to raise_error
      expect { helper.brand_icon_class }.not_to raise_error
      expect { helper.brand_text }.not_to raise_error
    end

    context 'エラーハンドリング' do
      it 'nil値に対して安全に動作すること' do
        expect(helper.flash_alert_class(nil)).to eq('alert-info')
        expect(helper.flash_icon_class(nil)).to eq('bi bi-info-circle')
        expect(helper.flash_title_for(nil)).to be_nil
      end

      it 'コントローラーが未定義でもエラーにならないこと' do
        allow(helper).to receive(:controller).and_return(nil)
        expect { helper.current_section }.not_to raise_error
      end
    end
  end

  # ============================================
  # パフォーマンステスト（新機能含む）
  # ============================================

  describe 'performance (extended)' do
    it '新機能ヘルパーが高速に動作すること' do
      flash_types = %w[notice alert error warning info success]

      start_time = Time.current
      1000.times do
        flash_types.each do |type|
          helper.flash_alert_class(type)
          helper.flash_icon_class(type)
          helper.flash_title_for(type)
        end
      end
      elapsed_time = (Time.current - start_time) * 1000 # ミリ秒に変換
      
      expect(elapsed_time).to be < 100
    end

    it 'ブランディングヘルパーが高速に動作すること' do
      allow(helper).to receive(:current_section).and_return('admin')

      start_time = Time.current
      1000.times do
        helper.footer_classes
        helper.footer_brand_icon_class
        helper.brand_icon_class
        helper.brand_text
      end
      elapsed_time = (Time.current - start_time) * 1000 # ミリ秒に変換
      
      expect(elapsed_time).to be < 50
    end
  end

  # ============================================
  # セキュリティテスト
  # ============================================

  describe 'security' do
    context 'XSS対策' do
      it 'HTMLタグを含む商品名を安全に処理すること' do
        malicious_names = [
          '<script>alert("XSS")</script>ビタミン錠',
          'onclick="alert(1)"注射針',
          '<img src=x onerror=alert(1)>マスク'
        ]

        malicious_names.each do |name|
          result = helper.categorize_by_name(name)
          expect(%w[医薬品 消耗品 その他]).to include(result)
        end
      end

      it 'JavaScriptイベントハンドラを含む入力を安全に処理すること' do
        event_handlers = %w[onload onclick onerror onmouseover onfocus]
        
        event_handlers.each do |handler|
          name = "#{handler}=alert(1) アスピリン錠"
          result = helper.categorize_by_name(name)
          expect(result).to eq('医薬品')
        end
      end
    end

    context 'SQLインジェクション対策' do
      it 'SQL文字を含む入力を安全に処理すること' do
        sql_injections = [
          "'; DROP TABLE products; --ビタミン",
          "1' OR '1'='1 血圧計",
          "UNION SELECT * FROM users-- マスク"
        ]

        sql_injections.each do |name|
          expect { helper.categorize_by_name(name) }.not_to raise_error
        end
      end
    end
  end

  # ============================================
  # エッジケーステスト（追加）
  # ============================================

  describe 'edge cases (extended)' do
    context '特殊文字の処理' do
      it 'Unicode文字を含む商品名を正しく処理すること' do
        unicode_names = {
          '💊ビタミン錠' => '医薬品',
          '🩹ガーゼ' => '消耗品',
          '🌡️体温計' => '医療機器',
          '🧪プロバイオティクス' => 'サプリメント'
        }

        unicode_names.each do |name, expected|
          expect(helper.categorize_by_name(name)).to eq(expected)
        end
      end

      it '改行やタブを含む商品名を正しく処理すること' do
        expect(helper.categorize_by_name("アスピリン\n錠")).to eq('医薬品')
        expect(helper.categorize_by_name("血圧\t計")).to eq('医療機器')
        expect(helper.categorize_by_name("マスク\r\n使い捨て")).to eq('消耗品')
      end
    end

    context 'メモリ効率' do
      it '極端に長い商品名でもメモリリークしないこと' do
        long_name = 'ビタミン' * 10000 + '錠'
        
        initial_memory = `ps -o rss= -p #{Process.pid}`.to_i
        result = helper.categorize_by_name(long_name)
        final_memory = `ps -o rss= -p #{Process.pid}`.to_i
        
        expect(result).to eq('医薬品')
        expect(final_memory - initial_memory).to be < 1000 # 1MB未満の増加
      end
    end
  end

  # ============================================
  # 実用的な統合テスト
  # ============================================

  describe 'practical integration tests' do
    it '実際の商品データベースのパターンを正しく分類すること' do
      # 実際によくある商品名パターン
      real_world_products = {
        'ロキソニン錠60mg' => '医薬品',
        'アセトアミノフェン細粒小児用20%' => '医薬品',
        'オムロン デジタル自動血圧計 HEM-7130' => '医療機器',
        'テルモ電子体温計C231' => '医療機器',
        'サージカルマスク50枚入' => '消耗品',
        'ニトリルグローブ Mサイズ 100枚' => '消耗品',
        'DHC ビタミンC 60日分' => 'サプリメント',
        'ネイチャーメイド スーパーフィッシュオイル' => 'サプリメント',
        '包帯' => 'その他',
        '綿棒' => 'その他'
      }

      real_world_products.each do |name, expected|
        expect(helper.categorize_by_name(name)).to eq(expected), 
          "商品名 '#{name}' が期待通り '#{expected}' に分類されませんでした"
      end
    end
  end

  # ============================================
  # TODO: 将来の機能拡張テスト
  # ============================================

  describe 'future features' do
    it 'AI駆動のカテゴリ推定が実装されること' do
      skip '機械学習によるカテゴリ推定機能は将来実装予定'
      # expect(helper.ai_categorize_by_name('新しい薬品XYZ')).to eq('医薬品')
    end

    it 'ローカライゼーション対応が実装されること' do
      skip '多言語対応は将来実装予定'
      # expect(helper.categorize_by_name('Medicine', locale: :en)).to eq('Medical')
    end

    it 'リスクスコア可視化ヘルパーが実装されること' do
      skip 'リスクスコア可視化機能は将来実装予定'
      # expect(helper.risk_score_badge(0.8)).to include('badge-danger')
    end
  end
end
