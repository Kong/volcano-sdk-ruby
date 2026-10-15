# frozen_string_literal: true

module Volcano
  RSpec.describe DurableMessageCatchUps do
    subject(:catch_ups) { described_class.new(-> {}, -> {}, ->(_error) {}) }

    def retry_delays(count)
      Array.new(count) do
        catch_ups.retry_later
        catch_ups.instance_variable_get(:@retry_delay)
      end
    end

    it 'waits half a second before the first retry, doubling to 30 seconds' do
      expect(retry_delays(9)).to eq([0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 30.0, 30.0, 30.0])
    end

    it 'starts the backoff over once a catch-up caught up' do
      retry_delays(3)
      catch_ups.caught_up

      expect(retry_delays(2)).to eq([0.5, 1.0])
    end

    it 'schedules no retry once closed' do
      catch_ups.close

      expect(retry_delays(1)).to eq([nil])
    end
  end
end
