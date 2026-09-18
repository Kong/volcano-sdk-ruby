# frozen_string_literal: true

require 'spec_helper'
require 'async'
require_relative '../../features/support/postgres_changes'

RSpec.describe VolcanoContract::PostgresChanges do
  it 'bounds both notification waits with one timeout' do
    verifier = described_class.allocate
    observers = Array.new(2) { instance_double(VolcanoContract::ChangeObserver) }
    Async do |task|
      allow(task).to receive(:with_timeout).with(10).and_wrap_original do |method, _, &block|
        method.call(0.03, &block)
      end
      observers.each { |observer| allow(observer).to receive(:next) { task.sleep(0.02) } }
      expect { verifier.send(:receive_changes, task, observers) }.to raise_error(Async::TimeoutError)
    end.wait
  end

  [[true, :record], [false, :id], [true, :table], [true, :id], [true, :mode]].each do |automatic, wrong_field|
    it "rejects a mismatched #{wrong_field} in the Postgres notification" do
      verifier = described_class.allocate
      verifier.instance_variable_set(:@table_name, 'records')
      row = { 'id' => 'row', 'value' => 'inserted', 'owner_id' => 'user' }
      fields = { type: 'INSERT', schema: 'public', table: 'records', timestamp: '2026-09-18T12:00:00Z',
                 record: automatic ? row : nil, id: automatic ? nil : 'row', mode: automatic ? nil : 'lightweight' }
      event = Volcano::Realtime::PostgresChange.new(**fields)
      verifier.send(:verify_change, event, 'INSERT', row, automatic: automatic)
      wrong_value = wrong_field == :record ? { 'id' => 'wrong' } : 'wrong'
      event = Volcano::Realtime::PostgresChange.new(**fields, wrong_field => wrong_value)
      expect { verifier.send(:verify_change, event, 'INSERT', row, automatic: automatic) }.to raise_error(RuntimeError)
    end
  end
end
