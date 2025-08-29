require_relative '../utils/http_cache'

module Plugins
  class NhlClient
    STATS_BASE = 'https://statsapi.web.nhl.com/api/v1'
    WEB_BASE   = 'https://api-web.nhle.com/v1' # fallback for resiliency

    TEAM_ABBR_TO_ID = {
      "ANA"=>24,"ARI"=>53,"BOS"=>6,"BUF"=>7,"CGY"=>20,"CAR"=>12,"CHI"=>16,"COL"=>21,"CBJ"=>29,
      "DAL"=>25,"DET"=>17,"EDM"=>22,"FLA"=>13,"LAK"=>26,"MIN"=>30,"MTL"=>8,"NSH"=>18,"NJD"=>1,
      "NYI"=>2,"NYR"=>3,"OTT"=>9,"PHI"=>4,"PIT"=>5,"SEA"=>55,"SJS"=>28,"STL"=>19,"TBL"=>14,
      "TOR"=>10,"VAN"=>23,"VGK"=>54,"WSH"=>15,"WPG"=>52
    }

    TEAM_COLORS = {
      "SJS"=>"#006D75","ANA"=>"#F47A38","ARI"=>"#8C2633","BOS"=>"#FFB81C","BUF"=>"#003087",
      "CGY"=>"#C8102E","CAR"=>"#CC0000","CHI"=>"#CF0A2C","COL"=>"#6F263D","CBJ"=>"#002654",
      "DAL"=>"#006847","DET"=>"#CE1126","EDM"=>"#FF4C00","FLA"=>"#C8102E","LAK"=>"#111111",
      "MIN"=>"#154734","MTL"=>"#AF1E2D","NSH"=>"#FFB81C","NJD"=>"#CE1126","NYI"=>"#00539B",
      "NYR"=>"#0038A8","OTT"=>"#DA1A32","PHI"=>"#F74902","PIT"=>"#CFC493","SEA"=>"#001628",
      "STL"=>"#003087","TBL"=>"#002868","TOR"=>"#00205B","VAN"=>"#00843D","VGK"=>"#B4975A",
      "WSH"=>"#C8102E","WPG"=>"#041E42"
    }

    def initialize(ttl: 30)
      @http = Utils::HttpCache.new(ttl_seconds: ttl)
    end

    def current_season_id
      today = Date.today
      year = today.month >= 7 ? today.year : today.year - 1
      "#{year}#{year+1}"
    end

    def team_id(abbr) = TEAM_ABBR_TO_ID[abbr]

    def team_info(id)
      url = "#{STATS_BASE}/teams/#{id}"
      @http.get_json(url)["teams"]&.first
    end

    def schedule_for_team(team_abbr:, start_date:, end_date:)
      id = team_id(team_abbr)
      url = "#{STATS_BASE}/schedule?teamId=#{id}&startDate=#{start_date}&endDate=#{end_date}&expand=schedule.linescore"
      data = @http.get_json(url)
      games = (data["dates"] || []).flat_map { |d| d["games"] || [] }
      games.map { |g| normalize_game(g) }
    rescue
      season = current_season_id
      url = "#{WEB_BASE}/club-schedule-season/#{team_abbr}/#{season}"
      data = @http.get_json(url)
      (data["games"] || []).select { |g|
        date = Date.parse(g["gameDate"]) rescue nil
        date && date >= Date.parse(start_date) && date <= Date.parse(end_date)
      }.map { |g| normalize_web_game(g) }
    end

    def live_games_for_teams(team_abbrs)
      date = Date.today.strftime("%Y-%m-%d")
      team_abbrs.flat_map do |abbr|
        id = team_id(abbr)
        url = "#{STATS_BASE}/schedule?teamId=#{id}&date=#{date}&expand=schedule.linescore"
        data = @http.get_json(url)
        games = (data["dates"] || []).flat_map { |d| d["games"] || [] }
        games.select { |g| g.dig("status","abstractGameState") == "Live" }.map { |g| normalize_game(g) }
      end.uniq { |g| g[:gamePk] }
    rescue
      []
    end

    def division_standings_for_team(team_abbr)
      id = team_id(team_abbr)
      team = team_info(id)
      division_id = team.dig("division","id")
      season = current_season_id
      url = "#{STATS_BASE}/standings/byDivision?season=#{season}"
      data = @http.get_json(url)
      records = (data["records"] || []).find { |r| r.dig("division","id") == division_id }
      return [] unless records
      records["teamRecords"].map do |tr|
        name = tr.dig("team","name")
        abbr = abbr_from_name(name)
        {
          teamAbbr: abbr,
          teamName: name,
          color: color_for(abbr),
          GP: tr["gamesPlayed"],
          W:  tr.dig("leagueRecord","wins"),
          L:  tr.dig("leagueRecord","losses"),
          OT: tr.dig("leagueRecord","ot"),
          PTS: tr["points"],
          RW:  tr["regulationWins"] || 0,
          ROW: tr["row"] || 0,
          GF:  tr["goalsScored"],
          GA:  tr["goalsAgainst"],
          DIFF: tr["goalsScored"].to_i - tr["goalsAgainst"].to_i
        }
      end.sort_by { |t| [-t[:PTS], -t[:RW], -t[:ROW], -t[:DIFF]] }
    rescue
      []
    end

    def color_for(abbr) = TEAM_COLORS[abbr] || "#444"

    def normalize_game(g)
      away_name = g.dig("teams","away","team","name")
      home_name = g.dig("teams","home","team","name")
      away_abbr = abbr_from_name(away_name)
      home_abbr = abbr_from_name(home_name)

      {
        gamePk: g["gamePk"],
        date: g["gameDate"],
        status: g.dig("status","detailedState"),
        live: g.dig("status","abstractGameState") == "Live",
        home: { id: g.dig("teams","home","team","id"), name: home_name, abbr: home_abbr,
                score: g.dig("teams","home","score"), color: color_for(home_abbr) },
        away: { id: g.dig("teams","away","team","id"), name: away_name, abbr: away_abbr,
                score: g.dig("teams","away","score"), color: color_for(away_abbr) },
        venue: g.dig("venue","name"),
        linescore: g.dig("linescore")
      }
    end

    def normalize_web_game(g)
      away_abbr = g.dig("awayTeam","abbrev")
      home_abbr = g.dig("homeTeam","abbrev")
      {
        gamePk: g["id"],
        date: g["gameDate"],
        status: g["gameState"],  # FINAL, LIVE, FUT
        live:  g["gameState"] == "LIVE",
        home: { abbr: home_abbr, name: g.dig("homeTeam","name"), score: g.dig("homeTeam","score"),
                color: color_for(home_abbr) },
        away: { abbr: away_abbr, name: g.dig("awayTeam","name"), score: g.dig("awayTeam","score"),
                color: color_for(away_abbr) },
        venue: g["venue"]
      }
    end

    def abbr_from_name(name)
      map = {
        "Anaheim Ducks"=>"ANA","Arizona Coyotes"=>"ARI","Boston Bruins"=>"BOS","Buffalo Sabres"=>"BUF",
        "Calgary Flames"=>"CGY","Carolina Hurricanes"=>"CAR","Chicago Blackhawks"=>"CHI","Colorado Avalanche"=>"COL",
        "Columbus Blue Jackets"=>"CBJ","Dallas Stars"=>"DAL","Detroit Red Wings"=>"DET","Edmonton Oilers"=>"EDM",
        "Florida Panthers"=>"FLA","Los Angeles Kings"=>"LAK","Minnesota Wild"=>"MIN","Montréal Canadiens"=>"MTL",
        "Nashville Predators"=>"NSH","New Jersey Devils"=>"NJD","New York Islanders"=>"NYI","New York Rangers"=>"NYR",
        "Ottawa Senators"=>"OTT","Philadelphia Flyers"=>"PHI","Pittsburgh Penguins"=>"PIT","Seattle Kraken"=>"SEA",
        "San Jose Sharks"=>"SJS","St. Louis Blues"=>"STL","Tampa Bay Lightning"=>"TBL","Toronto Maple Leafs"=>"TOR",
        "Vancouver Canucks"=>"VAN","Vegas Golden Knights"=>"VGK","Washington Capitals"=>"WSH","Winnipeg Jets"=>"WPG"
      }
      map[name] || name
    end
  end
end