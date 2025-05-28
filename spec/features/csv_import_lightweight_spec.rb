# frozen_string_literal: true

require 'rails_helper'

# 軽量版のCSVインポートテスト（JavaScriptなし）
RSpec.describe 'CSV Import (Lightweight)', type: :feature, js: false do
  let(:admin) { create(:admin) }

  before do
    login_as(admin, scope: :admin)
  end

  describe 'CSV import form' do
    it 'displays import form' do
      visit admin_inventories_path
      click_link 'CSVインポート'

      expect(page).to have_content('CSVインポート')
      expect(page).to have_field('file')
      expect(page).to have_button('インポート開始')
    end
  end

  describe 'CSV import validation' do
    it 'shows error for missing file' do
      visit import_form_admin_inventories_path
      click_button 'インポート開始'

      expect(page).to have_content('ファイルを選択してください')
    end

    it 'shows error for invalid file type' do
      visit import_form_admin_inventories_path

      # テキストファイルをアップロード
      file = Tempfile.new([ 'test', '.txt' ])
      file.write('invalid content')
      file.close

      attach_file 'file', file.path
      click_button 'インポート開始'

      # ファイルタイプバリデーションエラーメッセージを確認
      expect(page).to have_content('Invalid file type: .txt. Allowed types: .csv')

      file.unlink
    end
  end
end
