# frozen_string_literal: true

module Volcano
  RSpec.describe Redaction do
    it 'ignores empty and absent credentials while redacting populated ones' do
      message = 'request failed for secret-value'

      expect(described_class.message(message, secrets: [nil, '', 'secret-value']))
        .to eq('request failed for [REDACTED]')
      expect(message).to eq('request failed for secret-value')
    end
  end
end
