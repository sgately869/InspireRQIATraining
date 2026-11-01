# Session Timeline: full Power Query version

This setup is for the model imported from the original Theatre Utilisation Excel
queries: SessionReview, PreparedData, fxBuildOverview, etc. It does not read R
outputs, require RStudio, or use the R version's Sessions/Operations tables.

The visual keeps the previous appearance: grey planned slot, blue recorded run
span, and thin green occupied-time intervals. The model needs only SessionReview
and TimelineIntervals loaded for this visual. PreparedData and the existing
functions remain dependencies and can stay unloaded.

## 1. Add the two helper functions

Open Power BI Desktop > Transform data. For each row below:

1. Home > New Source > Blank Query.
2. Open Advanced Editor and replace all its contents with the entire named file.
3. Select Done and give the query the exact name shown.

| File to copy | Query name |
| --- | --- |
| 01-fxTimelineSessionKey.pq | fxTimelineSessionKey |
| 02-fxTimelineOperations.pq | fxTimelineOperations |

The helpers appear with function (fx) icons. Do not use Invoke to create another
query. The timeline query invokes them automatically.

The session key encodes all six original session identity fields: Service Area,
Location, Operating Theatre, Procedure Date, Slot Start Time and Slot End Time.
This prevents separate sessions in one theatre/day being combined accidentally.

The operation parser was extracted unchanged from the validated fxBuildOverview:
seconds are retained; clock-only overnight times use the same alignment;
duplicate logs are grouped; conflicting, reversed or incomplete operation
intervals do not become green bars. Missing patient IDs do not remove an otherwise
valid operation interval from theatre occupied time.

## 2. Add the session key to SessionReview

Select SessionReview and its LAST applied step. Use Add Column > Custom Column:

- New column name: `Timeline Session ID`
- Formula: `fxTimelineSessionKey(_)`

Set the new column's data type to Text. Add this step at the END so the existing
column selection/reordering steps do not remove it. Leave all original columns
and calculations in place. If this exact column already exists from this setup,
do not add it again.

## 3. Create the drawing-data query

Add another Blank Query. In Advanced Editor replace all its contents with
03-TimelineIntervals.pq and name the query exactly `TimelineIntervals`.

Keep Enable load and Include in report refresh on for:

- SessionReview
- TimelineIntervals

PreparedData can have Enable load off if no other report elements need it as a
loaded table; the new query still evaluates its necessary preparation steps.
Neither ImportIssues nor DataQualityIssues is required by this timeline.

Choose Close & Apply and let the queries finish.

The new query draws one planned interval per represented session, one run span
where available, and each valid deduplicated operation interval. It joins metadata
to SessionReview by the full session key, with explicit uniqueness/matching checks.
It does not sum session counts or planned minutes over operation rows.

## 4. Create the relationship

In Model view > Manage relationships > New:

- One (1) side: `SessionReview[Timeline Session ID]`
- Many (*) side: `TimelineIntervals[Timeline Session ID]`
- Cross-filter direction: Single, from SessionReview to TimelineIntervals.
- Active: yes.

If auto-detection already created this exact relationship, check it rather than
adding a duplicate. Do not relate TimelineIntervals directly to Sessions,
OverviewSessions or DrilldownData. This setup uses SessionReview as its filter
source. If Power BI reports duplicate keys on the one side, investigate them;
do not select many-to-many as a workaround.

## 5. Add the measure

Choose Modeling > New measure and paste this expression:

```dax
Timeline Visible Rows PQ =
    IF (
        HASONEVALUE ( SessionReview[Procedure Date] ),
        COUNTROWS ( TimelineIntervals )
    )
```

This prevents drawing all months if the date selection is cleared. It is a
measure, not a new calculated table or column. The optional second measure in
05-Timeline-Measures.dax.txt can be used as a date card above the visual.

## 6. Create the page filters and dropdowns

Create/open the Session Timeline page. Use fields from SessionReview, not the old
R-backed Sessions table, PreparedData or TimelineIntervals:

| Purpose | Field | Setting |
| --- | --- | --- |
| Day dropdown | SessionReview[Procedure Date] | Raw date, not Date Hierarchy; Dropdown; Single select on |
| Hospital dropdown | SessionReview[Hospital] | Dropdown, multiple selection allowed |
| Theatre dropdown | SessionReview[Operating Theatre] | Dropdown, multiple selection allowed |
| Optional specialty dropdown | SessionReview[Session Specialty] | Dropdown |
| Optional consultant dropdown | SessionReview[Responsible Consultant] | Dropdown |
| Page exclusion | SessionReview[Session Specialty] | Advanced filtering: is not Emergency Surgery |
| Page exclusion | SessionReview[Theatre Type] | Advanced filtering: is not Maternity |

Use the exact category spelling in your extracts. Select a historical day with
known activity. If copied from another report, replace the old slicer fields
with these fields; an unconnected slicer will not filter the new model.

## 7. Add Deneb and bind its fields

