# frozen_string_literal: true

require 'uri'

RSpec.describe Volcano do
  let(:strings) { PropCheck::Generators.printable_string }
  let(:base) { 'postgresql://user:password@db.example.test/app?sslmode=require&application_name=old' }

  it 'encodes user IDs as one application_name value without adding connection options' do
    check_property(strings) do |value|
      user_id = "user-#{value}"
      connection = described_class.database_connection_string(base, user_id: user_id)
      target, query = connection.split('?', 2)
      expect(target).to eq('postgresql://user:password@db.example.test/app')
      expect(URI.decode_www_form(query)).to eq([
                                                 %w[sslmode require],
                                                 ['application_name', "volcano_user_access:#{user_id}"]
                                               ])
    end
  end

  it 'replaces the prior access scope instead of accumulating application_name parameters' do
    check_property(strings) do |value|
      first = described_class.database_connection_string(base, user_id: "first-#{value}")
      second = described_class.database_connection_string(first, user_id: "second-#{value}")
      expect(second).to eq(described_class.database_connection_string(base, user_id: "second-#{value}"))
    end
  end
end
