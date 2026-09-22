# frozen_string_literal: true

RSpec.describe Volcano::Logs do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', access_token: 'access', _transport: transport) }

  let(:complete_page) { { 'data' => [], 'limit' => 1, 'has_more' => false, 'next_cursor' => nil } }

  [{ 'limit' => nil }, { 'limit' => '1' }, { 'has_more' => nil },
   { 'has_more' => 'false' }, { 'next_cursor' => 1 }].each do |fields|
    it "rejects invalid log pagination #{fields.inspect}" do
      payload = complete_page.merge(fields)
      response = Volcano::Transport::Response.new(status: 200, body: payload, headers: {}, data: nil)
      allow(transport).to receive(:search_project_logs).and_return(response)

      expect { client.logs.search('project', {}) }.to raise_error(TypeError, 'Expected a complete log response')
    end
  end

  [nil, '0', 0.5, false].each do |total|
    it "rejects an invalid activity total #{total.inspect}" do
      response = Volcano::Transport::Response.new(
        status: 200, body: { 'data' => [], 'total' => total }, headers: {}, data: nil
      )
      allow(transport).to receive(:get_project_log_activity).and_return(response)

      expect { client.logs.activity('project', {}) }.to raise_error(TypeError, 'Expected a complete log response')
    end
  end
end
