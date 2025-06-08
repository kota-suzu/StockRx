# frozen_string_literal: true

require 'rails_helper'

# マイグレーション管理システム統合テスト
#
# CLAUDE.md準拠の設計:
# - エンドツーエンドテスト
# - ユーザビリティ検証
# - セキュリティテスト
RSpec.describe 'Migration Management System', type: :feature do
  let(:admin) { create(:admin) }

  before do
    sign_in admin
  end

  describe 'migrations index page' do
    it 'displays migration management dashboard' do
      visit admin_migrations_path

      expect(page).to have_content('マイグレーション管理')
      expect(page).to have_content('システム統計')
      expect(page).to have_content('新規マイグレーション実行')
      expect(page).to have_content('実行履歴')
    end

    it 'shows system statistics' do
      # テスト用のマイグレーション実行レコードを作成
      create(:migration_execution, :completed, admin: admin)
      create(:migration_execution, :failed, admin: admin)
      create(:migration_execution, :running, admin: admin)

      visit admin_migrations_path

      # 統計情報が表示されることを確認
      expect(page).to have_content('総実行数')
      expect(page).to have_content('成功率')
      expect(page).to have_content('実行中')
    end
  end

  describe 'migration execution creation' do
    it 'allows creating new migration execution' do
      visit admin_migrations_path

      # 新規マイグレーション実行フォーム
      within '.new-migration-execution' do
        select '20250514131436', from: 'migration_execution[version]'
        fill_in 'migration_execution[configuration][batch_size]', with: '1000'
        fill_in 'migration_execution[configuration][cpu_threshold]', with: '75'
        fill_in 'migration_execution[configuration][memory_threshold]', with: '80'

        click_button '実行開始'
      end

      # 成功メッセージの確認
      expect(page).to have_content('マイグレーション実行を開始しました')

      # データベースに保存されていることを確認
      expect(MigrationExecution.last).to have_attributes(
        version: '20250514131436',
        admin: admin,
        status: 'pending'
      )
    end

    it 'validates configuration parameters' do
      visit admin_migrations_path

      within '.new-migration-execution' do
        select '20250514131436', from: 'migration_execution[version]'
        # バッチサイズを空のまま
        fill_in 'migration_execution[configuration][cpu_threshold]', with: '75'

        click_button '実行開始'
      end

      # バリデーションエラーの確認
      expect(page).to have_content('必須キーが不足しています')
    end
  end

  describe 'migration execution detail page' do
    let!(:execution) { create(:migration_execution, :running, admin: admin) }
    let!(:progress_logs) do
      [
        create(:migration_progress_log, migration_execution: execution, phase: 'initialization'),
        create(:migration_progress_log, migration_execution: execution, phase: 'data_migration'),
        create(:migration_progress_log, migration_execution: execution, phase: 'validation')
      ]
    end

    it 'displays detailed monitoring information' do
      visit admin_migration_path(execution)

      expect(page).to have_content(execution.name)
      expect(page).to have_content(execution.version)
      expect(page).to have_content('システムメトリクス')
      expect(page).to have_content('実行ログ')
    end

    it 'shows real-time progress updates' do
      visit admin_migration_path(execution)

      # 進行状況表示の確認
      expect(page).to have_css('.progress-circle')
      expect(page).to have_content("#{execution.progress_percentage}%")

      # ログエントリの確認
      progress_logs.each do |log|
        expect(page).to have_content(log.message)
        expect(page).to have_content("[#{log.phase.humanize}]")
      end
    end

    context 'when migration can be paused' do
      it 'shows pause button and allows pausing' do
        visit admin_migration_path(execution)

        expect(page).to have_button('一時停止')

        click_button '一時停止'

        expect(page).to have_content('マイグレーションを一時停止しました')
        expect(execution.reload.status).to eq('paused')
      end
    end

    context 'when migration is paused' do
      let!(:execution) { create(:migration_execution, :paused, admin: admin) }

      it 'shows resume button and allows resuming' do
        visit admin_migration_path(execution)

        expect(page).to have_button('再開')

        click_button '再開'

        expect(page).to have_content('マイグレーションを再開しました')
        expect(execution.reload.status).to eq('running')
      end
    end
  end

  describe 'migration execution controls' do
    let!(:execution) { create(:migration_execution, :running, admin: admin) }

    it 'allows cancelling migration' do
      visit admin_migration_path(execution)

      accept_confirm do
        click_button 'キャンセル'
      end

      expect(page).to have_content('マイグレーションをキャンセルしました')
      expect(execution.reload.status).to eq('cancelled')
    end

    context 'with completed migration that can be rolled back' do
      let!(:execution) do
        create(:migration_execution, :completed, admin: admin,
               rollback_data: [ { table: 'test', action: 'create' } ])
      end

      it 'allows rollback operation' do
        visit admin_migration_path(execution)

        expect(page).to have_button('ロールバック')

        accept_confirm do
          click_button 'ロールバック'
        end

        expect(page).to have_content('マイグレーションをロールバックしました')
      end
    end
  end

  describe 'system status monitoring' do
    it 'displays system status endpoint' do
      visit admin_migrations_system_status_path

      expect(page.status_code).to eq(200)

      json_response = JSON.parse(page.body)
      expect(json_response).to include(
        'active_executions_count',
        'system_load',
        'database_status'
      )
    end
  end

  describe 'search and filtering' do
    let!(:executions) do
      [
        create(:migration_execution, :completed, admin: admin, version: '20250514131436'),
        create(:migration_execution, :failed, admin: admin, version: '20250514131442'),
        create(:migration_execution, :running, admin: admin, version: '20250518032458')
      ]
    end

    it 'allows filtering by status' do
      visit admin_migrations_path

      # ステータスでフィルタリング
      select '完了', from: 'q[status_eq]'
      click_button '検索'

      expect(page).to have_content(executions[0].version)
      expect(page).not_to have_content(executions[1].version)
      expect(page).not_to have_content(executions[2].version)
    end

    it 'allows searching by version' do
      visit admin_migrations_path

      # バージョンで検索
      fill_in 'q[version_cont]', with: '20250514'
      click_button '検索'

      expect(page).to have_content(executions[0].version)
      expect(page).to have_content(executions[1].version)
      expect(page).not_to have_content(executions[2].version)
    end
  end

  describe 'permission and security' do
    context 'when admin does not have migration permissions' do
      before do
        allow_any_instance_of(Admin).to receive(:can_execute_migrations?).and_return(false)
      end

      it 'restricts access to migration execution' do
        visit admin_migrations_path

        expect(page).to have_content('権限がありません')
        expect(page).not_to have_button('実行開始')
      end
    end

    it 'requires authentication' do
      sign_out admin

      visit admin_migrations_path

      expect(current_path).to eq(new_admin_session_path)
      expect(page).to have_content('ログインしてください')
    end
  end

  describe 'responsive design' do
    it 'adapts to mobile viewport', js: true do
      page.driver.browser.manage.window.resize_to(375, 667) # iPhone SE size

      visit admin_migrations_path

      # モバイル用のレイアウト確認
      expect(page).to have_css('.metrics-grid')
      expect(page).to have_css('.log-controls')
    end
  end
end

# ============================================
# 設計ノート（CLAUDE.md準拠）
# ============================================

# 1. テスト網羅範囲
#    - UI操作の基本フロー
#    - エラーケースの処理
#    - セキュリティ制約
#    - レスポンシブデザイン

# 2. リアルタイム機能テスト
#    - ActionCable統合後にJavaScriptテスト追加
#    - WebSocket接続テスト
#    - 進行状況リアルタイム更新

# 3. パフォーマンステスト
#    - 大量データでの表示性能
#    - 並行実行時の動作
#    - メモリ使用量監視

# TODO: 拡張テスト実装
# - [HIGH] JavaScript機能テスト（ActionCable統合後）
# - [MEDIUM] パフォーマンステスト追加
# - [MEDIUM] アクセシビリティテスト
# - [LOW] 国際化テスト
