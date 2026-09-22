# frozen_string_literal: true

RSpec.describe Volcano do
  it 'accepts a typed database connection string consumer' do
    source = File.read(File.expand_path('../../tests/types/connection_string.rb', __dir__))
    output, errors, status = SteepConsumer.check(source)

    expect(status.success?).to be(true), output + errors
  end

  it 'rejects a non-string database user ID' do
    source = "Volcano.database_connection_string('postgresql://db/app', user_id: 7)"
    output, errors, status = SteepConsumer.check(source)

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::ArgumentTypeMismatch')
  end
end
