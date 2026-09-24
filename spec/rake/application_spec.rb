# frozen_string_literal: true

require 'rake'

RSpec.describe Rake::Application do
  let(:application) do
    Rake.with_application { load File.expand_path('../../Rakefile', __dir__) }
  end

  it 'keeps every mandatory check in the canonical quality task' do
    expect(application['quality'].prerequisites).to eq(
      %w[quality:audit quality:generated quality:lint quality:types quality:spec quality:defects
         quality:contract quality:package]
    )
  end

  it 'retains executable checks for every quality prerequisite' do
    application['quality'].prerequisite_tasks.each do |task|
      expect(task.actions).not_to be_empty, task.name
    end
  end
end
