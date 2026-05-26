class CalculationsController < ApplicationController
  before_action :set_year_options

  def index
    @amount = params[:amount].presence
    @from_year = params[:from_year].presence&.to_i || default_from_year
    @to_year = params[:to_year].presence&.to_i || CpiCalculator.latest_year
    @result = compute_result if @amount.present?
    set_seo_for_index
  end

  def show
    @amount = params[:amount].presence
    @from_year = params[:from_year].presence&.to_i || default_from_year
    @to_year = params[:to_year].presence&.to_i || CpiCalculator.latest_year
    @result = compute_result
    set_seo_for_index
    respond_to do |format|
      format.html { render "calculations/index" }
      format.turbo_stream
    end
  end

  private

  def compute_result
    CpiCalculator.convert(
      amount: @amount,
      from_year: @from_year,
      to_year: @to_year
    )
  rescue CpiCalculator::Error => e
    @error = e.message
    nil
  end

  def set_year_options
    @year_options = CpiCalculator.years.reverse
  end

  def default_from_year
    candidate = CpiCalculator.latest_year - 30
    CpiCalculator.years.include?(candidate) ? candidate : CpiCalculator.earliest_year
  end

  def set_seo_for_index
    if @result
      @page_title = "#{@result.amount_formatted} in #{@result.from_year} = #{@result.converted_formatted} in #{@result.to_year} | Cooked Fiat"
      @meta_description = "#{@result.amount_formatted} in #{@result.from_year} has the same purchasing power as #{@result.converted_formatted} in #{@result.to_year}. #{@result.cumulative_inflation_text} CPI-based inflation calculator."
    else
      @page_title = "Cooked Fiat — Inflation Calculator: Spending X in year A is like spending Y in year B"
      @meta_description = "Find out what your money was really worth. Compare the purchasing power of any US dollar amount between #{CpiCalculator.earliest_year} and #{CpiCalculator.latest_year} using official BLS CPI data."
    end
    @canonical_path = canonical_path_for_current_request
  end

  def canonical_path_for_current_request
    if @amount.present?
      "/calculation?" + {
        amount: @amount,
        from_year: @from_year,
        to_year: @to_year
      }.to_query
    else
      "/"
    end
  end
end
