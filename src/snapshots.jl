SnapShotResult = @NamedTuple{provname2combineddata::Dict{Symbol, DataFrame}, tradesummary::DataFrame, monthsummary::DataFrame, monthsummary_combined::DataFrame}

"""
Briefly acquires semaphore locks on all stream providers.
Returns time of the combined dataframe from all providers, for all rows past last_snapshot_time.
"""
function snapshot_summaries(last_snapshot_time::Union{Nothing, DateTime})::SnapShotResult
	ctx = currenttraderun()
	try
		lock_context(ctx)

		summarizetrades(;last_snapshot_time=last_snapshot_time)
		provname2combineddata = Dict{Symbol, DataFrame}()
		for provctrl in ctx.trprov_ctrls
			provname2combineddata[provctrl.providername] = provctrl.combineddata
		end

		return SnapShotResult(tuple(provname2combineddata, ctx.tradesummary, ctx.monthsummary, ctx.monthsummary_combined))
	finally
		unlock_context(ctx)
	end
end

function lock_context(ctx::TradeRunContext)
	for provctrl in ctx.trprov_ctrls
		lock_runchain(provctrl)
	end
end

function unlock_context(ctx::TradeRunContext)
	for provctrl in ctx.trprov_ctrls
		unlock_runchain(provctrl)
	end
end

function lock_runchain(provctrl::TradeProviderControl)
	for runnode in provctrl.runchain
		sp.acquire_queue(runnode.prov)
	end
end

function unlock_runchain(provctrl::TradeProviderControl)
	for runnode in provctrl.runchain
		sp.release_queue(runnode.prov)
	end
end