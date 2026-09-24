# frozen_string_literal: true

require 'open3'
require 'rubocop'

RSpec.describe RuboCop do
  let(:root) { File.expand_path('../..', __dir__) }

  def inspect_source(source, path)
    output, error, status = Open3.capture3(
      Gem.ruby, Gem.bin_path('rubocop', 'rubocop'), '--format', 'json', '--force-exclusion', '--stdin', path,
      stdin_data: "# frozen_string_literal: true\n\n#{source}\n", chdir: root
    )
    expect([0, 1]).to include(status.exitstatus), error
    [JSON.parse(output).fetch('files').first.fetch('offenses'), status.exitstatus]
  end

  directives = %w[disable todo].freeze
  coverage_directives = ['# simplecov:disable', '# simplecov : disable branch -- reason', '# :nocov:'].freeze
  %w[lib/volcano/quality_probe.rb spec/quality/quality_probe_spec.rb].each do |path|
    context "with #{path}" do
      it 'accepts valid Ruby through the project configuration' do
        offenses, status = inspect_source("value = 1\nString(value)", path)
        expect(status).to eq(0)
        expect(offenses).to be_empty
      end

      it 'enforces complexity and method length on this source tree' do
        source = <<~RUBY
          def quality_probe(value)
            if value == 1
              true
            elsif value == 2
              true
            elsif value == 3
              true
            elsif value == 4
              true
            elsif value == 5
              true
            else
              false
            end
          end
        RUBY
        offenses, status = inspect_source(source, path)

        expect(status).to eq(1)
        expect(offenses.map { |offense| offense.fetch('cop_name') }).to include(
          'Metrics/CyclomaticComplexity', 'Metrics/MethodLength'
        )
      end

      directives.each do |directive|
        it "reports offenses covered by rubocop:#{directive}" do
          offenses, status = inspect_source(
            "value=1 # rubocop:#{directive} Layout/SpaceAroundOperators\nString(value)", path
          )
          expect(status).to eq(1)
          expect(offenses).to include(a_hash_including('cop_name' => 'Layout/SpaceAroundOperators'))
        end
      end

      coverage_directives.each do |directive|
        it "rejects the coverage directive #{directive}" do
          offenses, status = inspect_source("#{directive}\nvalue = 1\nString(value)", path)

          expect(status).to eq(1)
          expect(offenses).to include(a_hash_including('cop_name' => 'Volcano/CoverageSuppression'))
        end
      end

      it 'rejects inline coverage suppression despite a RuboCop disable directive' do
        offenses, status = inspect_source(
          "# rubocop:disable Volcano/CoverageSuppression\nString(1) # simplecov:disable", path
        )

        expect(status).to eq(1)
        expect(offenses).to include(a_hash_including('cop_name' => 'Volcano/CoverageSuppression'))
      end

      it 'allows directive text inside strings and heredocs' do
        offenses, status = inspect_source(
          "String('# simplecov:disable')\nString(<<~TEXT)\n  # simplecov:disable\nTEXT", path
        )

        expect(status).to eq(0)
        expect(offenses).to be_empty
      end

      it 'rejects redundant disable comments' do
        offenses, status = inspect_source(
          "value = 1 # rubocop:disable Layout/SpaceAroundOperators\nString(value)", path
        )
        expect(status).to eq(1)
        expect(offenses).to include(a_hash_including('cop_name' => 'Lint/RedundantCopDisableDirective'))
      end
    end
  end

  it 'includes the package quickstart in normal lint discovery' do
    output, error, status = Open3.capture3(
      Gem.ruby, Gem.bin_path('rubocop', 'rubocop'), '--list-target-files', chdir: root
    )
    expect(status.exitstatus).to eq(0), error
    expect(output.lines.map(&:strip)).to include('.github/scripts/quickstart.rb')
  end
end
