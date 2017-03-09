require 'date'
require 'time'

require 'plist'

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
        if not exit_status.success?
          $file_logger.error "Error while reading provisioning profile: #{stderr.read}"
          raise CollectorError
        end
        @parsed_data = Plist::parse_xml(stdout.read.chomp)
        return @parsed_data
      end
    rescue StandardError => err
      $file_logger.error "Failed to read provisioning profile #{@file_path}: #{err.message}"
      raise CollectorError
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

  def has_beta_entitlements
    entitlements = @parsed_data["Entitlements"] || {}
    entitlements["beta-reports-active"] || false
  end

  def application_identifier
    entitlements = @parsed_data["Entitlements"] || {}
    entitlements["application-identifier"] || ""
  end

  def export_to_hash
    base64_encoded = Base64.strict_encode64(open(@file_path).read)
    {
      :name => @parsed_data["Name"],
      :uuid => @parsed_data["UUID"],
      :serials => self.serials.map {|s| s.to_s},
      :not_before => @parsed_data["CreationDate"].strftime('%Y-%m-%d %H:%M:%S'),
      :not_after => @parsed_data["ExpirationDate"].strftime('%Y-%m-%d %H:%M:%S'),
      :team_identifier => @parsed_data["TeamIdentifier"][0] || "",
      :team_name => @parsed_data["TeamName"] || "",
      :has_beta_entitlements => has_beta_entitlements,
      :provisioned_devices => @parsed_data["ProvisionedDevices"] || [],
      :provisions_all_devices => @parsed_data["ProvisionsAllDevices"] || false,
      :application_identifier => application_identifier,
      :is_wildcard_identifier => application_identifier.end_with?("*"),
      :file => base64_encoded
    }
  end

  def to_s
    @parsed_data["Name"]
  end

  def ==(other)
    self.serials == other.serials && self.class == other.class
  end

end
