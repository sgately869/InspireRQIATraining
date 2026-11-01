// Reversible, unambiguous key for the same six fields used by the core queries.
(Row as record) as text =>
let
    Keys = {"Service Area", "Location", "Operating Theatre", "Procedure Date", "Slot Start Time", "Slot End Time"},
    Values = Record.FieldValues(Record.SelectFields(Row, Keys))
in
    Binary.ToText(Json.FromValue(Values), BinaryEncoding.Base64)
