# frozen_string_literal: true

require 'volcano'

connection = Volcano.database_connection_string('postgresql://db.example.com/app', user_id: 'user-1')
raise 'Wrong database user' unless connection.include?('volcano_user_access%3Auser-1')
