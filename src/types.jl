################################################################################
"""
Summarization data for a single trade provider
"""
struct TradeProviderSummary
	providername::Symbol
	refchart_colnames::Vector{Symbol}
	combineddata::DataFrame  #all data from the runchain, including reference data
	trades::DataFrame        #filtered combineddata to include only trades
	exitres::DataFrame       #melted trades dataframe with rows corresponding to tradeactions like enter, exit, etc.
	exitprefixes::Set{Symbol}  #uniquely identifies exit strategies which have been detected in TradeProvider
end

################################################################################
"""
Complete summarization results for a trade run with navigation state
"""
mutable struct TradeRunSummary
	provider_summaries::Vector{TradeProviderSummary}
	provname2summary::Dict{Symbol, TradeProviderSummary}
	
	# Trade analysis and summaries
	summaries_excluded::Union{Nothing, DateTime}  #last_snapshot_time of trades that were excluded from the summary
	tradesummary::AbstractDataFrame               # all trades
	tradesummary_byprov::GroupedDataFrame            # grouped by :provider
	
	monthsummary::AbstractDataFrame              # return per month per provider
	monthsummary_byprov::GroupedDataFrame            # grouped by :provider
	monthsummary_combined::AbstractDataFrame     # return per month summing all providers
	
	# Trade navigation state (for browsing in remote process)
	curtradeprov_name::Union{Nothing, Symbol}    # Currently selected trade provider name
	curtradeidx::Int                             # Index of current trade
	curdate::Union{Nothing, UnixDate}           # Current date being viewed
	curbday::Union{Nothing, AbstractDataFrame}  # Cache for current business day
end

################################################################################
"""
Controls a chain of providers that feed into a single trade provider. Used to:
- Track the execution status of provider tasks
- Manage the provider chain configuration
"""
mutable struct TradeProviderControl
	const providername::Symbol
	const runchain::Vector{sg.RunNode}  #the list of dependencies which feed into the trade provider
	const refchartsinks::Vector{sp.RefChartSink}  #Reference signals which have been setup by the TradingPlan. Each refchartsink is used to handle a single set of named columns, from any number of reference providers.

	"""
	Given a RunNode that contains a AbsTradeProvider, finds the chain of RunNodes (with same AUT, where data is semantically dependent on the previous node in the chain) using breadsth-first-search (this results in nicer ordering of columns compared to DFS)

	Note that sg.ThreadQueues are one per MinuteBarProvider (driven from the front), this is one per AbsTradeProvider (driven from the back)
	"""
	function TradeProviderControl(tradeprov_node::sg.RunNode, refchartsinks::AbstractVector{<:sp.RefChartSink})
		@assert tradeprov_node.prov isa sp.AbsTradeProvider

		#create a runchain from the tradeprov_node to the AUT MinuteBarProvider
		runchain = sg.RunNode[tradeprov_node]
		assigned = Set{sg.RunNode}()
		push!(assigned, tradeprov_node)
		nextind = 1
		while nextind <= length(runchain)
			curnode = runchain[nextind]
			for parent in sg.incoming_same_AUT(curnode)
				if parent ∉ assigned
					@assert parent.prov.meta[:AUT] == curnode.prov.meta[:AUT] "AUT must be same with parent, even though pathname can be different"
					push!(runchain, parent)
					push!(assigned, parent)
				end
			end
			nextind += 1
		end
		reverse!(runchain)
		@infiltrate !allunique([rn.uuid for rn in runchain])
		@assert allunique([rn.uuid for rn in runchain]) "each runnode must have a unique uuid"

		@assert count(rn->rn.prov isa sp.AbsTradeProvider, runchain) == 1 "each runchain must have exactly one AbsTradeProvider"
		providername = Symbol(runchain[end].prov.meta[:pathname],'!', runchain[end].prov.meta[:AUT])
		new(providername, runchain, refchartsinks)
	end
end

# Helper methods
function tradeprovider(ctrl::TradeProviderControl) ctrl.runchain[end].prov end

################################################################################
"""
Contains the basic execution info for a trade run
"""
mutable struct TradeRunInfo
	timecreated::DateTime
	timeexecuted::Union{DateTime, Nothing}
	timecompleted::Union{DateTime, Nothing}
	run_name::Symbol
	r::sg.TradeRun
	runtsks::Union{Nothing, Vector{Task}}  #we must wait for the tasks to complete before summarizing trades. Note that @sync is not designed for this because it only handles *lexically* enclosed @spawns
	prog::Union{Nothing, ProgressMeter.AbstractProgress}
end

################################################################################
"""
Manages the execution of a trade run, replacing the previous TradeRunControl concept.

This structure contains:
- Provider controls for each trade provider
- Provider mapping for quick lookup

Multiple TradeRunContext objects can exist, with traderuns and selected_idx remaining as globals.
"""
mutable struct TradeRunContext
	info::TradeRunInfo
	trprov_ctrls::Vector{TradeProviderControl}
	
	# Provider mapping
	provname2provctrl::Dict{Symbol, TradeProviderControl}  # Quick lookup for providers
	
	function TradeRunContext(run_name::Symbol, r::sg.TradeRun, provctrls::Vector{TradeProviderControl})
		info = TradeRunInfo(Dates.now(), nothing, nothing, run_name, r, nothing, nothing)
		provname2provctrl = Dict{Symbol, TradeProviderControl}()
		for provctrl in provctrls
			provname2provctrl[provctrl.providername] = provctrl
		end
		new(info, provctrls, provname2provctrl)
	end
end
