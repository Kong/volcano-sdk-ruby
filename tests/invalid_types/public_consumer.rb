# frozen_string_literal: true

require 'volcano'

Volcano.database_connection_string(42)
Volcano::FunctionResponse.new(data: nil, status: 'ok', headers: {}, version: nil)
Volcano.database_connection_string('postgres://localhost').missing_sdk_method
