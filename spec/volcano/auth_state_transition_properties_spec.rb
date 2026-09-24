# frozen_string_literal: true

class AuthStateNotificationModel
  attr_reader :current, :expected, :observed, :state

  def initialize
    @state = Volcano::AuthState.new
    @current = nil
    @handles = {}
    @active = {}
    @expected = []
    @observed = []
  end

  def apply(action)
    case action
    when 0, 1 then subscribe(action)
    when 2, 3 then unsubscribe(action - 2)
    else transition(action)
    end
  end

  private

  def subscribe(slot)
    unsubscribe(slot)
    @handles[slot] = @state.subscribe do |event, session|
      @observed << [slot, event, session&.access_token]
    end
    @active[slot] = true
    @expected << [slot, :initial_session, @current&.access_token]
  end

  def unsubscribe(slot)
    @handles.delete(slot)&.unsubscribe
    @active.delete(slot)
  end

  def transition(action)
    previous = @current
    @current = action == 5 ? nil : Volcano::Session.new("access-#{action}")
    event = transition_event(action, previous)
    @state.store(@current, event: event)
    token = @current&.access_token
    @active.each_key { |slot| @expected << [slot, event, token] }
  end

  def transition_event(action, previous)
    return :signed_out if action == 5
    return :token_refreshed if action == 7 && previous

    :signed_in
  end
end

RSpec.describe Volcano::AuthState do
  it 'preserves subscription order and state through arbitrary transitions' do
    actions = PropCheck::Generators.array(PropCheck::Generators.choose(0..7), min: 1, max: 40)
    check_property(actions) do |sequence|
      model = AuthStateNotificationModel.new
      sequence.each do |action|
        model.apply(action)
        expect(model.observed).to eq(model.expected)
        expect(model.state.current).to eq(model.current)
      end
    end
  end

  it 'does not deliver to a subscriber removed by an earlier callback' do
    state = described_class.new
    observed = []
    removed = nil
    state.subscribe { |event, _session| removed&.unsubscribe if event == :signed_in }
    removed = state.subscribe { |event, _session| observed << event }

    state.store(Volcano::Session.new('access'))

    expect(observed).to eq([:initial_session])
  end
end
