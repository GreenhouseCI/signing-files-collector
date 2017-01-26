require 'rubygems'

NAME_TO_GEM_MAP = {
    "zip" => "rubyzip",
    "keychain" => "ruby-keychain"
}

def load_or_install_gem(name)
  begin
    eval "require '#{name}'"
  rescue  LoadError => e
    puts "exception .. installing with gem"
    h = system "gem install #{NAME_TO_GEM_MAP[name]}"
    puts "gem installed #{h}"
    Gem.clear_paths
    eval "require '#{name}'"
  end
end