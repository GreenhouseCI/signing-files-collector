require 'rubygems'

def load_or_install_gem(gem_name)
  begin
    require gem_name
  rescue  LoadError => e
    puts "exception .. installing with gem"
    h = system "gem install '#{gem_name}'"
    puts "gem installed #{h}"
    Gem.clear_paths
    require gem_name
  end
end