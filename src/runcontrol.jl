"""
Creates a TradeProviderControl for each TradeProvider in the TradeRun (i.e. across all thread queues).

Returns a TradeRunContext object which manages the trade run.

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
	provname2provctrl = Dict{Symbol, TradeProviderControl}()
	for queue in r.threadqueues

		refchartsinks = collect(sp.RefChartSink, (n.prov for n in queue.nodes if n.prov isa sp.RefChartSink))

		for node in queue.nodes 
			if node.prov isa sp.AbsTradeProvider
				# Each threadqueue has a single AUT MinuteBarProvider, but possibly multiple TradeProviders and/or ReferenceSinks. We create a TradeProviderControl for each TradeProvider, and also give it all the RefChartSinks separately, since they are not dependencies of the TradeProvider.
				@assert node.vertinfo.color == :red "TradeProvider must be red"	
				provctrl = TradeProviderControl(node, refchartsinks)
				provname2provctrl[provctrl.providername] = provctrl
				push!(provctrls, provctrl)
			end
		end
	end
	push!(traderuns, TradeRunContext(run_name, r, provctrls))
	global selected_idx = length(traderuns)
end


"""
This is a nonblocking call. Use wait4traderun() to wait for it to complete.

NOTE:In the future this should create listeners for transaction requests and responses.
"""
function executetraderun(saveproviders::Bool=true)
	if selected_idx ∉ 1:length(traderuns)
		@error "no valid TradeRun selected at $selected_idx"
		return
	end

	truncontext = currenttraderun()
	if truncontext.info.timeexecuted !== nothing
		@error "selected trade run was created at $(truncontext.info.timecreated) and began executing at $(truncontext.info.timeexecuted)"
		return
	end
	truncontext.info.timeexecuted = Dates.now()

	sg.run!(truncontext.info.r, saveproviders) 
	truncontext.info.runtsks = copy(sg.runtsks)
end

function wait4traderun(truncontext::TradeRunContext=currenttraderun())
	for tsk in truncontext.info.runtsks
		wait(tsk)
	end
	truncontext.info.timecompleted = Dates.now()
end

"Delete all traderuns"
function deletetraderuns()
	Base.empty!(traderuns)
	global selected_idx = 0
end

"""
If changing index, this calls 'summarizetrades()' if run has been executed.
"""
function selecttraderun(idx::Int)
	if idx == selected_idx return end

	n = length(traderuns)
	if idx in 1:n 
		global selected_idx = idx
		truncontext = currenttraderun()
		if truncontext.info.timeexecuted !== nothing
			@info "resummarizing trades..."
			summarizetrades()
		end
		@info "selected $selected_idx of $n traderuns."
	else
		@error "cannot select $idx out of $n traderuns"
	end
end
