# frozen_string_literal: true

require 'uri'

# Public namespace for Volcano SDK helpers.
module Volcano
  FULL_ACCESS_APP_NAME = 'volcano_full_access'
  USER_ACCESS_APP_NAME = 'volcano_user_access'
  INVALID_PERCENT_ENCODING = /%(?![0-9A-Fa-f]{2})/
  private_constant :FULL_ACCESS_APP_NAME, :USER_ACCESS_APP_NAME, :INVALID_PERCENT_ENCODING

  module_function

  def database_connection_string(base_connection_string, user_id: nil)
    unless base_connection_string.is_a?(String) && !base_connection_string.empty?
      raise ArgumentError,
            'database_connection_string: base_connection_string (DATABASE_URL) is required'
    end

    uri = database_connection_uri(base_connection_string)
    parameters = database_query_parameters(uri.query)
    parameters << "application_name=#{database_application_name_query_value(user_id)}"
    uri.query = parameters.join('&')
    uri.to_s
  end

  def database_connection_uri(value)
    uri = URI.parse(value)
    raise URI::InvalidURIError if !uri.absolute? || uri.fragment || INVALID_PERCENT_ENCODING.match?(value)

    uri
  rescue URI::InvalidURIError
    raise ArgumentError,
          'database_connection_string: base_connection_string is not a valid connection URL',
          cause: nil
  end
  private_class_method :database_connection_uri

  def database_query_parameters(query)
    return [] unless query

    query.split('&', -1).reject do |parameter|
      encoded_name = parameter.partition('=').first
      URI::DEFAULT_PARSER.unescape(encoded_name) == 'application_name'
    end
  end
  private_class_method :database_query_parameters

  def database_application_name_query_value(user_id)
    URI.encode_www_form_component(database_application_name(user_id)).gsub('+', '%20')
  end
  private_class_method :database_application_name_query_value

  def database_application_name(user_id)
    value = user_id.nil? ? '' : user_id.to_s
    value.empty? ? FULL_ACCESS_APP_NAME : "#{USER_ACCESS_APP_NAME}:#{value}"
  end
  private_class_method :database_application_name
end