If necessary: Visualizations > (...) > Get more visuals > search Deneb > Add.
Insert Deneb on the page. In its Values well add:

| Field | Setting |
| --- | --- |
| TimelineIntervals[Session Row] | Column |
| TimelineIntervals[Interval ID] | Column; retain even though not displayed |
| TimelineIntervals[Band] | Column |
| TimelineIntervals[Start Minute] | Decimal number; Don't summarize |
| TimelineIntervals[End Minute] | Decimal number; Don't summarize |
| TimelineIntervals[Timing Notes] | Column |
| [Timeline Visible Rows PQ] | Measure |

Do not rename these fields for the visual. If Start Minute/End Minute appear as
Sum of..., change them to Don't summarize. The interval identifier prevents
Power BI collapsing separate log intervals with identical start/end times.

In Filters on this visual, set Timeline Visible Rows PQ to is greater than 0.

## 8. Paste the specification

1. Deneb (...) > Edit.
2. Create a new specification with Vega-Lite and the Empty template.
3. Open 04-Session-Timeline.vega-lite.json in a text editor and copy ALL of it.
4. Replace the contents of Deneb's Specification editor with that text.
5. Apply/Run and return to the report.

This is raw specification JSON. Paste into Specification, not Config, and not
the Import template option. Menu wording varies by Deneb version. The JSON is
compatible with the previous visual because the new query exposes the same
drawing fields.

Make the visual almost the full page width. Sessions keep a readable row height;
additional rows scroll. Labels show hospital, theatre and planned slot. A hidden
key suffix keeps sessions distinct without showing technical IDs to report users.

## 9. Add a session detail table and verify

Use columns from SessionReview below the timeline:

- Hospital, Operating Theatre, Session Specialty, Responsible Consultant
- Procedure Date, Slot Start Time, Slot End Time
- First Actual Start, Last Actual End
- Start Type, Finish Type, Run Time Status, Op Time Status

Optional measures for the table/cards:

```dax
Timeline Sessions PQ = SUM ( SessionReview[No of Sessions] )
Timeline Patients PQ = SUM ( SessionReview[No of Patients] )
Timeline Planned Minutes PQ = SUM ( SessionReview[Session Duration] )
Timeline Run Minutes PQ = SUM ( SessionReview[Run Minutes] )
Timeline Op Minutes PQ = SUM ( SessionReview[Op Minutes] )
```

Create each optional measure separately. Avoid summing planned duration or session
counts from TimelineIntervals: those rows exist only for drawing bars.

Verify one known day/site/theatre:

1. Grey slot matches Slot Start Time and Slot End Time.
2. Blue span matches First Actual Start and Last Actual End.
3. Green segments match valid recorded operation intervals; overlapping bars
   occupy the same band so the theatre footprint counts each minute once.
4. A session without usable actual times still has its grey planned bar.
5. Date/site/theatre selections update both the chart and detail table.

If a slicer changes the table but not the chart, check the relationship and use
Format > Edit interactions to set the slicer's interaction with Deneb to Filter.
Bar-click cross-filtering/drillthrough is not configured in this specification.

## Timing interpretation and refresh

Grey is planned availability, blue includes recorded gaps, and green is recorded
occupied theatre time. Blue with no green is not automatically avoidable downtime:
missing patient timings can also cause gaps. Tooltips show the session timing
notes, including partial recorded spans and concurrency warnings.

Each green tooltip shows an individual operation interval's minutes. Do not sum
those tooltip durations when intervals overlap. Use SessionReview[Op Minutes] for
the non-overlapping session total. The drawing does not allocate separate patient
lanes or show concurrency counts. Valid zero-minute intervals use a thin tick.

Overnight coordinates remain relative to Procedure Date: +1d means the following
day, -1d the previous day. Fractional minutes retain seconds without browser
timezone conversion. The known 24-hour Encompass lag still applies; this visual
does not invent missing activity or assume an extract timestamp.

After setup, refresh the PBIX normally. SessionReview and TimelineIntervals must
both be included in report refresh. Scheduled service refresh follows the same
query dependencies, provided a gateway can access the raw-extract folder.

This adds necessary operation-interval work to the refresh. Query references are
not a guarantee of a single shared evaluation of PreparedData. No speedup is
claimed. The helper mirrors the current original workbook's operation parsing;
if you later alter fxBuildOverview timing rules, update this helper consistently.

## Verification scope

Native-M-Validation.json records seven native Power Query checks across 48
original timing fixtures, plus 192 comparisons to the previously validated native
reference. The preview uses those fixtures only. The additional full dummy-folder
refresh was stopped before completion because of its runtime; no full-folder
validation pass is claimed. No Trust real-data records were read. Power BI model
relationships, slicers and your specific published gateway still require checking
on your device.

Reference documentation:

- https://deneb.guide/docs/simple-example
- https://deneb.guide/docs/dataset
- https://learn.microsoft.com/en-us/power-bi/connect-data/refresh-include-in-report-refresh
