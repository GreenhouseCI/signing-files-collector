class ProvisioningProfileCollector
  @@PROVISIONING_PROFILE_DIR = "#{Dir.home}/Library/MobileDevice/Provisioning Profiles"
  @@PROVISIONING_PROFILE_PATTERN = "*.mobileprovision"

  def initialize; end

  def collect
    profile_path = find_provisioning_profiles
  end

  private

  def find_provisioning_profiles
    $file_logger.info "Searching for provisioning profiles in #{@@PROVISIONING_PROFILE_DIR}"
    matches = Array.new
    begin
      Dir.glob["#{PROVISIONING_PROFILE_DIR}/**/*.#{@@PROVISIONING_PROFILE_PATTERN}"].each { |filename|
        matches.push filename
      }
    rescue StandardError => err
      $file_logger.error "Failed to find provisioning profiles: #{err.message}"
      raise CollectorError
    end
    if not matches.any?
      $file_logger.error "No provisioning profiles could be found on this machine. Aborting"
      raise CollectorError
    end
    $file_logger.info "Found #{matches.length} provisioning profiles"
    matches
  end
end