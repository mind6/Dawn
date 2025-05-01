#=
Summarization of trades
Used by selecttraderun() and updatetradedata()
=#
using DataFrames, ProgressMeter

"Concatenate the trades and exit results from all TradeProviderControls with mdf.merge_dataframe()"
function summarizetrades()
   combined_trades_df = DataFrame[]
   pbar = Progress(length(get_tradeprovctrls()), desc="summarization", showspeed=true, barlen=40)
   for provctrl in get_tradeprovctrls()
      Dawn.summarize_trades(provctrl)
      push!(combined_trades_df, provctrl.trades)
      next!(pbar)
   end
   finish!(pbar)
   @info "merging trades"

   df = vcat(combined_trades_df...)
   @assert !isempty(df) "no trades were found. Have you called executetraderun()?"
   @debug "summary before merging" select(df, All())

   df = sort!(df, :datetime)
   df.month = Date.(df.datetime)
   df.month = lastdayofmonth.(df.month) #set new column to find months
   push!(df.dateordinal, missing) #add an extra row to work around the issue in merge_dataframe() with retcol when the last dateordinal is in a single group
   retcol = MyData.ensure_column_exists!(df, :log_ret, Float64, missing)
   df = MyMyFormats.merge_dataframe(df, :dateordinal, eachcol(df), retcol)
   pop!(df.dateordinal)

   for col in eachcol(df)
      if eltype(col) == Vector{Float64}
         col[nrow(df)] = first(col[nrow(df)]) #un-vectorize the last element, to wrok around the issue in merge_dataframe()
      end
   end

   if any(ismissing, df[!,retcol])
      @infiltrate 
      error("missing values found in col '$retcol'")
   end

   #get strategy prefix if it exists
   strategy_prefix::Symbol = :strategy0
   for tc in get_tradeprovctrls()#just find the last strategy
      meta_prefix = haskey(tradeprovider(tc).meta, :prefix) ? tradeprovider(tc).meta[:prefix] : Symbol()
      if meta_prefix !== Symbol()
         strategy_prefix = meta_prefix
      end
   end
   @info "trades merged. using strategy prefix $strategy_prefix"

   ### create tradesummary
   df.provider = [Symbol(r.providername) for r in eachrow(df)]

   @infiltrate selected_idx ∉ 1:length(traderuns)

   tradecontext.tradesummary = df
   tradecontext.tradesummary_gb = groupby(df, :provider)

   for grp in tradecontext.tradesummary_gb   #each provider can initiate at most one trade for each minute bar
      if !issorted(grp.datetime)
         @error "$(first(grp.provider)) trades are not sorted by datetime"
         @infiltrate
      end
   end

   # Check if the column exists, otherwise show a warning
   if retcol ∉ names(tradecontext.tradesummary)
      @warn "Column $retcol not found in tradesummary. It seems no trades were executed."
      return
   end

   # apply strategy prefix if possible
   transform!(tradecontext.tradesummary_gb, retcol => (x->MyMath.get_dolret.(x, prev=0.0)) => Symbol(strategy_prefix, :_dolret))
   transform!(tradecontext.tradesummary_gb, retcol => cumsum => :provider_cumret)
   metadata!(tradecontext.tradesummary, "sortinoratio", MyMath.sortinoratio_annualized(df; logret_col=retcol)[1])
   metadata!(tradecontext.tradesummary, "dollar_profit", mean(df[!, Symbol(strategy_prefix, :_dollar_profit)]))
   metadata!(tradecontext.tradesummary, "log_ret", mean(df[!, retcol]))

   ### create monthsummary
	gb = groupby(tradecontext.tradesummary, [:provider, :month])
	df = combine(gb, retcol => sum => :prov_mo_ret)
	tradecontext.monthsummary_gb = groupby(df, :provider)
	tradecontext.monthsummary = transform!(tradecontext.monthsummary_gb, :prov_mo_ret => cumsum => :prov_cum_mo_ret)	

   ### create monthsummary_combined
	df = combine(groupby(tradecontext.monthsummary, :month), :prov_mo_ret => sum => :combined_mo_ret)
	transform!(df, :combined_mo_ret => cumsum => :combined_cum_mo_ret)
   tradecontext.monthsummary_combined = df
   metadata!(tradecontext.monthsummary_combined, "sortinoratio", MyMath.sortinoratio_annualized(df; datetime_col=:month, logret_col=:combined_mo_ret)[1])
end

"(re)aggregate trades and their signals for the one TradeProviderControl"   
function summarize_trades(provctrl::TradeProviderControl) 
   @debug "summarize_trades($(provctrl.providername))"
   if provctrl.combineddata !== nothing && (provctrl.trades !== nothing || !haskey(provctrl.combineddata, :datetime))
      @debug "data already summarized, skipping."
      return 
   end

   combineddata = Dawn.combine_data_from_providers(provctrl.runchain)
   @debug "combined data" select(DataFrame(combineddata), All())

   provctrl.combineddata = combineddata
   if haskey(combineddata, :is_trade)
      provctrl.trades = filter(:is_trade => identity, combineddata)
      @debug "trades df" names(provctrl.trades) nrow(provctrl.trades)
   else
      error("no trades column found in the provider data of $(provctrl.providername). Have you called executetraderun()?")
   end

   provctrl.exitres = MyData.melt_trades(provctrl.trades) 
   @debug "exitres df" names(provctrl.exitres) nrow(provctrl.exitres)

   push!(provctrl.exitprefixes, map(r->"$(r.tradeaction)_", eachrow(provctrl.exitres))...)
   nothing
end

#extract and combine data from the providers in a runchain into one dataframe
function combine_data_from_providers(runchain::Vector{sg.RunNode})
   df = DataFrame()
   for node in runchain
      tskresult = TaskResult(node)
      if tskresult.failed
         error("task for provider $(node.prov.meta[:pathname]) failed: $(tskresult.error_message)")
      end

      oldncols = ncol(df)
      rename_func = if !hasproperty(tskresult, :df) # no summary view, use runresult directly
         @debug "no summary view for provider $(node.prov.meta[:pathname]). using runresult."
         rr = tskresult.runresult
         sp.get_all_columns(rr)
         rr.df
      elseif isempty(df)  # first one, don't prefix yet
         @debug "getting summary view for provider $(node.prov.meta[:pathname])."
         tskresult.df
      else   # regular cases, add provider pathname as prefix 
         @debug "getting summary view for provider $(node.prov.meta[:pathname]) and adding prefix."
         pname = String(node.prov.meta[:pathname])
         DataFrame([Symbol(pname,'_',String(symb))=>coldata for (symb,coldata) in pairs(eachcol(tskresult.df))])
      end

      MyData.merge_dataframe!(df, rename_func, :datetime)
      @debug "updated df" names(df) nrow(df) ncol(df)-oldncols
   end
   @assert issorted(df.datetime) 
   df
end
