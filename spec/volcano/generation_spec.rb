# frozen_string_literal: true

require 'digest'
require 'json'
require 'open3'
require 'tmpdir'

RSpec.describe 'OpenAPI generation' do
  ROOT = File.expand_path('../..', __dir__)
  OPENAPI_SHA256 = '74653534cb8abcb717fbd5c5426f17762657982ce7b6ccaedf2921b6c425ca3b'

  it 'preserves shared-variable digest and nullable function metadata validation' do
    generated = Volcano.const_get(:Generated, false)
    request_class = generated.const_get(:ReplaceSharedVariablesRequest, false)
    function_class = generated.const_get(:UpdateFunctionRequest, false)
    digest = 'a' * 64
    request = request_class.new(shared_variables: [], expected_shared_variables_digest: digest)

    expect(request.to_hash[:expected_shared_variables_digest]).to eq(digest)
    expect do
      request_class.new(shared_variables: [], expected_shared_variables_digest: "#{digest}\n")
    end.to raise_error(ArgumentError)
    expect(function_class.new(openapi_spec: nil).to_hash).to include(openapi_spec: nil)
  end

  it 'preserves explicit null without turning omitted object fields into null' do
    Dir.mktmpdir('volcano-ruby-nullable') do |directory|
      output = File.join(directory, 'generated')
      stdout, stderr, status = Open3.capture3(
        'npx', '--no-install', 'openapi-generator-cli', 'generate',
        '-i', 'tests/fixtures/nullable-object.yaml', '-g', 'ruby',
        '-c', 'openapi-generator.yaml', '-t', 'openapi/templates', '-o', output,
        '--global-property', 'apiTests=false,modelTests=false,apiDocs=false,modelDocs=false', chdir: ROOT
      )
      expect(status).to be_success, "#{stdout}\n#{stderr}"
      stdout, stderr, status = Open3.capture3(
        Gem.ruby, '-I', File.join(output, 'lib'), '-r', 'volcano-generated', '-r', 'json', '-e', <<~RUBY
          model = Volcano::Generated::NullableObjectProbe
          puts JSON.generate(
            omitted: model.new.to_hash,
            explicit_null: model.new(document: nil).to_hash,
            value: model.new(document: { 'enabled' => false }).to_hash,
            nonnullable: model.new(strict: nil).to_hash
          )
        RUBY
      )
      expect(status).to be_success, stderr
      expect(JSON.parse(stdout)).to eq(
        'omitted' => {}, 'explicit_null' => { 'document' => nil },
        'value' => { 'document' => { 'enabled' => false } }, 'nonnullable' => {}
      )
    end
  end

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
