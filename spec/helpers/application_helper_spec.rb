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
end
