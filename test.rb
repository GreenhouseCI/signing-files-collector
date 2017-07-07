require 'zlib'
require 'stringio'
require 'json'
require 'objspace'
require 'fileutils'

def gunzip(data)
  io = StringIO.new(data, "rb")
  gz = Zlib::GzipReader.new(io)
  decompressed = gz.read
end

def gzip(string)
  wio = File.new("some_file.gz", "w")
  w_gz = Zlib::GzipWriter.new(wio)
  w_gz.write(string)
  w_gz.close
  wio
end


data = (1..100).collect {|i| {"id_#{i}" => "value_#{i}" } }
contents = data.to_json

puts "content:"
puts contents

compressed = gzip(contents)
# decompressed = gunzip(compressed)

puts "compressed string:"
puts compressed

# puts "decompressed success? #{decompressed == contents}"

puts "uncompressed data size: #{contents.length}"
puts "object space of contents: #{ObjectSpace.memsize_of(contents)}"
puts "decompressed data size: #{File.stat(compressed).size}"
puts "object space of compressed contents: #{ObjectSpace.memsize_of(compressed)}"
# puts "compress ratio: #{compressed.length.to_f / contents.length.to_f}"

# File.read(compressed)