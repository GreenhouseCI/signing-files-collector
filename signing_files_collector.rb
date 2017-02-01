require "fileutils"
require 'json'
require "logger"
require "net/http"
require "open3"
require "set"
require "uri"

require "./codesigning_identities_collector.rb"
require "./collector_errors.rb"
require "./provisioning_profile_collector.rb"

$LOG_FILE_NAME = "signing_files_collector.log"

class SigningFilesCollector
  @@PACKAGE_NAME = "signing_files_package.zip"

  def initialize
    @execute_dir = Dir.pwd
    @log_file_path = File.join @execute_dir, $LOG_FILE_NAME
    @package_dir = generate_package_dir_name
    @provisioning_profiles = Array.new
    @codesigning_identities = Array.new
  end

  def collect
    begin
      log_to_all "Preparing to collect iOS signing files"
      create_temp_dir
      @provisioning_profiles = ProvisioningProfileCollector.new().collect
      @codesigning_identities = CodesigningIdentitiesCollector.new().collect
      log_to_all "Discarding unreferenced signing files"
      discard_unreferenced
      # log_to_all "Creating upload package"
      # create_upload_package
      # log_to_all "Adding log file to upload package"
      # add_log_to_upload_package
      log_to_all "iOS signing file collection complete"
      log_to_all "Starting to upload signing files to GH"
      upload_signing_files
      $stdout_logger.info "Please return to Greenhouse CI UI to continue"

    rescue CollectorError
      log_to_all "Signing file collection failed. Aborting"
      if File.exist?(@log_file_path)
        $stdout_logger.info "You can find the debug log at #{@log_file_path}"
        $stdout_logger.info "Please attach it when opening a support ticket"
      end
    ensure
      log_to_all "Upload logs to GH"
      upload_log
      log_to_all "Deleting all temporal folders and files"
      remove_package_dir
    end
  end

private

  def generate_package_dir_name
    timestamp = Time.now.to_i
    dir_name = "/tmp/gh_signing_files_#{timestamp}"
    $file_logger.info "Temporal package directory has been generated at #{dir_name}"
    dir_name
  end

  def create_temp_dir
    $file_logger.debug "Creating temp directory #{@package_dir}"
    begin
      Dir.mkdir(@package_dir) if not File.exists?(@package_dir)
    rescue SystemCallError => ose
      $file_logger.error "Failed to prepare environment: #{ose.message}"
      raise CollectorError
    end
  end

  def discard_unreferenced
    $file_logger.info "Matching provisioning profiles & codesigning identities"
    referenced_codesigning_ids = Set.new
    referenced_provisioning_profiles = Set.new
    @provisioning_profiles.each { |profile|
      @codesigning_identities.each { |csid|
        if profile.serials.include? csid.serial
          $file_logger.debug "Codesigning id #{csid} matches #{profile}"
          referenced_codesigning_ids.add csid
          referenced_provisioning_profiles.add profile
        end
      }
    }
    @provisioning_profiles = referenced_provisioning_profiles.to_a
    @codesigning_identities = referenced_codesigning_ids.to_a
  end

  def create_upload_package
    $file_logger.info "Preparing upload package"
    begin
      create_provisioning_profile_symlink
      puts "*" * 84
      puts "Please allow script to access your keychain when prompted, once per matched identity"
      puts "*" * 84
      export_csids_to_file
      puts "*" * 84
      puts "Thank you!"
      puts "*" * 84
      Dir.chdir @package_dir
      signing_files = Dir.glob "*.mobileprovision"
      signing_files.concat Dir.glob("*.p12")
      $file_logger.debug "Packaging the following signing files:"
      $file_logger.debug signing_files

      if not signing_files.any?
        $file_logger.error "No siginig files found in the package dir, aborting"
        raise CollectorError
      end

      cmd = "zip -r #{@@PACKAGE_NAME} ./*"
      begin
        Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
          exit_status = wait_thr.value
          if not exit_status.success?
            $file_logger.error "Error while creating upload package: #{stderr.read}"
            raise CollectorError
          end
        end
      rescue StandardError => err
        $file_logger.error "Faild to run popen command while preparing upload package: #{err.message}"
        raise CollectorError
      end

    rescue StandardError => err
      $file_logger.error "Failed to prepare upload package: #{err.message}"
      raise CollectorError
    end
  end

  def create_provisioning_profile_symlink
    @provisioning_profiles.each { |profile|
      profile.create_symlink @package_dir
    }
  end

  def export_csids_to_file
    @codesigning_identities.each_with_index { |csid, index|
      csid.export_to_file @package_dir, index
    }
  end

  def add_log_to_upload_package
    begin
      $file_logger.debug "Adding our log #{@log_file_path} to the upload package"
      Dir.chdir @package_dir
      cmd = "zip -j #{@@PACKAGE_NAME} #{@log_file_path}"
      begin
        Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
          exit_status = wait_thr.value
          if not exit_status.success?
            $file_logger.error "Error while adding log file to upload package: #{stderr.read}"
            raise CollectorError
          end
        end
      rescue StandardError => err
        $file_logger.error "Faild to run popen to add log file to package: #{err.message}"
        raise CollectorError
      end

    rescue StandardError => err
      $file_logger.error "Failed to add log to upload package: #{err.message}"
      raise CollectorError
    end
  end

  def upload_log
    puts PACKAGE_URL
    url = URI(LOG_URL)
    http = Net::HTTP.new(url.host, url.port)

    request = Net::HTTP::Post.new(url)
    request["content-type"] = 'multipart/form-data; boundary=----7MA4YWxkTrZu0gW'
    request.body = "------7MA4YWxkTrZu0gW\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{@log_file_path}\"\r\nContent-Type: false\r\n\r\n\r\n------7MA4YWxkTrZu0gW--"

    response = http.request(request)
    puts response.read_body
  end

  def upload_signing_files
    puts UPLOAD_KEY
    puts PACKAGE_URL
  end

  def remove_package_dir
    $file_logger.info "Cleaning up"
    $file_logger.info "Removing package directory #{@package_dir}"
    begin
      FileUtils.rmtree @package_dir
      $file_logger.debug "Package dir removed successfully"
    rescue SystemCallError => ose
      $file_logger.error "Failed to clean up package dir: #{ose.message}"
      raise CollectorError
    end
  end

  def remove_log
    $file_logger.info "Removing log file #{@log_file_path}"
    begin
      File.delete @log_file_path
    rescue SystemCallError => ose
      $file_logger.error "Failed to clean up log file: #{ose.message}"
      raise CollectorError
    end
  end
end

def log_to_all(message, method = :info)
  $file_logger.send method, message
  $stdout_logger.send method, message
end

PACKAGE_URL = ARGV[0]
LOG_URL = ARGV[1]
UPLOAD_KEY = ARGV[2]

File.delete($LOG_FILE_NAME) if File.exist?($LOG_FILE_NAME)

log_file = File.open $LOG_FILE_NAME, "a"
$file_logger = Logger.new log_file
$file_logger.level = Logger::DEBUG
$file_logger.formatter = proc { |severity, datetime, progname, msg|
  date_format = datetime.strftime("%Y-%m-%d %H:%M:%S")
  "#{date_format} #{severity} #{caller[4]} #{msg}\n"
}
$stdout_logger = Logger.new STDOUT
$stdout_logger.level = Logger::INFO
$stdout_logger.formatter = proc { |severity, datetime, progname, msg|
  date_format = datetime.strftime("%Y-%m-%d %H:%M:%S")
  "#{date_format} #{severity} #{msg}\n"
}

SigningFilesCollector.new().collect