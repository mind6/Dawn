#=
=#
using TerminalPager
using Revise, Dawn, MyBase, Dates, MyData
using StreamProviders
import StreamProviders as sp
import Strategies2: path_a1, PlanNodeSpec, RunSpec, DateInterval, RealtimeRun

ENV["JULIA_DEBUG"] = "StreamProviders"
# ENV["JULIA_DEBUG"] = ""

test_plan = PlanNodeSpec[
	@namevaluepair(path_a1) => ["TMV"]
]

test_run::RunSpec = RealtimeRun(test_plan, 4002)
deletetraderuns()
# tmp = AssetData("TMV")

# pc=MyData.MyPython.PythonCall
# pc.print("hi there")
createtraderun(@namevaluepair(test_run)..., false)
executetraderun()
# trun = currenttraderun()
# wait4traderun()

summarizetrades()


