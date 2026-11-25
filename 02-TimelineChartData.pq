let
    TheatreRows = (let
    SessionKeys = {"Service Area", "Location", "Operating Theatre", "Procedure Date", "Slot Start Time", "Slot End Time"},
    Selected = Table.SelectColumns(PreparedData, SessionKeys & {"Include in Sessions", "Patient CSN", "Log ID", "Start Time", "End Time", "Primary Procedure", "Other Procedures"}),
    Included = Table.Buffer(Table.SelectRows(Selected, each [Include in Sessions] = true)),
    Grouped = Table.Group(Included, SessionKeys, {{"Operations", each fxTimelineOperations(_), type table}}),
    WithID = Table.Buffer(Table.AddColumn(Grouped, "Timeline Session ID", each fxTimelineSessionKey(_), type text)),
    CheckedID = if List.Count(List.Distinct(WithID[Timeline Session ID])) <> Table.RowCount(WithID)
        then error "Timeline session keys collide at millisecond precision. Review the planned slot timestamps."
        else WithID,
    Small = Table.SelectColumns(CheckedID, {"Timeline Session ID", "Procedure Date", "Operations"}),
    Expanded = Table.ExpandTableColumn(Small, "Operations", {"OperationKey", "Start", "End", "ValidOp", "Primary Procedure", "Other Procedures"}, {"Operation Key", "Interval Start", "Interval End", "Valid Op Interval", "Primary Procedure", "Other Procedures"}),
    Valid = Table.SelectRows(Expanded, each [Valid Op Interval] = true),
    OpID = Table.AddColumn(Valid, "Interval ID", each "Op|" & [Timeline Session ID] & "|" & [Operation Key], type text),
    Operations = Table.AddColumn(OpID, "Record Type", each "Operation", type text),
    Dates = List.Buffer(List.RemoveNulls(Included[Procedure Date])),
    CalendarList = if List.IsEmpty(Dates) then {} else List.Dates(List.Min(Dates), Duration.Days(List.Max(Dates)-List.Min(Dates))+1, #duration(1,0,0,0)),
    Calendar0 = Table.FromColumns({CalendarList},type table [Procedure Date=date]),
    Calendar = Table.AddColumn(Calendar0,"Record Type",each "Calendar",type text),
    Fields = {"Record Type", "Timeline Session ID", "Interval ID", "Interval Start", "Interval End", "Procedure Date", "Primary Procedure", "Other Procedures"},
    Combined = Table.Combine({Table.SelectColumns(Operations,Fields),Table.SelectColumns(Calendar,Fields,MissingField.UseNull)}),
    Typed = Table.TransformColumnTypes(Combined,{{"Record Type",type text},{"Timeline Session ID",type text},{"Interval ID",type text},{"Interval Start",type datetime},{"Interval End",type datetime},{"Procedure Date",type date}})
in Typed),
    Fields = {"Record Type", "Timeline Session ID", "Interval ID", "Interval Start", "Interval End", "Procedure Date", "Primary Procedure", "Other Procedures"},
    Operations = Table.SelectRows(TheatreRows, each [Record Type] = "Operation"),
    Dates = List.RemoveNulls(PreparedData[Procedure Date]),
    CalendarDates = if List.IsEmpty(Dates) then {} else List.Dates(List.Min(Dates), Duration.Days(List.Max(Dates)-List.Min(Dates))+1, #duration(1,0,0,0)),
    Calendar = Table.AddColumn(Table.FromColumns({CalendarDates}, type table [Procedure Date=date]), "Record Type", each "Calendar", type text),
    Result = Table.Combine({Operations, Table.SelectColumns(Calendar, Fields, MissingField.UseNull)})
in
    Table.TransformColumnTypes(Result, {{"Procedure Date", type date}, {"Interval Start", type datetime}, {"Interval End", type datetime}, {"Primary Procedure", type text}, {"Other Procedures", type text}})
