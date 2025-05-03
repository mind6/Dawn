#=
Debug specific trades or dates.
=#
using TerminalPager
using Revise, Dawn, MyBase, Dates, MyData
using StreamProviders
import StreamProviders as sp
import Strategies2: path_a1, PlanNodeSpec, RunSpec, HistoricalRun, DateInterval

# ENV["JULIA_DEBUG"] = "StreamProviders"
ENV["JULIA_DEBUG"] = ""

test_plan = PlanNodeSpec[
	@namevaluepair(path_a1) => ["SPY", "VIX"] => ["SOXL"]
]

testdate = Date("2020-06-15")
test_run::RunSpec = HistoricalRun(test_plan, DateInterval(testdate, testdate+Day(1)))

# @profview_allocs
begin
	deletetraderuns()

	createtraderun(@namevaluepair(test_run)..., false; ignore_cache=Type{<:Provider}[BasicStatsProvider, SparseStatsProvider,AbsTradeProvider])
end

begin
	executetraderun(false)

# ctrl = Dawn.provname2provctrl[:path_a3!TSLA]

	wait4traderun()
end

summarizetrades()

begin
	ctrl = Dawn.get_tradeprovctrl_by_providername(:path_a1!SOXL)

	start = DateTime("2020-06-15T09:30:00")
	rng = MyData.getrange(ctrl.combineddata, DateTime(start), DateTime(start+Hour(3)))
end
#TODO: look at entry candidates specifically for this asset and date
#TODO: look at trigger prices for unleveraged version of SOXL
df = ctrl.combineddata[rng, :] 

# df |> pager #NOTE:copy and paste into REPL for TerminalPager keys to work




