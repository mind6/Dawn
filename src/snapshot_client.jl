#=
Client-side reconstruction of TradeRunSummary from minimal TradeRunSnapshot data
This module should be used on the client side that receives the TradeRunSnapshot via RPC
=#


"""
Creates a detailed trading summary for a specific two-day period with complete signal history.

This function runs a targeted historical backtest with verbose=true specifically for the 
currently selected date range. The verbose flag captures all intermediate calculations
and signal data that would be memory-prohibitive to store for an entire backtest.

The result is a TradeRunSummary containing detailed minute-by-minute trading signals,
enabling deep analysis of specific trading events without the memory overhead of
keeping verbose data for the entire trading history.
"""
function get_twodays_verbose_summary(summary::TradeRunSummary; localtraderun::Bool=false)::TradeRunSummary
	@assert getcurrentdateid(summary) !== nothing

	bm1_2day = Dawn.get_twodays_bm1(summary)
	startdate = bm1_2day[1,:dateordinal]
	enddate = bm1_2day[end,:dateordinal] + 1
	provider_name = Dawn.getcurrentprovider(summary)

	f = localtraderun ? create_verbose_snapshot : remote_create_verbose_snapshot
	verbose_snapshot = f(summary.source_snapshot.traderun_idx, provider_name, startdate, enddate)
	summarize_snapshot(verbose_snapshot)
end

