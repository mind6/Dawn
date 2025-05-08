#=
Functions for navigating trades within a TradeRunSummary.

These functions replace the older navigation functions that worked with TradeRunContext.
The navigation state now lives with the TradeRunSummary, making it self-contained for RPC.
=#
"""
Switch to another provider.

# Arguments
- `summary`: The TradeRunSummary to navigate
- `provname`: Symbol of the provider to select

# Returns
Tuple of (provider_name, trade_datetime)
"""
function selectprovider!(summary::TradeRunSummary, provname::Symbol)
	if !haskey(summary.provname2summary, provname)
		error("Provider $provname not found in summary")
	end
	
	summary.curtradeprov_name = provname
	
	# Reset to first trade
	provsummary = getcurrentprovsummary(summary)
	if isempty(provsummary.trades)
		summary.curtradeidx = 0
		summary.curdate = nothing
		return (provname, nothing)
	else
		summary.curtradeidx = 1
		summary.curdate = provsummary.trades[1, :dateordinal]
		return (provname, provsummary.trades[1, :datetime])
	end
end

"""
Select a trade for navigation in the summary.

# Arguments
- `summary`: The TradeRunSummary to navigate
- `timeoftrade`: Optional DateTime to select a specific trade, default is the first trade
- `provname`: Optional Symbol to select a specific provider, default is the first provider

# Returns
Tuple of (provider_name, trade_datetime)
"""
function selecttrade!(summary::TradeRunSummary, timeoftrade::Union{Nothing, DateTime}=nothing; 
                      provname::Union{Nothing, Symbol}=nothing)
	# Set the current provider
	if provname !== nothing
		summary.curtradeprov_name = provname
	elseif summary.curtradeprov_name === nothing && !isempty(summary.provider_summaries)
		summary.curtradeprov_name = summary.provider_summaries[1].providername
	end
	
	if summary.curtradeprov_name === nothing
		error("No provider selected or available")
	end
	
	# Get the provider summary
	if !haskey(summary.provname2summary, summary.curtradeprov_name)
		error("No summary found for provider $(summary.curtradeprov_name)")
	end
	provsummary = summary.provname2summary[summary.curtradeprov_name]
	
	if isempty(provsummary.trades)
		error("No trades found for provider $(summary.curtradeprov_name)")
	end
	
	# Set the trade index
	summary.curtradeidx = timeoftrade === nothing ? 1 : MyData.getloc(provsummary.trades, timeoftrade)
	
	# Set the date
	summary.curdate = provsummary.trades[summary.curtradeidx, :dateordinal]
	
	return (summary.curtradeprov_name, provsummary.trades[summary.curtradeidx, :datetime])
end

"""
Navigate to next/previous trade (cycles around).

# Arguments
- `summary`: The TradeRunSummary to navigate
- `offset`: 1 for next trade, -1 for previous trade

# Returns
Tuple of (provider_name, trade_datetime)
"""
function nexttrade!(summary::TradeRunSummary, offset::Int=1)
	if summary.curtradeprov_name === nothing
		error("No provider selected. Call selecttrade! first")
	end
	
	provsummary = summary.provname2summary[summary.curtradeprov_name]
	if isempty(provsummary.trades)
		error("No trades found for current provider")
	end
	
	summary.curtradeidx = MyMath.modind(summary.curtradeidx + offset, nrow(provsummary.trades))
	summary.curdate = provsummary.trades[summary.curtradeidx, :dateordinal]
	
	return (summary.curtradeprov_name, provsummary.trades[summary.curtradeidx, :datetime])
end

"""
Navigate to previous trade.

# Returns
Tuple of (provider_name, trade_datetime)
"""
function prevtrade!(summary::TradeRunSummary)
	nexttrade!(summary, -1)
end

"""
Navigate to next/previous day.

# Arguments
- `summary`: The TradeRunSummary to navigate
- `offset`: 1 for next day, -1 for previous day

# Returns
Tuple of (provider_name, day)
"""
function nextday!(summary::TradeRunSummary, offset::Int=1)
	if summary.curtradeprov_name === nothing || summary.curdate === nothing
		error("No provider or date selected. Call selecttrade! first")
	end
	
	provsummary = getcurrentprovsummary(summary)
	bm1 = provsummary.combineddata
	
	if offset > 0
		ind = searchsortedfirst(bm1.dateordinal, summary.curdate) + offset
	else
		ind = searchsortedlast(bm1.dateordinal, summary.curdate) + offset
	end
	
	summary.curdate = bm1.dateordinal[ind]
	
	# Try to sync to a trade on this day
	dft = provsummary.trades
	trade_ind = searchsortedfirst(dft.dateordinal, summary.curdate)
	if trade_ind ∈ 1:nrow(dft) && dft.dateordinal[trade_ind] == summary.curdate
		summary.curtradeidx = trade_ind
	end
	
	return (summary.curtradeprov_name, summary.curdate)
end

"""
Navigate to previous day.

# Returns
Tuple of (provider_name, day)
"""
function prevday!(summary::TradeRunSummary)
	nextday!(summary, -1)
end

