# frozen_string_literal: true

require 'base64'
require 'stringio'
require 'uri'

RSpec.describe Volcano::StorageBucket do
  let(:project) { 'project-123' }
  let(:anon_key) { "header.#{Base64.urlsafe_encode64(JSON.generate(project_id: project), padding: false)}.signature" }
  let(:client) { Volcano::Client.new(api_url: 'https://api.example.test', anon_key: anon_key) }
  let(:bucket) { client.storage.from('bucket &+#?%') }
  let(:strings) { PropCheck::Generators.printable_string }

  it 'round-trips arbitrary object path characters without changing the URL authority or query' do
    check_property(strings) do |value|
      path = "folder/#{value.tr('/', '_')} name"
      url = URI(bucket.get_public_url(path))
      segments = url.path.split('/', -1).map { |segment| URI::DEFAULT_PARSER.unescape(segment) }
      expect(segments).to eq(['', 'public', project, 'bucket &+#?%', *path.split('/', -1)])
      expect([url.scheme, url.host, url.query, url.fragment]).to eq(['https', 'api.example.test', nil, nil])
    end
  end

  it 'refuses dot segments anywhere in an otherwise valid object path' do
    check_property(strings) do |value|
      prefix = "folder-#{value.tr('/', '_')}"
      expect { bucket.get_public_url("#{prefix}/../file") }.to raise_error(ArgumentError, /dot segments/)
      expect { bucket.get_public_url("#{prefix}/./file") }.to raise_error(ArgumentError, /dot segments/)
    end
  end
end
