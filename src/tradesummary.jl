"""
populate TradeProviderControls with dataframes that summarize the trades which have been requested (and possibly completed).

You can repeatedly call this as new data comes in on the providers. (thread safety not really implemented currently, use Provider.queue_num?)

   retcol: column (e.g. a fractional return column) for which we will calculate date cumulative value over each provider, as well as across all providers. 

Verifies that each provider can initiate at most one trade for each minute bar
"""
function summarizetrades(strategy_prefix::Symbol=:delayed60)
   for ctrl in get_tradeprovctrls()
      AUT = ctrl.runchain[end].prov.meta[:AUT]

      ### create combineddata with data from all providers in the runchain and refchartsinks
      ctrl.combineddata = sp.combined_provider_data([[rn.prov for rn in ctrl.runchain]; ctrl.refchartsinks])
      metadata!(ctrl.combineddata, "symbol", AUT; style=:note)
      MyData.setcolumn_asindex!(ctrl.combineddata, :datetime)

      ### save part of combineddata which contain trades
      ctrl.trades = filter(:exitstrat_onenter=>!ismissing, ctrl.combineddata)
      metadata!(ctrl.trades, "symbol", AUT; style=:note)
      MyData.setcolumn_asindex!(ctrl.trades, :datetime)

      ### create exitres dataframe which melts trades df with individual rows corresponding to tradeactions like enter, exit, etc.
      ctrl.exitres = DataFrame(provider=[], datetime=DateTime[], tradeaction=MyFormats.TradeAction[])
      for trrow in eachrow(ctrl.trades) 
         colnames = [[:datetime,:tradeaction]; get_reference_columnnames(ctrl.refchartsinks...)]

         newrow = Pair{Symbol, Any}[:provider=>ctrl.providername, :AUT_close=>trrow.close]
         for colname in colnames
            push!(newrow, colname=>trrow[colname])
         end
         for strat in trrow.exitstrat_onenter
            pre = sp.typeprefix(strat)
            push!(newrow, Symbol(pre, :_frac_return)=>strat.frac_return)
            push!(newrow, Symbol(pre, :_log_return)=>strat.log_return)
            push!(newrow, Symbol(pre, :_dollar_profit)=>strat.dollar_profit)
            push!(newrow, Symbol(pre, :_elapsed)=>strat.elapsed)
            push!(ctrl.exitprefixes, pre)
         end

         push!(ctrl.exitres, NamedTuple(newrow); cols=:union)
      end
   end

   ### create tradesummary
   df = vcat([prov.exitres for prov in get_tradeprovctrls()]...; cols=:union)
   # push!(df, df[end, :]) #to test handling of multiple simultaneous trades 
   sort!(df, :datetime)
   global tradesummary = df
   global tradesummary_gb = groupby(df, :provider)

   for grp in tradesummary_gb   #each provider can initiate at most one trade for each minute bar
      if !allunique(grp.datetime)
         dups = grp[nonunique(grp[!,[:datetime]]),:]
         error("unexpected trade when there is another at the same time for same provider:\n$dups")
      end
   end
   retcol = Symbol(strategy_prefix, :_log_return)
   # retcol = Symbol(strategy_prefix, :_frac_return)
   if retcol ∉ propertynames(df)
      @warn "Column $retcol not found in tradesummary. It seems no trades were executed."
      return
   end
   transform!(df, 
      retcol => cumsum => :combined_cumret, 
      :datetime => (x->floor.(x,Month)) => :month)
   transform!(tradesummary_gb, retcol => cumsum => :provider_cumret)
   metadata!(tradesummary, "sortinoratio", MyMath.sortinoratio_annualized(df; logret_col=retcol)[1])
   metadata!(tradesummary, "dollar_profit", mean(df[!, Symbol(strategy_prefix, :_dollar_profit)]))
   metadata!(tradesummary, "log_ret", mean(df[!, retcol]))

   ### create monthsummary
	gb = groupby(Dawn.tradesummary, [:provider, :month])
	df = combine(gb, retcol => sum => :prov_mo_ret)
	global monthsummary_gb = groupby(df, :provider)
	global monthsummary = transform!(monthsummary_gb, :prov_mo_ret => cumsum => :prov_cum_mo_ret)	
   
   ### create monthsummary_combined
	df = combine(groupby(Dawn.monthsummary, :month), :prov_mo_ret => sum => :combined_mo_ret)
	transform!(df, :combined_mo_ret => cumsum => :combined_cum_mo_ret)
   global monthsummary_combined = df
   metadata!(monthsummary_combined, "sortinoratio", MyMath.sortinoratio_annualized(df; datetime_col=:month, logret_col=:combined_mo_ret)[1])
end
