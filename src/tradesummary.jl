#=
Summarization of trades
Used by selecttraderun() and updatetradedata()
=#
using DataFrames, ProgressMeter

"""
populate TradeProviderControls with dataframes that summarize the trades which have been requested (and executed).

Returns TradeRunSummary containing all trade summaries.
"""
function summarizetrades(;strategy_prefix::Symbol=:delayed60, last_snapshot_time::Union{Nothing, DateTime}=nothing)::TradeRunSummary
	ctx = currenttraderun()
	
	# Process each TradeProviderControl and prepare its data
	pbar = Progress(length(ctx.trprov_ctrls), desc="summarizing trades", showspeed=true, barlen=50)
	provider_summaries = TradeProviderSummary[]
	provname2summary = Dict{Symbol, TradeProviderSummary}()
	
	for provctrl in ctx.trprov_ctrls
		# Prepare provider data
		summary = summarize_provider_trades(provctrl, strategy_prefix, last_snapshot_time)
		push!(provider_summaries, summary)
		provname2summary[summary.providername] = summary
		next!(pbar)
	end
	finish!(pbar)
	@info "Creating merged trade summary"

	# Combine all provider trades into a single dataframe
	all_exitres = [summary.exitres for summary in provider_summaries]
	if isempty(all_exitres)
		@warn "No trade results found, " * (last_snapshot_time === nothing ? "have you called executetraderun()?" : "last_snapshot_time is $(last_snapshot_time).")
	end

	# Prepare return column and profit column identifiers
	retcol = Symbol(strategy_prefix, :_log_return)
	profit_col = Symbol(strategy_prefix, :_dollar_profit)

	### create the trade summary dataframe
	tradesummary = let df = vcat(all_exitres...; cols=:union)
		sort!(df, :datetime)
		colnames = propertynames(df)
		if !isempty(df) && (retcol ∉ colnames || profit_col ∉ colnames)
			error("Column $retcol or $profit_col not found in trade summary with $(nrow(df)) rows. The following columns are present: $colnames")
		end

		# Set up month column for monthly summaries
		df.month = Dates.floor.(df.datetime, Dates.Month)
		
		# Find the strategy prefix from trade providers if not provided
		detected_prefix = detect_strategy_prefix(ctx, strategy_prefix)
		if detected_prefix != strategy_prefix
			strategy_prefix = detected_prefix
			@info "Using detected strategy prefix: $strategy_prefix"
		end
		
		# Create aggregated metrics
		transform!(df, 
			retcol => cumsum => :combined_cumret)
		
		# Add metadata
		metadata!(df, "sortinoratio", MyMath.sortinoratio_annualized(df; logret_col=retcol)[1])
		metadata!(df, "dollar_profit", mean(df[!, profit_col]))
		metadata!(df, "log_ret", mean(df[!, retcol]))

		df
	end

	### create the grouped trade summary dataframe
	tradesummary_gb = let gdf = groupby(tradesummary, :provider)
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
	monthsummary, monthsummary_gb, monthsummary_combined = create_monthly_summaries(tradesummary, retcol)
	
	# Create the complete summary
	summary = TradeRunSummary(
		provider_summaries,
		provname2summary,
		last_snapshot_time,
		tradesummary,
		tradesummary_gb,
		monthsummary,
		monthsummary_gb,
		monthsummary_combined
	)
	
	# Store in the context for navigation
	ctx.summary = summary
	
	return summary
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
Create monthly summary dataframes
"""
function create_monthly_summaries(tradesummary::AbstractDataFrame, retcol::Symbol)
	# Monthly returns by provider
	gb = groupby(tradesummary, [:provider, :month])
	df = combine(gb, retcol => sum => :prov_mo_ret)
	monthsummary_gb = groupby(df, :provider)
	monthsummary = transform!(monthsummary_gb, :prov_mo_ret => cumsum => :prov_cum_mo_ret)
	
	# Monthly returns combined across all providers
	df = combine(groupby(monthsummary, :month), :prov_mo_ret => sum => :combined_mo_ret)
	transform!(df, :combined_mo_ret => cumsum => :combined_cum_mo_ret)
	monthsummary_combined = df
	metadata!(monthsummary_combined, "sortinoratio", MyMath.sortinoratio_annualized(df; datetime_col=:month, logret_col=:combined_mo_ret)[1])
	
	return (monthsummary, monthsummary_gb, monthsummary_combined)
end

"""
Summarize trades for a single provider control
"""
function summarize_provider_trades(provctrl::TradeProviderControl, strategy_prefix::Symbol, last_snapshot_time::Union{Nothing, DateTime}=nothing)::TradeProviderSummary
	@debug "Summarizing trades for $(provctrl.providername)"

	# Get the AUT (Asset Under Trade)
	AUT = provctrl.runchain[end].prov.meta[:AUT]
	
	# Create combined data from all providers in the runchain
	combineddata = let df = sp.combined_provider_data([[rn.prov for rn in provctrl.runchain]; provctrl.refchartsinks])
		if last_snapshot_time !== nothing
			# Find the first row index that is later than last_snapshot_time
			start_idx = searchsortedfirst(df.datetime, last_snapshot_time, lt=(<=))
			
			# Handle edge cases
			if start_idx > nrow(df)
				# No data after last_snapshot_time
				df = @view df[1:0, :]  # Empty view
			else
				df = @view df[start_idx:end, :]
			end
		end
		metadata!(df, "symbol", AUT; style=:note)
		MyData.setcolumn_asindex!(df, :datetime)
		df
	end
	
	# Extract trades
	trades = filter(:exitstrat_onenter => !ismissing, combineddata)
	metadata!(trades, "symbol", AUT; style=:note)
	MyData.setcolumn_asindex!(trades, :datetime)
	
	# Create exit results (melted trades dataframe)
	exitres = DataFrame(provider=[], datetime=DateTime[], tradeaction=MyFormats.TradeAction[])
	exitprefixes = Set{Symbol}()
	
	for trrow in eachrow(trades)
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
			push!(exitprefixes, pre)
		end
		
		push!(exitres, NamedTuple(newrow); cols=:union)
	end
	
	return TradeProviderSummary(
		provctrl.providername,
		combineddata,
		trades,
		exitres,
		exitprefixes
	)
end
