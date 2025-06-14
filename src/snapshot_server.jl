"""
Optimized snapshot implementation that minimizes data transfer over RPC
Only sends raw combineddata and metadata, with all processing done client-side
"""

"""
This function creates a detailed snapshot for a specific asset over a given date range. It:
Saves the current traderun index
Extracts a single-asset plan from the original multi-asset trading plan
Creates a focused historical run with verbose data collection
Executes this targeted run and captures its snapshot
Restores the original traderun selection
The function exists to support detailed analysis of specific trading periods (typically used by get_twodays_verbose_summary to examine short timeframes) without running an entire backtest. This provides an efficient way to generate high-resolution data for visualization and analysis of specific trading events.
"""
function create_verbose_snapshot(traderun_idx::Int, provider_name::Symbol, startdate::UnixDate, enddate::UnixDate)::TradeRunSnapshot
	saved_traderun_idx = Dawn.selectedidx()

	origplan = Dawn.traderuns[Dawn.selectedidx()].info.r.spec.plan
	shortplan = sg.create_single_asset_plan(origplan, 
		split(String(provider_name), '!')...);
	shortrun::sg.RunSpec = sg.HistoricalRun(shortplan, DateInterval(startdate, enddate); verbose=true)

	createtraderun(@namevaluepair(shortrun)..., false)
	executetraderun(false)
	@time wait4traderun()
	ret = create_snapshot(nothing)
	Dawn.selecttraderun(saved_traderun_idx)		
	return ret
end

"""
Extract parameter metadata from a TradeProviderControl
"""
function extract_parameter_metadata(provctrl::TradeProviderControl)
	metadata = Dict{String, Any}()
	
	# Add any useful parameters from the trade provider
	tp = tradeprovider(provctrl)
	if haskey(tp.meta, :atrcol)
		metadata["atrcol"] = tp.meta[:atrcol]
	end
	
	return metadata
end

"""
Server-side function that returns minimal data for RPC transfer
"""
function create_snapshot(last_snapshot_time::Union{Nothing,DateTime})::TradeRunSnapshot
	ctx = currenttraderun()
	try
		lock_context(ctx)

		# Extract minimal data needed for client-side processing
		provider_data = []
		strategy_prefix = detect_strategy_prefix(ctx, :delayed60)

		for provctrl in ctx.trprov_ctrls
			# Summarize provider data and add to collection
			prov_data = summarize_provider_trades(provctrl, strategy_prefix, last_snapshot_time)
			push!(provider_data, prov_data)
		end

		return TradeRunSnapshot(
			Dawn.selectedidx(),
			provider_data,
			now(),
			last_snapshot_time,
			strategy_prefix
		)
	finally
		unlock_context(ctx)
	end
end

function lock_context(ctx::TradeRunContext)
	for provctrl in ctx.trprov_ctrls
		lock_runchain(provctrl, true)
	end
end

function unlock_context(ctx::TradeRunContext)
	for provctrl in ctx.trprov_ctrls
		lock_runchain(provctrl, false)
	end
end

function lock_runchain(provctrl::TradeProviderControl, dolock::Bool)
	for rn in provctrl.runchain
		if dolock
			lock(rn.prov)
		else
			unlock(rn.prov)
		end
	end
end
