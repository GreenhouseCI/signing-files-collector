# frozen_string_literal: true

require "keychain"
require "logger"

class CodesigningIdentitiesCollector
  def collect(temp_dir)
    log_to_all "Collecting codesigning identities"
    unlock_default_keychain
    read_ids_from_keychain
    export_signing_identities_to_files_in temp_dir
  rescue Keychain::UserCancelledError
    log_to_all "User did not grant keychain access", :error
    exit 1
  rescue => ex
    msg = "Error while exporting codesigning identities: #{ex.message}"
    log_to_all msg, :error
    exit 1
  end

  private

  attr_accessor :signing_identities, :keychain

  def log_to_all(message, method = :info)
    $file_logger.send method, message
    $stdout_logger.send method, message
  end

  def unlock_default_keychain
    self.keychain = Keychain.default
    return unless keychain.locked?

    puts "*" * 57
    puts "Please enter the password to unlock your default keychain"
    puts "*" * 57
    keychain.unlock!
  end

  def read_ids_from_keychain
    scope = Keychain::Scope.new Sec::Classes::IDENTITY, keychain
    log_to_all "Found #{scope.all.size} codesigning identities in the default keychain"
    if scope.all.empty?
      raise "No codesigning identities found in the default keychain. Aborting"
    end
    self.signing_identities = scope.all.map { |csid| CodesigningIdentity.new(csid) }
  end

  def export_signing_identities_to_files_in(temp_dir)
    log_to_all "Exporting codesigning identities from keychain"
    puts "*" * 84
    puts "Please allow the script to access your keychain when prompted, once for each identity"
    puts "*" * 84
    signing_identities.each_with_index do |csid, index|
      next unless csid.useful?

      csid.export_to_file temp_dir, index
    end
  end
end


class CodesigningIdentity
  IPHONE_DEVELOPER_DESCRIPTOR = "iPhone Developer"
  IPHONE_DISTRIBUTION_DESCRIPTOR = "iPhone Distribution"

  def initialize(data)
    self.data = data
    self.cert = data.certificate.x509
    self.ref = cert.subject.to_s
  end

  def useful?
    is_iphone_type = iphone_type?
    is_not_expired = not_expired?
    $stdout_logger.info "#{ref} is #{is_iphone_type ? "" : " not "} suitable for iOS codesigning"
    $stdout_logger.info "#{ref} is #{is_not_expired ? "" : " not "} expired"
    return iphone_type? && not_expired?
  end

  def iphone_type?
    $file_logger.debug "Processing certificate with subject #{ref}"
    is_iphone_developer = !!(ref =~ /#{IPHONE_DEVELOPER_DESCRIPTOR}/)
    is_iphone_distribution = !!(ref =~ /#{IPHONE_DISTRIBUTION_DESCRIPTOR}/)
    $file_logger.debug "Developer - #{is_iphone_developer}; Distribution - #{is_iphone_distribution}"
    is_iphone_developer || is_iphone_distribution
  end

  def not_expired?
    return (Time.now >= cert.not_before) && (Time.now < cert.not_after)
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
end


# log_file_path = ARGV[0]
# temp_dir = ARGV[1]
#
# log_file = File.open log_file_path, "a"
# $file_logger = Logger.new log_file
# $file_logger.level = Logger::DEBUG
# $file_logger.formatter = proc { |severity, datetime, progname, msg| "#{severity} #{caller[4]} #{msg}\n" }
# $stdout_logger = Logger.new STDOUT
# $stdout_logger.level = Logger::INFO
#
# CodesigningIdentitiesCollector.new().collect temp_dir
