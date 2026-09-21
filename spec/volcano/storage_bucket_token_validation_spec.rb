# frozen_string_literal: true

require 'base64'
require 'json'

RSpec.describe Volcano::StorageBucket do
  [nil, [], true, 7, 'project'].each do |payload|
    it "rejects non-object anon-key claims #{payload.inspect}" do
      encoded = Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
      client = Volcano::Client.new(anon_key: "header.#{encoded}.signature")

      expect { client.storage.from('assets').get_public_url('file.txt') }
        .to raise_error(ArgumentError, 'Anon key must contain a project ID')
    end
  end
end
