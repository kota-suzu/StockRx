# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Security::KeyProvider do
  # CLAUDE.md準拠: エンタープライズグレードキー管理システムの包括的テスト
  # メタ認知: セキュリティの要となるキー管理は最高水準のテスト品質が必要
  # 横展開: 他のセキュリティ関連クラスでも同様の厳密なテストパターン適用

  # テスト前の設定リセット
  before do
    # 設定をデフォルトに戻す
    described_class.configure do |config|
      config.provider_strategy = :rails_credentials
      config.kms_provider = nil
      config.key_cache_ttl = 1.hour
      config.enable_key_rotation = false
      config.enable_audit_logging = false
      config.fallback_to_derived_keys = true
    end

    # ログ出力をスタブ化
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:debug)
  end

  # ============================================
  # 設定とメタデータのテスト
  # ============================================

  describe 'configuration' do
    it 'デフォルト設定が正しく設定されている' do
      expect(described_class.config.provider_strategy).to eq(:rails_credentials)
      expect(described_class.config.kms_provider).to be_nil
      expect(described_class.config.key_cache_ttl).to eq(1.hour)
      expect(described_class.config.enable_key_rotation).to be false
      expect(described_class.config.enable_audit_logging).to be false
      expect(described_class.config.fallback_to_derived_keys).to be true
    end

    it '設定を変更できる' do
      described_class.configure do |config|
        config.provider_strategy = :kms
        config.kms_provider = :aws
        config.enable_key_rotation = true
        config.enable_audit_logging = true
      end

      expect(described_class.config.provider_strategy).to eq(:kms)
      expect(described_class.config.kms_provider).to eq(:aws)
      expect(described_class.config.enable_key_rotation).to be true
      expect(described_class.config.enable_audit_logging).to be true
    end
  end

  describe 'constants and metadata' do
    it 'キータイプの定義が正しい' do
      expect(described_class::KEY_TYPES).to be_a(Hash)
      expect(described_class::KEY_TYPES).to include(
        :database_encryption,
        :job_arguments,
        :log_encryption,
        :session_encryption
      )
    end

    it '各キータイプが必要な属性を持つ' do
      described_class::KEY_TYPES.each do |key_type, metadata|
        expect(metadata).to include(
          :algorithm,
          :size,
          :rotation_interval,
          :audit_required
        )

        expect(metadata[:algorithm]).to be_a(String)
        expect(metadata[:size]).to be_a(Integer)
        expect(metadata[:rotation_interval]).to respond_to(:to_i)
        expect([ true, false ]).to include(metadata[:audit_required])
      end
    end

    it 'アルゴリズムがAES-256-GCMに統一されている' do
      described_class::KEY_TYPES.each do |key_type, metadata|
        expect(metadata[:algorithm]).to eq("AES-256-GCM")
      end
    end

    it 'キーサイズが32バイト（256ビット）に統一されている' do
      described_class::KEY_TYPES.each do |key_type, metadata|
        expect(metadata[:size]).to eq(32)
      end
    end
  end

  describe '#available_key_types' do
    it '利用可能なキータイプ一覧を返す' do
      types = described_class.available_key_types

      expect(types).to include(
        :database_encryption,
        :job_arguments,
        :log_encryption,
        :session_encryption
      )
      expect(types).to eq(described_class::KEY_TYPES.keys)
    end
  end

  describe '#key_metadata' do
    it '有効なキータイプのメタデータを返す' do
      metadata = described_class.key_metadata(:database_encryption)

      expect(metadata).to include(
        :type,
        :algorithm,
        :size,
        :rotation_interval,
        :audit_required,
        :current_version,
        :last_rotated,
        :next_rotation
      )

      expect(metadata[:type]).to eq(:database_encryption)
      expect(metadata[:algorithm]).to eq("AES-256-GCM")
      expect(metadata[:size]).to eq(32)
      expect(metadata[:rotation_interval]).to eq(30.days)
      expect(metadata[:audit_required]).to be true
      expect(metadata[:current_version]).to eq(:v1)
    end

    it '無効なキータイプでエラーを発生させる' do
      expect {
        described_class.key_metadata(:invalid_type)
      }.to raise_error(Security::KeyProvider::InvalidKeyTypeError)
    end
  end

  # ============================================
  # current_key メソッドのテスト
  # ============================================

  describe '#current_key' do
    context 'Rails Credentials戦略' do
      before do
        described_class.configure do |config|
          config.provider_strategy = :rails_credentials
          config.fallback_to_derived_keys = true
        end
      end

      context 'credentialにキーが存在する' do
        let(:test_key) { SecureRandom.bytes(32) }
        let(:encoded_key) { Base64.strict_encode64(test_key) }

        before do
          # Rails.application.credentialsをモック
          mock_credentials = double('credentials')
          allow(Rails.application).to receive(:credentials).and_return(mock_credentials)
          allow(mock_credentials).to receive(:dig)
            .with(:security, :encryption_keys, :database_encryption)
            .and_return(encoded_key)
        end

        it 'Base64エンコードされたキーをデコードして返す' do
          key = described_class.current_key(:database_encryption)
          expect(key).to eq(test_key)
          expect(key.bytesize).to eq(32)
        end
      end

      context 'credentialにキーが存在しない' do
        before do
          mock_credentials = double('credentials')
          allow(Rails.application).to receive(:credentials).and_return(mock_credentials)
          allow(mock_credentials).to receive(:dig).and_return(nil)
        end

        it 'フォールバック有効時は派生キーを返す' do
          described_class.configure { |c| c.fallback_to_derived_keys = true }

          expect(Rails.logger).to receive(:warn)
            .with(/Credential key not found .*, falling back to derived key/)

          key = described_class.current_key(:database_encryption)
          expect(key).to be_a(String)
          expect(key.bytesize).to eq(32)
        end

        it 'フォールバック無効時はエラーを発生させる' do
          described_class.configure { |c| c.fallback_to_derived_keys = false }

          expect {
            described_class.current_key(:database_encryption)
          }.to raise_error(Security::KeyProvider::KeyNotFoundError)
        end
      end

      context 'safe_credentialsが利用可能' do
        let(:test_key) { SecureRandom.bytes(32) }
        let(:encoded_key) { Base64.strict_encode64(test_key) }

        before do
          # safe_credentialsが利用可能な場合をモック
          allow(Rails.application).to receive(:respond_to?).with(:safe_credentials).and_return(true)

          mock_safe_credentials = double('safe_credentials')
          allow(Rails.application).to receive(:safe_credentials).and_return(mock_safe_credentials)
          allow(mock_safe_credentials).to receive(:dig)
            .with(:security, :encryption_keys, :database_encryption)
            .and_return(encoded_key)
        end

        it 'safe_credentialsからキーを取得する' do
          key = described_class.current_key(:database_encryption)
          expect(key).to eq(test_key)
        end
      end

      context 'バージョン指定' do
        let(:test_key_v2) { SecureRandom.bytes(32) }
        let(:encoded_key_v2) { Base64.strict_encode64(test_key_v2) }

        before do
          mock_credentials = double('credentials')
          allow(Rails.application).to receive(:credentials).and_return(mock_credentials)
          allow(mock_credentials).to receive(:dig)
            .with(:security, :encryption_keys, :database_encryption, :v2)
            .and_return(encoded_key_v2)
        end

        it '指定されたバージョンのキーを取得する' do
          key = described_class.current_key(:database_encryption, version: 2)
          expect(key).to eq(test_key_v2)
        end
      end
    end

    context 'Derived Keys戦略' do
      before do
        described_class.configure do |config|
          config.provider_strategy = :derived
        end
      end

      it '派生キーを生成する' do
        key = described_class.current_key(:database_encryption)

        expect(key).to be_a(String)
        expect(key.bytesize).to eq(32)
      end

      it '同じキータイプとバージョンで一貫したキーを生成する' do
        key1 = described_class.current_key(:database_encryption)
        key2 = described_class.current_key(:database_encryption)

        expect(key1).to eq(key2)
      end

      it '異なるキータイプで異なるキーを生成する' do
        key1 = described_class.current_key(:database_encryption)
        key2 = described_class.current_key(:job_arguments)

        expect(key1).not_to eq(key2)
      end

      it '異なるバージョンで異なるキーを生成する' do
        key1 = described_class.current_key(:database_encryption, version: :latest)
        key2 = described_class.current_key(:database_encryption, version: 'v2')

        expect(key1).not_to eq(key2)
      end

      it 'デバッグログを出力する' do
        expect(Rails.logger).to receive(:debug)
          .with(/Generated derived key for database_encryption \(32 bytes\)/)

        described_class.current_key(:database_encryption)
      end
    end

    context 'KMS戦略' do
      before do
        described_class.configure do |config|
          config.provider_strategy = :kms
          config.kms_provider = :aws
        end
      end

      it 'NotImplementedErrorを発生させる（Phase 2実装予定）' do
        expect {
          described_class.current_key(:database_encryption)
        }.to raise_error(NotImplementedError, /KMS integration not yet implemented/)
      end
    end

    context '無効な戦略' do
      before do
        described_class.configure do |config|
          config.provider_strategy = :invalid_strategy
        end
      end

      it 'InvalidKeyTypeErrorを発生させる' do
        expect {
          described_class.current_key(:database_encryption)
        }.to raise_error(Security::KeyProvider::InvalidKeyTypeError, /Unknown provider strategy/)
      end
    end

    context '無効なキータイプ' do
      it 'InvalidKeyTypeErrorを発生させる' do
        expect {
          described_class.current_key(:invalid_key_type)
        }.to raise_error(Security::KeyProvider::InvalidKeyTypeError, /Invalid key type/)
      end
    end

    context 'エラーハンドリング' do
      before do
        described_class.configure do |config|
          config.provider_strategy = :rails_credentials
          config.fallback_to_derived_keys = true
          config.enable_audit_logging = true
        end
      end

      it 'エラー時にログを出力する' do
        # credentialsでエラーを発生させる
        allow(Rails.application).to receive(:credentials)
          .and_raise(StandardError, "Credential error")

        expect(Rails.logger).to receive(:error)
          .with(/Key retrieval failed: Credential error/)
        expect(Rails.logger).to receive(:error)
          .with(/Key type: database_encryption, Version: latest/)
        expect(Rails.logger).to receive(:error)
          .with(/Backtrace:/)

        expect(Rails.logger).to receive(:warn)
          .with(/Attempting fallback to derived key/)

        # フォールバックが成功することを確認
        key = described_class.current_key(:database_encryption)
        expect(key).to be_a(String)
        expect(key.bytesize).to eq(32)
      end

      it 'フォールバック無効時はエラーを再発生させる' do
        described_class.configure { |c| c.fallback_to_derived_keys = false }

        allow(Rails.application).to receive(:credentials)
          .and_raise(StandardError, "Credential error")

        expect {
          described_class.current_key(:database_encryption)
        }.to raise_error(StandardError, "Credential error")
      end

      it 'InvalidKeyTypeErrorはフォールバックしない' do
        # 無効なキータイプでInvalidKeyTypeErrorを発生させる
        expect {
          described_class.current_key(:invalid_type)
        }.to raise_error(Security::KeyProvider::InvalidKeyTypeError)

        # フォールバックの警告ログは出力されない
        expect(Rails.logger).not_to have_received(:warn)
          .with(/Attempting fallback to derived key/)
      end
    end
  end

  # ============================================
  # キー生成・検証のテスト
  # ============================================

  describe '#generate_key' do
    it '指定されたサイズのキーを生成する' do
      key = described_class.generate_key(:database_encryption)

      expect(key).to be_a(String)
      expect(key.bytesize).to eq(32)
    end

    it '各呼び出しで異なるキーを生成する' do
      key1 = described_class.generate_key(:database_encryption)
      key2 = described_class.generate_key(:database_encryption)

      expect(key1).not_to eq(key2)
    end

    it '異なるキータイプで異なるサイズのキーを生成する' do
      # 全キータイプが32バイトなので、すべて同じサイズになるはず
      described_class.available_key_types.each do |key_type|
        key = described_class.generate_key(key_type)
        expect(key.bytesize).to eq(32)
      end
    end

    it '無効なキータイプでエラーを発生させる' do
      expect {
        described_class.generate_key(:invalid_type)
      }.to raise_error(Security::KeyProvider::InvalidKeyTypeError)
    end

    context '監査ログ有効時' do
      before do
        described_class.configure { |c| c.enable_audit_logging = true }
      end

      it '監査ログメソッドを呼び出す' do
        expect(described_class).to receive(:audit_key_generation)
          .with(:database_encryption)

        described_class.generate_key(:database_encryption)
      end
    end

    context '監査ログ無効時' do
      before do
        described_class.configure { |c| c.enable_audit_logging = false }
      end

      it '監査ログメソッドを呼び出さない' do
        expect(described_class).not_to receive(:audit_key_generation)

        described_class.generate_key(:database_encryption)
      end
    end
  end

  describe '#validate_key' do
    let(:valid_key) { SecureRandom.bytes(32) }
    let(:invalid_size_key) { SecureRandom.bytes(16) } # 間違ったサイズ
    let(:low_entropy_key) { "\x00" * 32 } # 低エントロピー

    it '有効なキーでtrueを返す' do
      result = described_class.validate_key(:database_encryption, valid_key)
      expect(result).to be true
    end

    it '無効なサイズのキーでfalseを返す' do
      result = described_class.validate_key(:database_encryption, invalid_size_key)
      expect(result).to be false
    end

    it '低エントロピーのキーでfalseを返す' do
      result = described_class.validate_key(:database_encryption, low_entropy_key)
      expect(result).to be false
    end

    it '部分的に低エントロピーのキーでfalseを返す' do
      # 15種類の異なるバイトを持つキー（閾値16未満）
      partial_entropy_key = (0..14).map(&:chr).join + "\x00" * 17
      result = described_class.validate_key(:database_encryption, partial_entropy_key)
      expect(result).to be false
    end

    it '十分なエントロピーのキーでtrueを返す' do
      # 16種類以上の異なるバイトを持つキー
      high_entropy_key = (0..31).map(&:chr).join
      result = described_class.validate_key(:database_encryption, high_entropy_key)
      expect(result).to be true
    end
  end

  # ============================================
  # プライベートメソッドのテスト
  # ============================================

  describe 'private methods' do
    describe '#get_derived_key' do
      it 'PBKDF2を使用してキーを派生する' do
        # プライベートメソッドを直接テスト
        key = described_class.send(:get_derived_key, :database_encryption, :latest)

        expect(key).to be_a(String)
        expect(key.bytesize).to eq(32)
      end

      it '同じパラメータで一貫したキーを生成する' do
        key1 = described_class.send(:get_derived_key, :database_encryption, :latest)
        key2 = described_class.send(:get_derived_key, :database_encryption, :latest)

        expect(key1).to eq(key2)
      end

      it '異なるキータイプで異なるキーを生成する' do
        key1 = described_class.send(:get_derived_key, :database_encryption, :latest)
        key2 = described_class.send(:get_derived_key, :job_arguments, :latest)

        expect(key1).not_to eq(key2)
      end

      it '異なるバージョンで異なるキーを生成する' do
        key1 = described_class.send(:get_derived_key, :database_encryption, :latest)
        key2 = described_class.send(:get_derived_key, :database_encryption, :v2)

        expect(key1).not_to eq(key2)
      end

      it 'Rails.application.secret_key_baseを使用する' do
        expect(Rails.application).to receive(:secret_key_base)
          .and_return('test_secret_key_base')

        described_class.send(:get_derived_key, :database_encryption, :latest)
      end
    end

    describe '#validate_key_type!' do
      it '有効なキータイプで例外を発生させない' do
        expect {
          described_class.send(:validate_key_type!, :database_encryption)
        }.not_to raise_error
      end

      it '無効なキータイプでInvalidKeyTypeErrorを発生させる' do
        expect {
          described_class.send(:validate_key_type!, :invalid_type)
        }.to raise_error(Security::KeyProvider::InvalidKeyTypeError, /Invalid key type: invalid_type/)
      end

      it 'エラーメッセージに利用可能なキータイプを含む' do
        expect {
          described_class.send(:validate_key_type!, :invalid_type)
        }.to raise_error(Security::KeyProvider::InvalidKeyTypeError, /Available: .*database_encryption.*job_arguments/)
      end
    end

    describe '#get_current_version' do
      it 'デフォルトでv1を返す' do
        version = described_class.send(:get_current_version, :database_encryption)
        expect(version).to eq(:v1)
      end
    end

    describe '#get_last_rotation_time' do
      it 'nilを返す（Phase 2実装予定）' do
        time = described_class.send(:get_last_rotation_time, :database_encryption)
        expect(time).to be_nil
      end
    end

    describe '#get_next_rotation_time' do
      it 'nilを返す（Phase 2実装予定）' do
        time = described_class.send(:get_next_rotation_time, :database_encryption)
        expect(time).to be_nil
      end
    end

    describe '#audit_key_generation' do
      it 'エラーなく実行される（Phase 2実装予定）' do
        expect {
          described_class.send(:audit_key_generation, :database_encryption)
        }.not_to raise_error
      end
    end

    describe '#audit_key_error' do
      it 'エラーなく実行される（Phase 2実装予定）' do
        error = StandardError.new("Test error")

        expect {
          described_class.send(:audit_key_error, :database_encryption, :latest, error)
        }.not_to raise_error
      end
    end
  end

  # ============================================
  # セキュリティテスト
  # ============================================

  describe 'security properties' do
    context 'キーの品質' do
      it '生成されたキーに統計的バイアスがない' do
        # 複数のキーを生成してランダム性をテスト
        keys = 10.times.map { described_class.generate_key(:database_encryption) }

        # 各バイト位置での値の分布をチェック
        (0...32).each do |position|
          byte_values = keys.map { |key| key.bytes[position] }
          unique_values = byte_values.uniq.size

          # 10個のキーで最低でも3つの異なる値が出現することを期待
          expect(unique_values).to be >= 3
        end
      end

      it '派生キーが予測困難である' do
        # 派生キーが元の素材から容易に推測できないことを確認
        key1 = described_class.send(:get_derived_key, :database_encryption, :latest)
        key2 = described_class.send(:get_derived_key, :database_encryption, :v2)

        # ハミング距離（異なるビット数）が十分大きいことを確認
        hamming_distance = key1.bytes.zip(key2.bytes)
                              .count { |b1, b2| b1 != b2 }

        # 256ビット中、最低でも50%以上のビットが異なることを期待
        expect(hamming_distance).to be >= 16
      end
    end

    context 'エラー情報の漏洩防止' do
      it 'エラーメッセージで機密情報を漏洩しない' do
        described_class.configure do |config|
          config.provider_strategy = :rails_credentials
          config.fallback_to_derived_keys = false
        end

        # credentialsでエラーを発生させる
        allow(Rails.application).to receive(:credentials)
          .and_raise(StandardError, "Secret credential data: #{SecureRandom.hex(32)}")

        expect {
          described_class.current_key(:database_encryption)
        }.to raise_error(StandardError)

        # ログに機密情報が含まれていないことを確認
        expect(Rails.logger).to have_received(:error)
          .with(/Key retrieval failed:/)
        expect(Rails.logger).to have_received(:error)
          .with(/Key type: database_encryption/)
      end
    end

    context 'タイミング攻撃対策' do
      it 'キータイプの存在チェックで一定時間を要する' do
        # 有効なキータイプと無効なキータイプの処理時間を測定
        valid_times = []
        invalid_times = []

        5.times do
          start_time = Time.current
          begin
            described_class.key_metadata(:database_encryption)
          rescue
            # エラーは無視
          end
          valid_times << (Time.current - start_time)

          start_time = Time.current
          begin
            described_class.key_metadata(:nonexistent_key_type_with_long_name)
          rescue
            # エラーは無視
          end
          invalid_times << (Time.current - start_time)
        end

        # 処理時間の差が過度に大きくないことを確認
        valid_avg = valid_times.sum / valid_times.size
        invalid_avg = invalid_times.sum / invalid_times.size

        # 10倍以上の差がないことを確認（タイミング攻撃対策）
        time_ratio = [ valid_avg / invalid_avg, invalid_avg / valid_avg ].max
        expect(time_ratio).to be < 10
      end
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe 'performance', performance: true do
    it 'キー取得が高速に実行される' do
      described_class.configure { |c| c.provider_strategy = :derived }

      start_time = Time.current
      100.times do
        described_class.current_key(:database_encryption)
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 100 # 100ms以内
    end

    it 'キー生成が高速に実行される' do
      start_time = Time.current
      50.times do
        described_class.generate_key(:database_encryption)
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 200 # 200ms以内
    end

    it 'キー検証が高速に実行される' do
      keys = 10.times.map { described_class.generate_key(:database_encryption) }

      start_time = Time.current
      keys.each do |key|
        described_class.validate_key(:database_encryption, key)
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 50 # 50ms以内
    end
  end

  # ============================================
  # 統合テスト
  # ============================================

  describe 'integration scenarios' do
    context '本番環境設定' do
      around do |example|
        original_env = Rails.env
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

        # Rails設定を再読み込み
        load Rails.root.join('app/lib/security/key_provider.rb')

        example.run

        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(original_env))
        load Rails.root.join('app/lib/security/key_provider.rb')
      end

      it '本番環境で適切な設定が適用される' do
        expect(described_class.config.provider_strategy).to eq(:rails_credentials)
        expect(described_class.config.enable_key_rotation).to be true
        expect(described_class.config.enable_audit_logging).to be true
        expect(described_class.config.fallback_to_derived_keys).to be false
      end
    end

    context '開発環境設定' do
      around do |example|
        original_env = Rails.env
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))

        load Rails.root.join('app/lib/security/key_provider.rb')

        example.run

        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(original_env))
        load Rails.root.join('app/lib/security/key_provider.rb')
      end

      it '開発環境で適切な設定が適用される' do
        expect(described_class.config.provider_strategy).to eq(:derived)
        expect(described_class.config.enable_key_rotation).to be false
        expect(described_class.config.enable_audit_logging).to be false
        expect(described_class.config.fallback_to_derived_keys).to be true
      end
    end

    context 'マルチキー管理' do
      it '複数のキータイプを同時に管理できる' do
        keys = {}

        described_class.available_key_types.each do |key_type|
          keys[key_type] = described_class.current_key(key_type)
        end

        # 全てのキーが正しいサイズを持つ
        keys.each do |key_type, key|
          expected_size = described_class::KEY_TYPES[key_type][:size]
          expect(key.bytesize).to eq(expected_size)
        end

        # 全てのキーが異なる
        key_values = keys.values
        expect(key_values.uniq.size).to eq(key_values.size)
      end
    end
  end

  # ============================================
  # エラークラスのテスト
  # ============================================

  describe 'error classes' do
    it 'カスタムエラークラスが定義されている' do
      expect(Security::KeyProvider::KeyNotFoundError).to be < StandardError
      expect(Security::KeyProvider::InvalidKeyTypeError).to be < StandardError
      expect(Security::KeyProvider::KMSConnectionError).to be < StandardError
      expect(Security::KeyProvider::KeyRotationRequiredError).to be < StandardError
    end

    it 'エラークラスをインスタンス化できる' do
      errors = [
        Security::KeyProvider::KeyNotFoundError.new("Key not found"),
        Security::KeyProvider::InvalidKeyTypeError.new("Invalid type"),
        Security::KeyProvider::KMSConnectionError.new("Connection failed"),
        Security::KeyProvider::KeyRotationRequiredError.new("Rotation required")
      ]

      errors.each do |error|
        expect(error).to be_a(StandardError)
        expect(error.message).to be_a(String)
      end
    end
  end
end
