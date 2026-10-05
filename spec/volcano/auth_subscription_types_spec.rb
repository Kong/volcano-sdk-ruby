# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::AuthSubscription do
  it 'accepts a typed consumer of the public subscription handle' do
    fixture = File.expand_path('../../tests/types/auth_subscription.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.success?).to be(true), output + errors
    expect { load(fixture) }.not_to raise_error
    expect(empty_subscription.unsubscribe).to be_nil
  end

  it 'rejects a consumer that passes arguments to unsubscribe' do
    fixture = File.expand_path('../../tests/types_invalid/auth_subscription.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::UnexpectedPositionalArgument')
  end

  it 'ships the subscription signature in the gem manifest' do
    files = Gem::Specification.load(File.expand_path('../../volcano-sdk.gemspec', __dir__)).files

    expect(files).to include('sig/auth_subscription.rbs')
  end
end
