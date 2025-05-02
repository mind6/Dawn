# TradeRunControl to TradeRunContext Refactor

## Overview
This refactor reorganizes the Dawn module by replacing `TradeRunControl` with `TradeRunContext` and restructuring how state is managed across the application.

## Key Changes

### 1. Type Structure Changes

**BEFORE:**
- `TradeRunControl` only contained execution metadata
- Per-run state scattered across module-level globals

**AFTER:**
- `TradeRunContext` encapsulates all per-run state
- `TradeRunInfo` contains execution metadata (moved inside `TradeRunContext`)
- Only minimal global state remains

### 2. New Type Definitions

**TradeRunInfo** (inner structure):
- `timecreated`, `timeexecuted`, `timecompleted`
- `run_name`, `r`, `runtsks`

**TradeRunContext** (main structure):
- `info: TradeRunInfo` - execution metadata
- `trprov_ctrls: Vector{TradeProviderControl}` - provider controls
- `provname2provctrl: Dict` - provider lookup
- `tradesummary`, `tradesummary_gb` - trade analysis
- `monthsummary`, `monthsummary_gb`, `monthsummary_combined` - monthly analysis
- `curtradectrl`, `curtradeidx`, `curdate`, `curbday` - navigation state

### 3. Global State Management

**Remaining Globals:**
```julia
const traderuns = TradeRunContext[]  # Collection of all contexts
selected_idx::Int = 0                # Currently selected run
```

**Moved to TradeRunContext:**
- `tradesummary` and related DataFrames
- `curtradectrl` and navigation state
- `provname2provctrl` mapping

### 4. Access Pattern Evolution

**BEFORE:**
```julia
# Direct global access
if selected_idx ∉ 1:length(traderuns)
if curtradectrl === nothing
```

**AFTER:**
```julia
# Through currenttraderun()
truncontext = currenttraderun()
if truncontext.curtradectrl === nothing
```

### 5. Function Updates

All functions now access state through the current context:

**createtraderun():**
- Creates `TradeRunContext` instead of `TradeRunControl`
- Populates context fields instead of globals

**summarizetrades():**
- Updates context fields instead of module globals
- Maintains per-context provider mappings

**Navigation functions:**
- Access and update state through context
- Use `currenttraderun()` to get active context

### 6. Benefits

1. **Better encapsulation**: State is logically grouped by run
2. **Multiple contexts**: Can maintain multiple run contexts
3. **Cleaner interface**: Fewer global variables to manage
4. **Thread safety**: Easier to isolate state between contexts
5. **Maintainability**: Clear structure for state management

## Migration Example

**Before:**
```julia
# Multiple globals to manage
tradesummary_gb[(provider,)]
curtradectrl.trades[curtradeidx,:]
```

**After:**
```julia
# All state accessed through context
truncontext = currenttraderun()
truncontext.tradesummary_gb[(provider,)]
truncontext.curtradectrl.trades[truncontext.curtradeidx,:]
```

## Backward Compatibility

- All external function signatures remain unchanged
- `testsnapshots.jl` and other tests work without modification
- API functions like `currenttraderun()` maintain compatibility

## Testing

The refactored code maintains full compatibility with existing tests including `testsnapshots.jl`.
