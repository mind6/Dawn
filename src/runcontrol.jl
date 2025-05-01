"""
Creates a TradeProviderControl for each TradeProvider in the TradeRun (i.e. across all thread queues).

Creates and manages a TradeRunControl object within the global tradecontext.

Note: The columns synchronized by refchartsinks can be customized in two ways:
1. At specification time in the PathSpec using the :ref_fields keyword argument
2. After creation using StreamProviders.update_ref_fields!(refchartsink, [column1, column2, ...])
"""
function createtraderun(run_name::Symbol, args...; kwargs...)
   createtraderun(run_name, getproperty(sg, run_name), args...; kwargs...)
end
function createtraderun(run_name::Symbol, runspec::sg.RunSpec, usecache::Bool=true; ignore_cache::Vector{Type{<:Provider}}=Type{<:Provider}[])
   r = sg.TradeRun(runspec, usecache; ignore_cache=ignore_cache)   
   sg.instantiate!(r)

   provctrls = TradeProviderControl[]
   for queue in r.threadqueues

      refchartsinks = collect(sp.RefChartSink, (n.prov for n in queue.nodes if n.prov isa sp.RefChartSink))

      for node in queue.nodes 
         if node.prov isa sp.AbsTradeProvider
            # Each threadqueue has a single AUT MinuteBarProvider, but possibly multiple TradeProviders and/or ReferenceSinks. We create a TradeProviderControl for each TradeProvider, and also give it all the RefChartSinks separately, since they are not dependencies of the TradeProvider.
            @assert node.vertinfo.color == :red "TradeProvider must be red"   
            provctrl = TradeProviderControl(node, refchartsinks)
            tradecontext.provname2provctrl[provctrl.providername] = provctrl
            push!(provctrls, provctrl)
         end
      end
   end
   push!(tradecontext.traderuns, TradeRunControl(Dates.now(), nothing, nothing, run_name, r, provctrls, nothing))
   tradecontext.selected_idx = length(tradecontext.traderuns)
end


"""
This is a nonblocking call. Use wait4traderun() to wait for it to complete.

NOTE:In the future this should create listeners for transaction requests and responses.
"""
function executetraderun(saveproviders::Bool=true)
   if tradecontext.selected_idx ∉ 1:length(tradecontext.traderuns)
      @error "no valid TradeRun selected at $(tradecontext.selected_idx)"
      return
   end

   trun = currenttraderun()
   if trun.timeexecuted !== nothing
      @error "selected trade run was created at $(trun.timecreated) and began executing at $(trun.timeexecuted)"
      return
   end
   trun.timeexecuted = Dates.now()

   sg.run!(trun.r, saveproviders) 
   trun.runtsks = copy(sg.runtsks)
end

function wait4traderun(trun::TradeRunControl=currenttraderun())
   for tsk in trun.runtsks
      wait(tsk)
   end
   trun.timecompleted = Dates.now()
end

"Delete all traderuns"
function deletetraderuns()
   Base.empty!(tradecontext.traderuns)
   tradecontext.selected_idx = 0
end

"""
If changing index, this calls 'summarizetrades()' if run has been executed.
"""
function selecttraderun(idx::Int)
   if idx == tradecontext.selected_idx return end

   n = length(tradecontext.traderuns)
   if idx in 1:n 
      tradecontext.selected_idx = idx
      trun = currenttraderun()
      if trun.timeexecuted !== nothing
         @info "resummarizing trades..."
         summarizetrades()
      end
      @info "selected $(tradecontext.selected_idx) of $n traderuns."
   else
      @error "cannot select $idx out of $n traderuns"
   end
end
