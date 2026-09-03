# frozen_string_literal: true

require 'uri'

# Public namespace for Volcano SDK helpers.
module Volcano
  FULL_ACCESS_APP_NAME = 'volcano_full_access'
  USER_ACCESS_APP_NAME = 'volcano_user_access'
  CONNECTION_URI_PREFIX = %r{\A[a-z][a-z0-9+.-]*://}i
  INVALID_PERCENT_ENCODING = /%(?![0-9A-Fa-f]{2})/
  private_constant :FULL_ACCESS_APP_NAME, :USER_ACCESS_APP_NAME,
                   :CONNECTION_URI_PREFIX, :INVALID_PERCENT_ENCODING

  module_function

  def database_connection_string(base_connection_string, user_id: nil)
    unless base_connection_string.is_a?(String) && !base_connection_string.empty?
      raise ArgumentError,
            'database_connection_string: base_connection_string (DATABASE_URL) is required'
    end

    target, query = database_connection_parts(base_connection_string)
    parameters = database_query_parameters(query)
    parameters << "application_name=#{database_application_name_query_value(user_id)}"
    "#{target}?#{parameters.join('&')}"
  end

  def database_connection_parts(value)
    prefix_end = database_connection_prefix_end(value)
    query_start = database_query_start(value, prefix_end)
    return [value, nil] unless query_start

    [value[0...query_start], value[(query_start + 1)..]]
  end
  private_class_method :database_connection_parts

  def database_connection_prefix_end(value)
    prefix = CONNECTION_URI_PREFIX.match(value)
    return prefix.end(0) if prefix && !INVALID_PERCENT_ENCODING.match?(value)

    raise ArgumentError,
          'database_connection_string: base_connection_string is not a valid connection URL',
          cause: nil
  end
  private_class_method :database_connection_prefix_end

  def database_query_start(value, prefix_end)
    userinfo_end = database_userinfo_end(value, prefix_end)
    value.index('?', userinfo_end ? userinfo_end + 1 : prefix_end)
  end
  private_class_method :database_query_start

  def database_userinfo_end(value, prefix_end)
    authority_end = value.index('/', prefix_end)
    userinfo_end = value.index('@', prefix_end)
    return unless userinfo_end
    return userinfo_end unless authority_end

    userinfo_end if userinfo_end < authority_end
  end
  private_class_method :database_userinfo_end

  def database_query_parameters(query)
    return [] unless query

    parameters = query.split('&', -1).reject do |parameter|
      encoded_name = parameter.partition('=').first
      URI::DEFAULT_PARSER.unescape(encoded_name) == 'application_name'
    end
    parameters.pop while parameters.last == ''
    parameters
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
