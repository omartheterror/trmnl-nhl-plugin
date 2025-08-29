# serve.rb — local preview and TRMNL endpoint
require "sinatra"
require "time"

set :bind, "0.0.0.0"
set :port, ENV.fetch("PORT", 4567)
set :views, File.join(__dir__, "views")

require_relative "lib/plugins/nhl"
require_relative "lib/plugins/nhl_client"

helpers do
  def as_bool(v, default=true)
    return default if v.nil?
    s = v.to_s.strip.downcase
    return true  if %w[true 1 yes on].include?(s)
    return false if %w[false 0 no off].include?(s)
    default
  end

  def as_int(v, default)
    Integer(v) rescue default
  end

  def build_settings_from_params(p)
    {
      "preferred_team" => (p["team"] || "SJS"),
      "extra_teams"    => (p["extras"].is_a?(Array) ? p["extras"] : p["extras"].to_s.split(/[,;]\s*|[\s]+/)).reject(&:empty?),
      "lookback_days"  => as_int(p["lookback"], 7),
      "lookahead_days" => as_int(p["lookahead"], 7),
      "show_division_standings" => as_bool(p["standings"], true),
      "refresh_seconds" => as_int(p["refresh"], 90)
    }
  end
end

# Local preview (defaults)
get "/" do
  plugin_setting = {
    "preferred_team" => "SJS",
    "extra_teams" => [],
    "lookback_days" => 7,
    "lookahead_days" => 7,
    "show_division_standings" => true,
    "refresh_seconds" => 90
  }
  plugin = Plugins::NHL::Plugin.new(plugin_setting)
  data   = plugin.locals
  erb :"plugins/nhl/screen", locals: data, layout: false
end

# TRMNL Polling URL endpoint
get "/screen" do
  settings = build_settings_from_params(params)
  plugin   = Plugins::NHL::Plugin.new(settings)
  data     = plugin.locals
  erb :"plugins/nhl/screen", locals: data, layout: false
