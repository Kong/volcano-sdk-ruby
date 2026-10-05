# frozen_string_literal: true

RSpec.describe Volcano::DurableExecutionError do
  it 'preserves absent error type and message' do
    expect(described_class.new).to have_attributes(type: nil, message: nil)
  end

  it 'owns immutable copies of the supplied error fields' do
    type = +'Failure'
    message = +'Failed execution'
    error = described_class.new(type: type, message: message)
    type.replace('Other')
    message.replace('Changed')

    expect(error.type).to eq('Failure').and be_frozen
    expect(error.message).to eq('Failed execution').and be_frozen
  end
end
