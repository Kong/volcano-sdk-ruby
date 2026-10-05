# frozen_string_literal: true

require 'uri'

module Volcano
  RSpec.describe Redaction do
    let(:credential_values) { PropCheck::Generators.printable_string }

    it 'ignores empty and absent credentials while redacting populated ones' do
      message = 'request failed for secret-value'

      expect(described_class.message(message, secrets: [nil, '', 'secret-value']))
        .to eq('request failed for [REDACTED]')
      expect(message).to eq('request failed for secret-value')
    end

    it 'removes raw, form-encoded, and path-encoded credentials without changing the input' do
      check_property(credential_values) do |value|
        secret = "credential-#{value}"
        form = URI.encode_www_form_component(secret)
        path = form.gsub('+', '%20')
        message = "raw=#{secret};form=#{form};path=#{path}"

        redacted = described_class.message(message, secrets: [secret])

        expect(redacted).to eq('raw=[REDACTED];form=[REDACTED];path=[REDACTED]')
        expect(message).to eq("raw=#{secret};form=#{form};path=#{path}")
      end
    end

    it 'redacts overlapping credentials regardless of their input order' do
      generator = PropCheck::Generators.tuple(credential_values, credential_values)
      check_property(generator) do |first, second|
        short = "credential-#{first}"
        long = "#{short}-#{second}"
        message = "#{long} | #{short}"

        expect(described_class.message(message, secrets: [short, long])).to eq('[REDACTED] | [REDACTED]')
        expect(described_class.message(message, secrets: [long, short])).to eq('[REDACTED] | [REDACTED]')
      end
    end

    it 'preserves typed error metadata and the original exception while redacting' do
      check_property(credential_values) do |value|
        secret = "credential-#{value}"
        error = Error::ValidationError.new("failed #{secret}", status: 422, code: 'invalid', retry_after: 3)
        error.set_backtrace(['request.rb:12'])

        redacted = described_class.exception(error, secrets: [secret])

        expect(redacted).to be_a(Error::ValidationError)
        expect(redacted.message).to eq('failed [REDACTED]')
        expect([redacted.status, redacted.code, redacted.retry_after]).to eq([422, 'invalid', 3])
        expect(redacted.backtrace).to eq(error.backtrace)
        expect(error.message).to eq("failed #{secret}")
      end
    end
  end
end
