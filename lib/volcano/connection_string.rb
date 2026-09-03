# frozen_string_literal: true

require 'uri'

# Public namespace for Volcano SDK helpers.
module Volcano
  FULL_ACCESS_APP_NAME = 'volcano_full_access'
  USER_ACCESS_APP_NAME = 'volcano_user_access'
  private_constant :FULL_ACCESS_APP_NAME, :USER_ACCESS_APP_NAME

  module_function

  def database_connection_string(base_connection_string, user_id: nil)
    unless base_connection_string.is_a?(String) && !base_connection_string.empty?
      raise ArgumentError,
            'database_connection_string: base_connection_string (DATABASE_URL) is required'
    end

    uri = database_connection_uri(base_connection_string)
    parameters = database_query_parameters(uri)
    parameters.reject! { |name, _value| name == 'application_name' }
    parameters << ['application_name', database_application_name(user_id)]
    uri.query = URI.encode_www_form(parameters).gsub('+', '%20')
    uri.to_s
  end

  def database_connection_uri(value)
    uri = URI.parse(value)
    raise URI::InvalidURIError unless uri.absolute?

    uri
  rescue URI::InvalidURIError
    raise ArgumentError,
          'database_connection_string: base_connection_string is not a valid connection URL',
          cause: nil
  end
  private_class_method :database_connection_uri

  def database_query_parameters(uri)
    URI.decode_www_form(uri.query.to_s)
  rescue ArgumentError
    raise ArgumentError,
          'database_connection_string: base_connection_string is not a valid connection URL',
          cause: nil
  end
  private_class_method :database_query_parameters

  def database_application_name(user_id)
    value = user_id.nil? ? '' : user_id.to_s
    value.empty? ? FULL_ACCESS_APP_NAME : "#{USER_ACCESS_APP_NAME}:#{value}"
  end
  private_class_method :database_application_name
end
