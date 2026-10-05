# frozen_string_literal: true

require 'volcano'

response = Volcano::FunctionResponse.new(
  data: { 'ok' => true, 'items' => [1, nil] }, status: 200,
  headers: { 'Content-Type' => 'application/json' }, version: 'v1'
)
raise 'Wrong members' unless Volcano::FunctionResponse.members == %i[data status headers version]
raise 'Wrong response' unless response.data == { 'ok' => true, 'items' => [1, nil] }
raise 'Mutable data' unless response.data.frozen?

binary = "\x00\xFF".b
binary_response = Volcano::FunctionResponse["\x00\xFF".b, 206, { 'Content-Type' => 'application/octet-stream' }, nil]
raise 'Binary changed' unless binary_response.data == binary

updated = response.with(status: 201, version: nil)
raise 'Wrong update' unless updated.status == 201 && updated.version.nil?
raise 'Wrong snapshot' unless updated.to_h[:status] == 201
raise 'Wrong tuple' unless updated.deconstruct == [response.data, 201, response.headers, nil]
raise 'Wrong key' unless updated.deconstruct_keys([:status])[:status] == 201
raise 'Wrong full keys' unless updated.deconstruct_keys(nil)[:headers] == response.headers

mapped = updated.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped snapshot' unless mapped['status'] == '201'
