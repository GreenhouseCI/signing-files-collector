require 'date'
require 'time'

require './utils.rb'

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
    profile_data = read
    profile_expires_on = profile_data["ExpirationDate"]
    $file_logger.debug "Profile expires on #{profile_expires_on.strftime("%Y/%m/%d")}"
    if profile_expires_on.nil? and not profile_expires_on.instance_of?(DateTime)
      $file_logger.error "Failed to parse expiry date from provisioning profile #{@file_path}"
      raise CollectorError
    end

    expired = profile_expires_on <= DateTime.now
    message = expired ? "expired" : "valid"
    $file_logger.info "Provisioning profile #{@file_path} is #{message}"
    expired
  end

  def serials
    return @serials if @serials.any?

    profile_data = read
    certificates = profile_data["DeveloperCertificates"]
    if certificates.nil? and not certificates.instance_of?(Array)
      $file_logger.error "Failed to parse certificates from provisioning profile #{@file_path}"
      raise CollectorError
    end

    serials = Array.new

    certificates.each { |cert|
      certificate = OpenSSL::X509::Certificate.new(cert.read)
      serials.push certificate.serial
    }
    @serials = serials
    serials
  end

  def create_symlink temp_dir
    begin
      symlink_path = File.join temp_dir, File.basename(@file_path)
      $file_logger.debug "Create symlink #{symlink_path} for provisioning profile #{@file_path}"
      FileUtils.symlink @file_path, symlink_path
    rescue StandardError => err
      $file_logger.error "Failed to prepare provisioning profile for packaging: #{err.message}"
      raise CollectorError
    end
  end

end