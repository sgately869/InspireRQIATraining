let
    // This branch reads PreparedData only. It never evaluates SessionReview.
    SessionKeys = {"Service Area", "Location", "Operating Theatre", "Procedure Date", "Slot Start Time", "Slot End Time"},
    OperationColumns = {"Include in Sessions", "Patient CSN", "Log ID", "Start Time", "End Time", "Operation Time Minutes (Performed)", "Non-Overlap Operation Time Minutes (Performed)", "Overlap Minutes (Performed)"},
    Selected = Table.SelectColumns(PreparedData, SessionKeys & OperationColumns, MissingField.UseNull),
    Included = Table.Buffer(Table.SelectRows(Selected, each [Include in Sessions] = true)),
    Grouped = Table.Group(Included, SessionKeys, {{"Operations", each fxTimelineOperations(_), type table}}),
    WithSessionID = Table.AddColumn(Grouped, "Timeline Session ID", each fxTimelineSessionKey(_), type text),
    OperationTables = Table.SelectColumns(WithSessionID, {"Timeline Session ID", "Operations"}),
    Expanded = Table.ExpandTableColumn(OperationTables, "Operations", {"OperationKey", "Start", "End", "ValidOp"}, {"Operation Key", "Interval Start", "Interval End", "Valid Op Interval"}),
    Valid = Table.SelectRows(Expanded, each [Valid Op Interval] = true),
    WithIntervalID = Table.AddColumn(Valid, "Interval ID", each "Op|" & [Timeline Session ID] & "|" & [Operation Key], type text),
    Output = Table.SelectColumns(WithIntervalID, {"Timeline Session ID", "Interval ID", "Interval Start", "Interval End"}),
    Typed = Table.TransformColumnTypes(Output, {{"Timeline Session ID", type text}, {"Interval ID", type text}, {"Interval Start", type datetime}, {"Interval End", type datetime}})
in
    Typed
