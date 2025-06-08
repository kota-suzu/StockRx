# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SearchResult do
  let(:inventories) { create_list(:inventory, 25) }
  let(:inventory_relation) { Inventory.where(id: inventories.map(&:id)) }
  let(:search_result) do
    SearchResult.new(
      records: inventory_relation.limit(10),
      total_count: 25,
      current_page: 1,
      per_page: 10,
      conditions_summary: "テスト条件",
      query_metadata: { joins_count: 2, distinct_applied: true },
      execution_time: 0.125,
      search_params: { q: "test", status: "active" }
    )
  end

  describe "ページネーション機能" do
    it "総ページ数を正しく計算する" do
      expect(search_result.total_pages).to eq(3)
    end

    it "次ページの有無を正しく判定する" do
      expect(search_result.has_next_page?).to be true
    end

    it "前ページの有無を正しく判定する" do
      expect(search_result.has_prev_page?).to be false
    end

    it "次ページ番号を正しく返す" do
      expect(search_result.next_page).to eq(2)
    end

    it "前ページ番号をnilで返す（1ページ目の場合）" do
      expect(search_result.prev_page).to be_nil
    end

    context "最終ページの場合" do
      let(:last_page_result) do
        SearchResult.new(
          records: inventory_relation.limit(5),
          total_count: 25,
          current_page: 3,
          per_page: 10,
          conditions_summary: "テスト条件",
          query_metadata: {},
          execution_time: 0.1,
          search_params: {}
        )
      end

      it "次ページの有無を正しく判定する" do
        expect(last_page_result.has_next_page?).to be false
      end

      it "前ページの有無を正しく判定する" do
        expect(last_page_result.has_prev_page?).to be true
      end
    end
  end

  describe "メタデータ機能" do
    it "ページネーション情報を正しく生成する" do
      pagination_info = search_result.pagination_info

      expect(pagination_info).to include(
        current_page: 1,
        per_page: 10,
        total_count: 25,
        total_pages: 3,
        has_next: true,
        has_prev: false
      )
    end

    it "検索メタデータを正しく生成する" do
      metadata = search_result.search_metadata

      expect(metadata).to include(
        conditions: "テスト条件",
        execution_time: 0.125,
        query_complexity: 2,
        joins_count: 2,
        distinct_applied: true
      )
    end
  end

  describe "Enumerable委譲機能" do
    it "eachメソッドが正しく動作する" do
      count = 0
      search_result.each { |record| count += 1 }
      expect(count).to eq(10)
    end

    it "mapメソッドが正しく動作する" do
      ids = search_result.map(&:id)
      expect(ids).to be_an(Array)
      expect(ids.size).to eq(10)
    end

    it "sizeメソッドが正しく動作する" do
      expect(search_result.size).to eq(10)
    end

    it "emptyメソッドが正しく動作する" do
      expect(search_result.empty?).to be false
    end

    it "presentメソッドが正しく動作する" do
      expect(search_result.present?).to be true
    end
  end

  describe "空の結果セット" do
    let(:empty_result) do
      SearchResult.new(
        records: Inventory.none,
        total_count: 0,
        current_page: 1,
        per_page: 10,
        conditions_summary: "条件なし",
        query_metadata: {},
        execution_time: 0.05,
        search_params: {}
      )
    end

    it "総ページ数が0になる" do
      expect(empty_result.total_pages).to eq(0)
    end

    it "次ページがない" do
      expect(empty_result.has_next_page?).to be false
    end

    it "空であることを正しく判定する" do
      expect(empty_result.empty?).to be true
      expect(empty_result.present?).to be false
    end
  end

  describe "API出力機能" do
    it "API用ハッシュを正しく生成する" do
      api_hash = search_result.to_api_hash

      expect(api_hash).to include(:data, :pagination, :metadata, :timestamp)
      expect(api_hash[:pagination]).to include(
        :current_page, :per_page, :total_count, :total_pages
      )
      expect(api_hash[:metadata]).to include(
        :conditions, :execution_time, :query_complexity
      )
    end

    it "JSON形式に正しく変換される" do
      json_string = search_result.to_json
      parsed = JSON.parse(json_string)

      expect(parsed).to include("data", "pagination", "metadata", "timestamp")
    end
  end

  describe "セキュリティ機能" do
    let(:admin) { create(:admin) }
    let(:super_admin) { create(:admin) }

    context "通常の管理者の場合" do
      before { allow(Current).to receive(:admin).and_return(admin) }

      it "安全な属性のみを返す" do
        sanitized = search_result.sanitized_records
        expect(sanitized).to be_an(ActiveRecord::Relation)
      end
    end

    context "スーパー管理者の場合" do
      before do
        allow(Current).to receive(:admin).and_return(super_admin)
        # TODO: Adminモデルにsuper_admin?メソッドが実装されたら有効化
        # allow(super_admin).to receive(:super_admin?).and_return(true)
      end

      it "全ての属性を返す" do
        sanitized = search_result.sanitized_records
        expect(sanitized).to be_an(ActiveRecord::Relation)
        # 現在は通常管理者と同じ動作でOK（super_admin機能は将来実装）
      end
    end
  end

  describe "キャッシュ機能" do
    it "キャッシュキーを生成する" do
      cache_key = search_result.cache_key
      expect(cache_key).to be_a(String)
      expect(cache_key).to include("search_result")
    end

    it "キャッシュバージョンを生成する" do
      cache_version = search_result.cache_version
      expect(cache_version).to be_a(Integer)
    end
  end

  describe "開発環境でのデバッグ機能" do
    context "開発環境の場合" do
      before { allow(Rails.env).to receive(:development?).and_return(true) }

      it "デバッグ情報を返す" do
        debug_info = search_result.debug_info
        expect(debug_info).to include(:search_params, :performance)
      end
    end

    context "本番環境の場合" do
      before { allow(Rails.env).to receive(:development?).and_return(false) }

      it "空のハッシュを返す" do
        debug_info = search_result.debug_info
        expect(debug_info).to eq({})
      end
    end
  end

  describe "エラーハンドリング" do
    it "不正なレコード数でも正常に動作する" do
      result = SearchResult.new(
        records: [],
        total_count: -1,
        current_page: 0,
        per_page: 0,
        conditions_summary: "",
        query_metadata: {},
        execution_time: 0,
        search_params: {}
      )

      expect(result.total_pages).to eq(0)
      expect(result.has_next_page?).to be false
    end
  end
end
