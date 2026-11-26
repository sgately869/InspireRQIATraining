let
    Source = Table.SelectColumns(PreparedData, {
        "Procedure Date", "Hospital", "Operating Theatre", "Theatre Type", "Session",
        "Session [Responsible Consultant]", "Patient CSN", "Log ID", "Primary Procedure",
        "Other Procedures", "Start Time", "End Time", "Slot Start Time", "Slot End Time",
        "Operation Time minutes (Scheduled)"
    }),

    HasText = (Value as nullable text) as logical =>
        Value <> null and Text.Trim(Text.Replace(Value, Character.FromNumber(160), " ")) <> "",

    Identifier = (Value as any) as nullable text =>
        let TextValue = try Text.Trim(Text.From(Value, "en-GB")) otherwise null
        in if HasText(TextValue) then TextValue else null,

    IsClockOnly = (Value as any) as logical =>
        if Value.Is(Value, type time) then true
        else if Value.Is(Value, type number) then Value >= 0 and Value < 1
        else if Value.Is(Value, type text)
            then (try Time.FromText(Text.Trim(Value), [Culture = "en-GB"]) otherwise null) <> null
        else false,

    ToDateTime = (Value as any, Day as nullable date, ClockOnly as logical) as nullable datetime =>
        if Value = null then null
        else if ClockOnly then
            let Clock = try Time.From(Value, "en-GB") otherwise null
            in if Clock = null or Day = null then null
                else DateTime.From(Day) + #duration(0, Time.Hour(Clock), Time.Minute(Clock), Time.Second(Clock))
        else if Value.Is(Value, type date)
            or (Value.Is(Value, type text) and not Text.Contains(Value, ":")
                and (try Date.FromText(Text.Trim(Value), [Culture = "en-GB"]) otherwise null) <> null)
        then null
        else try DateTime.From(Value, "en-GB") otherwise null,

    ParseRow = (Row as record) as record =>
        let
            Day = Row[Procedure Date],
            SlotStart = Row[Slot Start Time],
            SlotEnd = Row[Slot End Time],
            IsOvernight = SlotStart <> null and SlotEnd <> null and Date.From(SlotEnd) > Date.From(SlotStart),
            RawStart = try Row[Start Time] otherwise null,
            RawEnd = try Row[End Time] otherwise null,
            StartClockOnly = IsClockOnly(RawStart),
            EndClockOnly = IsClockOnly(RawEnd),
            StartCandidate = ToDateTime(RawStart, Day, StartClockOnly),
            DistanceFromSlot = (Stamp as datetime) as number =>
                if Stamp < SlotStart then Duration.TotalSeconds(SlotStart - Stamp)
                else if Stamp > SlotEnd then Duration.TotalSeconds(Stamp - SlotEnd)
                else 0,
            ActualStart =
                if IsOvernight and StartClockOnly and StartCandidate <> null and StartCandidate < SlotStart
                    and DistanceFromSlot(StartCandidate + #duration(1, 0, 0, 0)) < DistanceFromSlot(StartCandidate)
                then StartCandidate + #duration(1, 0, 0, 0)
                else StartCandidate,
            EndDay = if ActualStart = null then Day else Date.From(ActualStart),
            EndCandidate = ToDateTime(RawEnd, EndDay, EndClockOnly),
            ActualEnd =
                if IsOvernight and EndClockOnly and ActualStart <> null and EndCandidate <> null
                    and Date.From(ActualStart) < Date.From(SlotEnd) and EndCandidate < ActualStart
                then EndCandidate + #duration(1, 0, 0, 0)
                else EndCandidate,
            ValidPair = ActualStart <> null and ActualEnd <> null and ActualEnd > ActualStart,
            PatientID = Identifier(try Row[Patient CSN] otherwise null),
            LogID = Identifier(try Row[Log ID] otherwise null),
            TimingKey = if PatientID <> null and ValidPair then
                "Timing|" & Binary.ToText(Json.FromValue({PatientID, ActualStart, ActualEnd}), BinaryEncoding.Hex)
                else null,
            PrimaryName = try if Value.Is(Row[Primary Procedure], type text)
                then Row[Primary Procedure] else null otherwise null,
            HasSecondary = try
                if Row[Other Procedures] = null then false
                else if Value.Is(Row[Other Procedures], type text) then HasText(Row[Other Procedures])
                else true
                otherwise true,
            RawBooked = try Row[#"Operation Time minutes (Scheduled)"] otherwise null,
            Booked = if Value.Is(RawBooked, type text) or Value.Is(RawBooked, type number)
                then try Number.From(RawBooked, "en-GB") otherwise null
                else null
        in [
            #"Actual Start" = ActualStart,
            #"Actual End" = ActualEnd,
            #"Valid Pair" = ValidPair,
            #"Patient ID" = PatientID,
            #"Log Key" = if LogID = null then null else "Log|" & LogID,
            #"Timing Key" = TimingKey,
            #"Primary Name" = PrimaryName,
            #"Has Secondary" = HasSecondary,
            #"Booked Value" = if Booked <> null and Booked > 0 and Booked < #infinity then Booked else null
        ],

    WithParsed = Table.AddColumn(Source, "Parsed", each ParseRow(_), type record),
    ParsedFields = {
        "Actual Start", "Actual End", "Valid Pair", "Patient ID", "Log Key", "Timing Key",
        "Primary Name", "Has Secondary", "Booked Value"
    },
    Parsed = Table.ExpandRecordColumn(WithParsed, "Parsed", ParsedFields),
    CaseFields = {
        "Procedure Date", "Hospital", "Operating Theatre", "Theatre Type",
        "Session", "Session [Responsible Consultant]"
    },
    Narrow = Table.SelectColumns(Parsed, CaseFields & ParsedFields),
    Identifiable = Table.Buffer(Table.SelectRows(Narrow, each [Log Key] <> null or [Timing Key] <> null)),
    Logged = Table.SelectRows(Identifiable, each [Log Key] <> null),
    Unlogged = Table.SelectRows(Identifiable, each [Log Key] = null),
    LoggedKeys = Table.AddColumn(Logged, "Operation Key", each [Log Key], type text),
    // Resolve an unlogged duplicate only when its exact patient and interval identify one logged operation.
    LogMatches = Table.Group(
        Table.SelectRows(Logged, each [Timing Key] <> null),
        {"Timing Key"},
        {{"Matched Log Keys", each List.Distinct([Log Key], Comparer.Ordinal), type list}}
    ),
    UnloggedMatches = Table.NestedJoin(Unlogged, {"Timing Key"}, LogMatches, {"Timing Key"}, "Log Match", JoinKind.LeftOuter),
    UnloggedKeys = Table.AddColumn(UnloggedMatches, "Operation Key", each
        let Keys = if Table.IsEmpty([Log Match]) then {} else [Log Match]{0}[Matched Log Keys]
        in if List.IsEmpty(Keys) then [Timing Key] else if List.Count(Keys) = 1 then Keys{0} else null,
        type nullable text
    ),
    Keyed = if Table.IsEmpty(Unlogged) then LoggedKeys else Table.Combine({
        LoggedKeys,
        Table.RemoveColumns(Table.SelectRows(UnloggedKeys, each [Operation Key] <> null), {"Log Match"})
    }),

    Label = (Values as list) as text =>
        let Names = List.Distinct(List.RemoveNulls(List.Transform(Values, each Identifier(_))), Comparer.OrdinalIgnoreCase)
        in if List.IsEmpty(Names) then "Unspecified" else if List.Count(Names) = 1 then Names{0} else "Mixed / multiple",

    MakeCase = (Rows as table) as nullable record =>
        let
            PrimaryNames = List.Distinct(List.Select(Rows[Primary Name], each HasText(_)), Comparer.Ordinal),
            HasSecondary = List.AnyTrue(Rows[Has Secondary]),
            Days = List.Distinct(List.RemoveNulls(Rows[Procedure Date])),
            Patients = List.Distinct(List.RemoveNulls(Rows[Patient ID]), Comparer.Ordinal),
            Starts = List.Distinct(List.RemoveNulls(Rows[Actual Start])),
            Ends = List.Distinct(List.RemoveNulls(Rows[Actual End])),
            CanUseCase =
                List.Count(PrimaryNames) = 1 and not HasSecondary and List.Count(Days) = 1
                and List.Count(Patients) <= 1 and List.Count(Starts) = 1 and List.Count(Ends) = 1
                and List.AnyTrue(Rows[Valid Pair])
        in
            if not CanUseCase then null
            else
                let Bookings = List.Distinct(List.RemoveNulls(Rows[Booked Value]))
                in [
                    #"Procedure Date" = Days{0},
                    Hospital = Label(Rows[Hospital]),
                    #"Operating Theatre" = Label(Rows[Operating Theatre]),
                    #"Theatre Type" = Label(Rows[Theatre Type]),
                    #"Session Specialty" = Label(Rows[Session]),
                    #"Responsible Consultant" = Label(Table.Column(Rows, "Session [Responsible Consultant]")),
                    #"Primary Procedure" = PrimaryNames{0},
                    #"Procedure Key" = Binary.ToText(Text.ToBinary(PrimaryNames{0}, TextEncoding.Utf8), BinaryEncoding.Hex),
                    #"Actual Minutes" = Duration.TotalMinutes(Ends{0} - Starts{0}),
                    #"Booked Minutes" = if List.Count(Bookings) = 1 then Bookings{0} else null
                ],

    GroupedOperations = Table.Group(Keyed, {"Operation Key"}, {{"Case", each MakeCase(_), type nullable record}}),
    CaseType = type table [
        #"Procedure Date" = date, Hospital = text, #"Operating Theatre" = text, #"Theatre Type" = text,
        #"Session Specialty" = text, #"Responsible Consultant" = text, #"Primary Procedure" = text,
        #"Procedure Key" = text, #"Actual Minutes" = number, #"Booked Minutes" = nullable number
    ],
    Cases = Table.Buffer(Table.FromRecords(List.RemoveNulls(GroupedOperations[Case]), CaseType)),

    // Display labels distinguish exact names that the Power BI model would otherwise combine.
    Names = Table.Distinct(Table.SelectColumns(Cases, {"Procedure Key", "Primary Procedure"}), {"Procedure Key"}),
    ModelNameComparer = Comparer.FromCulture("en-GB", true),
    ComparableNames = Table.AddColumn(Names, "Display Group", each Text.TrimEnd([Primary Procedure]), type text),
    LabelGroups = Table.Group(ComparableNames, {"Display Group"}, {{"Labels", (NamesInGroup as table) as table =>
        if Table.RowCount(NamesInGroup) = 1 then
            Table.AddColumn(NamesInGroup, "Procedure", each [Primary Procedure], type text)
        else
            let OrderedNames = Table.Sort(NamesInGroup, {{"Procedure Key", Order.Ascending}}),
                NumberedNames = Table.AddIndexColumn(OrderedNames, "Exact Label Number", 1, 1, Int64.Type)
            in Table.AddColumn(NumberedNames, "Procedure", each
                Text.TrimEnd([Primary Procedure]) & " [exact label " & Number.ToText([Exact Label Number], "0", "en-GB") & "]",
                type text),
        type table}}, GroupKind.Global, ModelNameComparer),
    CandidateLabels = Table.SelectColumns(
        Table.ExpandTableColumn(LabelGroups, "Labels", {"Procedure Key", "Procedure"}),
        {"Procedure Key", "Procedure"}
    ),
    // A source name may contain the same suffix as a generated label.
    DisplayNames =
        if List.Count(List.Distinct(List.Transform(CandidateLabels[Procedure], Text.TrimEnd), ModelNameComparer))
            = Table.RowCount(CandidateLabels)
        then CandidateLabels
        else Table.SelectColumns(
            Table.AddColumn(Names, "Procedure", each Text.TrimEnd([Primary Procedure]) & " [exact key " & [Procedure Key] & "]", type text),
            {"Procedure Key", "Procedure"}
        ),
    JoinedLabels = Table.NestedJoin(Cases, {"Procedure Key"}, DisplayNames, {"Procedure Key"}, "Display", JoinKind.LeftOuter),
    Output = Table.ExpandTableColumn(JoinedLabels, "Display", {"Procedure"}, {"Procedure"}),
    Typed = Table.TransformColumnTypes(Output, {{"Procedure", type text}})
in
    Table.ReorderColumns(Typed, {
        "Procedure", "Primary Procedure", "Procedure Key", "Procedure Date", "Hospital",
        "Operating Theatre", "Theatre Type", "Session Specialty", "Responsible Consultant",
        "Actual Minutes", "Booked Minutes"
    })
