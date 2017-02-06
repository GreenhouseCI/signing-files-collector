class CodesigningIdentity
  IPHONE_DEVELOPER_DESCRIPTOR = "iPhone Developer"
  IPHONE_DISTRIBUTION_DESCRIPTOR = "iPhone Distribution"

  def initialize(data)
    @data = data
    @cert = @data.certificate.x509
    @ref = @cert.subject.to_s
    @serial = nil
  end

  def useful?
    is_iphone_type = iphone_type?
    is_not_expired = !is_expired?
    log_to_all "#{@ref} is#{is_iphone_type ? "" : " not"} suitable for iOS codesigning"
    log_to_all "#{@ref} is#{is_not_expired ? " not" : ""} expired"
    return iphone_type? && !is_expired?
  end

  def iphone_type?
    $file_logger.debug "Processing certificate with subject #{@ref}"
    is_iphone_developer = !!(@ref =~ /#{IPHONE_DEVELOPER_DESCRIPTOR}/)
    is_iphone_distribution = !!(@ref =~ /#{IPHONE_DISTRIBUTION_DESCRIPTOR}/)
    $file_logger.debug "Developer - #{is_iphone_developer}; Distribution - #{is_iphone_distribution}"
    is_iphone_developer || is_iphone_distribution
  end

  def is_expired?
    return (Time.now <= @cert.not_before) || (Time.now > @cert.not_after)
  end

  def serial
    return @serial unless @serial.nil?

    @serial = @cert.serial
  end

  def export_to_hash
    base64_encoded = Base64.encode64(@data.pkcs12.to_der)
    {
        :serial => @cert.serial.to_s,
        :subject => @ref,
        :not_before => @cert.not_before.to_s,
        :not_after => @cert.not_after.to_s,
        :file => base64_encoded
    }
  end

  def to_s
    @ref
  end

  private

  attr_accessor :data, :cert, :ref
  attr_writer :serial
end
