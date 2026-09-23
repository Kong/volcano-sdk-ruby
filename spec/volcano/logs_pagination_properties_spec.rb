# frozen_string_literal: true

RSpec.describe Volcano::Logs do
  it 'preserves opaque pagination cursors across pages' do
    check_property(PropCheck::Generators.printable_string) do |cursor|
      calls = []
      transport = instance_double(Volcano.const_get(:GeneratedTransport))
      allow(transport).to receive(:search_project_logs) do |**arguments|
        calls << arguments
        has_more = calls.one?
        Volcano::Transport::Response.new(
          status: 200,
          body: { 'data' => [], 'limit' => 1, 'has_more' => has_more, 'next_cursor' => (cursor if has_more) },
          headers: {}, data: nil
        )
      end
      client = Volcano::Client.new(anon_key: 'anon', access_token: 'access', _transport: transport)

      page = client.logs.search('project', 'limit' => 1)
      client.logs.search('project', 'cursor' => page.next_cursor)

      expect(page.next_cursor).to eq(cursor).and be_frozen
      expect(calls.last.fetch(:request)).to eq('cursor' => cursor)
    end
  end
end
