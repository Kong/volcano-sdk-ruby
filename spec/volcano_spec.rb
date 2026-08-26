# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano do
  it 'exports the client' do
    expect(Volcano::Client.name).to eq('Volcano::Client')
  end
end
