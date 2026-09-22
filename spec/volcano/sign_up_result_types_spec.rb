# frozen_string_literal: true

RSpec.describe Volcano::SignUpResult do
  it 'accepts a typed session and signup result consumer' do
    source = File.read(File.expand_path('../../tests/types/session_sign_up.rb', __dir__))
    output, errors, status = SteepConsumer.check(source)

    expect(status.success?).to be(true), output + errors
  end

  it 'rejects a non-string session access token' do
    output, errors, status = SteepConsumer.check('Volcano::Session.new(access_token: 7)')

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::UnresolvedOverloading')
  end

  it 'rejects a non-boolean confirmation requirement' do
    output, errors, status = SteepConsumer.check(
      "Volcano::SignUpResult.new(confirmation_required: 'yes', message: 'Accepted')"
    )

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::ArgumentTypeMismatch')
  end

  it 'rejects invalid bracket constructor arguments' do
    output, errors, status = SteepConsumer.check('Volcano::Session[access_token: 7]')

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::UnresolvedOverloading')
  end

  it 'rejects invalid values passed to Data updates' do
    source = <<~RUBY
      session = Volcano::Session.new(access_token: 'access')
      session.with(access_token: 7)
      result = Volcano::SignUpResult.new(confirmation_required: false, message: 'Accepted')
      result.with(confirmation_required: 'yes')
    RUBY
    output, errors, status = SteepConsumer.check(source)

    expect(status.exitstatus).to eq(1), output + errors
    expect(output.scan('Ruby::ArgumentTypeMismatch').length).to eq(2)
  end
end
