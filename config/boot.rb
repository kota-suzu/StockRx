ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

# Bootsnap setup with Docker conflict prevention
unless ENV["DISABLE_BOOTSNAP"] == "1"
  require "bootsnap/setup" # Speed up boot time by caching expensive operations.
end
