################################################################################
"""
Controls a chain of providers that feed into a single trade provider. Used to:
- Track the execution status of provider tasks
- Generate combined trade data and summaries
- Manage exit strategy results
"""
mutable struct TradeProviderControl
   const providername::Symbol
   const runchain::Vector{sg.RunNode}  #the list of dependencies which feed into the trade provider
   const refchartsinks::Vector{sp.RefChartSink}  #Reference signals which have been setup by the TradingPlan. Each refchartsink is used to handle a single set of named columns, from any number of reference providers.

   ### Fields populated during summarization

   combineddata::Union{DataFrame, Nothing}  #all data from the runchain, including reference data. This is the data accessed by get_twodays_bm1() and get_bm1_row()
   trades::Union{DataFrame, Nothing}   #filtered combineddata to include only trades
   exitres::Union{DataFrame, Nothing}  #melted trades dataframe with rows corresponding to tradeactions like enter, exit, etc.
   exitprefixes::Set{Symbol}  #uniquely identifies exit strategies which have been detected in TradeProvider. These prefixes are used in column names of exitres

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
      new(providername, runchain, refchartsinks, nothing, nothing, nothing, Set{Symbol}())
   end
end

# Helper methods
function tradeprovider(ctrl::TradeProviderControl) ctrl.runchain[end].prov end

################################################################################
"""
Manages the execution and state of a complete trading operation. This structure contains
all global state related to trade runs to provide better organization and isolation.

This replaces TradeRunControl and consolidates previously global variables into a 
cohesive context object that includes:

- Management of multiple trade runs
- Tracking of current selection
- Provider mapping
- Trade summaries and analysis
- Navigation state for exploring trades
"""
mutable struct TradeRunContext
   # Management of trade runs
   traderuns::Vector{TradeRunControl}      # Collection of all trade runs
   selected_idx::Int                       # Index of currently selected trade run
   provname2provctrl::Dict{Symbol, TradeProviderControl}  # Quick lookup for providers
   
   # Trade analysis and summaries
   tradesummary::Union{Nothing, AbstractDataFrame}            # all trades
   tradesummary_gb::Union{Nothing, GroupedDataFrame}          # grouped by :provider
   
   monthsummary::Union{Nothing, AbstractDataFrame}            # return per month per provider
   monthsummary_gb::Union{Nothing, GroupedDataFrame}          # grouped by :provider
   monthsummary_combined::Union{Nothing, AbstractDataFrame}   # return per month summing all providers
   
   # Trade navigation state
   curtradectrl::Union{Nothing, TradeProviderControl}  # Currently selected trade control
   curtradeidx::Int                                    # Index of current trade
   curdate::Union{Nothing, UnixDate}                  # Current date being viewed
   curbday::Union{Nothing, AbstractDataFrame}         # Cache for current business day
   
   function TradeRunContext()
      new(TradeRunControl[], 0, Dict{Symbol, TradeProviderControl}(),
          nothing, nothing,
          nothing, nothing, nothing,
          nothing, -1, nothing, nothing)
   end
end

mutable struct TradeRunControl
   timecreated::DateTime
   timeexecuted::Union{DateTime, Nothing}
   timecompleted::Union{DateTime, Nothing}
   run_name::Symbol
   r::sg.TradeRun
   trprov_ctrls::Vector{TradeProviderControl}
   runtsks::Union{Nothing, Vector{Task}}  #we must wait for the tasks to complete before summarizing trades. Note that @sync is not designed for this because it only handles *lexically* enclosed @spawns
end
