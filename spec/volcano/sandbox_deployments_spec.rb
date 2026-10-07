# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::SandboxDeployments do
  def project = '00000000-0000-4000-8000-000000000001'
  def template = '00000000-0000-4000-8000-000000000002'
  def deployment = '00000000-0000-4000-8000-000000000003'
  def request_id = '00000000-0000-4000-8000-000000000004'
  let(:facade) { Volcano::Client.new(anon_key: 'anon', service_key: 'service', api_url: 'https://sandbox.test').sandboxes }
  let(:requests) { [] }
  let(:uploaded) { [] }
  let(:row) do
    { id: deployment, status: 'active', created_at: '2026-10-07T10:00:00Z', updated_at: '2026-10-07T10:00:00Z' }
  end

  def source = "\x1f\x8b\x00\xffsource".b

  def reply(payload = nil, status: 200, binary: false)
    response = Typhoeus::Response.new(code: status, body: binary ? payload : JSON.generate(payload),
                                      headers: { 'Content-Type' => binary ? 'application/gzip' : 'application/json' })
    Typhoeus.stub(%r{\Ahttps://sandbox.test}).and_return do |request|
      requests << request
      capture_upload(request)
      response
    end
  end

  def capture_upload(request)
    file = request.options[:body].is_a?(Hash) && request.options[:body]['code']
    uploaded << File.binread(file.path) if file.is_a?(File)
  end

  after { Typhoeus::Expectation.clear }

  it 'uploads exact archive bytes and keeps a caller retry identity' do
    reply(row, status: 202)
    2.times do
      result = facade.deploy(project, template, source, name: 'custom', ports: [8080], request_id: request_id)
      expect(result.id).to eq(deployment)
    end
    expect(requests.map { |request| request.options[:headers][:'Idempotency-Key'] }).to eq([request_id, request_id])
    expect(requests.last.options[:body]['ports']).to eq('[8080]')
    expect(uploaded).to eq([source, source])
  end

  it 'reads history and deployment status' do
    reply({ data: [row], pagination: { limit: 20, has_more: true, next_cursor: 'next' } })
    page = facade.deployments(project, template, cursor: 'current', limit: 7)
    expect(page.data.first.id).to eq(deployment)
    expect(page.next_cursor).to eq('next')
    expect(requests.last.options[:params]).to include(cursor: 'current', limit: 7)
    reply(row)
    expect(facade.deployment(project, template, deployment).status).to eq('active')
  end

  it 'returns exact gzip bytes and regional log pages then deletes the template' do
    reply(source, binary: true)
    expect(facade.source(project, template, deployment)).to eq(source)
    reply({ data: [{ timestamp: '2026-10-07T10:00:00Z', message: 'building' }], next_cursor: 'next' })
    logs = facade.logs(project, template, deployment, region: 'aws-us-east-1', cursor: 'cursor', limit: 10)
    expect(logs.data.first.message).to eq('building')
    expect(logs.next_cursor).to eq('next')
    expect(requests.last.options[:params]).to include(region: 'aws-us-east-1', cursor: 'cursor', limit: 10)
    reply(nil, status: 202)
    expect(facade.delete_template(project, template)).to be_nil
  end

  it 'represents exhausted log and history pages without a cursor' do
    reply({ data: [], pagination: { limit: 20, has_more: false } })
    expect(facade.deployments(project, template).next_cursor).to be_nil
    expect(requests.last.options[:params]).to include(limit: 10)
    reply({ data: [] })
    expect(facade.logs(project, template, deployment, region: 'aws-us-east-1').next_cursor).to be_nil
  end

  it 'rejects oversized archives and invalid ports before dispatch' do
    expect { facade.deploy(project, template, 'x' * ((32 * 1024 * 1024) + 1), name: 'custom') }
      .to raise_error(Volcano::Error::ValidationError)
    expect { facade.deploy(project, template, source, name: 'custom', ports: [0]) }
      .to raise_error(Volcano::Error::ValidationError)
    expect(requests).to be_empty
  end
end
