# config/puma.rb
port ENV.fetch("PORT", "4567")
environment ENV.fetch("RACK_ENV", "production")
workers 0
threads 0, 5