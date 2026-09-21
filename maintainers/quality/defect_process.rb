# frozen_string_literal: true

require 'timeout'

module Quality
  # Bound each isolated test process and terminate its entire process group on timeout.
  class DefectProcess
    def initialize(timeout: 60)
      @timeout = timeout
    end

    def run(command, directory:, log:)
      pid = Process.spawn(*command, chdir: directory, out: log, err: %i[child out], pgroup: true)
      Timeout.timeout(@timeout) { Process.wait2(pid).last.exitstatus }
    rescue Timeout::Error
      terminate(pid)
      :timeout
    end

    private

    def terminate(pid)
      Process.kill('KILL', -pid)
    rescue Errno::ESRCH
      nil
    ensure
      reap(pid)
    end

    def reap(pid)
      Process.wait(pid)
    rescue Errno::ECHILD
      nil
    end
  end
end
