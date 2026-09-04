# frozen_string_literal: true

require 'digest'
require 'open3'
require 'tmpdir'

RSpec.describe 'OpenAPI generation' do
  ROOT = File.expand_path('../..', __dir__)
  OPENAPI_SHA256 = '076d97809c95f50567d8b100f4188c1fe2b74e73a388e335c79850e66edfc0e4'

  it 'uses the exact bundled contract and emits the required POC operations' do
    expect(Digest::SHA256.file(File.join(ROOT, 'openapi/openapi.yaml')).hexdigest).to eq(OPENAPI_SHA256)

    Dir.mktmpdir('volcano-ruby-openapi') do |directory|
      output = File.join(directory, 'generated')
      stdout, stderr, status = Open3.capture3(
        File.join(ROOT, 'bin/generate-openapi'),
        output,
        chdir: ROOT
      )
      expect(status).to be_success, "#{stdout}\n#{stderr}"

      generated_source = Dir.glob(File.join(output, '**/*.rb')).map { |path| File.binread(path) }.join
      expect(generated_source).to include(
        'auth_signup',
        'auth_signin',
        'auth_get_user',
        'query_database_select',
        'upload_storage_object',
        'download_storage_object',
        'resolve_function_for_invocation',
        'invoke_function',
        'search_project_logs',
        'get_project_log_activity',
        'acquire_project_lock',
        'release_project_lock'
      )
      model_base = File.binread(
        File.join(output, 'lib/volcano-generated/api_model_base.rb')
      )
      expect(model_base).to include('value.map { |v| _to_hash(v) }')
      expect(model_base).not_to include('value.compact.map')
    end
  end

  it 'refuses a nonempty custom output without deleting its contents' do
    Dir.mktmpdir('volcano-ruby-openapi-safety') do |directory|
      output = File.join(directory, 'existing')
      sentinel = File.join(output, 'preserve.txt')
      FileUtils.mkdir_p(output)
      File.binwrite(sentinel, 'preserve')

      _stdout, stderr, status = Open3.capture3(
        File.join(ROOT, 'bin/generate-openapi'),
        output,
        chdir: ROOT
      )

      expect(status).not_to be_success
      expect(stderr).to include('refusing existing custom generated output path')
      expect(File.binread(sentinel)).to eq('preserve')
    end
  end

  it 'refuses a lexical alias to an existing custom output without overwriting it' do
    Dir.mktmpdir('volcano-ruby-openapi-lexical-alias') do |directory|
      output = File.join(directory, 'existing')
      sentinel = File.join(output, 'README.md')
      FileUtils.mkdir(output)
      File.binwrite(sentinel, 'preserve lexical alias')
      aliased_output = File.join(directory, 'missing', '..', 'existing')

      _stdout, _stderr, status = Open3.capture3(
        File.join(ROOT, 'bin/generate-openapi'),
        aliased_output,
        chdir: ROOT
      )

      expect(File.binread(sentinel) == 'preserve lexical alias').to be(true)
      expect(status).not_to be_success
    end
  end

  it 'refuses a symlink alias to an existing custom output without overwriting it' do
    Dir.mktmpdir('volcano-ruby-openapi-symlink-alias') do |directory|
      target = File.join(directory, 'target')
      sentinel = File.join(target, 'README.md')
      link = File.join(directory, 'existing-link')
      FileUtils.mkdir(target)
      File.binwrite(sentinel, 'preserve symlink alias')
      File.symlink(target, link)
      aliased_output = File.join(directory, 'missing', '..', 'existing-link')

      _stdout, _stderr, status = Open3.capture3(
        File.join(ROOT, 'bin/generate-openapi'),
        aliased_output,
        chdir: ROOT
      )

      expect(File.binread(sentinel) == 'preserve symlink alias').to be(true)
      expect(status).not_to be_success
    end
  end

  it 'generates into a new custom output under an existing parent' do
    Dir.mktmpdir('volcano-ruby-openapi-new-output') do |directory|
      output = File.join(directory, 'generated')

      stdout, stderr, status = Open3.capture3(
        File.join(ROOT, 'bin/generate-openapi'),
        output,
        chdir: ROOT
      )

      expect(status).to be_success, "#{stdout}\n#{stderr}"
      expect(File).to exist(File.join(output, 'lib/volcano-generated.rb'))
    end
  end

  it 'does not treat an explicit empty custom output as the committed output' do
    Dir.mktmpdir('volcano-ruby-openapi-empty-output') do |directory|
      script = File.join(directory, 'bin/generate-openapi')
      sentinel = File.join(directory, 'lib/volcano/generated/preserve.txt')
      FileUtils.mkdir_p(File.dirname(script))
      FileUtils.mkdir_p(File.dirname(sentinel))
      FileUtils.cp(File.join(ROOT, 'bin/generate-openapi'), script)
      File.binwrite(sentinel, 'preserve committed output')

      _stdout, _stderr, status = Open3.capture3(script, '', chdir: directory)

      expect(File.binread(sentinel) == 'preserve committed output').to be(true)
      expect(status).not_to be_success
    end
  end
end
