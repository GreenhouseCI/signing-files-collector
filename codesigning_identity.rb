class CodesigningIdentity
  IPHONE_DEVELOPER_DESCRIPTOR = "iPhone Developer"
  IPHONE_DISTRIBUTION_DESCRIPTOR = "iPhone Distribution"

  def initialize(data)
    @data = data
    @cert = @data.certificate.x509
    @serial = nil
  end

  def not_expired?
    return (Time.now >= @cert.not_before) && (Time.now < @cert.not_after)
  end

  def serial
    return @serial unless @serial.nil?

    @serial = @cert.serial
  end

  def export_to_file(dir, file_index)
    exported = data.pkcs12
    file_path = File.join dir, "cert#{file_index + 1}.p12"
    File.open(file_path, "w") { |file| file.write exported.to_der }
    $file_logger.debug "#{file_path} written"
    file_path
  end

  private

  attr_accessor :data, :cert
  attr_writer :serial
end