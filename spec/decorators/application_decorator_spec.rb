# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationDecorator do
  # CLAUDE.md準拠: 基底デコレーターの包括的テスト
  # メタ認知: 共通UIヘルパーメソッドの複雑な分岐ロジックの品質保証
  # 横展開: 他のデコレーターでも同様のテストパターン適用

  # テスト用のダミーデコレータークラス
  class TestDecorator < ApplicationDecorator
    def name
      object.name
    end
  end

  # テスト用のダミーモデル
  class TestModel
    attr_accessor :name, :status, :created_at, :updated_at

    def initialize(attributes = {})
      @name = attributes[:name]
      @status = attributes[:status]
      @created_at = attributes[:created_at] || Time.current
      @updated_at = attributes[:updated_at] || Time.current
    end
  end

  let(:model) { TestModel.new(name: 'Test Item', status: 'active') }
  let(:decorator) { TestDecorator.new(model) }

  describe '#status_badge' do
    context 'with different status values' do
      it 'returns success badge for active status' do
        model.status = 'active'
        badge = decorator.status_badge
        expect(badge).to include('badge-success')
        expect(badge).to include('Active')
      end

      it 'returns warning badge for pending status' do
        model.status = 'pending'
        badge = decorator.status_badge
        expect(badge).to include('badge-warning')
        expect(badge).to include('Pending')
      end

      it 'returns danger badge for cancelled status' do
        model.status = 'cancelled'
        badge = decorator.status_badge
        expect(badge).to include('badge-danger')
        expect(badge).to include('Cancelled')
      end

      it 'returns danger badge for rejected status' do
        model.status = 'rejected'
        badge = decorator.status_badge
        expect(badge).to include('badge-danger')
        expect(badge).to include('Rejected')
      end

      it 'returns info badge for completed status' do
        model.status = 'completed'
        badge = decorator.status_badge
        expect(badge).to include('badge-info')
        expect(badge).to include('Completed')
      end

      it 'returns primary badge for processing status' do
        model.status = 'processing'
        badge = decorator.status_badge
        expect(badge).to include('badge-primary')
        expect(badge).to include('Processing')
      end

      it 'returns secondary badge for unknown status' do
        model.status = 'unknown'
        badge = decorator.status_badge
        expect(badge).to include('badge-secondary')
        expect(badge).to include('Unknown')
      end

      it 'returns secondary badge for nil status' do
        model.status = nil
        badge = decorator.status_badge
        expect(badge).to include('badge-secondary')
        expect(badge).to include('')
      end
    end

    context 'with custom CSS classes' do
      it 'adds custom classes to badge' do
        badge = decorator.status_badge(css_class: 'custom-class')
        expect(badge).to include('custom-class')
        expect(badge).to include('badge')
      end

      it 'handles multiple custom classes' do
        badge = decorator.status_badge(css_class: 'class1 class2')
        expect(badge).to include('class1 class2')
      end
    end

    context 'with custom label' do
      it 'uses custom label instead of status' do
        badge = decorator.status_badge(label: 'Custom Label')
        expect(badge).to include('Custom Label')
        expect(badge).not_to include(model.status)
      end

      it 'handles empty custom label' do
        badge = decorator.status_badge(label: '')
        expect(badge).to include('span')
        expect(badge).to match(/>[\s]*</)
      end
    end

    context 'HTML safety' do
      it 'returns HTML safe string' do
        badge = decorator.status_badge
        expect(badge).to be_html_safe
      end

      it 'escapes HTML in status value' do
        model.status = '<script>alert("xss")</script>'
        badge = decorator.status_badge
        expect(badge).not_to include('<script>')
        expect(badge).to include('&lt;script&gt;')
      end

      it 'escapes HTML in custom label' do
        badge = decorator.status_badge(label: '<strong>Bold</strong>')
        expect(badge).not_to include('<strong>')
        expect(badge).to include('&lt;strong&gt;')
      end
    end
  end

  describe '#formatted_date' do
    let(:test_date) { Time.zone.parse('2024-01-15 10:30:45') }

    context 'with default format' do
      it 'formats date with default format' do
        result = decorator.formatted_date(test_date)
        expect(result).to eq('2024-01-15')
      end
    end

    context 'with custom formats' do
      it 'formats with short format' do
        result = decorator.formatted_date(test_date, format: :short)
        expect(result).to eq('15 Jan')
      end

      it 'formats with long format' do
        result = decorator.formatted_date(test_date, format: :long)
        expect(result).to eq('January 15, 2024')
      end

      it 'formats with custom string format' do
        result = decorator.formatted_date(test_date, format: '%Y年%m月%d日')
        expect(result).to eq('2024年01月15日')
      end
    end

    context 'with nil date' do
      it 'returns default text for nil date' do
        result = decorator.formatted_date(nil)
        expect(result).to eq('N/A')
      end

      it 'returns custom default text for nil date' do
        result = decorator.formatted_date(nil, default: '未設定')
        expect(result).to eq('未設定')
      end
    end

    context 'with time included' do
      it 'includes time when specified' do
        result = decorator.formatted_date(test_date, include_time: true)
        expect(result).to eq('2024-01-15 10:30:45')
      end

      it 'uses custom time format' do
        result = decorator.formatted_date(test_date, include_time: true, format: '%Y-%m-%d %H:%M')
        expect(result).to eq('2024-01-15 10:30')
      end
    end
  end

  describe '#formatted_currency' do
    context 'with valid amounts' do
      it 'formats positive amount' do
        result = decorator.formatted_currency(1234.56)
        expect(result).to eq('¥1,235')
      end

      it 'formats negative amount' do
        result = decorator.formatted_currency(-1234.56)
        expect(result).to eq('-¥1,235')
      end

      it 'formats zero' do
        result = decorator.formatted_currency(0)
        expect(result).to eq('¥0')
      end

      it 'formats large amounts' do
        result = decorator.formatted_currency(1234567.89)
        expect(result).to eq('¥1,234,568')
      end
    end

    context 'with custom precision' do
      it 'shows decimal places when specified' do
        result = decorator.formatted_currency(1234.56, precision: 2)
        expect(result).to eq('¥1,234.56')
      end

      it 'handles zero precision' do
        result = decorator.formatted_currency(1234.56, precision: 0)
        expect(result).to eq('¥1,235')
      end
    end

    context 'with custom unit' do
      it 'uses custom currency unit' do
        result = decorator.formatted_currency(1234.56, unit: '$')
        expect(result).to eq('$1,235')
      end

      it 'handles empty unit' do
        result = decorator.formatted_currency(1234.56, unit: '')
        expect(result).to eq('1,235')
      end
    end

    context 'with nil amount' do
      it 'returns default text for nil' do
        result = decorator.formatted_currency(nil)
        expect(result).to eq('¥0')
      end

      it 'returns custom default for nil' do
        result = decorator.formatted_currency(nil, default: 'N/A')
        expect(result).to eq('N/A')
      end
    end
  end

  describe '#truncated_text' do
    context 'with text longer than limit' do
      it 'truncates text to default length' do
        long_text = 'a' * 100
        result = decorator.truncated_text(long_text)
        expect(result.length).to eq(53) # 50 chars + '...'
        expect(result).to end_with('...')
      end

      it 'truncates to custom length' do
        long_text = 'This is a very long text that needs truncation'
        result = decorator.truncated_text(long_text, length: 20)
        expect(result).to eq('This is a very lo...')
      end
    end

    context 'with text shorter than limit' do
      it 'returns original text without truncation' do
        short_text = 'Short text'
        result = decorator.truncated_text(short_text)
        expect(result).to eq('Short text')
      end
    end

    context 'with custom omission' do
      it 'uses custom omission string' do
        long_text = 'a' * 100
        result = decorator.truncated_text(long_text, length: 20, omission: '…')
        expect(result).to end_with('…')
        expect(result.length).to eq(20)
      end
    end

    context 'with nil text' do
      it 'returns empty string for nil' do
        result = decorator.truncated_text(nil)
        expect(result).to eq('')
      end
    end

    context 'HTML safety' do
      it 'preserves HTML safety of input' do
        safe_text = 'Safe text'.html_safe
        result = decorator.truncated_text(safe_text)
        expect(result).to be_html_safe
      end

      it 'does not mark unsafe text as safe' do
        unsafe_text = '<script>alert("xss")</script>'
        result = decorator.truncated_text(unsafe_text)
        expect(result).not_to be_html_safe
      end
    end
  end

  describe '#link_if_present' do
    context 'with valid URL' do
      it 'creates link for http URL' do
        result = decorator.link_if_present('http://example.com', 'Example')
        expect(result).to include('<a href="http://example.com"')
        expect(result).to include('>Example</a>')
      end

      it 'creates link for https URL' do
        result = decorator.link_if_present('https://example.com', 'Example')
        expect(result).to include('<a href="https://example.com"')
      end

      it 'adds target="_blank" by default' do
        result = decorator.link_if_present('http://example.com', 'Example')
        expect(result).to include('target="_blank"')
      end

      it 'adds rel="noopener" for security' do
        result = decorator.link_if_present('http://example.com', 'Example')
        expect(result).to include('rel="noopener"')
      end
    end

    context 'with custom options' do
      it 'adds custom CSS classes' do
        result = decorator.link_if_present('http://example.com', 'Example', class: 'btn btn-primary')
        expect(result).to include('class="btn btn-primary"')
      end

      it 'allows custom target' do
        result = decorator.link_if_present('http://example.com', 'Example', target: '_self')
        expect(result).to include('target="_self"')
      end

      it 'merges custom attributes' do
        result = decorator.link_if_present('http://example.com', 'Example', data: { confirm: 'Are you sure?' })
        expect(result).to include('data-confirm="Are you sure?"')
      end
    end

    context 'with nil or empty URL' do
      it 'returns text only for nil URL' do
        result = decorator.link_if_present(nil, 'No Link')
        expect(result).to eq('No Link')
        expect(result).not_to include('<a')
      end

      it 'returns text only for empty URL' do
        result = decorator.link_if_present('', 'No Link')
        expect(result).to eq('No Link')
      end

      it 'returns default text when both URL and text are nil' do
        result = decorator.link_if_present(nil, nil)
        expect(result).to eq('N/A')
      end
    end

    context 'HTML safety' do
      it 'returns HTML safe string for links' do
        result = decorator.link_if_present('http://example.com', 'Example')
        expect(result).to be_html_safe
      end

      it 'escapes HTML in link text' do
        result = decorator.link_if_present('http://example.com', '<script>alert("xss")</script>')
        expect(result).not_to include('<script>')
        expect(result).to include('&lt;script&gt;')
      end
    end
  end

  describe '#boolean_icon' do
    context 'with true value' do
      it 'returns check icon' do
        result = decorator.boolean_icon(true)
        expect(result).to include('fa-check')
        expect(result).to include('text-success')
      end
    end

    context 'with false value' do
      it 'returns times icon' do
        result = decorator.boolean_icon(false)
        expect(result).to include('fa-times')
        expect(result).to include('text-danger')
      end
    end

    context 'with nil value' do
      it 'returns minus icon' do
        result = decorator.boolean_icon(nil)
        expect(result).to include('fa-minus')
        expect(result).to include('text-muted')
      end
    end

    context 'with custom options' do
      it 'uses custom icons' do
        result = decorator.boolean_icon(true, true_icon: 'fa-thumbs-up', false_icon: 'fa-thumbs-down')
        expect(result).to include('fa-thumbs-up')
      end

      it 'uses custom colors' do
        result = decorator.boolean_icon(true, true_class: 'text-primary')
        expect(result).to include('text-primary')
        expect(result).not_to include('text-success')
      end

      it 'adds custom CSS classes' do
        result = decorator.boolean_icon(true, class: 'fa-2x')
        expect(result).to include('fa-2x')
      end
    end

    context 'HTML safety' do
      it 'returns HTML safe string' do
        result = decorator.boolean_icon(true)
        expect(result).to be_html_safe
      end
    end
  end

  describe '#progress_bar' do
    context 'with valid percentages' do
      it 'creates progress bar with percentage' do
        result = decorator.progress_bar(75)
        expect(result).to include('width: 75%')
        expect(result).to include('75%')
        expect(result).to include('progress-bar')
      end

      it 'handles 0 percent' do
        result = decorator.progress_bar(0)
        expect(result).to include('width: 0%')
        expect(result).to include('0%')
      end

      it 'handles 100 percent' do
        result = decorator.progress_bar(100)
        expect(result).to include('width: 100%')
        expect(result).to include('100%')
      end
    end

    context 'with out of range values' do
      it 'caps negative values at 0' do
        result = decorator.progress_bar(-50)
        expect(result).to include('width: 0%')
      end

      it 'caps values over 100 at 100' do
        result = decorator.progress_bar(150)
        expect(result).to include('width: 100%')
      end
    end

    context 'with color thresholds' do
      it 'uses danger color for low values' do
        result = decorator.progress_bar(20)
        expect(result).to include('bg-danger')
      end

      it 'uses warning color for medium values' do
        result = decorator.progress_bar(50)
        expect(result).to include('bg-warning')
      end

      it 'uses success color for high values' do
        result = decorator.progress_bar(80)
        expect(result).to include('bg-success')
      end
    end

    context 'with custom options' do
      it 'uses custom color' do
        result = decorator.progress_bar(50, color: 'primary')
        expect(result).to include('bg-primary')
      end

      it 'adds custom CSS classes' do
        result = decorator.progress_bar(50, class: 'progress-bar-striped')
        expect(result).to include('progress-bar-striped')
      end

      it 'allows hiding label' do
        result = decorator.progress_bar(50, show_label: false)
        expect(result).not_to include('50%')
      end

      it 'uses custom label' do
        result = decorator.progress_bar(50, label: '50 out of 100')
        expect(result).to include('50 out of 100')
        expect(result).not_to include('50%')
      end
    end

    context 'HTML safety' do
      it 'returns HTML safe string' do
        result = decorator.progress_bar(50)
        expect(result).to be_html_safe
      end
    end
  end

  describe 'delegated methods' do
    it 'delegates unknown methods to object' do
      expect(decorator.name).to eq('Test Item')
    end

    it 'responds to object methods' do
      expect(decorator.respond_to?(:name)).to be true
    end

    it 'responds to decorator methods' do
      expect(decorator.respond_to?(:status_badge)).to be true
    end
  end

  describe 'helper method access' do
    it 'has access to Rails helper methods' do
      # ApplicationDecorator includes Draper::Decorator which provides helper access
      expect(decorator).to respond_to(:h)
    end
  end
end