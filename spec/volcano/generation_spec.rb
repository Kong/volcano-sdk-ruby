# frozen_string_literal: true

require 'digest'
require 'open3'
require 'tmpdir'

RSpec.describe 'OpenAPI generation' do
  ROOT = File.expand_path('../..', __dir__)
  OPENAPI_SHA256 = 'c26ab2f32961699b19f710c1174906b7baae077eefcec299a6c19a36d2f559f6'

  it 'uses the exact bundled contract and emits all eight POC operations' do
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
        'acquire_project_lock',
        'release_project_lock'
      )
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
