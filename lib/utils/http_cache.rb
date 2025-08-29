require 'json'
require 'net/http'
require 'uri'

module Utils
  class HttpCache
    def initialize(ttl_seconds: 30)
      @ttl = ttl_seconds
      @cache = {} # { url => { at:, data: } }
    end

    def get_json(url)
      now = Time.now.to_i
      if @cache[url] && now - @cache[url][:at] < @ttl
        return @cache[url][:data]
      end
      uri = URI.parse(url)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.open_timeout = 5
        http.read_timeout = 8
        http.get(uri.request_uri, { 'User-Agent' => 'TRMNL-NHL-Plugin' })
      end
      data = JSON.parse(res.body)
      @cache[url] = { at: now, data: data }
      data
    rescue => e
      return @cache[url][:data] if @cache[url]
      raise e
    end
  end
end