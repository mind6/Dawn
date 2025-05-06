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

function get_tradeprovctrl_by_providername(providername::Symbol)::TradeProviderControl
	truncontext = currenttraderun()
	if !haskey(truncontext.provname2provctrl, providername)
		error("trade control for $providername not found. Have you called `summarizetrades()`?")
	end
	truncontext.provname2provctrl[providername]
end

function get_reference_columnnames(refchartsinks::sp.RefChartSink...)::Vector{Symbol}
	cols = Symbol[]
	for refsink in refchartsinks
		for aut in Dawn.sp.get_referencenAUTs(refsink)
			for field in refsink.ref_fields
				colname = Dawn.sp.get_refdata_columnname(refsink, aut, field)
				push!(cols, colname)
			end
		end
	end
	cols
end


function selectedidx() selected_idx end

function currenttraderun() traderuns[selected_idx] end

