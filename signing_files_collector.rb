require "base64"
require "fileutils"
require "json"
require "logger"
require "net/http"
require "open3"
require "set"
require "tempfile"
require "uri"
require "zlib"

require "./codesigning_identities_collector.rb"
require "./collector_errors.rb"
require "./provisioning_profile_collector.rb"


class SigningFilesCollector

  def initialize(log_file_path)
    @signing_files_collection_id = nil
    @log_file_path = log_file_path
    @provisioning_profiles = Array.new
    @codesigning_identities = Array.new
  end

  def collect
    start_collection
    begin
      log_to_all "Preparing to collect iOS signing files"
      @provisioning_profiles = ProvisioningProfileCollector.new.collect
      @codesigning_identities = CodesigningIdentitiesCollector.new.collect
      log_to_all "Discarding unreferenced signing files"
      discard_unreferenced
      log_to_all "Preparing signing files for upload"
      @json_object = prepare_signing_files_for_upload
      log_to_all "iOS signing file collection complete"
      log_to_all "Starting to upload signing files to Nevercode"
      upload_signing_files
      $stdout_logger.info "Please return to Nevercode UI to continue"
    rescue Exception => e
      log_to_all "Signing file collection failed. Aborting"
      $file_logger.error e.message
      $file_logger.error e.backtrace
      if File.exist?(@log_file_path)
        $stdout_logger.info "You can find the debug log at #{@log_file_path}"
        $stdout_logger.info "Please attach it when opening a support ticket"
    end
    ensure
      log_to_all "Uploading logs to Nevercode"
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
          $file_logger.debug "Codesigning id '#{csid}' matches '#{profile}'"
          referenced_codesigning_ids.add csid
          referenced_provisioning_profiles.add profile
        end
      }
      if not profile_matched
        $file_logger.debug "Provisioning profile '#{profile}' did not match any codesigning identity"
      end
    }
    @codesigning_identities.each { |csid|
      if not referenced_codesigning_ids.include? csid
        $file_logger.debug "Codesigning identity '#{csid}' did not match any provisioning profile"
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

  def start_collection
    $file_logger.debug "Create signing files collection #{SIGNING_FILES_COLLECTION_URL}"
    begin
      url = URI(SIGNING_FILES_COLLECTION_URL)
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = url.scheme == 'https'

      request = Net::HTTP::Post.new(url)
      request['Authorization'] = UPLOAD_KEY
      response = http.request(request)
      $file_logger.debug response.body
      collection = JSON.parse(response.body)
      $file_logger.debug collection
      @signing_files_collection_id = collection['id']
    rescue StandardError => err
      $file_logger.error "Failed to initialize signing files collection: #{err.message}"
      raise err
    end
  end

  def upload_log
    log_url = "#{SIGNING_FILES_COLLECTION_URL}/#{@signing_files_collection_id}/logs/"
    $file_logger.debug "Sending logs to #{log_url}"
    begin
      url = URI(log_url)
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = url.scheme == 'https'

      boundary = 'AaB03x'
      post_body = []
      post_body << "--#{boundary}\r\n"
      post_body << "Content-Disposition: form-data; name=\"logfile\"; filename=\"#{File.basename(@log_file_path)}\"\r\n"
      post_body << "Content-Type: text/plain\r\n"
      post_body << "\r\n"
      post_body << File.read(@log_file_path)
      post_body << "\r\n--#{boundary}--\r\n"

      request = Net::HTTP::Post.new(url)
      request.body = post_body.join
      request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
      request['Authorization'] = UPLOAD_KEY

      response = http.request(request)
      $file_logger.debug response.body
    rescue StandardError => err
      $file_logger.error "Failed to upload collector log to server: #{err.message}"
    end
  end

  def attach_object(request, json_object)
    def gzip(json_object, file_name)
      wio = File.new(file_name, "w")
      w_gz = Zlib::GzipWriter.new(wio)
      w_gz.write(json_object)
      w_gz.close
      wio
    end

    if json_object.length > OBJECT_LENGTH_LIMIT
      file_name = "compressed-json-object.gz"
      $file_logger.info "JSON object is too big: #{json_object.length}. Compressing"
      compressed_json_object = gzip(json_object, file_name)
      $file_logger.info "Compressed file size: #{File.stat(compressed_json_object).size}"

      boundary = 'AaB03x'
      post_body = []
      post_body << "--#{boundary}\r\n"
      post_body << "Content-Disposition: form-data; name=\"archive\"; filename=\"#{File.basename(file_name)}\"\r\n"
      post_body << "Content-Type: text/plain\r\n"
      post_body << "\r\n"
      post_body << File.read(file_name)
      post_body << "\r\n--#{boundary}--\r\n"

      request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
      request.body = post_body.join
      request
    else
      request['Content-Type'] = 'application/json'
      request.body = json_object
      request
    end
  end

  def upload_signing_files
    files_url = "#{SIGNING_FILES_COLLECTION_URL}/#{@signing_files_collection_id}/files/"
    $file_logger.debug "Sending signing files to #{files_url}"
    begin
      url = URI(files_url)
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = url.scheme == 'https'

      request = Net::HTTP::Post.new(url)
      request['Authorization'] = UPLOAD_KEY
      request = attach_object(request, @json_object)

      response = http.request(request)
      $file_logger.debug response.body
    rescue StandardError => err
      $file_logger.error "Failed to upload signing files to server: #{err.message}"
      raise CollectorError
    end

  end

end

def log_to_all(message, method = :info)
  $file_logger.send method, message
  $stdout_logger.send method, message
end

SIGNING_FILES_COLLECTION_URL = ARGV[0]
UPLOAD_KEY = ARGV[1]

OBJECT_LENGTH_LIMIT = 1000000

log_basename = File.join(Dir.tmpdir(), 'nevercode-signing-files-collector-log-')
log_file_path = Dir::Tmpname.make_tmpname(log_basename, '.log')

$file_logger = Logger.new log_file_path
$file_logger.level = Logger::DEBUG
$file_logger.formatter = proc { |severity, datetime, progname, msg|
  date_format = datetime.strftime("%Y-%m-%d %H:%M:%S")
  "#{date_format} #{severity} #{__FILE__}: #{__LINE__} #{msg}\n"
}
$stdout_logger = Logger.new STDOUT
$stdout_logger.level = Logger::INFO
$stdout_logger.formatter = proc { |severity, datetime, progname, msg|
  date_format = datetime.strftime("%Y-%m-%d %H:%M:%S")
  "#{date_format} #{severity} #{msg}\n"
}

collector = SigningFilesCollector.new log_file_path
collector.collect
