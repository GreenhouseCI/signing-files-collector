require 'base64'
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


class SigningFilesCollector

  def initialize
    @execute_dir = WORKING_DIR #Dir.pwd
    @log_file_path = File.join(@execute_dir, $LOG_FILE_NAME)
    @provisioning_profiles = Array.new
    @codesigning_identities = Array.new
  end

  def collect
    begin
      log_to_all "Preparing to collect iOS signing files"
      @provisioning_profiles = ProvisioningProfileCollector.new.collect
      @codesigning_identities = CodesigningIdentitiesCollector.new.collect
      log_to_all "Discarding unreferenced signing files"
      discard_unreferenced
      log_to_all "Preparing signing files for upload"
      @json_object = prepare_signing_files_for_upload
      puts @json_object
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
    end
  end

private

  def discard_unreferenced
    $file_logger.info "Matching provisioning profiles & codesigning identities"
    referenced_codesigning_ids = Set.new
    referenced_provisioning_profiles = Set.new
    @provisioning_profiles.each { |profile|
      profile_matched ||= false
      @codesigning_identities.each { |csid|
        if profile.serials.include? csid.serial
          profile_matched = true
          $file_logger.debug "Codesigning id #{csid} matches #{profile}"
          referenced_codesigning_ids.add csid
          referenced_provisioning_profiles.add profile
        end
      }
      if not profile_matched
        $file_logger.debug "Provisioning profile #{profile} did not match any codesigning identity"
      end
    }
    @codesigning_identities.each { |csid|
      if not referenced_codesigning_ids.include? csid
        $file_logger.debug "Codesigning identity #{csid} did not match any provisioning profile"
      end
    }
    @provisioning_profiles = referenced_provisioning_profiles.to_a
    @codesigning_identities = referenced_codesigning_ids.to_a
  end

  def prepare_signing_files_for_upload
    $file_logger.info "Preparing upload object"
    begin
      @upload_object = Hash.new
      puts "*" * 84
      puts "Please allow script to access your keychain when prompted, once per matched identity"
      puts "*" * 84
      export_csids_to_hash
      puts "*" * 84
      puts "Thank you!"
      puts "*" * 84

      export_profiles_to_hash

      signing_files = @upload_object[:certificates].map { |cert| cert[:subject] }
      signing_files += @upload_object[:provisioning_profiles].map { |profile| profile[:name]}
      $file_logger.debug "Preparing the following signing files:"
      $file_logger.debug signing_files

      if not signing_files.any?
        $file_logger.error "No signing files found in the package dir, aborting"
        raise CollectorError
      end
      @upload_object.to_json

    rescue StandardError => err
      $file_logger.error "Failed to prepare upload object: #{err.message}"
      raise CollectorError
    end
  end

  def export_csids_to_hash
    certificates = Array.new
    @codesigning_identities.each { |csid|
      certificates << csid.export_to_hash
    }
    @upload_object[:certificates] = certificates
  end

  def export_profiles_to_hash
    profiles = Array.new
    @provisioning_profiles.each { |profile|
      profiles << profile.export_to_hash
    }
    @upload_object[:provisioning_profiles] = profiles
  end

  def upload_log
    $file_logger.debug "Sending logs to #{LOG_URL}"
    begin
      url = URI(LOG_URL)
      http = Net::HTTP.new(url.host, url.port)

      request = Net::HTTP::Post.new(url)
      request["content-type"] = 'multipart/form-data; boundary=----7MA4YWxkTrZu0gW'
      request["Authorization"] = UPLOAD_KEY
      request.body = "------7MA4YWxkTrZu0gW\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{@log_file_path}\"\r\nContent-Type: false\r\n\r\n\r\n------7MA4YWxkTrZu0gW--"
      response = http.request(request)
      puts response.read_body
    rescue StandardError => err
      $file_logger.error "Failed to upload signing files to server: #{err.message}"
      log_to_all "You probably did not run Priit's server", :error
    end
  end

  def upload_signing_files
    $file_logger.debug "Sending signing files to #{SIGNING_FILES_UPLOAD_URL}"
    begin
      url = URI(SIGNING_FILES_UPLOAD_URL)
      http = Net::HTTP.new(url.host, url.port)

      request = Net::HTTP::Post.new(url)
      request["content-type"] = 'text/json'
      request["Authorization"] = UPLOAD_KEY
      request.body = @json_object

      response = http.request(request)
      puts response.read_body
    rescue StandardError => err
      $file_logger.error "Failed to upload signing files to server: #{err.message}"
      log_to_all "You probably did not run Priit's server", :error
      raise CollectorError
    end

  end

end

def log_to_all(message, method = :info)
  $file_logger.send method, message
  $stdout_logger.send method, message
end

WORKING_DIR = ARGV[0]
SIGNING_FILES_UPLOAD_URL = ARGV[1]
LOG_URL = ARGV[2]
UPLOAD_KEY = ARGV[3]

$LOG_FILE_NAME = WORKING_DIR << "/signing_files_collector.log"

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

SigningFilesCollector.new.collect
