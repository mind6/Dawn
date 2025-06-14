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
	# Create the snapshot first
	snapshot = create_snapshot(last_snapshot_time)
	
	# Use client-side processing to build the summary
	summarize_snapshot(snapshot)
end

"""
Summarize trades for a single provider control
This function is now only used by server-side code
"""
function summarize_provider_trades(provctrl::TradeProviderControl, strategy_prefix::Symbol, last_snapshot_time::Union{Nothing, DateTime}=nothing)
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

	# Get reference columns and symbols
	refcols = get_reference_columnnames(provctrl.refchartsinks...)
	refsyms = get_reference_symbols(provctrl.refchartsinks...)
	
	# Extract parameter metadata from providers
	param_metadata = extract_parameter_metadata(provctrl)
	
	# Convert to format fast to serialize
	hidemissings!(combineddata)
	
	# Create provider data tuple
	return (
		providername=provctrl.providername,
		combineddata=combineddata,
		refchart_colnames=refcols,
		reference_symbols=refsyms,
		param_metadata=param_metadata,
		AUT=AUT
	)
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
