# frozen_string_literal: true

module Volcano
  RSpec.describe GeneratedTransport do
    let(:generated) { Generated }
    let(:api_client) { described_class::ApiClient.new(generated::Configuration.new) }
    let(:verification_record) { { name: '_token.app.example.com', type: 'CNAME', value: '_validation.volcano.dev' } }
    let(:managed_response) do
      { domain: 'app.example.com', tls_mode: 'managed', domain_status: 'pending_verification',
        verification_status: 'pending', verification_records: [verification_record],
        routing_target_hostname: 'frontend.frontends.volcano.dev',
        effective_urls: ['https://frontend.frontends.volcano.dev/'],
        created_at: '2026-09-02T12:00:00Z', updated_at: '2026-09-02T12:00:00Z' }
    end

    it 'encodes a managed custom-domain request without certificate material' do
      tls = generated::FrontendCustomDomainTLSConfig.new(mode: 'managed')
      request = generated::CreateFrontendCustomDomainRequest.new(domain: 'app.example.com', tls: tls)

      expect(request.to_hash).to eq(domain: 'app.example.com', tls: { mode: 'managed' })
    end

    it 'encodes a BYOC custom-domain request with certificate material' do
      tls = generated::FrontendCustomDomainTLSConfig.new(
        mode: 'byoc', certificate_pem: 'certificate', private_key_pem: 'private key'
      )
      request = generated::CreateFrontendCustomDomainRequest.new(domain: 'app.example.com', tls: tls)

      expect(request.to_hash[:tls]).to eq(mode: 'byoc', certificate_pem: 'certificate', private_key_pem: 'private key')
    end

    it 'defaults an omitted custom-domain TLS mode to BYOC' do
      material = { certificate_pem: 'certificate', private_key_pem: 'private key' }

      expect(generated::FrontendCustomDomainTLSConfig.new(material).to_hash).to eq(mode: 'byoc', **material)
      expect(generated::FrontendCustomDomainTLSConfig.build_from_hash(material).mode).to eq('byoc')
    end

    it 'decodes the managed lifecycle and DNS records' do
      response = api_client.convert_to_type(managed_response, 'FrontendCustomDomainResponse')

      expect(response.domain_status).to eq('pending_verification')
      expect(response.verification_status).to eq('pending')
      expect(response.verification_records.map(&:to_hash)).to eq([verification_record])
      expect(response.routing_target_hostname).to eq('frontend.frontends.volcano.dev')
      expect(response.required_routing_record).to be_nil
    end

    it 'decodes a failed managed verification with its failure category' do
      failed = managed_response.merge(domain_status: 'failed', verification_status: 'failed',
                                      failure_reason: 'ownership')

      response = api_client.convert_to_type(failed, 'FrontendCustomDomainResponse')

      expect(response.verification_status).to eq('failed')
      expect(response.failure_reason).to eq('ownership')
    end

    it 'decodes the ownership record required by a reservation conflict' do
      conflict = api_client.convert_to_type(
        { error: 'ownership verification required', code: 'ownership_verification_required',
          required_record: verification_record },
        'FrontendCustomDomainConflictError'
      )

      expect(conflict.code).to eq('ownership_verification_required')
      expect(conflict.required_record.to_hash).to eq(verification_record)
    end

    it 'decodes a conflict without an ownership recovery path' do
      conflict = api_client.convert_to_type({ error: 'custom domain already in use' },
                                            'FrontendCustomDomainConflictError')

      expect(conflict.to_hash).to eq(error: 'custom domain already in use')
    end

    it 'decodes discriminated project-config TLS from symbol keys' do
      domain = generated::ApiModelBase._deserialize(
        'ProjectConfigCustomDomain', { domain: 'app.example.com', tls: { mode: 'managed' } }
      )

      expect(domain.tls).to be_a(generated::ManagedProjectConfigFrontendCustomDomainTLSConfig)
      expect(domain.to_hash).to eq(domain: 'app.example.com', tls: { mode: 'managed' })
    end

    it 'decodes discriminated project-config TLS from string keys' do
      domain = generated::ApiModelBase._deserialize(
        'ProjectConfigCustomDomain', { 'domain' => 'app.example.com', 'tls' => { 'mode' => 'byoc' } }
      )

      expect(domain.tls).to be_a(generated::BYOCProjectConfigFrontendCustomDomainTLSConfig)
      expect(domain.to_hash).to eq(domain: 'app.example.com', tls: { mode: 'byoc' })
    end

    it 'does not accept unknown project-config TLS modes' do
      expect(generated::ApiModelBase._deserialize('ProjectConfigFrontendCustomDomainTLSConfig', mode: 'other'))
        .to be_nil
    end
  end
end
