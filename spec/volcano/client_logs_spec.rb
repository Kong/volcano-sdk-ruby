# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::Client do
  let(:calls) { [] }
  let(:transport) do
    call_log = calls
    Object.new.tap do |fake|
      fake.define_singleton_method(:search_project_logs) do |**arguments|
        call_log << [:search_project_logs, arguments]
        Volcano::Transport::Response.new(
          status: 200,
          body: {
            'data' => [
              {
                'id' => 'event-1',
                'timestamp' => '2026-09-02T12:00:00Z',
                'body' => { 'message' => 'ready' },
                'resource' => { 'type' => 'function', 'id' => 'function-1' }
              }
            ],
            'limit' => 25, 'has_more' => true, 'next_cursor' => 'cursor-2'
          },
          headers: {}, data: nil
        )
      end
      fake.define_singleton_method(:get_project_log_activity) do |**arguments|
        call_log << [:get_project_log_activity, arguments]
        Volcano::Transport::Response.new(
          status: 200,
          body: {
            'data' => [
              {
                'start_time' => '2026-09-02T12:00:00Z',
                'end_time' => '2026-09-02T12:05:00Z',
                'counts' => {
                  'levels' => { 'info' => 2 },
                  'regions' => { 'us-east-1' => 2 },
                  'resource_ids' => { 'function-1' => 2 }
                },
                'total' => 2
              }
            ],
            'total' => 2
          },
          headers: {}, data: nil
        )
      end
    end
  end
  let(:client) do
    described_class.new(anon_key: 'anon-key', _transport: transport).tap do |value|
      value.auth.current_session = Volcano::Session.new(
        access_token: 'access-token', refresh_token: 'refresh-token', user_id: 'user-1'
      )
    end
  end

  it 'searches project logs and returns an immutable page', :aggregate_failures do
    request = { 'resource' => { 'type' => 'function' }, 'limit' => 25 }

    result = client.logs.search('project-1', request)

    expect(result).to have_attributes(limit: 25, has_more: true, next_cursor: 'cursor-2')
    expect(result.data.first.fetch('body')).to eq('message' => 'ready').and be_frozen
    expect(result.data).to be_frozen
    expect(calls).to eq(
      [[
        :search_project_logs,
        { authorization: 'access-token', project_id: 'project-1', request: request }
      ]]
    )
  end

  it 'returns immutable log activity buckets', :aggregate_failures do
    request = { 'resource' => { 'type' => 'function' }, 'bucket_count' => 12 }

    result = client.logs.activity('project-1', request)

    expect(result.total).to eq(2)
    expect(result.data.first.fetch('counts')).to eq(
      'levels' => { 'info' => 2 },
      'regions' => { 'us-east-1' => 2 },
      'resource_ids' => { 'function-1' => 2 }
    ).and be_frozen
    expect(calls.first).to eq(
      [
        :get_project_log_activity,
        { authorization: 'access-token', project_id: 'project-1', request: request }
      ]
    )
  end

  it 'rejects invalid project IDs before transport' do
    ['', '   '].each do |project_id|
      expect do
        client.logs.search(project_id, 'resource' => { 'type' => 'function' })
      end.to raise_error(ArgumentError, /project_id/)
    end

    expect(calls).to be_empty
  end

  it 'rejects non-Hash requests before transport' do
    expect { client.logs.activity('project-1', []) }.to raise_error(TypeError, /Hash/)

    expect(calls).to be_empty
  end
end
