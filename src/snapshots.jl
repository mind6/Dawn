"""
Briefly acquires semaphore locks on all stream providers.
Returns time of the combined dataframe from all providers, for all rows past last_snapshot_time.
"""
function snapshot_combined_data(last_snapshot_time::DateTime)::DataFrame
	
end


