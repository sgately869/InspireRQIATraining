(Rows as table) as table =>
let
    IsTimeOnly = (V as any) as logical =>
        if V = null then false
        else if Value.Is(V, type time) then true
        else if Value.Is(V, type number) then V >= 0 and V < 1
        else if Value.Is(V, type text) then (try Time.FromText(Text.Trim(V), [Culture="en-GB"]) otherwise null) <> null
        else false,
    AsDateTime = (V as any, D as date) as nullable datetime =>
        if V = null then null
        else if IsTimeOnly(V) then
            let T = try Time.From(V, "en-GB") otherwise null
            in if T = null then null else DateTime.From(D) + #duration(0, Time.Hour(T), Time.Minute(T), Time.Second(T))
        else try DateTime.From(V, "en-GB") otherwise null,
            Parsed = Table.AddColumn(Rows, "Timing", (R) =>
                let
                    RawStart = Record.Field(R, "Start Time"), RawEnd = Record.Field(R, "End Time"),
                    S0 = AsDateTime(RawStart, Record.Field(R, "Procedure Date")),
                    SlotStart = Record.Field(R, "Slot Start Time"), SlotEnd = Record.Field(R, "Slot End Time"),
                    DistanceFromSlot = (T as datetime) as number =>
                        if T < SlotStart then Duration.TotalSeconds(SlotStart-T)
                        else if T > SlotEnd then Duration.TotalSeconds(T-SlotEnd) else 0,
                    S = if S0 <> null and IsTimeOnly(RawStart) and S0 < SlotStart and Date.From(SlotEnd) > Date.From(SlotStart)
                        and DistanceFromSlot(S0 + #duration(1,0,0,0)) < DistanceFromSlot(S0) then S0 + #duration(1,0,0,0) else S0,
                    E0 = AsDateTime(RawEnd, if S = null then Record.Field(R, "Procedure Date") else Date.From(S)),
                    // An orphan end clock time in an explicitly overnight planned slot uses
                    // the same nearest-planned-interval day alignment as an orphan start.
                    // Full datetimes and paired start/end parsing retain their existing rules.
                    E = if S <> null and E0 <> null and E0 < S and IsTimeOnly(RawEnd) then E0 + #duration(1,0,0,0)
                        else if S = null and E0 <> null and IsTimeOnly(RawEnd) and Date.From(SlotEnd) > Date.From(SlotStart)
                            and DistanceFromSlot(E0 + #duration(1,0,0,0)) < DistanceFromSlot(E0) then E0 + #duration(1,0,0,0) else E0,
                    Problem = if S = null or E = null then "Missing or invalid actual Start Time / End Time"
                        else if E < S then "Actual End Time is before Start Time" else null
                in [ActualStart=S, ActualEnd=E, TimingProblem=Problem]),
            Times = Table.Buffer(Table.ExpandRecordColumn(Parsed, "Timing", {"ActualStart","ActualEnd","TimingProblem"})),
            WithOperationKey = Table.AddColumn(Times, "OperationKey", each
                if [Log ID] <> null then "Log:" & [Log ID]
                else "Timing:" & Binary.ToText(Json.FromValue({[Patient CSN],[ActualStart],[ActualEnd]}), BinaryEncoding.Base64), type text),

    ProcedureText = (T as table, ColumnName as text) as nullable text =>
        let
            Values = if Table.HasColumns(T, ColumnName) then Table.Column(T, ColumnName) else {},
            Cleaned = List.Transform(Values, each try Text.Trim(Text.From(_)) otherwise null),
            Names = List.Distinct(List.Select(Cleaned, each _ <> null and _ <> ""), Comparer.OrdinalIgnoreCase)
        in
            if List.IsEmpty(Names) then null else Text.Combine(Names, "; "),

    Operations = Table.Group(WithOperationKey,{"OperationKey"},{{"Result",(T)=>
        let
            DistinctTimes=Table.Distinct(Table.SelectColumns(T,{"Patient CSN","ActualStart","ActualEnd","TimingProblem"})),
            Conflict=Table.RowCount(DistinctTimes)<>1,
            R=DistinctTimes{0},
            Problem=if Conflict then "Conflicting patient or timing values for the same Log ID" else R[TimingProblem]
        in [
            Start = R[ActualStart],
            End = R[ActualEnd],
            ValidOp = Problem = null,
            #"Primary Procedure" = ProcedureText(T, "Primary Procedure"),
            #"Other Procedures" = ProcedureText(T, "Other Procedures")
        ],type record}}),
    Expanded=Table.ExpandRecordColumn(Operations,"Result",{"Start", "End", "ValidOp", "Primary Procedure", "Other Procedures"})
in Expanded
