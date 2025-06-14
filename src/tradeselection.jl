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
		summary.curdate = combineddata(provsummary).dateordinal[1]
		return (provname, nothing)
	else
		summary.curtradeidx = 1
		summary.curdate = provsummary.trades[1, :dateordinal]
		return (provname, provsummary.trades[1, :datetime])
	end
end

"""
Select a trade for navigation. Validates inputs before making any state changes.

Returns: (provider_name, trade_datetime)
"""
function selecttrade!(summary::TradeRunSummary, timeoftrade::Union{Nothing, DateTime}=nothing; 
                      provname::Union{Nothing, Symbol}=nothing)
	# Determine target provider
	target_prov = provname !== nothing ? provname : 
	              (summary.curtradeprov_name !== nothing ? summary.curtradeprov_name :
	               (!isempty(summary.provider_summaries) ? summary.provider_summaries[1].providername : nothing))
	
	if target_prov === nothing
		error("No provider selected or available")
	end
	
	# Validate provider exists
	if !haskey(summary.provname2summary, target_prov)
		error("Provider $(target_prov) not found in summary")
	end
	
	provsummary = summary.provname2summary[target_prov]
	if isempty(provsummary.trades)
		error("No trades found for provider $(target_prov)")
	end
	
	# Determine target trade index
	target_idx = 1
	if timeoftrade !== nothing
		try
			target_idx = MyData.getloc(provsummary.trades, timeoftrade)
		catch e
			error("Failed to locate trade at $(timeoftrade) for provider $(target_prov): $(e)")
		end
	end
	
	# All validations passed - update state
	summary.curtradeprov_name = target_prov
	summary.curtradeidx = target_idx
	summary.curdate = provsummary.trades[target_idx, :dateordinal]
	
	return (target_prov, provsummary.trades[target_idx, :datetime])
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
Navigate to next/previous day (cycles around).

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
	bm1 = combineddata(provsummary)
	
	if offset > 0
		ind = searchsortedlast(bm1.dateordinal, summary.curdate) + offset
	else
		ind = searchsortedfirst(bm1.dateordinal, summary.curdate) + offset
	end
	
	# Cycle around if out of bounds
	ind = MyMath.modind(ind, length(bm1.dateordinal))
	
	summary.curdate = bm1.dateordinal[ind]
	
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

"""
Navigate to the first day with data.

# Returns
Tuple of (provider_name, day)
"""
function firstday!(summary::TradeRunSummary)
	if summary.curtradeprov_name === nothing
		error("No provider selected. Call selecttrade! first")
	end
	
	provsummary = getcurrentprovsummary(summary)
	bm1 = combineddata(provsummary)
	
	if isempty(bm1.dateordinal)
		error("No data available for provider $(summary.curtradeprov_name)")
	end
	
	summary.curdate = bm1.dateordinal[1]
	
	return (summary.curtradeprov_name, summary.curdate)
end

"""
Navigate to the last day with data.

# Returns
Tuple of (provider_name, day)
"""
function lastday!(summary::TradeRunSummary)
	if summary.curtradeprov_name === nothing
		error("No provider selected. Call selecttrade! first")
	end
	
	provsummary = getcurrentprovsummary(summary)
	bm1 = combineddata(provsummary)
	
	if isempty(bm1.dateordinal)
		error("No data available for provider $(summary.curtradeprov_name)")
	end
	
	summary.curdate = bm1.dateordinal[end]
	
	return (summary.curtradeprov_name, summary.curdate)
end

"""
Set the selected trade to the first trade of the current day if one exists.

# Returns
Tuple of (provider_name, trade_datetime) or (provider_name, nothing) if no trade found
"""
function synctradetoday!(summary::TradeRunSummary)
	if summary.curtradeprov_name === nothing || summary.curdate === nothing
		error("No provider or date selected. Call selecttrade! first")
	end
	
	provsummary = getcurrentprovsummary(summary)
	dft = provsummary.trades
	
	if isempty(dft)
		return (summary.curtradeprov_name, nothing)
	end
	
	trade_ind = searchsortedfirst(dft.dateordinal, summary.curdate)
	if trade_ind ∈ 1:nrow(dft) && dft.dateordinal[trade_ind] == summary.curdate
		summary.curtradeidx = trade_ind
		return (summary.curtradeprov_name, dft.datetime[trade_ind])
	end
	
	return (summary.curtradeprov_name, nothing)
end

