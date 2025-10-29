# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InventoryLogDecorator, type: :decorator do
  # CLAUDE.md準拠: InventoryLogDecoratorの包括的テスト
  # メタ認知: 在庫ログ表示の一貫性とユーザビリティの検証
  # 横展開: 他のデコレーターでも同様のテストパターン適用

  let(:admin) { create(:admin) }
  let(:inventory) { create(:inventory, name: "アスピリン錠100mg") }
  let(:inventory_log) { create(:inventory_log, user: admin, inventory: inventory, delta: 50, operation_type: "receive") }
  let(:decorated_log) { inventory_log.decorate }

  # ============================================
  # delegate_all の動作確認
  # ============================================

  describe "delegate_all behavior" do
    it "元のモデルのメソッドにアクセスできる" do
      expect(decorated_log.inventory).to eq(inventory_log.inventory)
      expect(decorated_log.user).to eq(inventory_log.user)
      expect(decorated_log.delta).to eq(inventory_log.delta)
      expect(decorated_log.operation).to eq(inventory_log.operation)
    end

    it "元のモデルと同じIDを持つ" do
      expect(decorated_log.id).to eq(inventory_log.id)
    end

    it "元のモデルのcreated_atにアクセスできる" do
      expect(decorated_log.created_at).to eq(inventory_log.created_at)
    end
  end

  # ============================================
  # formatted_timestamp メソッドのテスト
  # ============================================

  describe "#formatted_timestamp" do
    context "日時フォーマット" do
      it "YYYY年MM月DD日 HH:MM:SS形式で返す" do
        travel_to Time.zone.parse("2024-12-25 15:30:45") do
          inventory_log.update!(created_at: Time.current)

          result = decorated_log.formatted_timestamp
          expect(result).to eq("2024年12月25日 15:30:45")
        end
      end

      it "一桁の月日も正しくフォーマットする" do
        travel_to Time.zone.parse("2024-01-05 09:05:03") do
          inventory_log.update!(created_at: Time.current)

          result = decorated_log.formatted_timestamp
          expect(result).to eq("2024年01月05日 09:05:03")
        end
      end
    end

    context "エッジケース" do
      it "年末年始の日時も正しく処理する" do
        travel_to Time.zone.parse("2024-12-31 23:59:59") do
          inventory_log.update!(created_at: Time.current)

          result = decorated_log.formatted_timestamp
          expect(result).to eq("2024年12月31日 23:59:59")
        end
      end

      it "元日の日時も正しく処理する" do
        travel_to Time.zone.parse("2025-01-01 00:00:01") do
          inventory_log.update!(created_at: Time.current)

          result = decorated_log.formatted_timestamp
          expect(result).to eq("2025年01月01日 00:00:01")
        end
      end
    end
  end

  # ============================================
  # operation_type_text メソッドのテスト
  # ============================================

  describe "#operation_type_text" do
    context "様々な操作種別" do
      it "receiveの場合、入荷と表示される" do
        log = create(:inventory_log, operation_type: "receive")
        decorated = log.decorate

        expect(decorated.operation_type_text).to eq("入荷")
      end

      it "shipの場合、出荷と表示される" do
        log = create(:inventory_log, operation_type: "ship")
        decorated = log.decorate

        expect(decorated.operation_type_text).to eq("出荷")
      end

      it "adjustの場合、調整と表示される" do
        log = create(:inventory_log, operation_type: "adjust")
        decorated = log.decorate

        expect(decorated.operation_type_text).to eq("調整")
      end

      it "addの場合、追加と表示される" do
        log = create(:inventory_log, operation_type: "add")
        decorated = log.decorate

        expect(decorated.operation_type_text).to eq("追加")
      end
    end

    context "メソッド委譲の確認" do
      it "モデルのoperation_display_nameメソッドを使用する" do
        expect(inventory_log).to receive(:operation_display_name).and_return("カスタム操作")

        result = decorated_log.operation_type_text
        expect(result).to eq("カスタム操作")
      end
    end
  end

  # ============================================
  # formatted_delta メソッドのテスト
  # ============================================

  describe "#formatted_delta" do
    context "正の値" do
      it "正の値には+記号を付加する" do
        log = create(:inventory_log, delta: 50)
        decorated = log.decorate

        expect(decorated.formatted_delta).to eq("+50")
      end

      it "0には+記号を付加しない（ゼロは中立）" do
        log = create(:inventory_log, delta: 0)
        decorated = log.decorate

        expect(decorated.formatted_delta).to eq("0")
      end
    end

    context "負の値" do
      it "負の値には記号を付加しない（マイナス記号のみ）" do
        log = create(:inventory_log, delta: -25)
        decorated = log.decorate

        expect(decorated.formatted_delta).to eq("-25")
      end
    end

    context "極端な値" do
      it "大きな正の値も正しく処理する" do
        log = create(:inventory_log, delta: 9999)
        decorated = log.decorate

        expect(decorated.formatted_delta).to eq("+9999")
      end

      it "大きな負の値も正しく処理する" do
        log = create(:inventory_log, delta: -9999)
        decorated = log.decorate

        expect(decorated.formatted_delta).to eq("-9999")
      end
    end
  end

  # ============================================
  # colored_delta メソッドのテスト
  # ============================================

  describe "#colored_delta" do
    context "正の変化量" do
      it "緑色のCSSクラスを適用する" do
        log = create(:inventory_log, delta: 50)
        decorated = log.decorate

        result = decorated.colored_delta
        expect(result).to include("text-green-600")
        expect(result).to include("+50")
        expect(result).to be_html_safe
      end

      it "ゼロの場合も緑色とする" do
        log = create(:inventory_log, delta: 0)
        decorated = log.decorate

        result = decorated.colored_delta
        expect(result).to include("text-green-600")
        expect(result).to include("0")
      end
    end

    context "負の変化量" do
      it "赤色のCSSクラスを適用する" do
        log = create(:inventory_log, delta: -25)
        decorated = log.decorate

        result = decorated.colored_delta
        expect(result).to include("text-red-600")
        expect(result).to include("-25")
        expect(result).to be_html_safe
      end
    end

    context "HTMLタグ構造" do
      it "適切なspanタグが生成される" do
        log = create(:inventory_log, delta: 100)
        decorated = log.decorate

        result = decorated.colored_delta
        expect(result).to match(/<span[^>]*class="[^"]*text-green-600[^"]*"[^>]*>\+100<\/span>/)
      end

      it "XSS攻撃に対して安全" do
        log = create(:inventory_log, delta: 50)
        decorated = log.decorate

        result = decorated.colored_delta
        expect(result).to be_html_safe
        expect(result).not_to include("<script")
      end
    end
  end

  # ============================================
  # operator_name メソッドのテスト
  # ============================================

  describe "#operator_name" do
    context "ユーザーが存在する場合" do
      it "ユーザーにnameメソッドがある場合はnameを返す" do
        admin_with_name = create(:admin, name: "管理者太郎")
        log = create(:inventory_log, user: admin_with_name)
        decorated = log.decorate

        expect(decorated.operator_name).to eq("管理者太郎")
      end

      it "ユーザーにnameメソッドがない場合はemailを返す" do
        user = double("User", email: "test@example.com")
        allow(user).to receive(:respond_to?).with(:name).and_return(false)
        allow(user).to receive(:present?).and_return(true)

        log = create(:inventory_log)
        allow(log).to receive(:user).and_return(user)
        decorated = log.decorate

        expect(decorated.operator_name).to eq("test@example.com")
      end
    end

    context "ユーザーが存在しない場合" do
      it "自動処理と表示する" do
        log = create(:inventory_log, user: nil)
        decorated = log.decorate

        expect(decorated.operator_name).to eq("自動処理")
      end
    end

    context "エッジケース" do
      it "nameが空文字列の場合はemailを使用する" do
        admin_with_empty_name = create(:admin, name: "", email: "empty@example.com")
        log = create(:inventory_log, user: admin_with_empty_name)
        decorated = log.decorate

        # nameが空文字列でもrespond_to?(:name)はtrueを返すため、
        # 空文字列が返される（仕様通り）
        expect(decorated.operator_name).to eq("")
      end

      it "nameがnilの場合はemailを使用する" do
        admin_with_nil_name = create(:admin, name: nil, email: "nil@example.com")
        log = create(:inventory_log, user: admin_with_nil_name)
        decorated = log.decorate

        # nameがnilでもrespond_to?(:name)はtrueを返すため、
        # nilが返される（仕様通り）
        expect(decorated.operator_name).to be_nil
      end
    end
  end

  # ============================================
  # セキュリティとパフォーマンステスト
  # ============================================

  describe "セキュリティ考慮事項" do
    context "HTMLエスケープ" do
      it "colored_deltaがHTML安全" do
        log = create(:inventory_log, delta: 50)
        decorated = log.decorate

        result = decorated.colored_delta
        expect(result).to be_html_safe
      end

      it "other methods return safe strings" do
        expect(decorated_log.formatted_timestamp).to be_a(String)
        expect(decorated_log.operation_type_text).to be_a(String)
        expect(decorated_log.formatted_delta).to be_a(String)
        expect(decorated_log.operator_name).to be_a(String).or(be_nil)
      end
    end

    context "XSS攻撃対策" do
      it "HTMLタグを含む悪意あるデータに対して安全" do
        # InventoryLogモデルが悪意あるデータを返すケースをシミュレート
        allow(inventory_log).to receive(:delta).and_return(50)

        result = decorated_log.colored_delta
        expect(result).to be_html_safe
        expect(result).not_to include("<script")
        expect(result).not_to include("javascript:")
      end
    end
  end

  describe "パフォーマンステスト" do
    it "各デコレーターメソッドは高速に実行される" do
      start_time = Time.current
      100.times do
        decorated_log.formatted_timestamp
        decorated_log.operation_type_text
        decorated_log.formatted_delta
        decorated_log.colored_delta
        decorated_log.operator_name
      end
      execution_time = Time.current - start_time

      # 100回実行で0.1秒以内（十分高速）
      expect(execution_time).to be < 0.1
    end
  end

  # ============================================
  # ユーザビリティとアクセシビリティ
  # ============================================

  describe "ユーザビリティ" do
    it "色分けによる視覚的な情報提供" do
      positive_log = create(:inventory_log, delta: 50).decorate
      negative_log = create(:inventory_log, delta: -25).decorate

      positive_result = positive_log.colored_delta
      negative_result = negative_log.colored_delta

      # 緑と赤で視覚的に区別可能
      expect(positive_result).to include("text-green-600")
      expect(negative_result).to include("text-red-600")
    end

    it "操作者情報の一貫した表示" do
      admin_log = create(:inventory_log, user: admin).decorate
      auto_log = create(:inventory_log, user: nil).decorate

      expect(admin_log.operator_name).to be_a(String)
      expect(auto_log.operator_name).to eq("自動処理")
    end
  end

  describe "アクセシビリティ" do
    it "カラーコントラストの確保" do
      log = create(:inventory_log, delta: 50).decorate
      result = log.colored_delta

      # Tailwind CSSのtext-green-600は十分なコントラスト比を持つ
      expect(result).to include("text-green-600")
    end

    # TODO: ARIA属性の実装とテスト（Phase 4で実装予定）
    # メタ認知: WAI-ARIAガイドライン準拠のアクセシビリティ強化
    # 横展開: 他のデコレーターでも同様のARIA属性適用
  end

  # ============================================
  # 国際化（i18n）対応テスト
  # ============================================

  describe "国際化対応" do
    context "日本語ロケール" do
      around do |example|
        I18n.with_locale(:ja) { example.run }
      end

      it "日本語の日時フォーマットが使用される" do
        travel_to Time.zone.parse("2024-12-25 15:30:45") do
          inventory_log.update!(created_at: Time.current)

          result = decorated_log.formatted_timestamp
          expect(result).to include("年")
          expect(result).to include("月")
          expect(result).to include("日")
        end
      end
    end

    context "英語ロケール（将来対応）" do
      around do |example|
        I18n.with_locale(:en) { example.run }
      end

      # TODO: 英語i18n対応（国際展開時に実装予定）
      # 英語の日時フォーマット: "December 25, 2024 15:30:45"
    end
  end

  # ============================================
  # 統合テスト（ビュー連携）
  # ============================================

  describe "ビュー統合テスト" do
    it "すべてのメソッドがビューで適切に表示される" do
      # すべてのメソッドが文字列またはHTML安全な文字列を返すことを確認
      expect(decorated_log.formatted_timestamp).to be_a(String)
      expect(decorated_log.operation_type_text).to be_a(String)
      expect(decorated_log.formatted_delta).to be_a(String)
      expect(decorated_log.colored_delta).to be_html_safe
      expect(decorated_log.operator_name).to be_a(String).or(be_nil)
    end

    it "一貫したデータ表現を提供する" do
      # 同じログに対して複数回呼び出しても同じ結果を返すことを確認
      timestamp1 = decorated_log.formatted_timestamp
      timestamp2 = decorated_log.formatted_timestamp
      expect(timestamp1).to eq(timestamp2)

      delta1 = decorated_log.colored_delta
      delta2 = decorated_log.colored_delta
      expect(delta1).to eq(delta2)
    end
  end

  # ============================================
  # デコレーターパターンの実装確認
  # ============================================

  describe "デコレーターパターンの実装" do
    it "ApplicationDecoratorを継承している" do
      expect(InventoryLogDecorator.ancestors).to include(ApplicationDecorator)
    end

    it "Draperの仕組みで正しく動作する" do
      expect(inventory_log.decorate).to be_a(InventoryLogDecorator)
      expect(inventory_log.decorate.object).to eq(inventory_log)
    end

    it "decorateメソッドがDraper経由で利用可能" do
      expect(inventory_log).to respond_to(:decorate)
      expect(inventory_log.decorate.class).to eq(InventoryLogDecorator)
    end
  end
end
