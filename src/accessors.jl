#=
Read-only accessors for Dawn state.
=#
function get_tradeprovctrls()::AbstractVector{TradeProviderControl}
	if selected_idx ∉ 1:length(traderuns)
		@error "no valid TradeRun selected at $selected_idx"
		return
	end

	traderuns[selected_idx].trprov_ctrls
end

function get_reference_columnnames_from_symbols(reference_symbols::Vector{String}, ref_fields::Vector{Symbol}=[:close])::Vector{Symbol}
	cols = Symbol[]
	for sym in reference_symbols
		for field in ref_fields
			colname = sp.get_refdata_columnname(sym, field)
			push!(cols, colname)
		end
	end
	cols
end

function get_reference_columnnames(refchartsinks::sp.RefChartSink...)::Vector{Symbol}
	cols = Symbol[]
	for refsink in refchartsinks
		for aut in sp.get_reference_AUTs(refsink)
			for field in refsink.ref_fields
				colname = sp.get_refdata_columnname(aut, field)
				push!(cols, colname)
			end
		end
	end
	cols
end

function get_reference_symbols(refchartsinks::sp.RefChartSink...)::Vector{AbstractString}
	symbols = String[]
	for refsink in refchartsinks
		append!(symbols, sp.get_reference_AUTs(refsink))
	end
	symbols
end

function selectedidx() selected_idx end

function currenttraderun() traderuns[selected_idx] end


"""
Get current trade from summary.
"""
function getcurrenttrade(summary::TradeRunSummary)
	if summary.curtradeprov_name === nothing || summary.curtradeidx == 0
		return nothing
	end
	
	provsummary = getcurrentprovsummary(summary)
	provsummary.trades[summary.curtradeidx, :]
end

"""
Get current provider from summary.
"""
function getcurrentprovider(summary::TradeRunSummary)
	summary.curtradeprov_name
end

function getcurrentpathname(summary::TradeRunSummary)::Symbol
	Symbol(split(String(summary.curtradeprov_name), '!')[1])
end

function getcurrentprovsummary(summary::TradeRunSummary)
	if summary.curtradeprov_name === nothing
		return nothing
	end
	summary.provname2summary[summary.curtradeprov_name]
end


"""
Get current trade id from summary.
"""
function getcurrenttradeid(summary::TradeRunSummary)
	if summary.curtradeprov_name === nothing || summary.curtradeidx == 0
		return nothing
	end
	
	provsummary = getcurrentprovsummary(summary)
	(summary.curtradeprov_name, provsummary.trades[summary.curtradeidx, :datetime])
end

"""
Get current date id from summary.
"""
function getcurrentdateid(summary::TradeRunSummary)
	if summary.curtradeprov_name === nothing || summary.curdate === nothing
		return nothing
	end
	
	(summary.curtradeprov_name, summary.curdate)
end

"""
Get current day's minute bars from summary.
"""
function get_current_bm1(summary::TradeRunSummary)
	if summary.curtradeprov_name === nothing || summary.curdate === nothing
		return DataFrame()
	end
	
	provsummary = getcurrentprovsummary(summary)
	bm1 = combineddata(provsummary)
	
	bm1start = searchsortedfirst(bm1.dateordinal, summary.curdate)
	bm1end = searchsortedlast(bm1.dateordinal, summary.curdate)
	
	@view bm1[bm1start:bm1end, :]
end

"""
Get two days of minute bars from summary.
"""
function get_twodays_bm1(summary::TradeRunSummary)
	if summary.curtradeprov_name === nothing || summary.curdate === nothing
		return DataFrame()
	end
	
	provsummary = getcurrentprovsummary(summary)
	bm1 = combineddata(provsummary)
	
	bm1start = searchsortedfirst(bm1.dateordinal, summary.curdate)
	bm1end = searchsortedlast(bm1.dateordinal, summary.curdate)
	if bm1start != 1
		bm1start = searchsortedfirst(bm1.dateordinal, bm1.dateordinal[bm1start-1])
	end
	
	@view bm1[bm1start:bm1end, :]
end

