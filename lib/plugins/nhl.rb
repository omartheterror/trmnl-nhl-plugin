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
        @setting = plugin_setting || {}

        # Start with a conservative TTL; we will re-instantiate the client after we
        # detect live/game-day state to align API polling to your policy.
        ttl = as_int(@setting["refresh_seconds"], 60)
        @client = Plugins::NhlClient.new(ttl: ttl)
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

        # If your views assume keys exist, return a minimal locals hash to avoid nil errors.
        {
          preferred_team: preferred,
          extra_teams: extras,
          teams: teams
          # add more keys as your views require, e.g. :schedule, :standings, :live_games...
        }
      end  # closes def locals

      private

      # Converts val to a positive Integer or returns default.
      # Handles nil, empty strings, "0", negatives, and non-numeric input robustly.
      def as_int(val, default)
        case val
        when Integer
          val.positive? ? val : default
        when String
          s = val.strip
          return default if s.empty?
          n = Integer(s, exception: false)
          n && n.positive? ? n : default
        else
          default
        end
      end
    end  # closes class Plugin
  end    # closes module NHL
end      # closes module Plugins