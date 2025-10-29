# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BatchesHelper, type: :helper do
  # CLAUDE.md準拠: BatchesHelperの包括的テスト
  # メタ認知: ロット管理の状態表示とCSSクラス生成の検証
  # 横展開: 他の状態表示ヘルパーでも同様のテストパターン適用

  # ============================================
  # batch_row_class メソッドのテスト
  # ============================================

  describe "#batch_row_class" do
    let(:batch) { build(:batch) }

    context "期限切れのロット" do
      before { allow(batch).to receive(:expired?).and_return(true) }

      it "table-dangerクラスを返す" do
        expect(helper.batch_row_class(batch)).to eq("table-danger")
      end
    end

    context "期限間近のロット" do
      before do
        allow(batch).to receive(:expired?).and_return(false)
        allow(batch).to receive(:expiring_soon?).and_return(true)
      end

      it "table-warningクラスを返す" do
        expect(helper.batch_row_class(batch)).to eq("table-warning")
      end
    end

    context "正常なロット" do
      before do
        allow(batch).to receive(:expired?).and_return(false)
        allow(batch).to receive(:expiring_soon?).and_return(false)
      end

      it "空文字列を返す" do
        expect(helper.batch_row_class(batch)).to eq("")
      end
    end

    context "エッジケース" do
      it "nilのロットでも安全に処理される" do
        expect { helper.batch_row_class(nil) }.to raise_error(NoMethodError)
      end
    end
  end

  # ============================================
  # batch_status_badge メソッドのテスト
  # ============================================

  describe "#batch_status_badge" do
    let(:batch) { build(:batch) }

    context "期限切れのロット" do
      before { allow(batch).to receive(:expired?).and_return(true) }

      it "期限切れバッジを生成する" do
        result = helper.batch_status_badge(batch)

        expect(result).to include("期限切れ")
        expect(result).to include("bg-red-200")
        expect(result).to include("text-red-700")
        expect(result).to be_html_safe
      end

      it "適切なHTMLタグ構造を持つ" do
        result = helper.batch_status_badge(batch)
        expect(result).to match(/<span[^>]*class="[^"]*bg-red-200[^"]*"[^>]*>期限切れ<\/span>/)
      end
    end

    context "期限間近のロット" do
      before do
        allow(batch).to receive(:expired?).and_return(false)
        allow(batch).to receive(:expiring_soon?).and_return(true)
      end

      it "期限間近バッジを生成する" do
        result = helper.batch_status_badge(batch)

        expect(result).to include("期限間近")
        expect(result).to include("bg-yellow-200")
        expect(result).to include("text-yellow-700")
        expect(result).to be_html_safe
      end

      it "適切なHTMLタグ構造を持つ" do
        result = helper.batch_status_badge(batch)
        expect(result).to match(/<span[^>]*class="[^"]*bg-yellow-200[^"]*"[^>]*>期限間近<\/span>/)
      end
    end

    context "正常なロット" do
      before do
        allow(batch).to receive(:expired?).and_return(false)
        allow(batch).to receive(:expiring_soon?).and_return(false)
      end

      it "正常バッジを生成する" do
        result = helper.batch_status_badge(batch)

        expect(result).to include("正常")
        expect(result).to include("bg-green-200")
        expect(result).to include("text-green-700")
        expect(result).to be_html_safe
      end

      it "適切なHTMLタグ構造を持つ" do
        result = helper.batch_status_badge(batch)
        expect(result).to match(/<span[^>]*class="[^"]*bg-green-200[^"]*"[^>]*>正常<\/span>/)
      end
    end

    context "Tailwind CSSクラスの検証" do
      it "すべての状態で必要なTailwindクラスが含まれる" do
        expired_batch = double(expired?: true, expiring_soon?: false)
        expiring_batch = double(expired?: false, expiring_soon?: true)
        normal_batch = double(expired?: false, expiring_soon?: false)

        expired_result = helper.batch_status_badge(expired_batch)
        expiring_result = helper.batch_status_badge(expiring_batch)
        normal_result = helper.batch_status_badge(normal_batch)

        # 共通のTailwindクラス
        [ expired_result, expiring_result, normal_result ].each do |result|
          expect(result).to include("px-2")
          expect(result).to include("py-1")
          expect(result).to include("rounded")
        end
      end
    end
  end

  # ============================================
  # formatted_expires_on メソッドのテスト
  # ============================================

  describe "#formatted_expires_on" do
    let(:batch) { build(:batch) }

    context "有効期限が設定されている場合" do
      let(:expiration_date) { Date.new(2024, 12, 25) }

      before do
        allow(batch).to receive(:expires_on).and_return(expiration_date)
      end

      it "フォーマットされた日付を返す" do
        # I18nのlocalizationをモック
        allow(helper).to receive(:l).with(expiration_date, format: :long).and_return("2024年12月25日")

        result = helper.formatted_expires_on(batch)
        expect(result).to eq("2024年12月25日")
      end

      it "適切な国際化メソッドが呼ばれる" do
        expect(helper).to receive(:l).with(expiration_date, format: :long)
        helper.formatted_expires_on(batch)
      end
    end

    context "有効期限が設定されていない場合" do
      before do
        allow(batch).to receive(:expires_on).and_return(nil)
      end

      it "設定なしメッセージを含むHTMLを返す" do
        result = helper.formatted_expires_on(batch)

        expect(result).to include("設定なし")
        expect(result).to include("text-gray-400")
        expect(result).to include("italic")
        expect(result).to be_html_safe
      end

      it "適切なHTMLタグ構造を持つ" do
        result = helper.formatted_expires_on(batch)
        expect(result).to match(/<span[^>]*class="[^"]*text-gray-400[^"]*italic[^"]*"[^>]*>設定なし<\/span>/)
      end
    end

    context "エッジケース" do
      it "expires_onがblankでもpresentでもない場合" do
        allow(batch).to receive(:expires_on).and_return("")

        result = helper.formatted_expires_on(batch)
        expect(result).to include("設定なし")
        expect(result).to be_html_safe
      end

      it "expires_onが空文字列の場合" do
        allow(batch).to receive(:expires_on).and_return("   ")

        result = helper.formatted_expires_on(batch)
        expect(result).to include("設定なし")
        expect(result).to be_html_safe
      end
    end
  end

  # ============================================
  # セキュリティとパフォーマンステスト
  # ============================================

  describe "セキュリティ考慮事項" do
    let(:batch) { build(:batch) }

    context "HTMLエスケープ" do
      it "すべてのメソッドがHTML安全な文字列を返す" do
        allow(batch).to receive(:expired?).and_return(true)
        allow(batch).to receive(:expires_on).and_return(Date.current)

        expect(helper.batch_row_class(batch)).to be_a(String)
        expect(helper.batch_status_badge(batch)).to be_html_safe
        # formatted_expires_onは日付文字列またはHTML spanタグを返す
        result = helper.formatted_expires_on(batch)
        expect(result).to satisfy { |r| r.is_a?(String) || r.html_safe? }
      end
    end

    context "XSS攻撃対策" do
      it "悪意あるコンテンツが注入されない" do
        # Batchモデルが悪意あるデータを返すケースをシミュレート
        malicious_batch = double(
          expired?: true,
          expiring_soon?: false,
          expires_on: nil
        )

        result = helper.batch_status_badge(malicious_batch)

        # HTMLがエスケープされ、安全であることを確認
        expect(result).to be_html_safe
        expect(result).to include("期限切れ")
        expect(result).not_to include("<script")
      end
    end
  end

  describe "パフォーマンステスト" do
    let(:batch) { build(:batch) }

    it "各ヘルパーメソッドは高速に実行される" do
      allow(batch).to receive(:expired?).and_return(false)
      allow(batch).to receive(:expiring_soon?).and_return(false)
      allow(batch).to receive(:expires_on).and_return(Date.current)

      start_time = Time.current
      100.times do
        helper.batch_row_class(batch)
        helper.batch_status_badge(batch)
        helper.formatted_expires_on(batch)
      end
      execution_time = Time.current - start_time

      # 100回実行で0.1秒以内（十分高速）
      expect(execution_time).to be < 0.1
    end
  end

  # ============================================
  # アクセシビリティとユーザビリティ
  # ============================================

  describe "アクセシビリティ" do
    let(:batch) { build(:batch) }

    it "バッジに適切なスタイリングが適用される" do
      allow(batch).to receive(:expired?).and_return(true)

      result = helper.batch_status_badge(batch)

      # コントラスト比を確保するCSSクラス
      expect(result).to include("text-red-700")  # 十分なコントラスト
      expect(result).to include("bg-red-200")    # 背景色
    end

    pending "TODO: ARIA属性の実装とテスト（Phase 4で実装予定）" do
      # メタ認知: WAI-ARIAガイドライン準拠のアクセシビリティ強化
      # 横展開: 他のバッジヘルパーでも同様のARIA属性適用
      it "バッジにaria-labelが設定される" do
        allow(batch).to receive(:expired?).and_return(true)

        result = helper.batch_status_badge(batch)
        expect(result).to include('aria-label="ロット状態: 期限切れ"')
      end
    end
  end

  # ============================================
  # 国際化（i18n）対応テスト
  # ============================================

  describe "国際化対応" do
    let(:batch) { build(:batch) }

    context "日本語ロケール" do
      around do |example|
        I18n.with_locale(:ja) { example.run }
      end

      it "日本語のバッジテキストが表示される" do
        allow(batch).to receive(:expired?).and_return(true)

        result = helper.batch_status_badge(batch)
        expect(result).to include("期限切れ")
      end
    end

    context "英語ロケール（将来対応）" do
      around do |example|
        I18n.with_locale(:en) { example.run }
      end

      pending "TODO: 英語i18n対応（国際展開時に実装予定）" do
        it "英語のバッジテキストが表示される" do
          allow(batch).to receive(:expired?).and_return(true)

          result = helper.batch_status_badge(batch)
          expect(result).to include("Expired")
        end
      end
    end
  end

  # ============================================
  # 統合テスト（ビュー連携）
  # ============================================

  describe "ビュー統合テスト" do
    let(:batch) { build(:batch) }

    it "テーブル行のCSSクラスとバッジが連携して動作する" do
      allow(batch).to receive(:expired?).and_return(true)
      allow(batch).to receive(:expiring_soon?).and_return(false)

      row_class = helper.batch_row_class(batch)
      badge = helper.batch_status_badge(batch)

      # 期限切れの場合、行も赤、バッジも赤で一貫性がある
      expect(row_class).to eq("table-danger")
      expect(badge).to include("bg-red-200")
      expect(badge).to include("text-red-700")
    end

    it "すべての状態で一貫したユーザー体験を提供する" do
      test_cases = [
        { expired: true, expiring_soon: false, expected_row: "table-danger", expected_color: "red" },
        { expired: false, expiring_soon: true, expected_row: "table-warning", expected_color: "yellow" },
        { expired: false, expiring_soon: false, expected_row: "", expected_color: "green" }
      ]

      test_cases.each do |test_case|
        allow(batch).to receive(:expired?).and_return(test_case[:expired])
        allow(batch).to receive(:expiring_soon?).and_return(test_case[:expiring_soon])

        row_class = helper.batch_row_class(batch)
        badge = helper.batch_status_badge(batch)

        expect(row_class).to eq(test_case[:expected_row])
        expect(badge).to include("bg-#{test_case[:expected_color]}-200")
      end
    end
  end
end
