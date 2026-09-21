# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::User do
  it 'owns and deeply freezes constructor values', :aggregate_failures do
    email = +'user@example.com'
    metadata = { 'profile' => { 'roles' => [+'admin'] } }
    app_metadata = { 'provider' => +'email' }

    user = described_class.new(
      id: +'user-123', email: email, status: +'active',
      project_id: +'project-123', email_confirmed: true,
      user_metadata: metadata, app_metadata: app_metadata
    )
    email.replace('changed@example.com')
    metadata.fetch('profile').fetch('roles').first.replace('changed')
    app_metadata.fetch('provider').replace('changed')

    expect(user.email).to eq('user@example.com').and be_frozen
    expect(user.user_metadata.dig('profile', 'roles')).to eq(['admin']).and be_frozen
    expect(user.user_metadata.dig('profile', 'roles').first).to be_frozen
    expect(user.app_metadata).to eq('provider' => 'email').and be_frozen
  end

  it 'rejects unknown optional attributes' do
    expect { described_class.new(id: 'user', email: 'user@example.com', status: 'active', unexpected: true) }
      .to raise_error(ArgumentError, 'unknown keywords: unexpected')
  end

  it 'owns mutable timestamp values without freezing caller-owned objects' do
    timestamp = Time.utc(2026, 9, 21)
    user = described_class.new(id: 'user', email: 'user@example.com', status: 'active', created_at: timestamp)

    expect(user.created_at).to eq(timestamp).and be_frozen
    expect(user.created_at).not_to equal(timestamp)
    expect(timestamp).not_to be_frozen
    timestamp.localtime('+02:00')
    expect(user.created_at.utc_offset).to eq(0)
  end
end
