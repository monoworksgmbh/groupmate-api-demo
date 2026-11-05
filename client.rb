# Tiny groupmate API client. Ruby stdlib only.
require "json"
require "net/http"
require "uri"

# Load .env (KEY=value lines) next to this file. Variables already set in the shell win.
env_file = File.join(__dir__, ".env")
File.foreach(env_file) do |line|
  next unless (m = line.match(/\A\s*(?:export\s+)?([A-Z_][A-Z0-9_]*)\s*=\s*(.*?)\s*\z/))
  ENV[m[1]] ||= m[2].delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'")
end if File.exist?(env_file)

class Groupmate
  Response = Struct.new(:status, :body, :headers) do
    def ok? = status < 400
    def error_code = body.is_a?(Hash) ? body.dig("error", "code") : nil
  end

  # Product IDs from GROUPMATE_PRODUCT_IDS ("111,222" or GIDs), normalized to numeric strings.
  def self.product_ids = ENV.fetch("GROUPMATE_PRODUCT_IDS", "").split(/[\s,]+/).map { _1[/\d+\z/] }.compact

  def initialize(api_key: ENV.fetch("GROUPMATE_API_KEY") { abort "Set GROUPMATE_API_KEY" },
                 base_url: ENV.fetch("GROUPMATE_BASE_URL", "https://groupmate.fly.dev/api/v1"))
    @api_key = api_key
    @base_url = base_url.chomp("/")
  end

  def list(**params)     = request(:get, "/groups", params:)
  def get(id)            = request(:get, "/groups/#{id}")
  def create(group)      = request(:post, "/groups", body: { group: })
  def update(id, group)  = request(:patch, "/groups/#{id}", body: { group: })
  def delete(id)         = request(:delete, "/groups/#{id}")

  # { product_id => group } for the given products that are already in a group.
  def grouped(product_ids) = product_ids.to_h { [_1, list(product_id: _1).body["groups"]&.first] }.compact

  def request(method, path, params: nil, body: nil, retries: 3)
    uri = URI("#{@base_url}#{path}")
    uri.query = URI.encode_www_form(params) if params&.any?

    req = Net::HTTP.const_get(method.capitalize).new(uri)
    req["Authorization"] = "Bearer #{@api_key}"
    req["Accept"] = "application/json"
    if body
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(body)
    end

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { _1.request(req) }

    if res.code == "429" && retries > 0
      wait = res["Retry-After"].to_i.clamp(1, 60)
      warn "rate limited, retrying in #{wait}s"
      sleep wait
      return request(method, path, params:, body:, retries: retries - 1)
    end

    parsed = res.body.to_s.empty? ? nil : (JSON.parse(res.body) rescue res.body)
    Response.new(res.code.to_i, parsed, res.to_hash)
  end
end
