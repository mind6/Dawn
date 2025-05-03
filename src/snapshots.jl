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
	provs2lock = unique(prov->prov.queue_num, [runnode.prov for runnode in provctrl.runchain])
	for prov in provs2lock
		@info "$(lockit ? "locking" : "unlocking") $(typeof(prov).name.name)'s queue numbered $(prov.queue_num)"
		if lockit
			sp.acquire_queue(prov)
		else
			sp.release_queue(prov)
		end
	end
end

