# frozen_string_literal: true

require_relative 'volcano/version'
require_relative 'volcano/models'
require_relative 'volcano/errors'
require_relative 'volcano/redaction'
require_relative 'volcano/transport'
require_relative 'volcano/generated_transport'
require_relative 'volcano/auth'
require_relative 'volcano/database'
require_relative 'volcano/storage'
require_relative 'volcano/locks'
require_relative 'volcano/realtime/protocol'
require_relative 'volcano/realtime'
require_relative 'volcano/client'

# Public namespace for the Volcano Ruby SDK.
module Volcano
  private_constant :GeneratedTransport, :Redaction

  Realtime.private_constant :Protocol, :ProtocolDispatch, :ProtocolState
end
