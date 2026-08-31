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
end
