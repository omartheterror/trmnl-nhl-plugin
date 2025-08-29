# frozen_string_literal: true
# D:\Trmnl\plugin\NHL\lib\plugins\nhl.rb

# Provides the "brains" for the NHL TRMNL screen:
# - reads user settings (preferred team, extra teams, lookback/lookahead, standings toggle)
# - fetches schedule, live games, division standings via NhlClient
# - computes a smart refresh recommendation based on game state
#
# Paired ERB views:
#   views/plugins/nhl/screen.html.erb
#   views/plugins/nhl/_live.html.erb
#   views/plugins/nhl/_schedule.html.erb
#   views/plugins/nhl/_standings.html.erb

require "date"
require "time"
require_relative "nhl_client"

module Plugins
  module NHL
    class Plugin
      def initialize(plugin_setting)
        # Raw settings provided by TRMNL (strings / arrays from the Custom Form Builder)
        @setting = plugin_setting

        # Start with a conservative TTL; we will re-instantiate the client after we
        # detect live/game-day state to align API polling to your policy.
        @client = Plugins::NhlClient.new(ttl: as_int(@setting["refresh_seconds"], 60))
      end

      # TRMNL calls this. Return a Hash ("locals") that the ERB views will render.
      def locals
        # ------------------------ INPUT NORMALIZATION ------------------------
        # TRMNL often serializes values as strings. These helpers coerce to the
        # types we want (Array, Integer, Boolean), so the plugin is robust.

        # Preferred team:
        # Default is SJS (San Jose Sharks). To choose a different club, set
        # `preferred_team` to another 3-letter abbreviation (e.g., "TOR", "VGK").
        preferred = (@setting["preferred_team"] || "SJS").to_s.strip.upcase

        # Extra teams (multi-select):
        # In the TRMNL form this may arrive as an Array (["VGK","LAK"]) OR a
        # string ("VGK, LAK") depending on editor/version. Normalize to Array.
        raw_extra = @setting["extra_teams"]
        extras =
          case raw_extra
          when Array  then raw_extra
          when String then raw_extra.split(/[,;]\s*|[\s]+/)
          else []
          end
        extras = extras.map { |t| t.to_s.strip.upcase }.reject(&:empty?).uniq

        # Make the full tracked set (used for LIVE aggregation)
        teams = ([preferred] + extras).uniq

        # Schedule window (past/upcoming days)

 
        # (Add any additional logic here if needed)
      end  # closes def locals

    end  # closes class Plugin
  end    # closes module NHL
end      # closes module Plugins
