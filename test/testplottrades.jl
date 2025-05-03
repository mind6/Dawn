using Revise, Test, MyFormats, Dates, MyPlots, PlotlyJS, Utils, TerminalPager
import PlotlyJS: SyncPlot
using Dawn, DawnPluto
import Strategies2 as sg
import Strategies2: @namevaluepair, path_a, path_a3

test_plan::sg.PlanSpec = sg.PlanNodeSpec[
	@namevaluepair(path_a3) =>["SPY"]=> ["TSLA"],
	@namevaluepair(path_a) =>["VIX"]=> ["VXX"]
]

# sg.find_greatest_common_date_interval(test_plan)

sg.test_run = sg.HistoricalRun(test_plan, DateInterval(Date("2018-01-18"), Date("2023-07-13")))

begin
	deletetraderuns()

	createtraderun(:test_run, true)
	trun = Dawn.currenttraderun()

	# ctrl = Dawn.provname2provctrl[:path_a2!BA]
	ctrl = Dawn.provname2provctrl[:path_a3!TSLA]

	#=
	Multithreaded traderun may not work with Tensorflow.

	If you did createtraderun(...) with usecache=false, try executetraderun() with `julia -t 1,1 --project`

	Maybe access to MyPython should be through DataServer, so Python code always runs in main thread.
	=#
	executetraderun() 
end

begin
	wait4traderun()
	summarizetrades()
end

plt=DawnPluto.plot_tradesummary().Plot

#TODO: get split events somehow into the charts

#= FIXME:

To see what was produced by the trade provider that produced the saved provider file:

	dropmissing(DataFrame(trun.trprov_ctrls[1].runchain[end].prov.data),:tradeaction)


Very mysterious failure around K:\DevDocuments\fourthwave\savedproviders\savedprovider_49e322fe8a94fae990e39e6bdd24bab1f7689a4e.jld2

When running plan with `@namevaluepair(path_a) => ["VXX"]`, the trade provider that produces this file generates all missing columns when run with Tensorflow, but outputs trades perfectly when running on a saved pipeline.

When running plan with `@namevaluepair(path_a3) => ["TSLA"]`, it works with Tensorflow.

I think it's just because I was interleaving tensorflow between two thread queues, which won't work even if Julia itself is running with a single thread.
=#