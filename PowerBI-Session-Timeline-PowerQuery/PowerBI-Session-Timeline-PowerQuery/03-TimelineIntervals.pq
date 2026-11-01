let
    SessionKeys = {"Service Area", "Location", "Operating Theatre", "Procedure Date", "Slot Start Time", "Slot End Time"},
    ReviewFields = {"Timeline Session ID", "Hospital", "Operating Theatre", "Procedure Date", "Slot Start Time", "Slot End Time", "First Actual Start", "Last Actual End", "Run Minutes", "Timing Notes"},
    ReviewRows = Table.Buffer(Table.SelectColumns(SessionReview, ReviewFields)),
    CheckedReview = if Table.RowCount(Table.Distinct(Table.SelectColumns(ReviewRows, {"Timeline Session ID"}))) <> Table.RowCount(ReviewRows)
        then error "SessionReview contains duplicate session keys; the timeline needs one row per session."
        else ReviewRows,

    Planned0 = Table.SelectColumns(CheckedReview, {"Timeline Session ID", "Slot Start Time", "Slot End Time"}),
    Planned1 = Table.RenameColumns(Planned0, {{"Slot Start Time", "Interval Start"}, {"Slot End Time", "Interval End"}}),
    Planned2 = Table.AddColumn(Planned1, "Band", each "Planned session", type text),
    Planned = Table.AddColumn(Planned2, "Interval ID", each "Plan|" & [Timeline Session ID], type text),

    RunRows = Table.SelectRows(CheckedReview, each [Run Minutes] <> null and [First Actual Start] <> null and [Last Actual End] <> null and [Last Actual End] >= [First Actual Start]),
    Runs0 = Table.SelectColumns(RunRows, {"Timeline Session ID", "First Actual Start", "Last Actual End"}),
    Runs1 = Table.RenameColumns(Runs0, {{"First Actual Start", "Interval Start"}, {"Last Actual End", "Interval End"}}),
    Runs2 = Table.AddColumn(Runs1, "Band", each "Actual run", type text),
    Runs = Table.AddColumn(Runs2, "Interval ID", each "Run|" & [Timeline Session ID], type text),

    OperationColumns = {"Include in Sessions", "Patient CSN", "Log ID", "Start Time", "End Time", "Operation Time Minutes (Performed)", "Non-Overlap Operation Time Minutes (Performed)", "Overlap Minutes (Performed)"},
    Selected = Table.SelectColumns(PreparedData, SessionKeys & OperationColumns, MissingField.UseNull),
    Included = Table.SelectRows(Selected, each [Include in Sessions] = true),
    Grouped = Table.Group(Included, SessionKeys, {{"Operations", each fxTimelineOperations(_), type table}}),
    WithSessionID = Table.AddColumn(Grouped, "Timeline Session ID", each fxTimelineSessionKey(_), type text),
    OperationTables = Table.SelectColumns(WithSessionID, {"Timeline Session ID", "Operations"}),
    Expanded = Table.ExpandTableColumn(OperationTables, "Operations", {"OperationKey", "Start", "End", "ValidOp"}, {"Operation Key", "Interval Start", "Interval End", "Valid Op Interval"}),
    ValidOperations = Table.SelectRows(Expanded, each [Valid Op Interval] = true),
    Ops0 = Table.AddColumn(ValidOperations, "Band", each "Occupied theatre time", type text),
    Ops = Table.AddColumn(Ops0, "Interval ID", each "Op|" & [Timeline Session ID] & "|" & [Operation Key], type text),

    DrawingColumns = {"Timeline Session ID", "Interval ID", "Band", "Interval Start", "Interval End"},
    Intervals = Table.Combine({Table.SelectColumns(Planned, DrawingColumns), Table.SelectColumns(Runs, DrawingColumns), Table.SelectColumns(Ops, DrawingColumns)}),
    CheckedIntervals = if Table.RowCount(Table.Distinct(Table.SelectColumns(Intervals, {"Interval ID"}))) <> Table.RowCount(Intervals)
        then error "Timeline interval IDs are not unique."
        else Intervals,
    Meta = Table.SelectColumns(CheckedReview, {"Timeline Session ID", "Hospital", "Operating Theatre", "Procedure Date", "Slot Start Time", "Slot End Time", "Timing Notes"}),
    Joined = Table.NestedJoin(CheckedIntervals, {"Timeline Session ID"}, Meta, {"Timeline Session ID"}, "Session", JoinKind.LeftOuter),
    CheckedJoin = if List.AnyTrue(List.Transform(Joined[Session], each Table.RowCount(_) <> 1))
        then error "An operation interval has no unique matching SessionReview row. Refresh SessionReview and the timeline together."
        else Joined,
    Metadata = Table.ExpandTableColumn(CheckedJoin, "Session", {"Hospital", "Operating Theatre", "Procedure Date", "Slot Start Time", "Slot End Time", "Timing Notes"}),
    WithLabel = Table.AddColumn(Metadata, "Session Row", each [Hospital] & " | " & [Operating Theatre] & " | "
        & Time.ToText(Time.From([Slot Start Time]), [Format="HH:mm", Culture="en-GB"]) & "-"
        & Time.ToText(Time.From([Slot End Time]), [Format="HH:mm", Culture="en-GB"])
        & "¦" & [Timeline Session ID], type text),
    WithStart = Table.AddColumn(WithLabel, "Start Minute", each Duration.TotalMinutes([Interval Start] - DateTime.From([Procedure Date])), type number),
    WithEnd = Table.AddColumn(WithStart, "End Minute", each Duration.TotalMinutes([Interval End] - DateTime.From([Procedure Date])), type number),
    WithNotes = Table.TransformColumns(WithEnd, {{"Timing Notes", each if _ = null or _ = "" then "No timing issues flagged" else _, type text}}),
    Output = Table.SelectColumns(WithNotes, {"Timeline Session ID", "Session Row", "Interval ID", "Band", "Start Minute", "End Minute", "Timing Notes", "Interval Start", "Interval End"}),
    Typed = Table.TransformColumnTypes(Output, {{"Timeline Session ID", type text}, {"Session Row", type text}, {"Interval ID", type text}, {"Band", type text}, {"Start Minute", type number}, {"End Minute", type number}, {"Timing Notes", type text}, {"Interval Start", type datetime}, {"Interval End", type datetime}})
in
    Typed
