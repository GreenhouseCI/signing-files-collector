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
    signing_identities = scope.all.map { |csid| CodesigningIdentity.new(csid) }
    useful_signing_identities = Array.new
    signing_identities.each { |csid|
      if csid.useful?
        useful_signing_identities << csid
      else
        $file_logger.debug "Codesigning identity #{csid} is ignored because it is either not suitable for iOS codesigning or expired"
      end
    }
    useful_signing_identities
  end

end