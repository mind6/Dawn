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
	ret =let
		selecttraderun(traderun_idx)

		origplan = Dawn.traderuns[Dawn.selectedidx()].info.r.spec.plan
		shortplan = sg.create_single_asset_plan(origplan, 
			split(String(provider_name), '!')...);
		shortrun::sg.RunSpec = sg.HistoricalRun(shortplan, DateInterval(startdate, enddate); verbose=true)

		createtraderun(@namevaluepair(shortrun)...; usecache=false)
		executetraderun(saveproviders=false)
		@time wait4traderun()
		create_snapshot(nothing)
	end
	Dawn.selecttraderun(saved_traderun_idx)		
	return ret
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
			(name=ctx.info.run_name, spec=ctx.info.r.spec),
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

"""
Lock or unlock the provctrl's runchain. 

A runchain is a chain of providers that ends with an AbsTradeProvider. It can have one or more MinuteBarProviders in the middle, each of which is driven by a separate thread.

The runchain is locked by acquiring the semaphore for each unique thread queue number in the runchain. Note that since semaphores are NOT reentrant, we cannot lock the same queue number twice.
"""
function lock_runchain(provctrl::TradeProviderControl, lockit::Bool=true)
	provs2lock = unique(prov -> prov.queue_num, [runnode.prov for runnode in provctrl.runchain])
	for prov in provs2lock
		@info "$(lockit ? "locking" : "unlocking") $(typeof(prov).name.name)'s queue numbered $(prov.queue_num)"
		if lockit
			sp.acquire_queue(prov)
		else
			sp.release_queue(prov)
		end
		end
	end

# Helper function to extract relevant parameters
function extract_parameter_metadata(provctrl::TradeProviderControl)::Dict{String, Any}
	metadata = Dict{String, Any}()
	
	for runnode in provctrl.runchain
		prov = runnode.prov
		# Check if provider has parameter with atrcol
		if hasfield(typeof(prov), :P) && hasfield(typeof(prov.P), :atrcol)
			metadata["atrcol"] = prov.P.atrcol
		end
		# Can extend for other important parameters
	end
	
	return metadata
end
