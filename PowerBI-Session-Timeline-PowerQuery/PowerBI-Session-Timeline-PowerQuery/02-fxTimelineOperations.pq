// Extracted unchanged from the validated fxBuildOverview operation parser.
// Invoke with the rows for ONE session; the caller groups by all six session keys.
(Rows as table) as table =>
let
    SuppliedColumns = {"Operation Time Minutes (Performed)","Non-Overlap Operation Time Minutes (Performed)","Overlap Minutes (Performed)"},
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
            Operations = Table.Group(WithOperationKey, {"OperationKey"}, {{"Result", (T) =>
                let
                    DistinctTimes = Table.Buffer(Table.Distinct(Table.SelectColumns(T, {"Patient CSN","ActualStart","ActualEnd","TimingProblem"}))),
                    Conflict = Table.RowCount(DistinctTimes) <> 1,
                    R = DistinctTimes{0},
                    Problem = if Conflict then "Conflicting patient or timing values for the same Log ID" else R[TimingProblem],
                    Reversed = R[ActualStart] <> null and R[ActualEnd] <> null and R[ActualEnd] < R[ActualStart],
                    // Never select one conflicting record or either end of a reversed interval.
                    // A missing boundary does not invalidate the other recorded boundary.
                    TrustedStart = if Conflict or Reversed then null else R[ActualStart],
                    TrustedEnd = if Conflict or Reversed then null else R[ActualEnd],
                    MissingID = R[Patient CSN]=null or Text.Trim(Text.From(R[Patient CSN]))="",
                    PatientKey = if MissingID then "Operation:" & T{0}[OperationKey] else "Patient:" & Text.From(R[Patient CSN]),
                    ValidOp = Problem=null,
                    SuppliedValue = (Name as text) as record =>
                        let
                            Raw = List.Select(Table.Column(T,Name),each _<>null and (not Value.Is(_,type text) or Text.Trim(_)<>"")),
                            ParsedValues = List.Transform(Raw,each if Value.Is(_,type number) then _ else if Value.Is(_,type text) then (try Number.FromText(Text.Trim(_),"en-GB") otherwise null) else null),
                            Good = List.Select(ParsedValues,each _<>null and not Number.IsNaN(_) and _>=0 and _<#infinity),
                            DistinctValues = List.Distinct(Good),
                            Invalid = List.Count(Good)<>List.Count(Raw) or List.Count(DistinctValues)>1,
                            Value = if not Conflict and not Invalid and List.Count(DistinctValues)=1 then DistinctValues{0} else null
                        in [Value=Value,Issue=Invalid],
                    Performed = SuppliedValue(SuppliedColumns{0}), NonOverlap = SuppliedValue(SuppliedColumns{1}), Overlap = SuppliedValue(SuppliedColumns{2})
                in [Start=R[ActualStart], End=R[ActualEnd], Problem=Problem, TrustedStart=TrustedStart, TrustedEnd=TrustedEnd,
                    PatientKey=PatientKey, MissingID=MissingID, ValidOp=ValidOp, Conflict=Conflict,
                    Reversed=not Conflict and Reversed, Missing=not Conflict and not Reversed and (R[ActualStart]=null or R[ActualEnd]=null),
                    SuppliedPerformed=Performed[Value], SuppliedNonOverlap=NonOverlap[Value], SuppliedOverlap=Overlap[Value],
                    SuppliedIssue=Conflict or Performed[Issue] or NonOverlap[Issue] or Overlap[Issue]], type record}}),
            Expanded = Table.Buffer(Table.ExpandRecordColumn(Operations,"Result",{"Start","End","Problem","TrustedStart","TrustedEnd","PatientKey","MissingID","ValidOp","Conflict","Reversed","Missing","SuppliedPerformed","SuppliedNonOverlap","SuppliedOverlap","SuppliedIssue"}))
in
    Expanded
