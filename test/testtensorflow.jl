using Revise, Test, Dates
using Dawn, MyBase, MyFormats
import Strategies2 as sg
import Strategies2: @namevaluepair, path_a, path_b,path_a3

test_plan::sg.PlanSpec = sg.PlanNodeSpec[
	@namevaluepair(path_a) => ["TSLA"],
	# @namevaluepair(path_a) => ["VIX"] => ["VXX"],
	# @namevaluepair(path_b) => ["VIX"] => ["VXX"],

]

dateinterval = sg.find_greatest_common_date_interval(test_plan)

sg.test_run = sg.HistoricalRun(test_plan, DateInterval(Date("2019-08-01"), Date("2019-09-01")))
# sg.test_run = sg.HistoricalRun(test_plan, dateinterval)

begin
	deletetraderuns()

	createtraderun(:test_run, false)
	trun = Dawn.currenttraderun()

	# ctrl = Dawn.provname2provctrl[:path_a2!BA]
	# ctrl = Dawn.provname2provctrl[:path_a3!TSLA]

	#=
	Multithreaded traderun may not work with Tensorflow.

	If you did createtraderun(...) with usecache=false, try executetraderun() with `julia -t 1,1 --project`

	Maybe access to MyPython should be through DataServer, so Python code always runs in main thread.
	=#
	executetraderun() 
	wait4traderun()
	summarizetrades()
end


