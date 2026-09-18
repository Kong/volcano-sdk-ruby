# frozen_string_literal: true

require 'spec_helper'
require 'async'
require_relative '../../features/support/postgres_changes'

RSpec.describe VolcanoContract::ChangeObserver do
  [true, false].each do |automatic|
    it "ignores unrelated rows when automatic is #{automatic}" do
      callbacks = []
      channel = instance_double(Volcano::Realtime::Channel)
      allow(channel).to receive(:on_postgres_changes) { |*, &callback| callbacks << callback }
      observer = described_class.new(channel, 'records', 'row')
      change = lambda do |id|
        Volcano::Realtime::PostgresChange.new(type: 'INSERT', schema: 'public', table: 'records',
                                              timestamp: '2026-09-18T12:00:00Z',
                                              record: automatic ? { 'id' => id } : nil,
                                              id: automatic ? nil : id)
      end
      callbacks.each { |callback| callback.call(change.call('other')) }
      expect([observer.events, observer.inserts, observer.wrong_table]).to eq([[], [], []])
      received = Async do |task|
        callbacks.take(2).each { |callback| callback.call(change.call('row')) }
        observer.next(task)
      end.wait
      expect(received).to eq(change.call('row'))
      expect(observer.inserts.length).to eq(1)
    end
  end
end
