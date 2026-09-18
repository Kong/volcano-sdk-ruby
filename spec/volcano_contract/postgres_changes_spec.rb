# frozen_string_literal: true

require 'spec_helper'
require_relative '../../features/support/postgres_changes'

RSpec.describe VolcanoContract::PostgresChanges do
  [[true, :record], [false, :id], [true, :table]].each do |automatic, wrong_field|
    it "rejects a mismatched #{wrong_field} in the Postgres notification" do
      verifier = described_class.allocate
      verifier.instance_variable_set(:@table_name, 'records')
      row = { 'id' => 'row', 'value' => 'inserted', 'owner_id' => 'user' }
      fields = { type: 'INSERT', schema: 'public', table: 'records', timestamp: '2026-09-18T12:00:00Z',
                 record: automatic ? row : nil, id: 'row', mode: 'lightweight' }
      event = Volcano::Realtime::PostgresChange.new(**fields)
      verifier.send(:verify_change, event, 'INSERT', row, automatic: automatic)
      wrong_value = wrong_field == :record ? { 'id' => 'wrong' } : 'wrong'
      event = Volcano::Realtime::PostgresChange.new(**fields, wrong_field => wrong_value)
      expect { verifier.send(:verify_change, event, 'INSERT', row, automatic: automatic) }.to raise_error(RuntimeError)
    end
  end
end
