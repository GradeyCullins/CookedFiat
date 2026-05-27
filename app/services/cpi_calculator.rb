require "json"

class CpiCalculator
  DATA_PATH = Rails.root.join("db", "cpi_data.json")

  class Error < StandardError; end
  class UnknownYear < Error; end
  class InvalidAmount < Error; end

  class << self
    def data
      @data ||= load_data
    end

    def reload!
      @data = load_data
    end

    def annual_averages
      data.fetch("annual_averages")
    end

    def years
      annual_averages.keys.map(&:to_i).sort
    end

    def earliest_year
      years.first
    end

    def latest_year
      years.last
    end

    def cpi_for(year)
      annual_averages[year.to_s] or raise UnknownYear, "No CPI for #{year}"
    end

    def source_info
      {
        series_name: data["series_name"],
        source: data["source"],
        source_url: data["source_url"],
        last_updated: data["last_updated"],
        provisional_years: provisional_years
      }
    end

    def provisional_years
      data.fetch("provisional_years", {})
    end

    def provisional_year?(year)
      provisional_years.key?(year.to_s)
    end

    def provisional_year_note(year)
      provisional_years.dig(year.to_s, "note")
    end

    def convert(amount:, from_year:, to_year:)
      amount = Float(amount)
      raise InvalidAmount, "Amount must be positive" if amount <= 0
      raise InvalidAmount, "Amount too large" if amount > 1_000_000_000_000

      from_cpi = cpi_for(from_year)
      to_cpi = cpi_for(to_year)
      converted = amount * (to_cpi / from_cpi)

      Result.new(
        amount: amount,
        from_year: from_year.to_i,
        to_year: to_year.to_i,
        from_cpi: from_cpi,
        to_cpi: to_cpi,
        converted: converted
      )
    rescue ArgumentError, TypeError
      raise InvalidAmount, "Amount must be a number"
    end

    private

    def load_data
      JSON.parse(File.read(DATA_PATH))
    end
  end

  Result = Data.define(:amount, :from_year, :to_year, :from_cpi, :to_cpi, :converted) do
    def inflation_factor
      converted / amount
    end

    def percent_change
      (inflation_factor - 1) * 100
    end

    def cumulative_inflation_text
      pct = percent_change
      if pct >= 0
        "Prices rose #{pct.round(1)}% over that span."
      else
        "Prices fell #{pct.abs.round(1)}% over that span."
      end
    end

    def amount_formatted
      format_usd(amount)
    end

    def converted_formatted
      format_usd(converted)
    end

    private

    def format_usd(value)
      whole, frac = format("%.2f", value).split(".")
      whole_with_commas = whole.reverse.scan(/\d{1,3}/).join(",").reverse
      "$#{whole_with_commas}.#{frac}"
    end
  end
end
