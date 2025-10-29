# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PdfQualityValidator do
  let(:sample_pdf_data) { "%PDF-1.4\n%âãÏÓ\n1 0 obj\n<<\n/Type /Catalog\n/Pages 2 0 R\n>>\nendobj\nxref\n0 3\n0000000000 65535 f \n0000000009 00000 n \n0000000058 00000 n \ntrailer\n<<\n/Size 3\n/Root 1 0 R\n>>\nstartxref\n115\n%%EOF" }
  let(:invalid_data) { "not a pdf" }

  describe '#initialize' do
    it 'initializes with default validation results' do
      validator = described_class.new

      expect(validator.instance_variable_get(:@validation_results)).to include(
        valid: true,
        errors: [],
        warnings: [],
        info: [],
        metadata: {},
        scores: {},
        overall_score: 0,
        recommendations: []
      )
    end
  end

  describe '#validate_pdf_data' do
    context 'with valid PDF data' do
      it 'returns validation results' do
        validator = described_class.new
        result = validator.validate_pdf_data(sample_pdf_data)

        expect(result).to be_a(Hash)
        expect(result[:valid]).to be true
        expect(result[:metadata][:pdf_version]).to eq('1.4')
        expect(result[:overall_score]).to be >= 0
      end
    end

    context 'with invalid PDF data' do
      it 'raises InvalidPdfError' do
        validator = described_class.new
        result = validator.validate_pdf_data(invalid_data)

        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/有効なPDFデータではありません/))
      end
    end

    context 'with empty data' do
      it 'returns invalid result' do
        validator = described_class.new
        result = validator.validate_pdf_data('')

        expect(result[:valid]).to be false
        expect(result[:errors]).to include('PDFデータが空です')
      end
    end
  end

  describe '#generate_quality_report' do
    it 'generates comprehensive quality report' do
      validator = described_class.new
      validator.validate_pdf_data(sample_pdf_data)

      report = validator.generate_quality_report

      expect(report).to include(:summary, :details, :scores, :metadata, :recommendations)
      expect(report[:summary]).to include(:valid, :score, :grade, :timestamp)
      expect(report[:summary][:grade]).to match(/[A-F]/)
    end
  end

  describe 'private methods' do
    let(:validator) { described_class.new }

    describe '#humanize_file_size' do
      it 'converts bytes to human readable format' do
        expect(validator.send(:humanize_file_size, 1024)).to eq('1.0 KB')
        expect(validator.send(:humanize_file_size, 1048576)).to eq('1.0 MB')
        expect(validator.send(:humanize_file_size, 0)).to eq('0 B')
        expect(validator.send(:humanize_file_size, nil)).to eq('0 B')
      end
    end

    describe '#calculate_grade' do
      it 'returns correct letter grades' do
        expect(validator.send(:calculate_grade, 95)).to eq('A')
        expect(validator.send(:calculate_grade, 85)).to eq('B')
        expect(validator.send(:calculate_grade, 75)).to eq('C')
        expect(validator.send(:calculate_grade, 65)).to eq('D')
        expect(validator.send(:calculate_grade, 55)).to eq('F')
      end
    end
  end

  describe 'quality thresholds' do
    it 'has defined quality thresholds' do
      expect(described_class::QUALITY_THRESHOLDS).to include(:file_size, :page_count, :metadata_fields)
      expect(described_class::SCORE_WEIGHTS).to include(:file_size, :metadata, :content, :layout)
    end
  end

  describe 'error handling' do
    context 'when PDF processing fails' do
      it 'handles errors gracefully' do
        validator = described_class.new

        # 異常なデータでテスト
        malformed_data = "%PDF-1.4\nmalformed content"
        result = validator.validate_pdf_data(malformed_data)

        expect(result).to be_a(Hash)
        expect(result[:overall_score]).to be >= 0
      end
    end
  end
end