"""
Get provider data for a specific provider name from a TradeRunSnapshot
"""
function get_provider_data(snapshot::TradeRunSnapshot, providername::Symbol)
	for prov_data in snapshot.provider_data
		if prov_data.providername == providername
			return prov_data
		end
	end
	return nothing
end

"""
Get current daily bar data from summary, enhanced with reference symbols' close data.
"""
function get_current_bday(summary::TradeRunSummary)
	dateid = getcurrentdateid(summary)
	if dateid === nothing
		return nothing
	end
	
	providername, curdate = dateid
	
	# Get provider data directly from source snapshot
	current_prov_data = get_provider_data(summary.source_snapshot, providername)
	if current_prov_data === nothing
		@warn "Provider data not found for $providername"
		return nothing
	end
	
	symbol = split(String(providername), '!')[2]
	
	# Create cache key that includes reference symbols to detect changes
	cache_key = string(symbol, "_", hash(current_prov_data.reference_symbols))
	
	# Cache invalidation - check if symbol or reference symbols changed
	if summary.curbday === nothing || metadata(summary.curbday, "cache_key", "") != cache_key
		# Load main asset's daily data
		base_bday = MyData.AssetData(symbol).bday
		
		# Enhance with reference data if available
		if !isempty(current_prov_data.reference_symbols)
			enhanced_bday = copy(base_bday)  # Start with main asset data
			ref_close_cols = Symbol[]
			
			# Add reference symbols' close data
			for ref_symbol in current_prov_data.reference_symbols
				try
					ref_bday = MyData.AssetData(ref_symbol).bday
					fieldname = :close
					ref_close_col = sp.get_refdata_columnname(ref_symbol, fieldname)
					push!(ref_close_cols, ref_close_col)
					
					# Join reference close data on date
					leftjoin!(enhanced_bday, 
						select(ref_bday, :dateordinal, fieldname => ref_close_col),
						on=:dateordinal)
				catch e
					@warn "Failed to load reference data for $ref_symbol: $e"
				end
			end
			
			summary.curbday = enhanced_bday
		else
			summary.curbday = base_bday
		end
		
		# Get atrcol from param_metadata if available
		atrcol = haskey(current_prov_data.param_metadata, "atrcol") ? 
			Symbol(current_prov_data.param_metadata["atrcol"]) : nothing
		
		# Set metadata for cache management and plotting
		metadata!(summary.curbday, "symbol", symbol; style=:note)
		metadata!(summary.curbday, "cache_key", cache_key; style=:note)
		metadata!(summary.curbday, "ref_close_cols", ref_close_cols; style=:note)
		metadata!(summary.curbday, "atrcol", atrcol; style=:note)
	end
	
	loc = searchsortedlast(summary.curbday.dateordinal, curdate)
	return (summary.curbday, loc)
end

"""
Get current trade summary row.
"""
function get_current_tradesummary_row(summary::TradeRunSummary)
	tradeid = getcurrenttradeid(summary)
	if tradeid === nothing
		error("No current trade selected")
	end
	
	provider, datetime = tradeid
	get_tradesummary_row(summary, provider, datetime)
end

"""
Get trade summary row from the grouped dataframe.
"""
function get_tradesummary_row(summary::TradeRunSummary, provider::Symbol, datetime::DateTime)
	subdf = summary.tradesummary_byprov[(provider, )]
	subdf[MyData.getloc(subdf.datetime, datetime), :]
end


"""
Get a row from combined data by datetime.
"""
function get_bm1_row(summary::TradeRunSummary, provname::Symbol, datetime::DateTime)
	provsummary = getcurrentprovsummary(summary)
	if provsummary === nothing
		return DataFrame()
	end
	df = combineddata(provsummary)
	df[MyData.getloc(df, datetime), :]
end

"""
Get a range of minute bars from combined data.
"""
function get_bm1_rows(summary::TradeRunSummary, provname::Symbol, date::UnixDate)
	provsummary = getcurrentprovsummary(summary)
	if provsummary === nothing
		return DataFrame()
	end
	bm1 = combineddata(provsummary)
	
	bm1start = searchsortedfirst(bm1.dateordinal, date)
	bm1end = searchsortedlast(bm1.dateordinal, date)
	
	@view bm1[bm1start:bm1end, :]
end

