# frozen_string_literal: true

require 'timeout'

module Quality
  # Bound each isolated test process and terminate its entire process group on timeout.
  class DefectProcess
    def initialize(timeout: 60)
      @timeout = timeout
    end

    # Run an argv array, optionally preceded by an environment hash. The program is always executed
    # directly: the [program, argv0] form stops Ruby from handing a lone command string to /bin/sh.
    def run(command, directory:, log:)
      environment, program, *arguments = command.first.is_a?(Hash) ? command : [{}, *command]
      pid = Process.spawn(environment, [program, program], *arguments,
                          chdir: directory, out: log, err: %i[child out], pgroup: true)
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
