# frozen_string_literal: true

require 'open3'
require 'rubocop'

RSpec.describe RuboCop::DirectiveComment do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:approved_lines) do
    [
      'def initialize( # rubocop:disable Metrics/ParameterLists -- Preserve typed constructor keywords.',
      '_transport: nil, # rubocop:disable Lint/UnderscorePrefixedVariableName -- Existing keyword API.',
      '_realtime_socket_factory: nil, # rubocop:disable Lint/UnderscorePrefixedVariableName -- Existing keyword API.',
      '_realtime_reconnect_delay: nil, # rubocop:disable Lint/UnderscorePrefixedVariableName -- Existing keyword API.'
    ]
  end

  def lint_targets
    output, error, status = Open3.capture3(
      Gem.ruby, Gem.bin_path('rubocop', 'rubocop'), '--list-target-files', chdir: root
    )
    expect(status.exitstatus).to eq(0), error
    output.lines.map(&:strip)
  end

  def directives(path)
    source = RuboCop::ProcessedSource.from_file(File.join(root, path), 3.2)
    source.comments.filter_map do |comment|
      next unless RuboCop::DirectiveComment.new(comment).mode

      [path, comment.source_range.source_line.strip]
    end
  end

  it 'limits directives to the four approved constructor lines' do
    expected = approved_lines.map { |line| ['lib/volcano/client.rb', line] }

    expect(lint_targets.flat_map { |path| directives(path) }).to match_array(expected)
  end

  it 'requires every approved exception to suppress exactly its documented diagnostic' do
    output, error, status = Open3.capture3(
      Gem.ruby, Gem.bin_path('rubocop', 'rubocop'), '--ignore-disable-comments', '--format', 'json',
      'lib/volcano/client.rb', chdir: root
    )
    expect(status.exitstatus).to eq(1), error
    offenses = JSON.parse(output).fetch('files').first.fetch('offenses')
    source = File.readlines(File.join(root, 'lib/volcano/client.rb'))
    lines = offenses.map { |offense| source.fetch(offense.fetch('location').fetch('start_line') - 1).strip }
    expect(lines).to match_array(approved_lines)
    expect(offenses.map { |offense| offense.fetch('cop_name') }.tally).to eq(
      'Metrics/ParameterLists' => 1, 'Lint/UnderscorePrefixedVariableName' => 3
    )
  end
end
