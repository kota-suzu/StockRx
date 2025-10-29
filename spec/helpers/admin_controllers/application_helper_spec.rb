# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::ApplicationHelper, type: :helper do
  # CLAUDE.md準拠: 管理画面用ヘルパーの包括的テスト
  # メタ認知: UIコンポーネントの一貫性とユーザビリティの検証
  # 横展開: 他のヘルパーでも同様のテストパターン適用

  let(:inventory) { create(:inventory) }

  # ============================================
  # legacy_button_to_new_format メソッドのテスト
  # ============================================

  describe "#legacy_button_to_new_format" do
    context "新形式のハッシュ（:text キーあり）が渡された場合" do
      let(:new_format_button) do
        {
          text: "カスタムボタン",
          path: "/custom/path",
          icon: "bi-custom",
          class: "btn-custom"
        }
      end

      it "そのまま返される" do
        result = helper.legacy_button_to_new_format(new_format_button)
        expect(result).to eq(new_format_button)
      end

      it "元のハッシュオブジェクトが変更されない" do
        original = new_format_button.dup
        helper.legacy_button_to_new_format(new_format_button)
        expect(new_format_button).to eq(original)
      end
    end

    context "レガシー形式のハッシュ（:text キーなし）が渡された場合" do
      let(:legacy_hash) do
        {
          action: "show",
          controller: "inventories",
          id: 1
        }
      end

      it "そのまま返される" do
        result = helper.legacy_button_to_new_format(legacy_hash)
        expect(result).to eq(legacy_hash)
      end
    end

    context "シンボルが渡された場合" do
      it "デフォルト設定が生成される" do
        result = helper.legacy_button_to_new_format(:show)
        expect(result).to be_a(Hash)
        expect(result[:text]).to eq("詳細")
        expect(result[:icon]).to eq("bi-eye")
      end

      it "編集シンボルの場合、適切な設定が生成される" do
        result = helper.legacy_button_to_new_format(:edit)
        expect(result[:text]).to eq("編集")
        expect(result[:icon]).to eq("bi-pencil")
        expect(result[:class]).to eq("btn-outline-warning")
      end

      it "削除シンボルの場合、適切な設定が生成される" do
        result = helper.legacy_button_to_new_format(:delete)
        expect(result[:text]).to eq("削除")
        expect(result[:icon]).to eq("bi-trash")
        expect(result[:class]).to eq("btn-outline-danger")
        expect(result[:method]).to eq(:delete)
        expect(result[:confirm]).to eq("削除してもよろしいですか？")
      end
    end

    context "文字列が渡された場合" do
      it "デフォルト設定が生成される" do
        result = helper.legacy_button_to_new_format("show")
        expect(result).to be_a(Hash)
        expect(result[:text]).to eq("詳細")
      end

      it "view文字列でもshow扱いされる" do
        result = helper.legacy_button_to_new_format("view")
        expect(result[:text]).to eq("詳細")
        expect(result[:icon]).to eq("bi-eye")
      end

      it "destroy文字列でもdelete扱いされる" do
        result = helper.legacy_button_to_new_format("destroy")
        expect(result[:text]).to eq("削除")
        expect(result[:method]).to eq(:delete)
      end
    end

    context "不明な形式が渡された場合" do
      it "空のハッシュが返される" do
        result = helper.legacy_button_to_new_format(123)
        expect(result).to eq({})
      end

      it "配列が渡されても空のハッシュが返される" do
        result = helper.legacy_button_to_new_format([ 1, 2, 3 ])
        expect(result).to eq({})
      end

      it "nilが渡されても空のハッシュが返される" do
        result = helper.legacy_button_to_new_format(nil)
        expect(result).to eq({})
      end
    end
  end

  # ============================================
  # default_button_config メソッドのテスト
  # ============================================

  describe "#default_button_config" do
    context "show/view タイプ" do
      it "詳細ボタンの設定を返す" do
        result = helper.default_button_config("show")

        expect(result[:text]).to eq("詳細")
        expect(result[:icon]).to eq("bi-eye")
        expect(result[:class]).to eq("btn-outline-primary")
        expect(result[:tooltip]).to eq("詳細を表示")
      end

      it "view タイプでも同じ設定を返す" do
        result = helper.default_button_config("view")
        expect(result[:text]).to eq("詳細")
        expect(result[:icon]).to eq("bi-eye")
      end

      it "シンボルでも正常に動作する" do
        result = helper.default_button_config(:show)
        expect(result[:text]).to eq("詳細")
      end

      context "リソースが指定された場合" do
        it "適切なパスが生成される" do
          result = helper.default_button_config("show", inventory)
          expect(result[:path]).to eq(admin_inventory_path(inventory))
        end
      end

      context "リソースが指定されない場合" do
        it "プレースホルダーパスが設定される" do
          result = helper.default_button_config("show")
          expect(result[:path]).to eq("#")
        end
      end
    end

    context "edit タイプ" do
      it "編集ボタンの設定を返す" do
        result = helper.default_button_config("edit")

        expect(result[:text]).to eq("編集")
        expect(result[:icon]).to eq("bi-pencil")
        expect(result[:class]).to eq("btn-outline-warning")
        expect(result[:tooltip]).to eq("編集")
      end

      context "リソースが指定された場合" do
        it "適切な編集パスが生成される" do
          result = helper.default_button_config("edit", inventory)
          expect(result[:path]).to eq(edit_admin_inventory_path(inventory))
        end
      end
    end

    context "delete/destroy タイプ" do
      it "削除ボタンの設定を返す" do
        result = helper.default_button_config("delete")

        expect(result[:text]).to eq("削除")
        expect(result[:icon]).to eq("bi-trash")
        expect(result[:class]).to eq("btn-outline-danger")
        expect(result[:method]).to eq(:delete)
        expect(result[:confirm]).to eq("削除してもよろしいですか？")
        expect(result[:tooltip]).to eq("削除")
      end

      it "destroy タイプでも同じ設定を返す" do
        result = helper.default_button_config("destroy")
        expect(result[:text]).to eq("削除")
        expect(result[:method]).to eq(:delete)
      end

      context "リソースが指定された場合" do
        it "適切な削除パスが生成される" do
          result = helper.default_button_config("delete", inventory)
          expect(result[:path]).to eq(admin_inventory_path(inventory))
        end
      end
    end

    context "不明なタイプ" do
      it "汎用ボタンの設定を返す" do
        result = helper.default_button_config("custom_action")

        expect(result[:text]).to eq("Custom action")
        expect(result[:icon]).to eq("bi-gear")
        expect(result[:class]).to eq("btn-outline-secondary")
        expect(result[:path]).to eq("#")
      end

      it "空文字列でも適切に処理される" do
        result = helper.default_button_config("")
        expect(result[:text]).to eq("")
        expect(result[:icon]).to eq("bi-gear")
      end

      it "日本語タイプでも適切に処理される" do
        result = helper.default_button_config("カスタム")
        expect(result[:text]).to eq("カスタム")
      end
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe "performance tests" do
    it "legacy_button_to_new_format は高速" do
      start_time = Time.current
      1000.times do
        helper.legacy_button_to_new_format(:show)
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 100 # 100ms以内
    end

    it "default_button_config は高速" do
      start_time = Time.current
      1000.times do
        helper.default_button_config("show", inventory)
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 100 # 100ms以内
    end
  end

  # ============================================
  # 設定値の整合性テスト
  # ============================================

  describe "configuration consistency" do
    context "ボタンタイプの統一性" do
      it "show と view は同じ設定になる" do
        show_config = helper.default_button_config("show")
        view_config = helper.default_button_config("view")

        expect(show_config[:text]).to eq(view_config[:text])
        expect(show_config[:icon]).to eq(view_config[:icon])
        expect(show_config[:class]).to eq(view_config[:class])
      end

      it "delete と destroy は同じ設定になる" do
        delete_config = helper.default_button_config("delete")
        destroy_config = helper.default_button_config("destroy")

        expect(delete_config[:text]).to eq(destroy_config[:text])
        expect(delete_config[:icon]).to eq(destroy_config[:icon])
        expect(delete_config[:method]).to eq(destroy_config[:method])
      end
    end

    context "必須フィールドの存在確認" do
      %w[show edit delete].each do |type|
        it "#{type} タイプは必須フィールドを持つ" do
          config = helper.default_button_config(type)

          expect(config).to have_key(:text)
          expect(config).to have_key(:path)
          expect(config).to have_key(:icon)
          expect(config).to have_key(:class)

          expect(config[:text]).to be_present
          expect(config[:path]).to be_present
          expect(config[:icon]).to be_present
          expect(config[:class]).to be_present
        end
      end
    end

    context "Bootstrap アイコンの整合性" do
      it "全てのアイコンが bi- プレフィックスを持つ" do
        %w[show edit delete custom].each do |type|
          config = helper.default_button_config(type)
          expect(config[:icon]).to start_with("bi-")
        end
      end
    end

    context "Bootstrap CSSクラスの整合性" do
      it "全てのクラスが btn- プレフィックスを持つ" do
        %w[show edit delete custom].each do |type|
          config = helper.default_button_config(type)
          expect(config[:class]).to start_with("btn-")
        end
      end
    end
  end

  # ============================================
  # セキュリティテスト
  # ============================================

  describe "security tests" do
    context "XSS防止" do
      it "悪意のあるスクリプトを含むタイプでも安全に処理される" do
        malicious_type = "<script>alert('XSS')</script>"
        result = helper.default_button_config(malicious_type)

        # humanize が適用されXSSは無害化される
        expect(result[:text]).not_to include("<script>")
        expect(result[:text]).to include("Script") # humanizeされた結果
      end

      it "HTMLタグを含む入力でも安全に処理される" do
        html_type = "<b>bold</b>"
        result = helper.default_button_config(html_type)

        expect(result[:text]).to eq("B Bold") # humanizeされた結果
      end
    end

    context "入力検証" do
      it "非常に長い文字列でも適切に処理される" do
        long_type = "a" * 1000
        expect {
          helper.default_button_config(long_type)
        }.not_to raise_error
      end

      it "特殊文字を含む入力でも適切に処理される" do
        special_type = "test!@#$%^&*()"
        expect {
          helper.default_button_config(special_type)
        }.not_to raise_error
      end
    end
  end

  # ============================================
  # エッジケースのテスト
  # ============================================

  describe "edge cases" do
    context "境界値テスト" do
      it "空文字列が渡されても適切に処理される" do
        result = helper.legacy_button_to_new_format("")
        expect(result).to be_a(Hash)
      end

      it "非常に深いネストハッシュでも処理される" do
        deep_hash = { a: { b: { c: { d: "value" } } } }
        result = helper.legacy_button_to_new_format(deep_hash)
        expect(result).to eq(deep_hash)
      end
    end

    context "型変換の確認" do
      it "数値シンボルでも適切に文字列変換される" do
        result = helper.default_button_config(123)
        expect(result[:text]).to eq("123")
      end

      it "true/false でも適切に処理される" do
        true_result = helper.default_button_config(true)
        false_result = helper.default_button_config(false)

        expect(true_result[:text]).to eq("True")
        expect(false_result[:text]).to eq("False")
      end
    end

    context "国際化対応" do
      it "日本語タイプでも適切に処理される" do
        result = helper.default_button_config("表示")
        expect(result[:text]).to eq("表示")
        expect(result).to have_key(:icon)
        expect(result).to have_key(:class)
      end

      it "Unicode文字でも適切に処理される" do
        result = helper.default_button_config("🔍検索")
        expect(result[:text]).to eq("🔍検索")
      end
    end
  end

  # ============================================
  # レガシー互換性テスト
  # ============================================

  describe "legacy compatibility" do
    it "古いスタイルのボタン設定も新形式に統一される" do
      legacy_configs = [
        :show,
        "edit",
        { action: "delete" },
        { text: "新形式", icon: "bi-check" }
      ]

      legacy_configs.each do |config|
        result = helper.legacy_button_to_new_format(config)
        expect(result).to be_a(Hash)

        if config.is_a?(Hash) && config[:text]
          # 新形式はそのまま
          expect(result).to eq(config)
        else
          # 旧形式は変換される
          expect(result).to have_key(:text) if result.present?
        end
      end
    end

    it "混在したボタン設定配列でも適切に処理される" do
      mixed_buttons = [ :show, "edit", { text: "カスタム" } ]

      results = mixed_buttons.map do |button|
        helper.legacy_button_to_new_format(button)
      end

      expect(results).to all(be_a(Hash))
      expect(results[0][:text]).to eq("詳細") # :show
      expect(results[1][:text]).to eq("編集") # "edit"
      expect(results[2][:text]).to eq("カスタム") # 新形式
    end
  end

  # ============================================
  # アクセシビリティテスト
  # ============================================

  describe "accessibility features" do
    context "tooltipの提供" do
      it "主要ボタンタイプにはtooltipが設定される" do
        %w[show edit delete].each do |type|
          config = helper.default_button_config(type)
          expect(config).to have_key(:tooltip)
          expect(config[:tooltip]).to be_present
        end
      end
    end

    context "確認ダイアログ" do
      it "削除系ボタンには確認ダイアログが設定される" do
        delete_config = helper.default_button_config("delete")
        destroy_config = helper.default_button_config("destroy")

        expect(delete_config[:confirm]).to be_present
        expect(destroy_config[:confirm]).to be_present
      end

      it "非破壊的ボタンには確認ダイアログは設定されない" do
        show_config = helper.default_button_config("show")
        edit_config = helper.default_button_config("edit")

        expect(show_config).not_to have_key(:confirm)
        expect(edit_config).not_to have_key(:confirm)
      end
    end
  end
end
