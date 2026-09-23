# frozen_string_literal: true

RSpec.describe Volcano::Client do
  it 'rejects a missing captured session when constructing an active binding' do
    client = described_class.new(anon_key: 'anon')
    auth = Volcano.const_get(:FunctionAuth).new(client)

    expect { auth.__send__(:active_binding) }.to raise_error(Volcano::Error::SessionChangedError)
  end
end
