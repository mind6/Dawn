#=
Summarization of trades
Used by selecttraderun() and updatetradedata()
=#
using DataFrames, ProgressMeter

"""
populate TradeProviderControls with dataframes that summarize the trades which have been requested (and executed).

Returns concatenated and transformed trade data across all provider controls in current trade run.
"""
function summarizetrades(strategy_prefix::Symbol=:delayed60)
   truncontext = currenttraderun()
   
   # Process each TradeProviderControl and prepare its data
   pbar = Progress(length(truncontext.trprov_ctrls), desc="summarizing trades", showspeed=true, barlen=50)
   for provctrl in truncontext.trprov_ctrls
      # Prepare provider data
      summarize_provider_trades(provctrl, strategy_prefix)
      next!(pbar)
   end
   finish!(pbar)
   @info "Creating merged trade summary"

   # Combine all provider trades into a single dataframe
   all_exitres = [provctrl.exitres for provctrl in truncontext.trprov_ctrls if provctrl.exitres !== nothing]
   if isempty(all_exitres)
      @warn "No trade results found. Have you called executetraderun()?"
      return
   end
   
   df = vcat(all_exitres...; cols=:union)
   @assert !isempty(df) "No trades were found. Have you called executetraderun()?"
   sort!(df, :datetime)
   
   # Set up month column for monthly summaries
   df.month = Dates.floor.(df.datetime, Dates.Month)
   
   # Find the strategy prefix from trade providers if not provided
   detected_prefix = detect_strategy_prefix(truncontext, strategy_prefix)
   if detected_prefix != strategy_prefix
      strategy_prefix = detected_prefix
      @info "Using detected strategy prefix: $strategy_prefix"
   end
   
   # Prepare return column identifier
   retcol = Symbol(strategy_prefix, :_log_return)
   if retcol ∉ propertynames(df)
      @warn "Column $retcol not found in trade summary. It seems no trades were executed or this strategy prefix is incorrect."
      return
   end
   
   # Store the trade summary in the context
   truncontext.tradesummary = df
   truncontext.tradesummary_gb = groupby(df, :provider)
   
   # Validate trades
   for grp in truncontext.tradesummary_gb
      if !issorted(grp.datetime)
         @error "$(first(grp.provider)) trades are not sorted by datetime"
      end
      
      if !allunique(grp.datetime)
         @warn "$(first(grp.provider)) has multiple trades at the same timestamp"
      end
   end
   
   # Create aggregated metrics
   transform!(df, 
      retcol => cumsum => :combined_cumret)
   transform!(truncontext.tradesummary_gb, retcol => cumsum => :provider_cumret)
   
   # Add metadata
   metadata!(truncontext.tradesummary, "sortinoratio", MyMath.sortinoratio_annualized(df; logret_col=retcol)[1])
   profit_col = Symbol(strategy_prefix, :_dollar_profit)
   if profit_col ∈ propertynames(df)
      metadata!(truncontext.tradesummary, "dollar_profit", mean(df[!, profit_col]))
   end
   metadata!(truncontext.tradesummary, "log_ret", mean(df[!, retcol]))
   
   # Create monthly summaries
   create_monthly_summaries(truncontext, retcol)
   
   return truncontext.tradesummary
end

"""
Detect the best strategy prefix to use based on provider metadata
"""
function detect_strategy_prefix(truncontext::TradeRunContext, default_prefix::Symbol)
   for tc in truncontext.trprov_ctrls
      meta_prefix = haskey(tradeprovider(tc).meta, :prefix) ? tradeprovider(tc).meta[:prefix] : Symbol()
      if meta_prefix !== Symbol()
         return meta_prefix
      end
   end
   return default_prefix
end

"""
Create monthly summary dataframes for the trade run context
"""
function create_monthly_summaries(truncontext::TradeRunContext, retcol::Symbol)
   # Monthly returns by provider
   gb = groupby(truncontext.tradesummary, [:provider, :month])
   df = combine(gb, retcol => sum => :prov_mo_ret)
   truncontext.monthsummary_gb = groupby(df, :provider)
   truncontext.monthsummary = transform!(truncontext.monthsummary_gb, :prov_mo_ret => cumsum => :prov_cum_mo_ret)
   
   # Monthly returns combined across all providers
   df = combine(groupby(truncontext.monthsummary, :month), :prov_mo_ret => sum => :combined_mo_ret)
   transform!(df, :combined_mo_ret => cumsum => :combined_cum_mo_ret)
   truncontext.monthsummary_combined = df
   metadata!(truncontext.monthsummary_combined, "sortinoratio", MyMath.sortinoratio_annualized(df; datetime_col=:month, logret_col=:combined_mo_ret)[1])
   
   return truncontext.monthsummary
end

"""
Summarize trades for a single provider control
"""
function summarize_provider_trades(provctrl::TradeProviderControl, strategy_prefix::Symbol) 
   @debug "Summarizing trades for $(provctrl.providername)"
   
   # Skip if already summarized
   if provctrl.combineddata !== nothing && provctrl.trades !== nothing && provctrl.exitres !== nothing
      @debug "Data already summarized, skipping."
      return
   end
   
   # Get the AUT (Asset Under Trade)
   AUT = provctrl.runchain[end].prov.meta[:AUT]
   
   # Create combined data from all providers in the runchain
   provctrl.combineddata = sp.combined_provider_data([[rn.prov for rn in provctrl.runchain]; provctrl.refchartsinks])
   metadata!(provctrl.combineddata, "symbol", AUT; style=:note)
   MyData.setcolumn_asindex!(provctrl.combineddata, :datetime)
   
   # Extract trades
   provctrl.trades = filter(:exitstrat_onenter => !ismissing, provctrl.combineddata)
   metadata!(provctrl.trades, "symbol", AUT; style=:note)
   MyData.setcolumn_asindex!(provctrl.trades, :datetime)
   
   # Create exit results (melted trades dataframe)
   provctrl.exitres = DataFrame(provider=[], datetime=DateTime[], tradeaction=MyFormats.TradeAction[])
   
   for trrow in eachrow(provctrl.trades)
      colnames = [[:datetime, :tradeaction]; get_reference_columnnames(provctrl.refchartsinks...)]
      
      newrow = Pair{Symbol, Any}[:provider => provctrl.providername, :AUT_close => trrow.close]
      for colname in colnames
         push!(newrow, colname => trrow[colname])
      end
      
      for strat in trrow.exitstrat_onenter
         pre = sp.typeprefix(strat)
         push!(newrow, Symbol(pre, :_frac_return) => strat.frac_return)
         push!(newrow, Symbol(pre, :_log_return) => strat.log_return)
         push!(newrow, Symbol(pre, :_dollar_profit) => strat.dollar_profit)
         push!(newrow, Symbol(pre, :_elapsed) => strat.elapsed)
         push!(provctrl.exitprefixes, pre)
      end
      
      push!(provctrl.exitres, NamedTuple(newrow); cols=:union)
   end
end
