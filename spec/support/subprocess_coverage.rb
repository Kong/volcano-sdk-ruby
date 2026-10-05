# frozen_string_literal: true

require 'simplecov'

SimpleCov.start do
  command_name "subprocess-#{Process.pid}"
  finalize_merge false
end
