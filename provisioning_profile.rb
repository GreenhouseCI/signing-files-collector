load_or_install_gem("plist")

class ProvisioningProfile

  def initialize(path)
    @file_path = path
    @parsed_data = Hash.new
    @serials = Array.new
  end

  def read
    if @parsed_data.any?
      return @parsed_data
    end
    cmd = ["security", "cms", "-D", "-i", @file_path]
    begin
      Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
        exit_status = wait_thr.value
        raise CollectorError(stderr.read) unless exit_status.success?
        @parsed_data = Plist::parse_xml(stdout.read.chomp)
        return @parsed_data
      end
    rescue StandardError => err
      $file_logger.error "Failed to read provisioning profile #{@file_path}: #{err.message}"
      raise CollectorError err.message
    end
  end

  def is_expired

  end
end