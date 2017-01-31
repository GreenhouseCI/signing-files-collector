require 'keychain'

require './codesigning_identity.rb'

class CodesigningIdentitiesCollector

  def collect
    $file_logger.info "Collecting codesigning identities"
    unlock_default_keychain
    signing_identities = read_ids_from_keychain
    signing_identities
  end

  private

  attr_accessor :keychain

  def unlock_default_keychain
    @keychain = Keychain.default
    return unless @keychain.locked?

    puts "*" * 57
    puts "Please enter the password to unlock your default keychain"
    puts "*" * 57
    @keychain.unlock!
  end

  def read_ids_from_keychain
    scope = Keychain::Scope.new Sec::Classes::IDENTITY, @keychain
    $file_logger.info "Found #{scope.all.size} codesigning identities in the default keychain"
    if scope.all.empty?
      raise "No codesigning identities found in the default keychain. Aborting"
    end
    scope.all.map { |csid| CodesigningIdentity.new(csid) }
  end

  # def export_signing_identities_to_files_in
  #   $file_logger.info "Exporting codesigning identities from keychain"
  #   puts "*" * 84
  #   puts "Please allow the script to access your keychain when prompted, once for each identity"
  #   puts "*" * 84
  #   signing_identities.each_with_index do |csid, index|
  #     next unless csid.useful?
  #
  #     csid.export_to_file @temp_dir, index
  #   end
  # end
end