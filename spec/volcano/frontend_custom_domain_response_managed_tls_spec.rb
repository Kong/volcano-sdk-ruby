# frozen_string_literal: true

require 'spec_helper'
require_relative '../../features/support/contract_world'

RSpec.describe Volcano.const_get(:Generated, false)::FrontendCustomDomainResponse do
  let(:generated) { Volcano.const_get(:Generated, false) }

  it 'keeps the request secret-free and the response provider-neutral' do
    tls = generated::ManagedFrontendCustomDomainTLSConfig.new(mode: 'managed')
    request = generated::CreateFrontendCustomDomainRequest.new(
      domain: 'app.example.com',
      tls: tls
    )

    expect(request.to_hash).to eq(
      domain: 'app.example.com',
      tls: { mode: 'managed' }
    )
    expect(described_class.attribute_map)
      .not_to have_key(:managed_tls_certificate)

    response = described_class.build_from_hash(
      domain: 'app.example.com',
      tls_mode: 'managed',
      domain_status: 'pending_verification',
      verification_status: 'pending',
      verification_records: [
        {
          name: '_token.app.example.com',
          type: 'CNAME',
          value: '_validation.volcano.dev'
        }
      ],
      required_routing_record: {
        record_type: 'CNAME',
        zone_apex_record_type: 'ALIAS',
        name: 'app.example.com',
        value: 'frontend.frontends.volcano.dev'
      },
      effective_urls: ['https://frontend.frontends.volcano.dev/'],
      created_at: '2026-09-02T12:00:00Z',
      updated_at: '2026-09-02T12:00:00Z'
    )
    expect(response.domain_status).to eq('pending_verification')
    expect(response.verification_status).to eq('pending')
    expect(response.verification_records.first.to_hash).to eq(
      name: '_token.app.example.com',
      type: 'CNAME',
      value: '_validation.volcano.dev'
    )
  end

  it 'decodes the discriminator from JSON string keys' do
    tls = generated::CreateFrontendCustomDomainTLSConfig.build('mode' => 'managed')

    expect(tls).to be_a(generated::ManagedFrontendCustomDomainTLSConfig)
    expect(tls.to_hash).to eq(mode: 'managed')
  end

  it 'accepts the failed verification state' do
    response = described_class.allocate

    expect { response.verification_status = 'failed' }.not_to raise_error
    expect(response.verification_status).to eq('failed')
  end

  it 'keeps managed project config certificate-free' do
    type_name = :ManagedProjectConfigFrontendCustomDomainTLSConfig
    expect(generated.const_defined?(type_name, false)).to be(true)

    managed_type = generated.const_get(type_name, false)
    expect(managed_type.attribute_map.keys).not_to include(
      :certificate_pem,
      :private_key_pem,
      :certificate_chain_pem
    )
    expect(managed_type.build_from_hash(mode: 'managed').to_hash).to eq(mode: 'managed')
  end

  it 'requires BYOC project config certificate material as a pair' do
    byoc_type = generated::BYOCProjectConfigFrontendCustomDomainTLSConfig

    expect(byoc_type.new(mode: 'byoc')).to be_valid
    expect(byoc_type.new(mode: 'byoc', certificate_pem: 'certificate')).not_to be_valid
    expect(byoc_type.new(mode: 'byoc', private_key_pem: 'private key')).not_to be_valid
    expect(byoc_type.new(
             mode: 'byoc', certificate_pem: 'certificate', private_key_pem: 'private key'
           )).to be_valid
  end

  it 'stores the managed TLS contract scenario state' do
    world = VolcanoContract::World.allocate

    world.managed_tls_request = :request
    world.managed_tls_wire = :wire
    world.managed_tls_response = :response

    expect(world.managed_tls_request).to eq(:request)
    expect(world.managed_tls_wire).to eq(:wire)
    expect(world.managed_tls_response).to eq(:response)
  end
end
