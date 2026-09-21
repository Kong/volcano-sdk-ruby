# frozen_string_literal: true

require 'support/session_fixtures'
require 'support/refresh_rejection_signals'

RSpec.describe Volcano::QueryBuilder do
  include SessionFixtures

  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', _transport: transport) }
  let(:signals) { SpecSupport::RefreshRejectionSignals.new }

  def denied(message)
    Volcano::Transport::Response.new(status: 401, body: { 'error' => message }, headers: {}, data: nil)
  end

  def read_error
    client.database('db').from('items').select('*').execute
  rescue Volcano::Error::VolcanoError => e
    e
  end

  before do
    client.auth.current_session = Volcano::Session.new(access_token('old'), 'refresh', 'user')
    allow(transport).to receive(:auth_refresh).and_return(denied('refresh failed'))
    allow(transport).to receive(:query_database_select) do
      signals.started << true
      signals.release_read.pop
      denied('read expired')
    end
    allow(client).to receive(:reject_refresh_if_current?).and_wrap_original do |original, *args, **options|
      result = original.call(*args, **options)
      signals.cleared << true
      signals.finish_clear.pop
      result
    end
  end

  def wait_for_clear
    2.times { signals.started.pop }
    signals.release_read << true
    signals.cleared.pop
  end

  def release_reads
    wait_for_clear
    signals.release_read << true
    follower = signals.results.pop
    signals.finish_clear << true
    [follower, signals.results.pop]
  end

  def concurrent_failures
    readers = Array.new(2) { Thread.new { signals.results << read_error } }
    Timeout.timeout(5) { release_reads }
  ensure
    readers&.each { |reader| reader.kill.join }
  end

  it 'preserves both failures when a read resumes immediately after rejected refresh clears credentials' do
    expect(concurrent_failures.map(&:message)).to eq(['read expired', 'read expired'])
    expect(client.current_session).to be_nil
    expect(transport).to have_received(:auth_refresh).once
  end
end
