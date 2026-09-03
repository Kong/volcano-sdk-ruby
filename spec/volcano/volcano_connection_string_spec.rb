# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano do
  it 'selects full access without changing the advertised connection target' do
    base = 'postgresql://user:p%40ss@db.example.com/app?sslmode=require&application_name=old#target'

    expect(described_class.database_connection_string(base)).to eq(
      'postgresql://user:p%40ss@db.example.com/app?' \
      'sslmode=require&application_name=volcano_full_access#target'
    )
  end

  it 'selects user access and encodes the user identifier as a query value' do
    result = described_class.database_connection_string(
      'postgres://user:password@db.example.com/app',
      user_id: 'user + one'
    )

    expect(result).to eq(
      'postgres://user:password@db.example.com/app?' \
      'application_name=volcano_user_access%3Auser%20%2B%20one'
    )
  end

  it 'treats an empty user identifier as full access' do
    result = described_class.database_connection_string(
      'postgres://user:password@db.example.com/app', user_id: ''
    )

    expect(result).to end_with('application_name=volcano_full_access')
  end

  it 'rejects missing, relative, and malformed connection URLs' do
    expect { described_class.database_connection_string(nil) }.to raise_error(
      ArgumentError, 'database_connection_string: base_connection_string (DATABASE_URL) is required'
    )
    expect { described_class.database_connection_string('databases/app') }.to raise_error(
      ArgumentError, 'database_connection_string: base_connection_string is not a valid connection URL'
    )
    expect do
      described_class.database_connection_string('postgres://db.example.com/%')
    end.to raise_error(
      ArgumentError, 'database_connection_string: base_connection_string is not a valid connection URL'
    )
  end
end
