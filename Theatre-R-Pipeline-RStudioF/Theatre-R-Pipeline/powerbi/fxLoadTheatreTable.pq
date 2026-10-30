// Create a text parameter pRPublishedFolder, then create this function query.
// Example parameter: C:\TheatrePipeline\demo\output
// This is a prepared-data import. It does not run R or read the raw XLSX files.
(TableName as text) as table =>
let
    Root = Text.TrimEnd(pRPublishedFolder, {"\", "/"}),
    Current = Json.Document(File.Contents(Root & "\current.json")),
    Batch = Root & "\" & Text.Replace(Current[batch_relative_path], "/", "\"),
    AllSchema = Json.Document(File.Contents(Batch & "\schema.json")),
    Schema = if Record.HasFields(AllSchema, TableName) then Record.Field(AllSchema, TableName) else error "Unknown theatre reporting table",
    Data = Csv.Document(File.Contents(Batch & "\" & TableName & ".csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Data, [PromoteAllScalars=true]),
    Expected = List.Transform(Schema, each [name]),
    Checked = if List.Sort(Table.ColumnNames(Headers)) <> List.Sort(Expected) then error "Prepared table headings do not match the published schema" else Headers,
    Types = List.Transform(Schema, each {[name],
        if [type]="number" then type number else if [type]="logical" then type logical
        else if [type]="datetime" then type datetime else if [type]="date" then type date else type text}),
    Typed = Table.TransformColumnTypes(Checked, Types, "en-GB"),
    WithBatch = Table.AddColumn(Typed, "Reporting Batch", each Current[run_id], type text)
in
    WithBatch
