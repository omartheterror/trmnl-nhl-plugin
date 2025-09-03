# frozen_string_literal: true
# D:\Trmnl\plugin\NHL\lib\plugins\nhl.rb

require "date"
require "time"
require_relative "nhl_client"

module Plugins
  module NHL
    class Plugin
      def initialize(plugin_setting)
        # Raw settings from TRMNL (strings / arrays from the Custom Form Builder)
        @setting = plugin_setting || {}

        # Conservative default TTL; can be tuned later
        ttl = as_int(@setting["refresh_seconds"], 60)
        @client = Plugins::NhlClient.new(ttl: ttl)
      end

      # TRMNL calls this. Return a Hash ("locals") that the ERB views will render.
      def locals
        # ------------------------ INPUT NORMALIZATION ------------------------
        preferred = (@setting["preferred_team"] || "SJS").to_s.strip.upcase

        raw_extra = @setting["extra_teams"]
        extras =
          case raw_extra
          when Array  then raw_extra
          when String then raw_extra.split(/[,;]\s*|[\s]+/)
          else []
          end
        extras = extras.map { |t| t.to_s.strip.upcase }.reject(&:empty?).uniq

        teams = ([preferred] + extras).uniq

        show_standings = as_bool(@setting["show_standings"], false)
        lookahead_days = as_int(@setting["lookahead_days"], 7)
        lookback_days  = as_int(@setting["lookback_days"], 0)

        # Dates (NHL APIs expect YYYY-MM-DD)
        today      = Date.today
        start_date = (today - lookback_days).strftime("%Y-%m-%d")
        end_date   = (today + lookahead_days).strftime("%Y-%m-%d")
        now_utc    = Time.now.utc

        # ------------------------ DATA FETCH ------------------------
        # LIVE (only for selected teams)
        live = safe_call { @client.live_games_for_teams(teams) }
        live = Array(live)

        # SCHEDULE window (only for selected teams), merged & deduped by :gamePk
        team_schedules = teams.flat_map do |abbr|
          Array(safe_call { @client.schedule_for_team(team_abbr: abbr, start_date: start_date, end_date: end_date) })
        end

        schedule = dedupe_games(team_schedules)

        # Partition into upcoming vs recent for convenience
        upcoming_games, recent_games = partition_games(schedule, now_utc)

        # STANDINGS (division of preferred team), optional
        standings = []
        if show_standings && preferred
          standings = Array(safe_call { @client.division_standings_for_team(preferred) })
        end

        # ------------------------ LOCALS (nil-safe) ------------------------
        h = {
          # Settings
          preferred_team: preferred,
          extra_teams:    extras,
          teams:          teams,
          show_standings: show_standings,
          lookahead_days: lookahead_days,
          lookback_days:  lookback_days,
          start_date:     start_date,
          end_date:       end_date,

          # Data
          live:           live,
          live_games:     live,          # alias some views use
          schedule:       schedule,
          games:          schedule,      # alias some views use
          upcoming_games: upcoming_games,
          recent_games:   recent_games,
          standings:      standings,

          # Convenience
          now_utc:        now_utc
        }

        # Ensure arrays are never nil (defensive)
        %i[live live_games schedule games upcoming_games recent_games standings extra_teams teams].each do |k|
          h[k] = Array(h[k])
        end

        h
      end  # def locals

      private

      # ---- Helpers ---------------------------------------------------------

      # Coerces to positive Integer or returns default.
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

      # Coerces "truthy" string/boolean-ish values.
      def as_bool(val, default = false)
        case val
        when TrueClass, FalseClass
          val
        when String
          s = val.strip.downcase
          return true  if %w[true 1 yes y on].include?(s)
          return false if %w[false 0 no n off].include?(s)
          default
        else
          default
        end
      end

      # Rescue wrapper so a single failing call doesn't take down the view.
      def safe_call
        yield
      rescue => e
        # You could log e.message here if you add a logger
        []
      end

      # Deduplicate games by :gamePk (when two selected teams play each other)
      # Also sort by game date/time ascending.
      def dedupe_games(games)
        by_pk = {}
        Array(games).each do |g|
          next unless g.is_a?(Hash)
          pk = g[:gamePk] || g["gamePk"]
          by_pk[pk] = symbolize_keys(g) if pk
        end
        by_pk.values.sort_by { |g| time_or_epoch(g[:date]) }
      end

      # Partition into upcoming vs recent based on status/date
      def partition_games(games, now_utc)
        upcoming = []
        recent   = []
        Array(games).each do |g|
          sg = symbolize_keys(g)
          t  = time_or_epoch(sg[:date])
          if sg[:live]
            # Treat live games as "upcoming" section if your template expects them there,
            # but most UIs render LIVE separately; we keep them in schedule plus live[] above.
            upcoming << sg
          elsif final_status?(sg[:status]) || t < now_utc
            recent << sg
          else
            upcoming << sg
          end
        end
        [upcoming.sort_by { |g| time_or_epoch(g[:date]) },
         recent.sort_by   { |g| time_or_epoch(g[:date]) }.reverse]
      end

      def final_status?(status)
        s = status.to_s.upcase
        s.include?("FINAL") || s.include?("GAME OVER") || s == "OFF"
      end

      def time_or_epoch(date_str)
        Time.parse(date_str.to_s).utc
      rescue
        Time.at(0).utc
      end

      def symbolize_keys(h)
        return h unless h.is_a?(Hash)
        h.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
      end
    end  # class Plugin
  end    # module NHL
end      # module Plugins