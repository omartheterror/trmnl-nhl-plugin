# frozen_string_literal: true
# D:\Trmnl\plugin\NHL\lib\plugins\nhl.rb

require "date"
require "time"
require_relative "nhl_client"

module Plugins
  module NHL
    class Plugin
      def initialize(plugin_setting)
        @setting = plugin_setting || {}
        ttl = as_int(@setting["refresh_seconds"], 60)
        @client = Plugins::NhlClient.new(ttl: ttl)
      end

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

        # Dates
        today      = Date.today
        start_date = (today - lookback_days).strftime("%Y-%m-%d")
        end_date   = (today + lookahead_days).strftime("%Y-%m-%d")
        now_utc    = Time.now.utc

        # ------------------------ DATA FETCH ------------------------
        live = safe_call { @client.live_games_for_teams(teams) }
        live = Array(live)

        # Schedule for selected teams
        team_schedules = teams.flat_map do |abbr|
          Array(safe_call { @client.schedule_for_team(team_abbr: abbr, start_date: start_date, end_date: end_date) })
        end
        schedule = dedupe_games(team_schedules)

        # Partition into upcoming vs recent
        upcoming_games, recent_games = partition_games(schedule, now_utc)

        # Limit to 2 games each
        upcoming_games = upcoming_games.first(2)
        recent_games   = recent_games.first(2)

        # If no upcoming games in next 5 days, find next game within 30 days
        next_game = nil
        if upcoming_games.empty?
          extended_end = (today + 30).strftime("%Y-%m-%d")
          extended_schedule = safe_call {
            @client.schedule_for_team(team_abbr: preferred, start_date: today.strftime("%Y-%m-%d"), end_date: extended_end)
          }
          extended_schedule = Array(extended_schedule).sort_by { |g| Time.parse(g[:date] || g["date"]) rescue Time.at(0) }
          next_game = extended_schedule.first if extended_schedule.any?
        end

        # Standings (optional)
        standings = []
        if show_standings && preferred
          standings = Array(safe_call { @client.division_standings_for_team(preferred) })
        end

        # ------------------------ LOCALS ------------------------
        {
          preferred_team: preferred,
          extra_teams: extras,
          teams: teams,
          show_standings: show_standings,
          lookahead_days: lookahead_days,
          lookback_days: lookback_days,
          start_date: start_date,
          end_date: end_date,
          now_utc: now_utc,
          live: live,
          live_games: live,
          schedule: schedule,
          games: schedule,
          upcoming_games: upcoming_games,
          recent_games: recent_games,
          standings: standings,
          next_game: next_game
        }
      end

      private

      # Converts val to positive Integer or returns default
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

      # Converts truthy strings/booleans
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

      # Safe wrapper for API calls
      def safe_call
        yield
      rescue => e
        []
      end

      # Deduplicate games by :gamePk and sort by date
      def dedupe_games(games)
        by_pk = {}
        Array(games).each do |g|
          next unless g.is_a?(Hash)
          pk = g[:gamePk] || g["gamePk"]
          by_pk[pk] = symbolize_keys(g) if pk
        end
        by_pk.values.sort_by { |g| time_or_epoch(g[:date]) }
      end

      # Partition into upcoming vs recent
      def partition_games(games, now_utc)
        upcoming = []
        recent   = []
        Array(games).each do |g|
          sg = symbolize_keys(g)
          t  = time_or_epoch(sg[:date])
          if sg[:live]
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
    end
  end
end