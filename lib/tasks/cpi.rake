require "net/http"
require "json"
require "uri"

namespace :cpi do
  desc "Refresh CPI annual averages from the U.S. Bureau of Labor Statistics public API (no API key required)."
  task refresh: :environment do
    series_id = ENV.fetch("BLS_SERIES_ID", "CUUR0000SA0")
    api_key   = ENV["BLS_API_KEY"] # optional; raises BLS quota when present

    start_year, end_year = year_window
    puts "Fetching BLS series #{series_id} from #{start_year}–#{end_year}…"

    json = fetch_bls(series_id, start_year, end_year, api_key)
    if json["status"] != "REQUEST_SUCCEEDED"
      abort "BLS API error: #{json["status"]} — #{Array(json["message"]).join("; ")}"
    end

    raw_series = json.dig("Results", "series", 0, "data") or abort "Unexpected BLS payload"

    annual_averages, provisional_years = annual_values_from(raw_series)

    if annual_averages.empty?
      abort "No annual averages found. The BLS publishes annual averages once per year (usually January) — try a wider window."
    end

    merged = merge_with_existing(annual_averages)
    write_data_file(series_id, merged, provisional_years)
    puts "Wrote #{merged.size} annual averages (#{merged.keys.min}–#{merged.keys.max}) to db/cpi_data.json"
  end

  desc "Show the year range and latest entry currently bundled."
  task status: :environment do
    require_relative Rails.root.join("app/services/cpi_calculator")
    CpiCalculator.reload!
    puts "Years: #{CpiCalculator.earliest_year}–#{CpiCalculator.latest_year}"
    puts "Latest CPI (#{CpiCalculator.latest_year}): #{CpiCalculator.cpi_for(CpiCalculator.latest_year)}"
  end
end

def year_window
  end_year = Date.current.year
  start_year = end_year - 9
  [ start_year, end_year ]
end

def annual_values_from(raw_series)
  annuals = {}
  latest_monthly_by_year = {}

  raw_series.each do |entry|
    year = entry["year"].to_s
    period = entry["period"].to_s
    value = numeric_cpi_value(entry["value"])
    next unless value

    if period == "M13" # M13 is the annual average row.
      annuals[year] = value
    elsif period.match?(/\AM\d{2}\z/)
      latest_monthly_by_year[year] ||= entry.merge("value" => value)
    end
  end

  current_year = Date.current.year.to_s
  if annuals[current_year].nil? && latest_monthly_by_year[current_year]
    latest = latest_monthly_by_year[current_year]
    annuals[current_year] = latest["value"]
    puts "Using #{latest["periodName"]} #{current_year} CPI as #{current_year} until the annual average is published."
  end

  [ annuals, provisional_years_for(current_year, latest_monthly_by_year, annuals) ]
end

def provisional_years_for(current_year, latest_monthly_by_year, annuals)
  return {} unless latest_monthly_by_year[current_year]

  latest = latest_monthly_by_year[current_year]
  return {} unless annuals[current_year] == latest["value"]

  {
    current_year => {
      "period" => latest["period"],
      "period_name" => latest["periodName"],
      "note" => "#{latest["periodName"]} CPI is used for #{current_year} until the annual average is published."
    }
  }
end

def numeric_cpi_value(value)
  Float(value)
rescue ArgumentError, TypeError
  nil
end

def fetch_bls(series_id, start_year, end_year, api_key)
  uri = URI("https://api.bls.gov/publicAPI/v2/timeseries/data/")
  body = {
    "seriesid"  => [ series_id ],
    "startyear" => start_year.to_s,
    "endyear"   => end_year.to_s,
    "annualaverage" => true
  }
  body["registrationkey"] = api_key if api_key

  req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
  req.body = body.to_json
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 15) { |h| h.request(req) }
  JSON.parse(res.body)
end

def merge_with_existing(new_annuals)
  path = Rails.root.join("db", "cpi_data.json")
  existing = JSON.parse(File.read(path)).fetch("annual_averages", {})
  existing.merge(new_annuals).sort.to_h
end

def write_data_file(series_id, annuals, provisional_years = {})
  path = Rails.root.join("db", "cpi_data.json")
  payload = {
    "series_id"        => series_id,
    "series_name"      => "Consumer Price Index for All Urban Consumers (CPI-U), U.S. city average, all items",
    "base_period"      => "1982-84=100",
    "source"           => "U.S. Bureau of Labor Statistics",
    "source_url"       => "https://www.bls.gov/cpi/",
    "last_updated"     => Date.current.to_s,
    "provisional_years" => provisional_years,
    "annual_averages"  => annuals
  }
  File.write(path, JSON.pretty_generate(payload) + "\n")
end
