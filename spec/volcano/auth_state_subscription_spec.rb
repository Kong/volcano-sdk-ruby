# frozen_string_literal: true

RSpec.describe Volcano::AuthState do
  it 'queues a reentrant subscription until the current notification finishes' do
    session = Volcano::Session.new('access', 'refresh', 'user')
    state = described_class.new(session: session)
    observed = []
    nested = nil
    outer = state.subscribe do |event, current|
      observed << [:outer, event, current]
      nested = state.subscribe { |inner_event, inner_session| observed << [:inner, inner_event, inner_session] }
      observed << :outer_finished
    end

    expect(observed).to eq([[:outer, :initial_session, session], :outer_finished, [:inner, :initial_session, session]])
    outer.unsubscribe
    nested.unsubscribe
    state.store(nil, event: :signed_out)
    expect(observed.size).to eq(3)
  end
end
