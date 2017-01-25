require 'fileutils'
require "logger"

require "./collector_errors.rb"
require './utils.rb'

load_or_install_gem('rubyzip')

$LOG_FILE_NAMAE = "signing_files_collector.log"

class SigningFilesCollector
  @@PACKAGE_NAME = "signing_files_package.zip"

  def initialize
    @execute_dir = Dir.pwd
    @log_file_path = File.join @execute_dir, $LOG_FILE_NAMAE
    @package_dir = generate_package_dir_name
    @provisioning_profiles = Array.new
    @codesigning_identities = Array.new
  end

  def collect
    begin
      $file_logger.info "Preparing to collect iOS signing files"
      create_temp_dir
      #TODO
      #@provisioning_profiles =
      #TODO
      #@codesigning_identities =
      raise CollectorError

    rescue CollectorError
      puts "Signing file collection failed. Aborting"
      if File.exist?(@log_file_path)
        $stdout_logger.info "You can find the debug log at #{@log_file_path}"
        $stdout_logger.info "Please attach it when opening a support ticket"
      end
    ensure
      remove_package_dir
    end
  end

private

  def generate_package_dir_name
    timestamp = Time.now.to_i
    "/tmp/gh_signing_files_#{timestamp}"
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

  def add_log_to_upload_package
    begin
      $file_logger.debug "Adding our log #{@log_file_path} to the upload package"
      Dir.chdir @package_dir

    rescue StandardError => err
    end
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


File.delete($LOG_FILE_NAMAE) if File.exist?($LOG_FILE_NAMAE)

log_file = File.open $LOG_FILE_NAMAE, "a"
$file_logger = Logger.new log_file
$file_logger.level = Logger::DEBUG
$file_logger.formatter = proc { |severity, datetime, progname, msg| "#{severity} #{caller[4]} #{msg}\n" }
$stdout_logger = Logger.new STDOUT
$stdout_logger.level = Logger::INFO

SigningFilesCollector.new().collect