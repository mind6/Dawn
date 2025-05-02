# TradeRunControl to TradeRunContext Refactoring Diagrams

## 1. Before and After Class Structure

```mermaid
graph TD
    %% BEFORE REFACTORING
    subgraph before[Before Refactoring]
        TRC[TradeRunControl]
        TRC --> |has| props1(timecreated<br/>timeexecuted<br/>timecompleted<br/>run_name<br/>r<br/>trprov_ctrls<br/>runtsks)
        
        DawnGlobals[Dawn Module Globals]
        DawnGlobals --> |contains| globalsProps(traderuns<br/>selected_idx<br/>provname2provctrl<br/>tradesummary<br/>tradesummary_gb<br/>monthsummary<br/>monthsummary_gb<br/>monthsummary_combined<br/>curtradectrl<br/>curtradeidx<br/>curdate<br/>curbday)
    end
    
    %% AFTER REFACTORING  
    subgraph after[After Refactoring]
        TRI[TradeRunInfo]
        TRI --> |has| infoProps(timecreated<br/>timeexecuted<br/>timecompleted<br/>run_name<br/>r<br/>runtsks)
        
        TRCnew[TradeRunContext]
        TRCnew --> |contains| info[info: TradeRunInfo]
        TRCnew --> |contains| providerProps(trprov_ctrls<br/>provname2provctrl)
        TRCnew --> |contains| summaryProps(tradesummary<br/>tradesummary_gb<br/>monthsummary<br/>monthsummary_gb<br/>monthsummary_combined)
        TRCnew --> |contains| navProps(curtradectrl<br/>curtradeidx<br/>curdate<br/>curbday)
        
        DawnGlobalsNew[Updated Dawn Globals]
        DawnGlobalsNew --> |contains| miniGlobals(traderuns<br/>selected_idx)
    end
```

## 2. State Organization

```mermaid
flowchart TD
    subgraph before[Before Refactoring]
        direction LR
        globalState[All State as Module Globals]
        globalState --> categories[12 different global variables]
    end
    
    subgraph after[After Refactoring]
        direction LR
        minimalGlobals[Minimal Globals]
        minimalGlobals --> |only| globalVars[traderuns & selected_idx]
        
        context[TradeRunContext]
        context --> |encapsulates| sections[4 logical sections]
        sections --> section1[Execution Info]
        sections --> section2[Provider Management]
        sections --> section3[Trade Analysis]
        sections --> section4[Navigation State]
    end
```

## 3. Function Data Flow

```mermaid
sequenceDiagram
    participant User
    participant Dawn
    participant Context as TradeRunContext
    participant Provider as TradeProviderControl
    
    Note over User,Dawn: After Refactoring
    
    User->>Dawn: createtraderun()
    Dawn->>Context: create()
    Context->>Provider: create provider controls
    Provider-->>Context: return controls
    Dawn->>Dawn: add to traderuns[]
    Dawn->>Dawn: update selected_idx
    
    User->>Dawn: summarizetrades()
    Dawn->>Dawn: get currenttraderun()
    Dawn->>Context: process data
    Context->>Provider: summarize_trades() 
    Provider-->>Context: return data
    Context->>Context: update summaries
    
    User->>Dawn: selecttrade()
    Dawn->>Dawn: get currenttraderun()
    Dawn->>Context: set navigation
    Context->>Context: update navigation state
```

## 4. Global Variables Transition

```mermaid
flowchart LR
    subgraph before[Before]
        style before fill:#FFE4E1
        globalsBefore[Global Variables]
        globalsBefore --> v1[traderuns]
        globalsBefore --> v2[selected_idx]
        globalsBefore --> v3[provname2provctrl]
        globalsBefore --> v4[summaries]
        globalsBefore --> v5[navigation state]
    end
    
    subgraph after[After]
        style after fill:#E6FFE6
        globalsAfter[Global Variables]
        globalsAfter --> gv1[traderuns]
        globalsAfter --> gv2[selected_idx]
        
        context[TradeRunContext]
        context --> cv1[provname2provctrl]
        context --> cv2[summaries]
        context --> cv3[navigation state]
    end
    
    before --transition--> after
```

## 5. TradeRunContext Structure

```mermaid
flowchart TD
    context[TradeRunContext]
    
    context --> section1[Execution Info]
    section1 --> info[info: TradeRunInfo]
    info --> infoFields[timecreated<br/>timeexecuted<br/>timecompleted<br/>run_name<br/>r<br/>runtsks]
    
    context --> section2[Provider Management]
    section2 --> trprov[trprov_ctrls]
    section2 --> provmap[provname2provctrl]
    
    context --> section3[Trade Analysis]
    section3 --> ts[tradesummary]
    section3 --> tsgb[tradesummary_gb]
    section3 --> ms[monthsummary]
    section3 --> msgb[monthsummary_gb]
    section3 --> msc[monthsummary_combined]
    
    context --> section4[Navigation State]
    section4 --> curtc[curtradectrl]
    section4 --> curti[curtradeidx]
    section4 --> curd[curdate]
    section4 --> curb[curbday]
    
    style section1 fill:#B0E2FF
    style section2 fill:#B4EEB4
    style section3 fill:#FFE4B5
    style section4 fill:#DDA0DD
```

## 6. Access Pattern Changes

```mermaid
sequenceDiagram
    participant Code as Client Code
    
    rect rgb(255,230,230)
    Note right of Code: BEFORE: Direct global access
    Code->>Code: current = traderuns[selected_idx]
    Code->>Code: provCtrl = provname2provctrl[name]
    Code->>Code: trade = curtradectrl.trades[curtradeidx]
    end
    
    rect rgb(230,255,230)
    Note right of Code: AFTER: Through context
    Code->>Code: context = currenttraderun()
    Code->>Code: provCtrl = context.provname2provctrl[name]
    Code->>Code: trade = context.curtradectrl.trades[context.curtradeidx]
    end
```

## 7. Overall Architecture

```mermaid
graph TB
    subgraph Dawn[Dawn Module]
        globals[Minimal Globals<br/>traderuns&#91;&#93;<br/>selected_idx]
        
        subgraph context[TradeRunContext Array]
            ctx1[Context 1]
            ctx2[Context 2]
            ctx3[Context N]
        end
        
        funcs[Module Functions<br/>createtraderun<br/>summarizetrades<br/>selecttrade<br/>etc]
    end
    
    subgraph context_detail[Each Context Contains]
        exec[Execution Info]
        prov[Provider Management]
        analysis[Trade Analysis]
        nav[Navigation State]
    end
    
    globals --> context
    context --> funcs
    funcs -.-> context_detail
```


These diagrams have been revised to use valid Mermaid syntax that should render properly in most environments. The changes include:

1. Using `graph` instead of `classDiagram` where appropriate
2. Removing quotes from class names that may cause parsing issues
3. Using simpler subgraph structures
4. Replacing some complex diagrams with more straightforward alternatives

All diagrams now focus on showing the structural and logical changes in the refactoring, rather than trying to represent exact class structure with properties and methods.

