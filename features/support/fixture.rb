# frozen_string_literal: true

require 'json'
require 'pathname'

module VolcanoContract
  def self.load_fixture(value)
    path = Pathname(value)
    validate_fixture_path(path)
    parse_fixture(path)
  end

  def self.validate_fixture_path(path)
    raise ArgumentError, 'VOLCANO_SDK_CONTRACT_FIXTURE must be an absolute path' unless path.absolute?

    mode = path.stat.mode & 0o777
    raise SecurityError, 'VOLCANO_SDK_CONTRACT_FIXTURE must have mode 0600' unless mode == 0o600
  end

  def self.parse_fixture(path)
    fixture = JSON.parse(path.read)
    raise TypeError, 'VOLCANO_SDK_CONTRACT_FIXTURE must contain a JSON object' unless fixture.is_a?(Hash)

    fixture
  end

  private_class_method :parse_fixture, :validate_fixture_path
end