"""
Client-side function to reconstruct TradeRunSummary from TradeRunSnapshot
"""
function summarize_snapshot(snapshot::TradeRunSnapshot)::TradeRunSummary
	provider_summaries = TradeProviderSummary[]
	provname2summary = Dict{Symbol, TradeProviderSummary}()
	
	# Process each provider's data
	for prov_data in snapshot.provider_data
		# convert from a format fast to serialize to the original format
		unhidemissings!(prov_data.combineddata)

		# Extract trades from combineddata
		trades = filter(:exitstrat_onenter => !ismissing, prov_data.combineddata)
		
		# Create exitres dataframe 
		exitres = DataFrame(provider=Symbol[], datetime=DateTime[], tradeaction=MyFormats.TradeAction[])
		exitprefixes = Set{Symbol}()
		
		for trade_row in eachrow(trades)
			colnames = [[:datetime, :tradeaction]; prov_data.refchart_colnames]
			
			newrow = Pair{Symbol, Any}[:provider => prov_data.providername, :AUT_close => trade_row.close]
			for colname in colnames
				push!(newrow, colname => trade_row[colname])
			end
			
			for strat in trade_row.exitstrat_onenter
				pre = sp.typeprefix(strat)
				push!(newrow, Symbol(pre, :_frac_return) => strat.frac_return)
				push!(newrow, Symbol(pre, :_log_return) => strat.log_return)
				push!(newrow, Symbol(pre, :_dollar_profit) => strat.dollar_profit)
				push!(newrow, Symbol(pre, :_elapsed) => strat.elapsed)
				push!(exitprefixes, pre)
			end
			
			push!(exitres, NamedTuple(newrow); cols=:union)
		end
		
		# Create provider summary using the new simplified structure
		summary = TradeProviderSummary(
			prov_data,     # Store a reference to the original provider_data
			trades,
			exitres,
			exitprefixes
		)
		
		push!(provider_summaries, summary)
		provname2summary[prov_data.providername] = summary
	end

	# Combine all provider trades into a single dataframe
	all_exitres = [summary.exitres for summary in provider_summaries]
	if isempty(all_exitres)
		@warn "No trade results found in snapshot."
	end

	# Prepare return column and profit column identifiers
	retcol = Symbol(snapshot.strategy_prefix, :_log_return)
	profit_col = Symbol(snapshot.strategy_prefix, :_dollar_profit)

	### create the trade summary dataframe
	tradesummary = let df = vcat(all_exitres...; cols=:union)
		sort!(df, :datetime)
		colnames = propertynames(df)
		if !isempty(df) && (retcol ∉ colnames || profit_col ∉ colnames)
			error("Column $retcol or $profit_col not found in trade summary with $(nrow(df)) rows. The following columns are present: $colnames")
		end

		# Set up month column for monthly summaries
		df.month = Dates.floor.(df.datetime, Dates.Month)
		
		# Create aggregated metrics
		transform!(df, 
			retcol => cumsum => :combined_cumret)
		
		# Add metadata
		metadata!(df, "sortinoratio", MyMath.sortinoratio_annualized(df; logret_col=retcol)[1]; style=:note)
		metadata!(df, "dollar_profit", mean(df[!, profit_col]); style=:note)
		metadata!(df, "log_ret", mean(df[!, retcol]); style=:note)
		metadata!(df, "tot_ret", sum(df[!, retcol]); style=:note)
		df
	end

	### report if the tradesummary matches the expected outcome
	trade_outcome = metadata(tradesummary)
	@info "[summarize_snapshot] tradesummary created with following results:\n$(repr(trade_outcome))"
	runname, runspec = snapshot.runinfo
	runname_str = TerminalStyles.YELLOW * String(runname) * TerminalStyles.END
	if runspec isa sg.HistoricalRun
		if isempty(runspec.expected_outcome)
			@info "[summarize_snapshot] $runname_str did not specify expected results"
		else
			haserror = false
			for (k, v) in runspec.expected_outcome
				if !haskey(trade_outcome, k)
					haserror = true
					@error "[summarize_snapshot] $runname_str expected result $k not found in tradesummary"
				elseif !isapprox(trade_outcome[k], v)
					haserror = true
					@error "[summarize_snapshot] $runname_str expected result $k = $v but got $(trade_outcome[k])"
				end
			end
			pass_str = haserror ? TerminalStyles.RED * "FAILED" * TerminalStyles.END : TerminalStyles.GREEN * "PASSED" * TerminalStyles.END
			@info "[summarize_snapshot] $runname_str $pass_str while expecting:\n$(repr(runspec.expected_outcome))"
		end
	else
		@info "[summarize_snapshot] $runname_str is a $(typeof(runspec))"
	end

	### create the grouped trade summary dataframe
	tradesummary_byprov = let gdf = groupby(tradesummary, :provider)
		# Validate grouped trades
		for grp in gdf
			if !issorted(grp.datetime)
				@error "$(first(grp.provider)) trades are not sorted by datetime"
			end
			if !allunique(grp.datetime)
				@warn "$(first(grp.provider)) has multiple trades at the same timestamp"
			end
		end
		transform!(gdf, retcol => cumsum => :provider_cumret)
		gdf
	end
	
	# Create monthly summaries
	monthsummary, monthsummary_byprov, monthsummary_combined = create_monthly_summaries(tradesummary, retcol)
	
	# Return the complete summary with initialized navigation state
	return TradeRunSummary(
		snapshot,          # Keep a reference to the original snapshot
		provider_summaries,
		provname2summary,
		tradesummary,
		tradesummary_byprov,
		monthsummary,
		monthsummary_byprov,
		monthsummary_combined,
		nothing,  # curtradectrl_name
		0,        # curtradeidx
		nothing,  # curdate
		nothing   # curbday
	)
end

"""
Create monthly summary dataframes
"""
function create_monthly_summaries(tradesummary::AbstractDataFrame, retcol::Symbol)
	# Monthly returns by provider
	gb = groupby(tradesummary, [:provider, :month])
	df = combine(gb, retcol => sum => :prov_mo_ret)
	monthsummary_byprov = groupby(df, :provider)
	monthsummary = transform!(monthsummary_byprov, :prov_mo_ret => cumsum => :prov_cum_mo_ret)
	
	# Monthly returns combined across all providers
	df = combine(groupby(monthsummary, :month), :prov_mo_ret => sum => :combined_mo_ret)
	transform!(df, :combined_mo_ret => cumsum => :combined_cum_mo_ret)
	monthsummary_combined = df
	metadata!(monthsummary_combined, "sortinoratio", MyMath.sortinoratio_annualized(df; datetime_col=:month, logret_col=:combined_mo_ret)[1]; style=:note)
	
	return (monthsummary, monthsummary_byprov, monthsummary_combined)
end
