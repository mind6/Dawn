using Test, Dawn, DataFrames, Dates, Statistics
using MyBase, Dates
import Strategies2: path_a, PlanNodeSpec, RunSpec, HistoricalRun, DateInterval

test_plan = PlanNodeSpec[
	@namevaluepair(path_a) => ["SPY"] =>["VXX"]
]

test_run::RunSpec = HistoricalRun(test_plan, DateInterval(Date(2019, 8, 1), Date(2019, 9,1)))

@testset verbose=true "Optimized Snapshot System" begin
    
    @testset "TradeRunSnapshot serialization" begin
        # Create a minimal snapshot
        snapshot = TradeRunSnapshot(
            [(providername=:test_provider,
              combineddata=DataFrame(datetime=[now()], close=[100.0], 
                                  exitstrat_onenter=[missing], tradeaction=[missing]),
              refchart_colnames=[:VIX_close, :SPY_close],
              AUT="SPY")],
            now(),
            nothing,
            :delayed60
        )
        
        # Test basic structure
        @test snapshot isa TradeRunSnapshot
        @test length(snapshot.provider_data) == 1
        @test snapshot.strategy_prefix == :delayed60
    end
    
    @testset "Client-side reconstruction" begin
        # Run a trade run to get real data
        deletetraderuns()
        createtraderun(@namevaluepair(test_run)..., true)
        executetraderun()
        wait4traderun()
        
        # Get snapshot from server
        snapshot = snapshot_summaries(nothing)
        
        # Test snapshot structure
        @test snapshot isa TradeRunSnapshot
        @test !isempty(snapshot.provider_data)
        
        # Verify combined data is preserved
        prov_data = first(snapshot.provider_data)
        @test prov_data.combineddata isa DataFrame
        @test :datetime in propertynames(prov_data.combineddata)
        @test :close in propertynames(prov_data.combineddata)
        
        # Reconstruct on client side
        reconstructed = Dawn.reconstruct_summary_from_snapshot(
            snapshot,
            Dawn.TradeProviderSummary,
            Dawn.TradeRunSummary, 
            Dawn.create_monthly_summaries,
            Dawn.sp
        )
        
        # Verify reconstruction produces valid TradeRunSummary
        @test reconstructed isa Dawn.TradeRunSummary
        @test length(reconstructed.provider_summaries) == length(snapshot.provider_data)
        
        # Get direct summary for comparison
        original = summarizetrades()
        
        # Compare key fields
        @test nrow(reconstructed.tradesummary) == nrow(original.tradesummary)
        @test Set(keys(reconstructed.provname2summary)) == Set(keys(original.provname2summary))
        
        # Test that combineddata is preserved and usable
        prov_summary = first(reconstructed.provider_summaries)
        @test !isempty(prov_summary.combineddata)
        @test prov_summary.combineddata === first(snapshot.provider_data).combineddata

        # Verify provider summary has data needed for get_twodays_bm1
        prov_summary = reconstructed.provname2summary[:path_a!VXX]
        @test !isempty(prov_summary.combineddata)
        @test :SPY_close in propertynames(prov_summary.combineddata)
    end
        
    @testset "Performance comparison" begin
        # Get real data
        original_summary = summarizetrades()
        snapshot = snapshot_summaries(nothing)
        
        # Compare data sizes
        original_size = sum(sizeof, [original_summary.tradesummary, 
                                   original_summary.monthsummary,
                                   original_summary.monthsummary_combined])
        
        snapshot_size = sum(sizeof, [pd.combineddata for pd in snapshot.provider_data])
        
        reduction_ratio = 1 - (snapshot_size / original_size)
        @info "Data size comparison: original=$original_size bytes, snapshot=$snapshot_size bytes"
        @info "Data size reduction: $(round(reduction_ratio * 100, digits=1))%"
        
        # We may not see huge reductions since we need to keep combineddata
        # but the structure is simpler and more direct
        @test snapshot_size <= original_size * 1.5
    end
end