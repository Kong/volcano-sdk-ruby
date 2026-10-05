# frozen_string_literal: true

require 'steep'

RSpec.describe Steep::Project do
  let(:root) { Pathname(File.expand_path('../..', __dir__)) }

  def configured_targets(filename)
    path = root.join(filename)
    project = described_class.new(steepfile_path: path)
    Steep::Project::DSL.parse(project, path.read, filename: path.to_s)
    project.targets.flat_map { |target| [target, *target.groups] }
  end

  %w[Steepfile Steepfile.transport].each do |filename|
    it "retains every diagnostic as an error in #{filename}" do
      targets = configured_targets(filename)
      expect(targets).not_to be_empty

      targets.each do |target|
        expect(target.code_diagnostics_config).to eq(Steep::Diagnostic::Ruby.all_error), target.name.to_s
      end
    end
  end
end
