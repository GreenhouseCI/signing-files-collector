class CodesigningIdentity
  IPHONE_DEVELOPER_DESCRIPTOR = "iPhone Developer"
  IPHONE_DISTRIBUTION_DESCRIPTOR = "iPhone Distribution"

  def initialize(data)
    self.data = data
    self.cert = data.certificate.x509
    self.ref = cert.subject.to_s
    @serial = nil
  end

  # def useful?
  #   is_iphone_type = iphone_type?
  #   is_not_expired = not_expired?
  #   $stdout_logger.info "#{ref} is #{is_iphone_type ? "" : " not "} suitable for iOS codesigning"
  #   $stdout_logger.info "#{ref} is #{is_not_expired ? "" : " not "} expired"
  #   return iphone_type? && not_expired?
  # end
  #
  # def iphone_type?
  #   $file_logger.debug "Processing certificate with subject #{ref}"
  #   is_iphone_developer = !!(ref =~ /#{IPHONE_DEVELOPER_DESCRIPTOR}/)
  #   is_iphone_distribution = !!(ref =~ /#{IPHONE_DISTRIBUTION_DESCRIPTOR}/)
  #   $file_logger.debug "Developer - #{is_iphone_developer}; Distribution - #{is_iphone_distribution}"
  #   is_iphone_developer || is_iphone_distribution
  # end

  def not_expired?
    return (Time.now >= cert.not_before) && (Time.now < cert.not_after)
  end

  def serial
    return @serial unless @serial.nil?

    @serial = cert.serial
  end

  def export_to_file(dir, file_index)
    exported = data.pkcs12
    file_path = File.join dir, "cert#{file_index + 1}.p12"
    File.open(file_path, "w") { |file| file.write exported.to_der }
    $file_logger.debug "#{file_path} written"
    file_path
  end

  private

  attr_accessor :data, :cert, :ref
  attr_writer :serial
end