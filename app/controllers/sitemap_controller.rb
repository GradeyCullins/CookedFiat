class SitemapController < ApplicationController
  HIGHLIGHT_AMOUNTS = [ 1, 10, 100, 1_000, 10_000, 100_000, 1_000_000 ].freeze
  HIGHLIGHT_FROM_YEARS = [ 1920, 1950, 1970, 1980, 1990, 2000, 2010, 2020 ].freeze

  def index
    @latest_year = CpiCalculator.latest_year
    @entries = build_entries
    respond_to do |format|
      format.xml
    end
  end

  private

  def build_entries
    entries = [ { loc: root_url, priority: 1.0 } ]
    HIGHLIGHT_FROM_YEARS.each do |from_year|
      HIGHLIGHT_AMOUNTS.each do |amount|
        entries << {
          loc: calculation_url(amount: amount, from_year: from_year, to_year: @latest_year),
          priority: 0.7
        }
      end
    end
    entries
  end
end
