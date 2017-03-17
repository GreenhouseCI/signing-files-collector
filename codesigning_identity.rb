class CodesigningIdentity
  IPHONE_DEVELOPER_DESCRIPTOR = "iPhone Developer"
  IPHONE_DISTRIBUTION_DESCRIPTOR = "iPhone Distribution"
  ASN1_STRFLGS_ESC_MSB = 4

  def initialize(data)
    @data = data
    @cert = @data.certificate.x509
    @ref = @cert.subject.to_s
    @serial = nil
    @common_name = nil
    @team_identifier = nil
    @team_name = nil
    parse_subject
  end

  def self.openssl_to_utf8(value)
    value = value.to_s(OpenSSL::X509::Name::ONELINE & ~ASN1_STRFLGS_ESC_MSB)
    value = value.force_encoding(Encoding::UTF_8)
  end

  def parse_subject
    subj = self.class.openssl_to_utf8(@cert.subject)
    subj_parts = subj.split(/(?:,\s)?([A-Z]+)\s+=\s+/)[1..-1] || []
    subj_parts = subj_parts.map { |part| part.gsub(/\A["']|["']\Z/, '') }
    subj_hash = Hash[*subj_parts]

    @common_name = subj_hash['CN']
    @team_identifier = subj_hash['OU']
    @team_name = subj_hash['O']
  end

  def useful?
    is_iphone_type = iphone_type?
    is_not_expired = !is_expired?
    log_to_all "#{@ref} is#{is_iphone_type ? '' : ' not'} suitable for iOS codesigning"
    log_to_all "#{@ref} is#{is_not_expired ? ' not' : ''} expired"
    is_iphone_type && !is_expired?
  end

  def iphone_type?
    $file_logger.debug "Processing certificate with subject #{@ref}"
    is_iphone_developer = !(@ref =~ /#{IPHONE_DEVELOPER_DESCRIPTOR}/).nil?
    is_iphone_distribution = !(@ref =~ /#{IPHONE_DISTRIBUTION_DESCRIPTOR}/).nil?
    $file_logger.debug "Developer - #{is_iphone_developer}; Distribution - #{is_iphone_distribution}"
    is_iphone_developer || is_iphone_distribution
  end

  def is_expired?
    (Time.now <= @cert.not_before) || (Time.now > @cert.not_after)
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
        :common_name => @common_name,
        :team_identifier => @team_identifier,
        :team_name => @team_name,
        :not_before => @cert.not_before.strftime('%Y-%m-%d %H:%M:%S'),
        :not_after => @cert.not_after.strftime('%Y-%m-%d %H:%M:%S'),
        :file => base64_encoded
    }
  end

  def to_s
    @ref
  end

  def ==(other)
    self.serial == other.serial && self.class == other.class
  end

  private

  attr_accessor :data, :cert, :ref
  attr_writer :serial
end
