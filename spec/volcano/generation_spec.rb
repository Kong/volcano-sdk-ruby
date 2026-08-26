# frozen_string_literal: true

require 'digest'
require 'open3'
require 'tmpdir'

RSpec.describe 'OpenAPI generation' do
  ROOT = File.expand_path('../..', __dir__)
  OPENAPI_SHA256 = 'c26ab2f32961699b19f710c1174906b7baae077eefcec299a6c19a36d2f559f6'

  it 'uses the exact bundled contract and emits all six POC operations' do
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
        'auth_signin',
        'query_database_select',
        'upload_storage_object',
        'download_storage_object',
        'acquire_project_lock',
        'release_project_lock'
      )
    end
  end
end
