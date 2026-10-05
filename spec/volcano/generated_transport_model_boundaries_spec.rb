# frozen_string_literal: true

module Volcano
  RSpec.describe GeneratedTransport do
    let(:generated) { Generated }
    let(:api_client) { described_class::ApiClient.new(generated::Configuration.new) }
    let(:storage) { described_class::StorageApi.new(api_client) }

    ['value', true, false, 1.5, ['nested', true], ['nested', false]].each do |value|
      it "deserializes the private filter-value union for #{value.inspect}" do
        expect(generated::ApiModelBase._deserialize('DatabaseQueryFilterValue', value)).to eq(value)
      end

      it "converts the private filter-value union for #{value.inspect}" do
        expect(api_client.convert_to_type(value, 'DatabaseQueryFilterValue')).to eq(value)
      end
    end

    %w[function frontend database].each do |type|
      it "resolves private discriminated #{type} log-resource models" do
        attributes = { type: type, ids: ['resource-id'] }

        model = generated::ApiModelBase._deserialize('LogRequestResource', attributes)

        expect(model.to_hash).to eq(attributes)
      end
    end

    it 'does not accept unknown log-resource discriminators' do
      expect(generated::ApiModelBase._deserialize('LogRequestResource', type: 'unknown')).to be_nil
    end

    [{ invalid: true }, [{ invalid: true }]].each do |value|
      it "rejects filter values outside the generated union: #{value.inspect}" do
        expect(api_client.convert_to_type(value, 'DatabaseQueryFilterValue')).to be_nil
      end
    end

    it 'preserves unrelated model lookup failures during nested deserialization' do
      expect { generated::ApiModelBase._deserialize('NonexistentModel', {}) }.to raise_error(NameError) do |error|
        expect(error.name).to eq(:NonexistentModel)
      end
    end

    it 'preserves unrelated model lookup failures during conversion' do
      expect { api_client.convert_to_type({}, 'NonexistentModel') }.to raise_error(NameError) do |error|
        expect(error.name).to eq(:NonexistentModel)
      end
    end

    %i[Conversion Generated].each do |name|
      context "with an unrelated #{name} error from scalar conversion" do
        let(:value) { +'value' }
        let(:failure) { NameError.new('unrelated conversion failure', name) }

        before { allow(value).to receive(:to_s).and_raise(failure) }

        it 'preserves the error from nested deserialization' do
          expect { generated::ApiModelBase._deserialize('String', value) }.to raise_error do |error|
            expect(error).to equal(failure)
          end
        end

        it 'preserves the error from response conversion' do
          expect { api_client.convert_to_type(value, 'String') }.to raise_error do |error|
            expect(error).to equal(failure)
          end
        end
      end
    end

    it 'rejects a missing storage bucket before a generated API call' do
      allow(api_client).to receive(:call_api)

      expect { storage.download_storage_object_with_http_info(nil, 'object') }
        .to raise_error(ArgumentError, 'bucket_name is required')
      expect(api_client).not_to have_received(:call_api)
    end

    it 'rejects a missing storage path before a generated API call' do
      allow(api_client).to receive(:call_api)

      expect { storage.download_storage_object_with_http_info('bucket', nil) }
        .to raise_error(ArgumentError, 'path is required')
      expect(api_client).not_to have_received(:call_api)
    end
  end
end
