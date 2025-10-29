# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  describe "#github_icon" do
    it "generates GitHub SVG icon with default class" do
      result = helper.github_icon

      expect(result).to include('<svg')
      expect(result).to include('class="github-icon"')
      expect(result).to include('viewBox="0 0 24 24"')
      expect(result).to include('fill="currentColor"')
      expect(result).to include('<path')
    end

    it "generates GitHub SVG icon with custom class" do
      result = helper.github_icon(css_class: "custom-github")

      expect(result).to include('class="custom-github"')
    end
  end

  describe "#flash_class" do
    it "converts notice to success" do
      expect(helper.flash_class("notice")).to eq("success")
    end

    it "converts alert to danger" do
      expect(helper.flash_class("alert")).to eq("danger")
    end

    it "converts error to danger" do
      expect(helper.flash_class("error")).to eq("danger")
    end

    it "converts warning to warning" do
      expect(helper.flash_class("warning")).to eq("warning")
    end

    it "converts info to info" do
      expect(helper.flash_class("info")).to eq("info")
    end

    it "returns original type for unknown types" do
      expect(helper.flash_class("custom")).to eq("custom")
    end

    it "handles symbol input" do
      expect(helper.flash_class(:notice)).to eq("success")
    end
  end

  describe "#active_class" do
    it "returns 'active' for current page" do
      allow(helper).to receive(:current_page?).with("/test").and_return(true)
      expect(helper.active_class("/test")).to eq("active")
    end

    it "returns empty string for non-current page" do
      allow(helper).to receive(:current_page?).with("/test").and_return(false)
      expect(helper.active_class("/test")).to eq("")
    end
  end

  describe "#audit_log_action_color" do
    it "returns success for login actions" do
      expect(helper.audit_log_action_color("login")).to eq("success")
      expect(helper.audit_log_action_color("signup")).to eq("success")
    end

    it "returns info for logout" do
      expect(helper.audit_log_action_color("logout")).to eq("info")
    end

    it "returns danger for destructive actions" do
      expect(helper.audit_log_action_color("failed_login")).to eq("danger")
      expect(helper.audit_log_action_color("delete")).to eq("danger")
      expect(helper.audit_log_action_color("destroy")).to eq("danger")
      expect(helper.audit_log_action_color("permission_change")).to eq("danger")
    end

    it "returns warning for update actions" do
      expect(helper.audit_log_action_color("update")).to eq("warning")
      expect(helper.audit_log_action_color("export")).to eq("warning")
      expect(helper.audit_log_action_color("password_change")).to eq("warning")
    end

    it "returns info for view actions" do
      expect(helper.audit_log_action_color("view")).to eq("info")
      expect(helper.audit_log_action_color("show")).to eq("info")
    end

    it "returns secondary for unknown actions" do
      expect(helper.audit_log_action_color("unknown")).to eq("secondary")
    end

    it "handles symbol input" do
      expect(helper.audit_log_action_color(:login)).to eq("success")
    end
  end

  describe "#security_event_color" do
    it "returns danger for security threats" do
      expect(helper.security_event_color("failed_login")).to eq("danger")
      expect(helper.security_event_color("rate_limit_exceeded")).to eq("danger")
      expect(helper.security_event_color("suspicious_activity")).to eq("danger")
    end

    it "returns success for positive security events" do
      expect(helper.security_event_color("login_success")).to eq("success")
      expect(helper.security_event_color("password_changed")).to eq("success")
    end

    it "returns info for permission events" do
      expect(helper.security_event_color("permission_granted")).to eq("info")
      expect(helper.security_event_color("access_granted")).to eq("info")
    end

    it "returns warning for session events" do
      expect(helper.security_event_color("session_expired")).to eq("warning")
    end

    it "returns secondary for unknown events" do
      expect(helper.security_event_color("unknown")).to eq("secondary")
    end
  end

  describe "#categorize_by_name" do
    it "returns 'その他' for blank product name" do
      expect(helper.categorize_by_name("")).to eq("その他")
      expect(helper.categorize_by_name(nil)).to eq("その他")
    end

    it "categorizes medical devices correctly" do
      expect(helper.categorize_by_name("血圧計")).to eq("医療機器")
      expect(helper.categorize_by_name("体温計")).to eq("医療機器")
      expect(helper.categorize_by_name("パルスオキシメーター")).to eq("医療機器")
      expect(helper.categorize_by_name("聴診器")).to eq("医療機器")
    end

    it "categorizes medical supplies correctly" do
      expect(helper.categorize_by_name("マスク")).to eq("消耗品")
      expect(helper.categorize_by_name("手袋")).to eq("消耗品")
      expect(helper.categorize_by_name("アルコール")).to eq("消耗品")
      expect(helper.categorize_by_name("ガーゼ")).to eq("消耗品")
      expect(helper.categorize_by_name("注射針")).to eq("消耗品")
    end

    it "categorizes supplements correctly" do
      expect(helper.categorize_by_name("ビタミンC")).to eq("サプリメント")
      expect(helper.categorize_by_name("サプリメント")).to eq("サプリメント")
      expect(helper.categorize_by_name("オメガ3")).to eq("サプリメント")
      expect(helper.categorize_by_name("プロバイオティクス")).to eq("サプリメント")
    end

    it "categorizes medicines correctly" do
      expect(helper.categorize_by_name("アスピリン錠")).to eq("医薬品")
      expect(helper.categorize_by_name("パラセタモールカプセル")).to eq("医薬品")
      expect(helper.categorize_by_name("軟膏")).to eq("医薬品")
      expect(helper.categorize_by_name("点眼薬")).to eq("医薬品")
      expect(helper.categorize_by_name("注射液")).to eq("医薬品")
      expect(helper.categorize_by_name("100mg錠")).to eq("医薬品")
    end

    it "returns 'その他' for unrecognized products" do
      expect(helper.categorize_by_name("不明な商品")).to eq("その他")
      expect(helper.categorize_by_name("テスト商品")).to eq("その他")
    end

    it "handles case insensitive matching" do
      expect(helper.categorize_by_name("アスピリン")).to eq("医薬品")
      expect(helper.categorize_by_name("Blood Pressure Monitor")).to eq("その他") # English not supported
    end
  end

  describe "#flash_alert_class" do
    it "converts flash types to Bootstrap alert classes" do
      expect(helper.flash_alert_class("notice")).to eq("alert-success")
      expect(helper.flash_alert_class("success")).to eq("alert-success")
      expect(helper.flash_alert_class("alert")).to eq("alert-danger")
      expect(helper.flash_alert_class("error")).to eq("alert-danger")
      expect(helper.flash_alert_class("warning")).to eq("alert-warning")
      expect(helper.flash_alert_class("info")).to eq("alert-info")
    end

    it "defaults to alert-info for unknown types" do
      expect(helper.flash_alert_class("unknown")).to eq("alert-info")
    end
  end

  describe "#flash_icon_class" do
    it "returns appropriate Bootstrap icons for flash types" do
      expect(helper.flash_icon_class("notice")).to eq("bi bi-check-circle")
      expect(helper.flash_icon_class("success")).to eq("bi bi-check-circle")
      expect(helper.flash_icon_class("alert")).to eq("bi bi-exclamation-triangle")
      expect(helper.flash_icon_class("error")).to eq("bi bi-exclamation-triangle")
      expect(helper.flash_icon_class("warning")).to eq("bi bi-exclamation-circle")
      expect(helper.flash_icon_class("info")).to eq("bi bi-info-circle")
    end

    it "defaults to info icon for unknown types" do
      expect(helper.flash_icon_class("unknown")).to eq("bi bi-info-circle")
    end
  end

  describe "#flash_title_for" do
    it "returns appropriate titles for flash types" do
      expect(helper.flash_title_for("notice")).to eq("成功")
      expect(helper.flash_title_for("success")).to eq("成功")
      expect(helper.flash_title_for("alert")).to eq("エラー")
      expect(helper.flash_title_for("error")).to eq("エラー")
      expect(helper.flash_title_for("warning")).to eq("警告")
      expect(helper.flash_title_for("info")).to eq("情報")
    end

    it "returns nil for unknown types" do
      expect(helper.flash_title_for("unknown")).to be_nil
    end
  end

  describe "#flash_detail_for" do
    it "returns help text for error types" do
      expect(helper.flash_detail_for("alert", "test")).to eq("エラーが解決しない場合は管理者にお問い合わせください。")
      expect(helper.flash_detail_for("error", "test")).to eq("エラーが解決しない場合は管理者にお問い合わせください。")
    end

    it "returns nil for non-error types" do
      expect(helper.flash_detail_for("notice", "test")).to be_nil
      expect(helper.flash_detail_for("info", "test")).to be_nil
    end
  end

  describe "footer helpers" do
    before do
      allow(helper).to receive(:current_section).and_return("admin")
    end

    describe "#footer_classes" do
      it "returns admin footer classes for admin section" do
        expect(helper.footer_classes).to eq("footer-admin py-4 mt-auto")
      end

      it "returns store footer classes for store section" do
        allow(helper).to receive(:current_section).and_return("store")
        expect(helper.footer_classes).to eq("footer-store py-4 mt-auto")
      end

      it "returns public footer classes for other sections" do
        allow(helper).to receive(:current_section).and_return("public")
        expect(helper.footer_classes).to eq("footer-public bg-dark text-light py-4 mt-auto")
      end
    end

    describe "#footer_container_classes" do
      it "returns container-fluid for admin and store" do
        expect(helper.footer_container_classes).to eq("container-fluid")

        allow(helper).to receive(:current_section).and_return("store")
        expect(helper.footer_container_classes).to eq("container-fluid")
      end

      it "returns container for public" do
        allow(helper).to receive(:current_section).and_return("public")
        expect(helper.footer_container_classes).to eq("container")
      end
    end

    describe "#footer_brand_icon_class" do
      it "returns section-specific icons" do
        expect(helper.footer_brand_icon_class).to eq("bi bi-boxes")

        allow(helper).to receive(:current_section).and_return("store")
        expect(helper.footer_brand_icon_class).to eq("bi bi-shop")

        allow(helper).to receive(:current_section).and_return("public")
        expect(helper.footer_brand_icon_class).to eq("bi bi-boxes-stacked")
      end
    end

    describe "#footer_brand_text" do
      it "returns StockRx brand text" do
        expect(helper.footer_brand_text).to eq("StockRx")
      end
    end
  end

  describe "branding helpers" do
    let(:mock_controller) { double("Controller") }

    before do
      allow(helper).to receive(:controller).and_return(mock_controller)
    end

    describe "#current_section" do
      it "returns admin for AdminControllers" do
        allow(mock_controller).to receive_message_chain(:class, :name).and_return("AdminControllers::DashboardController")
        expect(helper.current_section).to eq("admin")
      end

      it "returns store for StoreControllers" do
        allow(mock_controller).to receive_message_chain(:class, :name).and_return("StoreControllers::InventoriesController")
        expect(helper.current_section).to eq("store")
      end

      it "returns public for other controllers" do
        allow(mock_controller).to receive_message_chain(:class, :name).and_return("HomeController")
        expect(helper.current_section).to eq("public")
      end
    end

    describe "#brand_link_path" do
      it "returns admin root for admin users" do
        allow(helper).to receive(:current_admin).and_return(double("Admin"))
        allow(helper).to receive(:admin_root_path).and_return("/admin")

        expect(helper.brand_link_path).to eq("/admin")
      end

      it "returns store root for store users" do
        allow(helper).to receive(:current_admin).and_return(nil)
        allow(helper).to receive(:current_store_user).and_return(double("StoreUser"))
        allow(helper).to receive(:store_root_path).and_return("/store")

        expect(helper.brand_link_path).to eq("/store")
      end

      it "returns root path for public users" do
        allow(helper).to receive(:current_admin).and_return(nil)
        allow(helper).to receive(:current_store_user).and_return(nil)
        allow(helper).to receive(:root_path).and_return("/")

        expect(helper.brand_link_path).to eq("/")
      end
    end

    describe "#brand_icon_class" do
      before do
        allow(mock_controller).to receive_message_chain(:class, :name).and_return("AdminControllers::DashboardController")
      end

      it "returns section-specific brand icons" do
        expect(helper.brand_icon_class).to eq("bi bi-boxes")
      end
    end

    describe "#brand_text" do
      it "returns StockRx" do
        expect(helper.brand_text).to eq("StockRx")
      end
    end

    describe "#brand_classes" do
      it "returns Bootstrap flexbox classes" do
        expect(helper.brand_classes).to eq("d-flex align-items-center")
      end
    end
  end

  describe "CSS class helpers" do
    describe "#footer_divider_classes" do
      it "returns divider styling classes" do
        expect(helper.footer_divider_classes).to eq("my-3 opacity-25")
      end
    end

    describe "#footer_description_class" do
      it "returns small text class" do
        expect(helper.footer_description_class).to eq("small")
      end
    end

    describe "#footer_meta_alignment" do
      it "returns Bootstrap alignment class" do
        expect(helper.footer_meta_alignment).to eq("justify-content-md-end")
      end
    end

    describe "#brand_text_classes" do
      it "returns font weight class" do
        expect(helper.brand_text_classes).to eq("fw-bold")
      end
    end

    describe "#badge_classes" do
      it "returns Bootstrap badge classes" do
        expect(helper.badge_classes).to eq("ms-2 badge bg-light text-dark")
      end
    end
  end

  describe "color helpers" do
    describe "#footer_brand_icon_color" do
      before do
        allow(helper).to receive(:current_section).and_return("admin")
      end

      it "returns section-specific colors" do
        expect(helper.footer_brand_icon_color).to eq("text-primary")

        allow(helper).to receive(:current_section).and_return("store")
        expect(helper.footer_brand_icon_color).to eq("text-info")

        allow(helper).to receive(:current_section).and_return("public")
        expect(helper.footer_brand_icon_color).to eq("text-primary")
      end
    end

    describe "#footer_security_icon_color" do
      it "returns success color" do
        expect(helper.footer_security_icon_color).to eq("text-success")
      end
    end
  end

  describe "text helpers" do
    describe "#footer_default_description" do
      before do
        allow(helper).to receive(:current_section).and_return("admin")
      end

      it "returns section-specific descriptions" do
        expect(helper.footer_default_description).to eq("モダンな在庫管理システム - 管理者画面")

        allow(helper).to receive(:current_section).and_return("store")
        expect(helper.footer_default_description).to eq("モダンな在庫管理システム - 店舗画面")

        allow(helper).to receive(:current_section).and_return("public")
        expect(helper.footer_default_description).to eq("モダンな在庫管理システム")
      end
    end

    describe "#footer_security_text" do
      it "returns SSL protection text" do
        expect(helper.footer_security_text).to eq("SSL保護済み")
      end
    end

    describe "#footer_copyright_holder" do
      it "returns StockRx" do
        expect(helper.footer_copyright_holder).to eq("StockRx")
      end
    end
  end

  describe "#sort_icon" do
    it "returns empty string when column doesn't match current sort" do
      result = helper.sort_icon("name", "price", "asc")
      expect(result).to eq("".html_safe)
    end

    it "returns up arrow icon for ascending sort" do
      result = helper.sort_icon("name", "name", "asc")
      expect(result).to include("fa-sort-up")
    end

    it "returns down arrow icon for descending sort" do
      result = helper.sort_icon("name", "name", "desc")
      expect(result).to include("fa-sort-down")
    end

    it "uses params values when not provided" do
      allow(helper).to receive(:params).and_return({ sort: "name", direction: "asc" })
      result = helper.sort_icon("name")
      expect(result).to include("fa-sort-up")
    end

    it "handles nil current_sort" do
      result = helper.sort_icon("name", nil, "asc")
      expect(result).to eq("".html_safe)
    end
  end

  describe "#stock_level_badge" do
    let(:store_inventory) { double("StoreInventory") }

    it "returns danger badge for out of stock" do
      allow(store_inventory).to receive(:quantity).and_return(0)
      allow(store_inventory).to receive(:safety_stock_level).and_return(10)

      result = helper.stock_level_badge(store_inventory)
      expect(result[:class]).to eq("badge bg-danger")
      expect(result[:text]).to eq("在庫切れ")
    end

    it "returns warning badge for low stock" do
      allow(store_inventory).to receive(:quantity).and_return(5)
      allow(store_inventory).to receive(:safety_stock_level).and_return(10)

      result = helper.stock_level_badge(store_inventory)
      expect(result[:class]).to eq("badge bg-warning text-dark")
      expect(result[:text]).to eq("在庫少")
    end

    it "returns info badge for normal stock" do
      allow(store_inventory).to receive(:quantity).and_return(15)
      allow(store_inventory).to receive(:safety_stock_level).and_return(10)

      result = helper.stock_level_badge(store_inventory)
      expect(result[:class]).to eq("badge bg-info")
      expect(result[:text]).to eq("通常")
    end

    it "returns success badge for sufficient stock" do
      allow(store_inventory).to receive(:quantity).and_return(30)
      allow(store_inventory).to receive(:safety_stock_level).and_return(10)

      result = helper.stock_level_badge(store_inventory)
      expect(result[:class]).to eq("badge bg-success")
      expect(result[:text]).to eq("在庫充分")
    end
  end

  describe "#turnover_days" do
    let(:store_inventory) { double("StoreInventory") }

    it "returns N/A for zero quantity" do
      allow(store_inventory).to receive(:quantity).and_return(0)
      allow(store_inventory).to receive(:safety_stock_level).and_return(10)

      expect(helper.turnover_days(store_inventory)).to eq("N/A")
    end

    it "calculates turnover days for positive quantity" do
      allow(store_inventory).to receive(:quantity).and_return(100)
      allow(store_inventory).to receive(:safety_stock_level).and_return(30)

      # Daily consumption = 30/30 = 1, days = 100/1 = 100
      expect(helper.turnover_days(store_inventory)).to eq("100日")
    end

    it "handles very low safety stock level" do
      allow(store_inventory).to receive(:quantity).and_return(10)
      allow(store_inventory).to receive(:safety_stock_level).and_return(0)

      # Daily consumption = max(0/30, 1.0) = 1.0, days = 10/1 = 10
      expect(helper.turnover_days(store_inventory)).to eq("10日")
    end
  end

  describe "#format_ip_address" do
    it "masks the last octet of IP address" do
      expect(helper.format_ip_address("192.168.1.100")).to eq("192.168.1.***")
    end

    it "returns '不明' for blank IP" do
      expect(helper.format_ip_address("")).to eq("不明")
      expect(helper.format_ip_address(nil)).to eq("不明")
    end

    it "handles IPv6 addresses" do
      expect(helper.format_ip_address("2001:db8::1")).to eq("2001:db8::1")
    end
  end

  describe "#password_strength_class" do
    it "returns danger for expiring soon (0-7 days)" do
      expect(helper.password_strength_class(0)).to eq("text-danger")
      expect(helper.password_strength_class(7)).to eq("text-danger")
    end

    it "returns warning for medium term (8-30 days)" do
      expect(helper.password_strength_class(8)).to eq("text-warning")
      expect(helper.password_strength_class(30)).to eq("text-warning")
    end

    it "returns success for long term (>30 days)" do
      expect(helper.password_strength_class(31)).to eq("text-success")
      expect(helper.password_strength_class(100)).to eq("text-success")
    end
  end

  describe "#sort_direction" do
    it "returns desc when params direction is desc" do
      allow(helper).to receive(:params).and_return({ direction: "desc" })
      expect(helper.sort_direction).to eq("desc")
    end

    it "returns asc when params direction is not desc" do
      allow(helper).to receive(:params).and_return({ direction: "asc" })
      expect(helper.sort_direction).to eq("asc")
    end

    it "returns asc when params direction is missing" do
      allow(helper).to receive(:params).and_return({})
      expect(helper.sort_direction).to eq("asc")
    end
  end

  describe "#footer_badge_class" do
    it "returns section-specific badge classes" do
      allow(helper).to receive(:current_section).and_return("admin")
      expect(helper.footer_badge_class).to eq("bg-danger")

      allow(helper).to receive(:current_section).and_return("store")
      expect(helper.footer_badge_class).to eq("bg-success")

      allow(helper).to receive(:current_section).and_return("public")
      expect(helper.footer_badge_class).to eq("bg-secondary")
    end
  end

  describe "audit_log_action_color edge cases" do
    it "returns success for create action" do
      expect(helper.audit_log_action_color("create")).to eq("success")
    end
  end

  describe "categorize_by_name special cases" do
    it "categorizes complex medicine names" do
      expect(helper.categorize_by_name("インスリン注射液100IU")).to eq("医薬品")
      expect(helper.categorize_by_name("オメプラゾール細粒")).to eq("医薬品")
      expect(helper.categorize_by_name("プレドニゾロン錠5mg")).to eq("医薬品")
      expect(helper.categorize_by_name("ビタミンB液")).to eq("医薬品")
    end

    it "categorizes consumables with uppercase" do
      expect(helper.categorize_by_name("サージカルマスク")).to eq("消耗品")
    end

    it "categorizes supplements with complex names" do
      expect(helper.categorize_by_name("フィッシュオイルサプリ")).to eq("サプリメント")
    end

    it "handles multiple category keywords with correct priority" do
      # 医療機器キーワードが優先される
      expect(helper.categorize_by_name("血圧計用アルコール")).to eq("医療機器")
      # 消耗品キーワードが医薬品より優先
      expect(helper.categorize_by_name("注射針用ケース")).to eq("消耗品")
    end
  end

  describe "defined? checks" do
    describe "#brand_link_path with defined? checks" do
      it "handles case when current_admin is not defined" do
        allow(helper).to receive(:defined?).with(:current_admin).and_return(false)
        allow(helper).to receive(:defined?).with(:current_store_user).and_return(false)
        allow(helper).to receive(:root_path).and_return("/")

        expect(helper.brand_link_path).to eq("/")
      end

      it "handles case when current_store_user is not defined" do
        allow(helper).to receive(:defined?).with(:current_admin).and_return(true)
        allow(helper).to receive(:current_admin).and_return(nil)
        allow(helper).to receive(:defined?).with(:current_store_user).and_return(false)
        allow(helper).to receive(:root_path).and_return("/")

        expect(helper.brand_link_path).to eq("/")
      end
    end
  end

  # Branch coverage: Additional edge cases and conditions
  describe "comprehensive branch coverage" do
    describe "#flash_class edge cases" do
      it "handles nil type" do
        expect(helper.flash_class(nil)).to be_nil
      end

      it "handles empty string type" do
        expect(helper.flash_class("")).to eq("")
      end

      it "handles uppercase types" do
        expect(helper.flash_class("NOTICE")).to eq("NOTICE")
        expect(helper.flash_class("ERROR")).to eq("ERROR")
      end
    end

    describe "#active_class with various inputs" do
      it "handles complex paths" do
        allow(helper).to receive(:current_page?).with("/admin/stores/1/inventories").and_return(true)
        expect(helper.active_class("/admin/stores/1/inventories")).to eq("active")
      end

      it "handles paths with query params" do
        allow(helper).to receive(:current_page?).with("/inventories?search=test").and_return(true)
        expect(helper.active_class("/inventories?search=test")).to eq("active")
      end

      it "handles paths with anchors" do
        allow(helper).to receive(:current_page?).with("/inventories#section").and_return(false)
        expect(helper.active_class("/inventories#section")).to eq("")
      end
    end

    describe "#audit_log_action_color additional branches" do
      it "handles actions with prefixes" do
        expect(helper.audit_log_action_color("batch_delete")).to eq("danger")
        expect(helper.audit_log_action_color("bulk_update")).to eq("warning")
        expect(helper.audit_log_action_color("mass_export")).to eq("warning")
      end

      it "handles actions with underscores" do
        expect(helper.audit_log_action_color("user_login")).to eq("secondary")
        expect(helper.audit_log_action_color("admin_logout")).to eq("secondary")
      end

      it "handles numeric actions" do
        expect(helper.audit_log_action_color("123")).to eq("secondary")
      end
    end

    describe "#security_event_color additional branches" do
      it "handles events with variations" do
        expect(helper.security_event_color("login_failed")).to eq("secondary")
        expect(helper.security_event_color("rate_limit_warning")).to eq("secondary")
        expect(helper.security_event_color("suspicious_login")).to eq("secondary")
      end

      it "handles case variations" do
        expect(helper.security_event_color("FAILED_LOGIN")).to eq("secondary")
        expect(helper.security_event_color("Session_Expired")).to eq("secondary")
      end
    end

    describe "#categorize_by_name additional patterns" do
      it "handles products with numbers" do
        expect(helper.categorize_by_name("血圧計2000")).to eq("医療機器")
        expect(helper.categorize_by_name("マスク50枚入り")).to eq("消耗品")
        expect(helper.categorize_by_name("ビタミンC1000mg")).to eq("サプリメント")
      end

      it "handles products with special characters" do
        expect(helper.categorize_by_name("血圧計(デジタル)")).to eq("医療機器")
        expect(helper.categorize_by_name("マスク・手袋セット")).to eq("消耗品")
        expect(helper.categorize_by_name("ビタミンC+亜鉛")).to eq("サプリメント")
      end

      it "handles products with English mixed" do
        expect(helper.categorize_by_name("血圧計DIGITAL")).to eq("医療機器")
        expect(helper.categorize_by_name("サージカルmask")).to eq("消耗品")
      end

      it "handles very long product names" do
        long_name = "超高精度デジタル血圧計プロフェッショナル医療用2023年モデル"
        expect(helper.categorize_by_name(long_name)).to eq("医療機器")
      end

      it "handles whitespace variations" do
        expect(helper.categorize_by_name("  血圧計  ")).to eq("医療機器")
        expect(helper.categorize_by_name("\n\tマスク\n\t")).to eq("消耗品")
        expect(helper.categorize_by_name("   ")).to eq("その他")
      end
    end

    describe "#sort_icon edge cases" do
      it "handles nil column" do
        result = helper.sort_icon(nil, "name", "asc")
        expect(result).to eq("".html_safe)
      end

      it "handles empty string column" do
        result = helper.sort_icon("", "name", "asc")
        expect(result).to eq("".html_safe)
      end

      it "handles nil direction" do
        result = helper.sort_icon("name", "name", nil)
        expect(result).to include("fa-sort-down") # defaults to desc
      end

      it "handles invalid direction" do
        result = helper.sort_icon("name", "name", "invalid")
        expect(result).to include("fa-sort-down") # defaults to desc
      end

      it "handles case mismatch" do
        result = helper.sort_icon("Name", "name", "asc")
        expect(result).to eq("".html_safe)
      end
    end

    describe "#stock_level_badge edge cases" do
      let(:store_inventory) { double("StoreInventory") }

      it "handles nil safety_stock_level" do
        allow(store_inventory).to receive(:quantity).and_return(10)
        allow(store_inventory).to receive(:safety_stock_level).and_return(nil)

        result = helper.stock_level_badge(store_inventory)
        expect(result[:class]).to eq("badge bg-success")
        expect(result[:text]).to eq("在庫充分")
      end

      it "handles zero safety_stock_level" do
        allow(store_inventory).to receive(:quantity).and_return(5)
        allow(store_inventory).to receive(:safety_stock_level).and_return(0)

        result = helper.stock_level_badge(store_inventory)
        expect(result[:class]).to eq("badge bg-success")
        expect(result[:text]).to eq("在庫充分")
      end

      it "handles negative quantity" do
        allow(store_inventory).to receive(:quantity).and_return(-5)
        allow(store_inventory).to receive(:safety_stock_level).and_return(10)

        result = helper.stock_level_badge(store_inventory)
        expect(result[:class]).to eq("badge bg-danger")
        expect(result[:text]).to eq("在庫切れ")
      end

      it "handles exactly equal to safety stock" do
        allow(store_inventory).to receive(:quantity).and_return(10)
        allow(store_inventory).to receive(:safety_stock_level).and_return(10)

        result = helper.stock_level_badge(store_inventory)
        expect(result[:class]).to eq("badge bg-warning text-dark")
        expect(result[:text]).to eq("在庫少")
      end

      it "handles exactly 1.5x safety stock" do
        allow(store_inventory).to receive(:quantity).and_return(15)
        allow(store_inventory).to receive(:safety_stock_level).and_return(10)

        result = helper.stock_level_badge(store_inventory)
        expect(result[:class]).to eq("badge bg-info")
        expect(result[:text]).to eq("通常")
      end

      it "handles exactly 2x safety stock" do
        allow(store_inventory).to receive(:quantity).and_return(20)
        allow(store_inventory).to receive(:safety_stock_level).and_return(10)

        result = helper.stock_level_badge(store_inventory)
        expect(result[:class]).to eq("badge bg-success")
        expect(result[:text]).to eq("在庫充分")
      end
    end

    describe "#turnover_days edge cases" do
      let(:store_inventory) { double("StoreInventory") }

      it "handles nil safety_stock_level" do
        allow(store_inventory).to receive(:quantity).and_return(100)
        allow(store_inventory).to receive(:safety_stock_level).and_return(nil)

        expect(helper.turnover_days(store_inventory)).to eq("100日")
      end

      it "handles negative quantity" do
        allow(store_inventory).to receive(:quantity).and_return(-10)
        allow(store_inventory).to receive(:safety_stock_level).and_return(5)

        expect(helper.turnover_days(store_inventory)).to eq("N/A")
      end

      it "handles very large quantity" do
        allow(store_inventory).to receive(:quantity).and_return(10000)
        allow(store_inventory).to receive(:safety_stock_level).and_return(30)

        expect(helper.turnover_days(store_inventory)).to eq("10000日")
      end

      it "handles fractional days" do
        allow(store_inventory).to receive(:quantity).and_return(50)
        allow(store_inventory).to receive(:safety_stock_level).and_return(60)

        # Daily consumption = 60/30 = 2, days = 50/2 = 25
        expect(helper.turnover_days(store_inventory)).to eq("25日")
      end
    end

    describe "#format_ip_address edge cases" do
      it "handles invalid IP formats" do
        expect(helper.format_ip_address("192.168")).to eq("192.168")
        expect(helper.format_ip_address("192.168.1")).to eq("192.168.1")
        expect(helper.format_ip_address("192.168.1.256")).to eq("192.168.1.***")
      end

      it "handles localhost" do
        expect(helper.format_ip_address("127.0.0.1")).to eq("127.0.0.***")
        expect(helper.format_ip_address("::1")).to eq("::1")
      end

      it "handles IPv6 with brackets" do
        expect(helper.format_ip_address("[2001:db8::1]")).to eq("[2001:db8::1]")
      end
    end

    describe "#password_strength_class edge cases" do
      it "handles negative days" do
        expect(helper.password_strength_class(-1)).to eq("text-danger")
        expect(helper.password_strength_class(-100)).to eq("text-danger")
      end

      it "handles boundary values" do
        expect(helper.password_strength_class(8)).to eq("text-warning")
        expect(helper.password_strength_class(7)).to eq("text-danger")
        expect(helper.password_strength_class(30)).to eq("text-warning")
        expect(helper.password_strength_class(31)).to eq("text-success")
      end

      it "handles nil days" do
        expect(helper.password_strength_class(nil)).to eq("text-danger")
      end
    end

    describe "#sort_direction edge cases" do
      it "handles uppercase direction" do
        allow(helper).to receive(:params).and_return({ direction: "DESC" })
        expect(helper.sort_direction).to eq("asc")
      end

      it "handles lowercase desc" do
        allow(helper).to receive(:params).and_return({ direction: "desc" })
        expect(helper.sort_direction).to eq("desc")
      end

      it "handles invalid values" do
        allow(helper).to receive(:params).and_return({ direction: "descending" })
        expect(helper.sort_direction).to eq("asc")
      end

      it "handles nil params" do
        allow(helper).to receive(:params).and_return(nil)
        expect(helper.sort_direction).to eq("asc")
      end
    end

    describe "flash helper edge cases" do
      it "handles empty string messages" do
        expect(helper.flash_alert_class("")).to eq("alert-info")
        expect(helper.flash_icon_class("")).to eq("bi bi-info-circle")
        expect(helper.flash_title_for("")).to be_nil
        expect(helper.flash_detail_for("", "")).to be_nil
      end

      it "handles mixed case flash types" do
        expect(helper.flash_alert_class("Notice")).to eq("alert-info")
        expect(helper.flash_alert_class("SUCCESS")).to eq("alert-info")
        expect(helper.flash_alert_class("Alert")).to eq("alert-info")
      end
    end

    describe "current_section edge cases" do
      let(:mock_controller) { double("Controller") }

      before do
        allow(helper).to receive(:controller).and_return(mock_controller)
      end

      it "handles namespaced controllers" do
        allow(mock_controller).to receive_message_chain(:class, :name).and_return("Api::V1::InventoriesController")
        expect(helper.current_section).to eq("public")
      end

      it "handles controllers with Admin in name but not namespace" do
        allow(mock_controller).to receive_message_chain(:class, :name).and_return("AdminReportsController")
        expect(helper.current_section).to eq("public")
      end

      it "handles nil controller" do
        allow(helper).to receive(:controller).and_return(nil)
        expect(helper.current_section).to eq("public")
      end

      it "handles controller without class method" do
        allow(mock_controller).to receive(:class).and_raise(NoMethodError)
        expect(helper.current_section).to eq("public")
      end
    end

    describe "footer helpers with different sections" do
      it "handles unknown section" do
        allow(helper).to receive(:current_section).and_return("unknown")
        expect(helper.footer_classes).to eq("footer-public bg-dark text-light py-4 mt-auto")
        expect(helper.footer_container_classes).to eq("container")
        expect(helper.footer_brand_icon_class).to eq("bi bi-boxes-stacked")
        expect(helper.footer_brand_icon_color).to eq("text-primary")
        expect(helper.footer_badge_class).to eq("bg-secondary")
        expect(helper.footer_default_description).to eq("モダンな在庫管理システム")
      end
    end
  end
end
