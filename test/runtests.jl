using Revise, Test, MyFormats, Dates, MyPlots, PlotlyJS, Utils, TerminalPager
import PlotlyJS: SyncPlot
using Dawn, DawnPluto

# Dawn.sg.find_greatest_common_date_interval(Dawn.sg.plan_a1c)

begin
   deletetraderuns()

   createtraderun(:run_a1a_1, true)

   # ctrl = Dawn.provname2provctrl[:path_a2!BA]

   #=
   Multithreaded traderun may not work with Tensorflow.

   If you did createtraderun(...) with usecache=false, try executetraderun() with `julia -t 1,1 --project`

   Maybe access to MyPython should be through DataServer, so Python code always runs in main thread.
   =#
   executetraderun() 
   wait4traderun()
   summarizetrades()
end

plt=DawnPluto.plot_tradesummary().Plot



trun = Dawn.currenttraderun()

ctrl.combineddata

@testset "RefChartSink contains the expected columns" begin
   names = Dawn.get_reference_columnnames(ctrl.refchartsinks...)
   @info "Checking $names are in combineddata"
   @test issubset(names, propertynames(ctrl.combineddata))
end



refsink=trun.r.threadqueues[1].nodes[4].prov

row2 = Dawn.get_bm1_row(:path_a2!BA, DateTime("2022-01-21T15:08:00"))
structs2df(row2.mnodend_acts)


Dawn.selecttrade(:path_a2!BA, DateTime("2022-01-21T15:08:00"))

df=Dawn.get_twodays_bm1()
SyncPlot(MyPlots.mycandlestick(df; axis2_shared=[:VIX_close=>0.10, :SPY_close=>0.03]))

#DONE: render two days of data in response to chart click.
#DONE: add saving for TradeProvider

begin
   using DataStructures, DataFrames
   cols = Dict(:foo => [1,2,3], :mouse => [7,8,9],  :bar => [4,5,6])
   # df = DataFrame(collect(cols); copycols=false)
   df = DataFrame()
   push!(df, NamedTuple(collect(cols)); cols=:union)
   df
end
