"""
Optimized snapshot implementation that minimizes data transfer over RPC
Only sends raw combineddata and metadata, with all processing done client-side
"""

"""
Server-side function that returns minimal data for RPC transfer
"""
function snapshot_summaries(last_snapshot_time::Union{Nothing, DateTime})::TradeRunSnapshot
    ctx = currenttraderun()
    try
        lock_context(ctx)
        
        # Extract minimal data needed for client-side processing
        provider_data = []
        strategy_prefix = :delayed60  # This should come from detect_strategy_prefix(ctx, :delayed60)
        
        for provctrl in ctx.trprov_ctrls
            # Get the AUT from the runchain
            AUT = provctrl.runchain[end].prov.meta[:AUT]
            
            # Get combined data and filter by time if needed
            combineddata = sp.combined_provider_data([[rn.prov for rn in provctrl.runchain]; provctrl.refchartsinks])
            
            if last_snapshot_time !== nothing
                start_idx = searchsortedfirst(combineddata.datetime, last_snapshot_time, lt=(<=))
                if start_idx <= nrow(combineddata)
                    combineddata = @view combineddata[start_idx:end, :]
                else
                    combineddata = @view combineddata[1:0, :]
                end
            end
            metadata!(combineddata, "symbol", AUT; style=:note)
            MyData.setcolumn_asindex!(combineddata, :datetime)            
				
            # Get reference columns
            refcols = get_reference_columnnames(provctrl.refchartsinks...)
            
            # Store only essential data
            push!(provider_data, (
                providername = provctrl.providername,
                combineddata = combineddata,
                refchart_colnames = refcols,
                AUT = AUT
            ))
        end
        
        return TradeRunSnapshot(
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