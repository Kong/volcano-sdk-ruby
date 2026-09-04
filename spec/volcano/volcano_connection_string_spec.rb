# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano do
  it 'selects full access without changing the advertised connection target' do
    base = 'postgresql://user:p%40ss@db.example.com/app?sslmode=require&application_name=old'

    expect(described_class.database_connection_string(base)).to eq(
      'postgresql://user:p%40ss@db.example.com/app?' \
      'sslmode=require&application_name=volcano_full_access'
    )
  end

  it 'preserves unrelated query parameters without form decoding them' do
    base = 'postgresql://db.example.com/app?options=-c+search_path%3Dapp&application_name=old'

    expect(described_class.database_connection_string(base)).to eq(
      'postgresql://db.example.com/app?' \
      'options=-c+search_path%3Dapp&application_name=volcano_full_access'
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

  it 'preserves hostless URI authority' do
    expect(described_class.database_connection_string('postgresql:///app')).to eq(
      'postgresql:///app?application_name=volcano_full_access'
    )
  end

  it 'preserves libpq-compatible reserved characters in credentials' do
    expect(described_class.database_connection_string('postgres://u:pa?ss#word@host/db')).to eq(
      'postgres://u:pa?ss#word@host/db?application_name=volcano_full_access'
    )
  end

  it 'accepts multi-host IPv6 connection URIs' do
    expect(described_class.database_connection_string('postgresql://[::1],[::2]/db')).to eq(
      'postgresql://[::1],[::2]/db?application_name=volcano_full_access'
    )
  end

  it 'drops a trailing query separator before appending' do
    expect(described_class.database_connection_string('postgresql://host/db?sslmode=require&')).to eq(
      'postgresql://host/db?sslmode=require&application_name=volcano_full_access'
    )
  end

  it 'does not treat an at sign in a query value as user-info' do
    expect(described_class.database_connection_string('postgresql://host/db?options=foo@bar')).to eq(
      'postgresql://host/db?options=foo@bar&application_name=volcano_full_access'
    )
  end

  it 'rejects missing, relative, and malformed connection URLs' do
    expect { described_class.database_connection_string(nil) }.to raise_error(
      ArgumentError, 'database_connection_string: base_connection_string (DATABASE_URL) is required'
    )
    expect { described_class.database_connection_string('databases/app') }.to raise_error(
      ArgumentError, 'database_connection_string: base_connection_string is not a valid connection URL'
    )
    expect { described_class.database_connection_string('https://db.example.com/app') }.to raise_error(
      ArgumentError, 'database_connection_string: base_connection_string is not a valid connection URL'
    )
    expect do
      described_class.database_connection_string('postgres://db.example.com/%')
    end.to raise_error(
      ArgumentError, 'database_connection_string: base_connection_string is not a valid connection URL'
    )
  end
end
