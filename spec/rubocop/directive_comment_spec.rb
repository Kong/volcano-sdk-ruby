# frozen_string_literal: true

require 'open3'
require 'rubocop'

RSpec.describe RuboCop::DirectiveComment do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:approved_scopes) do
    {
      'lib/volcano/client.rb' => [
        'def initialize( # rubocop:disable Metrics/ParameterLists -- Preserve typed constructor keywords.',
        '_transport: nil, # rubocop:disable Lint/UnderscorePrefixedVariableName -- Existing keyword API.',
        '_realtime_socket_factory: nil, # rubocop:disable Lint/UnderscorePrefixedVariableName -- Existing keyword API.',
        '_realtime_reconnect_delay: nil, ' \
        '# rubocop:disable Lint/UnderscorePrefixedVariableName -- Existing keyword API.',
        'def database_with_token(name, token) ' \
        '# rubocop:disable Lint/UnusedPrivateMethod -- Typed cross-file private dispatch.'
      ],
      'lib/volcano/generated_transport.rb' => [
        'error.code.to_i # rubocop:disable Lint/NumberConversion -- Preserve generated ApiError status coercion.'
      ],
      'lib/volcano/lock_guard.rb' => [
        '@lease_clock = LockLeaseClock.new(ttl: ttl, started_at: started_at) ' \
        '# rubocop:disable Lint/NameTypo -- Inherited Class#new.'
      ]
    }
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

  def offense_lines(file)
    path = file.fetch('path')
    source = File.readlines(File.join(root, path))
    file.fetch('offenses').map do |offense|
      [path, source.fetch(offense.fetch('location').fetch('start_line') - 1).strip]
    end
  end

  it 'limits directives to the exact human-approved source lines' do
    expected = approved_scopes.flat_map { |path, lines| lines.map { |line| [path, line] } }

    expect(lint_targets.flat_map { |path| directives(path) }).to match_array(expected)
  end

  it 'requires every approved exception to suppress exactly its documented diagnostic' do
    output, error, status = Open3.capture3(
      Gem.ruby, Gem.bin_path('rubocop', 'rubocop'), '--ignore-disable-comments', '--format', 'json',
      *approved_scopes.keys, chdir: root
    )
    expect(status.exitstatus).to eq(1), error
    files = JSON.parse(output).fetch('files')
    expect(files.flat_map { |file| offense_lines(file) }).to match_array(
      approved_scopes.flat_map { |path, lines| lines.map { |line| [path, line] } }
    )
    cops = files.flat_map { |file| file.fetch('offenses').map { |offense| offense.fetch('cop_name') } }
    expect(cops.tally).to eq(
      'Metrics/ParameterLists' => 1, 'Lint/UnderscorePrefixedVariableName' => 3,
      'Lint/UnusedPrivateMethod' => 1, 'Lint/NumberConversion' => 1, 'Lint/NameTypo' => 1
    )
  end
end
