using Revise, Dates
using Dawn, MyBase
import Strategies2 as sg
import Strategies2: path_a, PlanNodeSpec, RunSpec, HistoricalRun, DateInterval

ENV["JULIA_DEBUG"] = ""

test_plan = PlanNodeSpec[
	@namevaluepair(path_a) => ["SPY"] => ["VXX", "TSLA"]
]

test_run::RunSpec = HistoricalRun(test_plan, DateInterval(Date(2019, 8, 1), Date(2019, 9,1)))

begin
	deletetraderuns()

	createtraderun(@namevaluepair(test_run)..., true)
	executetraderun(true)
	wait4traderun()
	snapsummary = summarize_snapshot(create_snapshot(nothing))
end
Dawn.selectprovider!(snapsummary, :path_a!VXX)


curdate = Dawn.getcurrentdateid(snapsummary)
day_plan = sg.create_single_asset_plan(test_plan, 
	split(String(curdate[1]), '!')...);
day_run::RunSpec = HistoricalRun(day_plan, DateInterval(Date(curdate[2]), Date(curdate[2])+Day(1)))

createtraderun(@namevaluepair(day_run)..., false)
executetraderun(false)
wait4traderun()
snapsummary = summarize_snapshot(create_snapshot(nothing))


