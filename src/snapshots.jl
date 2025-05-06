"""
Briefly acquires semaphore locks on all stream providers.
Returns TradeRunSummary for the snapshot data.
"""
function snapshot_summaries(last_snapshot_time::Union{Nothing, DateTime})::TradeRunSummary
	ctx = currenttraderun()
	try
		lock_context(ctx)

		summary = summarizetrades(;last_snapshot_time=last_snapshot_time)
		
		return summary
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
