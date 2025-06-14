# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InventoryPriceAdjustmentPatch, type: :service do
  let(:patch_options) { { adjustment_type: 'percentage', adjustment_value: 10, dry_run: true } }
  let(:patch) { described_class.new(patch_options) }

  # テストデータの作成
  before do
    FactoryBot.create_list(:inventory, 5, price: 1000)
    FactoryBot.create_list(:inventory, 3, price: 500, category: 'medicine')
  end

  describe '.estimate_target_count' do
    it '対象レコード数が正確に計算される' do
      count = described_class.estimate_target_count({})
      expect(count).to eq(8) # 全8件の在庫
    end

    it 'カテゴリフィルタが正しく適用される' do
      count = described_class.estimate_target_count({ category: 'medicine' })
      expect(count).to eq(3) # medicineカテゴリのみ
    end

    it '価格範囲フィルタが正しく適用される' do
      count = described_class.estimate_target_count({ min_price: 600 })
      expect(count).to eq(5) # 600円以上の商品
    end
  end

  describe '#initialize' do
    it '正しくオプションが設定される' do
      expect(patch.instance_variable_get(:@adjustment_type)).to eq('percentage')
      expect(patch.instance_variable_get(:@adjustment_value)).to eq(10)
    end

    context '無効な調整タイプの場合' do
      let(:patch_options) { { adjustment_type: 'invalid_type' } }

      it 'ArgumentErrorが発生する' do
        expect { patch }.to raise_error(ArgumentError, /adjustment_typeが無効です/)
      end
    end

    context '無効な調整値の場合' do
      let(:patch_options) { { adjustment_type: 'percentage', adjustment_value: 'invalid' } }

      it 'ArgumentErrorが発生する' do
        expect { patch }.to raise_error(ArgumentError, /adjustment_valueは数値である必要があります/)
      end
    end
  end

  describe '#execute_batch' do
    context 'dry_runモードの場合' do
      it 'データ変更なしで結果が返される' do
        result = patch.execute_batch(10, 0)

        expect(result[:count]).to be > 0
        expect(result[:finished]).to be true # 全データを処理
        
        # 実際のデータは変更されていない
        expect(Inventory.where(price: 1000).count).to eq(5)
      end

      it 'dry_run結果がサマリーに反映される' do
        patch.execute_batch(10, 0)
        summary = patch.dry_run_summary
        
        expect(summary).to include('価格調整 Dry-run 結果サマリー')
        expect(summary).to include('対象商品数: 8件')
      end
    end

    context '通常実行モードの場合' do
      let(:patch_options) { { adjustment_type: 'percentage', adjustment_value: 10, dry_run: false } }

      it '実際にデータが更新される' do
        expect { patch.execute_batch(10, 0) }.to change { 
          Inventory.where(price: 1100).count 
        }.from(0).to(5) # 1000円の商品が1100円に更新
      end

      it 'InventoryLogが作成される' do
        expect { patch.execute_batch(10, 0) }.to change { 
          InventoryLog.where(action: 'price_adjustment').count 
        }.by(8)
      end
    end
  end

  describe '#calculate_new_price' do
    context 'percentageタイプの場合' do
      let(:patch_options) { { adjustment_type: 'percentage', adjustment_value: 10 } }

      it '正しくパーセンテージ計算される' do
        new_price = patch.send(:calculate_new_price, 1000)
        expect(new_price).to eq(1100) # 10%増加
      end
    end

    context 'fixed_amountタイプの場合' do
      let(:patch_options) { { adjustment_type: 'fixed_amount', adjustment_value: 100 } }

      it '正しく固定金額が加算される' do
        new_price = patch.send(:calculate_new_price, 1000)
        expect(new_price).to eq(1100) # 100円加算
      end

      it '負の価格にならない' do
        new_price = patch.send(:calculate_new_price, 50)
        expect(new_price).to eq(0) # 最低0円
      end
    end

    context 'multiplyタイプの場合' do
      let(:patch_options) { { adjustment_type: 'multiply', adjustment_value: 1.08 } }

      it '正しく倍率計算される' do
        new_price = patch.send(:calculate_new_price, 1000)
        expect(new_price).to eq(1080) # 1.08倍（消費税）
      end
    end

    context 'set_valueタイプの場合' do
      let(:patch_options) { { adjustment_type: 'set_value', adjustment_value: 1500 } }

      it '正しく固定価格が設定される' do
        new_price = patch.send(:calculate_new_price, 1000)
        expect(new_price).to eq(1500) # 固定価格
      end
    end
  end

  describe '統計情報' do
    before do
      patch.execute_batch(10, 0) # dry_runでの実行
    end

    it 'execution_statisticsが正しく計算される' do
      stats = patch.execution_statistics
      
      expect(stats[:total_processed]).to eq(8)
      expect(stats[:adjustment_type]).to eq('percentage')
      expect(stats[:adjustment_value]).to eq(10)
      expect(stats[:total_price_before]).to eq(6500) # 5*1000 + 3*500
      expect(stats[:total_price_after]).to eq(7150) # 5*1100 + 3*550
    end

    it 'dry_run_summaryが正しく生成される' do
      summary = patch.dry_run_summary
      
      expect(summary).to include('対象商品数: 8件')
      expect(summary).to include('調整前合計金額: 6,500円')
      expect(summary).to include('調整後合計金額: 7,150円')
      expect(summary).to include('差額: +650円')
    end
  end

  describe 'エラーハンドリング' do
    let(:patch_options) { { adjustment_type: 'percentage', adjustment_value: 10, dry_run: false } }

    context 'データ更新でエラーが発生する場合' do
      before do
        # 特定の在庫でエラーを発生させる
        inventory = Inventory.first
        allow(inventory).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
        allow(Inventory).to receive_message_chain(:where, :limit, :offset, :includes).and_return([inventory])
      end

      it 'エラーが記録され、処理が継続される' do
        result = patch.execute_batch(1, 0)
        
        expect(result[:records].first[:success]).to be false
        expect(result[:records].first[:error]).to be_present
      end
    end
  end

  describe 'パラメータバリデーション' do
    context 'percentage範囲外の値' do
      let(:patch_options) { { adjustment_type: 'percentage', adjustment_value: 1500 } }

      it 'ArgumentErrorが発生する' do
        expect { patch }.to raise_error(ArgumentError, /percentage調整値は-100〜1000の範囲/)
      end
    end

    context 'multiply負の値' do
      let(:patch_options) { { adjustment_type: 'multiply', adjustment_value: -1.5 } }

      it 'ArgumentErrorが発生する' do
        expect { patch }.to raise_error(ArgumentError, /multiply調整値は正の数である必要があります/)
      end
    end

    context 'set_value負の値' do
      let(:patch_options) { { adjustment_type: 'set_value', adjustment_value: -100 } }

      it 'ArgumentErrorが発生する' do
        expect { patch }.to raise_error(ArgumentError, /set_value調整値は0以上である必要があります/)
      end
    end
  end

  describe 'DataPatchRegistry統合' do
    it 'パッチが正しく登録されている' do
      expect(DataPatchRegistry.patch_exists?('inventory_price_adjustment')).to be true
    end

    it 'メタデータが正しく設定されている' do
      metadata = DataPatchRegistry.patch_metadata('inventory_price_adjustment')
      
      expect(metadata[:description]).to include('価格一括調整')
      expect(metadata[:category]).to eq('inventory')
      expect(metadata[:target_tables]).to include('inventories')
    end
  end

  # TODO: 🟡 Phase 3（中）- 高度なテストケースの実装
  # 実装予定:
  # - 大量データでのパフォーマンステスト
  # - 複雑な条件フィルタリングテスト
  # - 並行実行時の一意性テスト
  # - ロールバック・復旧テスト

  describe 'パフォーマンステスト' do
    it '大量データでも適切な時間で完了する', :performance do
      # 大量データ作成（1000件）
      FactoryBot.create_list(:inventory, 1000, price: 1000)
      
      start_time = Time.current
      patch.execute_batch(100, 0) # 100件ずつ処理
      execution_time = Time.current - start_time

      expect(execution_time).to be < 3.0 # 3秒以内で完了
    end
  end
end