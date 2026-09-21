# frozen_string_literal: true

RSpec.describe Volcano::AuthState do
  let(:session) { Volcano::Session.new('access', 'refresh', 'user') }
  let(:state) { described_class.new(session: session) }

  it 'publishes rejection before notifying subscribers of credential removal' do
    generation, lineage, = state.capture_binding
    observed = []
    state.subscribe do |event, current|
      observed << [event, current, state.refresh_rejected?(generation, lineage)]
    end

    expect(state.reject_refresh_if_current?(generation)).to be(true)
    expect(observed).to eq([[:initial_session, session, false], [:signed_out, nil, true]])
    expect(state.current).to be_nil
  end

  it 'does not mark or clear a newer session when a stale refresh is rejected' do
    generation, lineage, = state.capture_binding
    replacement = Volcano::Session.new('replacement', 'replacement-refresh', 'other')
    state.store(replacement)

    expect(state.reject_refresh_if_current?(generation)).to be(false)
    expect(state.refresh_rejected?(generation, lineage)).to be(false)
    expect(state.current).to eq(replacement)
  end

  it 'does not turn an already empty state into a rejected refresh' do
    state = described_class.new
    generation, lineage, = state.capture_binding

    expect(state.reject_refresh_if_current?(generation)).to be(false)
    expect(state.refresh_rejected?(generation, lineage)).to be(false)
    expect(state.capture_binding).to eq([generation, lineage, nil])
  end
end
