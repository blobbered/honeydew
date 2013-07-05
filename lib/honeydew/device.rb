require 'net/http'

require 'honeydew/device_matchers'
require 'honeydew/device_actions'

module Honeydew
  class Device
    include Honeydew::DeviceActions
    include Honeydew::DeviceMatchers

    ServerTimeoutError = Class.new(Timeout::Error)
    FinderTimeout = Class.new(Timeout::Error)

    attr_reader :serial, :port

    def initialize(serial)
      @serial = serial

      unless Honeydew.attached_devices.include?(@serial)
        raise ArgumentError, "No device with serial #{@serial} attached"
      end

      @port = Honeydew.config.obtain_new_port
      start_honeydew_server
    end

    def using_timeout timeout
      old_timeout = Honeydew.config.timeout
      Honeydew.config.timeout = timeout
      yield
    ensure
      Honeydew.config.timeout = old_timeout
    end

    private

    def perform_assertion action, arguments = {}, options = {}
      ensure_device_ready

      log "performing assertion #{action} with arguments #{arguments}"
      Timeout.timeout Honeydew.config.timeout.to_i, FinderTimeout do
        sleep(0.3) until send_command action, arguments
      end
    rescue FinderTimeout
      false
    end

    def perform_action action, arguments = {}, options = {}
      ensure_device_ready

      log "performing action #{action} with arguments #{arguments}"
      send_command action, arguments
    end

    def send_command action, arguments
      endpoint = device_endpoint('/command')

      timeout_server_operation do
        Net::HTTP.post_form endpoint, {action: action, arguments: arguments.to_json.to_s}
      end
    end

    def log message
      return unless Honeydew.config.debug
      STDERR.puts "Device #{serial}: #{message}"
    end

    def ensure_device_ready
      @device_ready ||= begin
        wait_for_honeydew_server
        true
      end
    end

    def timeout_server_operation &block
      Timeout.timeout(Honeydew.config.server_timeout.to_i, ServerTimeoutError, &block)
    end

    def wait_for_honeydew_server
      log 'waiting for honeydew-server to respond'
      timeout_server_operation do
        sleep 0.1 until honeydew_server_alive?
      end
      log 'honeydew-server is alive and awaiting commands'

    rescue ServerTimeoutError
      raise 'timed out waiting for honeydew-server to respond'
    end

    def honeydew_server_alive?
      Net::HTTP.get_response(device_endpoint('/status')).code.to_i == 200
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::ENETRESET, EOFError
    end
  end
end
