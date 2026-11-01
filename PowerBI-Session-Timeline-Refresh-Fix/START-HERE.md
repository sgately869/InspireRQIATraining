# Timeline refresh correction

The previous TimelineIntervals Power Query referenced both SessionReview and
PreparedData, rebuilt planned/run intervals, and joined metadata over all drawing
rows. Referencing SessionReview can rerun its source and expensive session
summarisation instead of reading the already-loaded model table. Its interval
validation/join steps also enumerate drawing data repeatedly. Table.Buffer is
not a shared cache across separate queries.

This correction leaves a small Power Query branch for operation intervals only.
The model builds the timeline from the loaded SessionReview and operation tables
using DAX. It no longer invokes SessionReview inside the timeline M query or
joins session metadata repeatedly in M. There is still a separate PreparedData
evaluation for operations; this does not guarantee a single source read or a
specific whole-model refresh time.

## 1. Cancel the current refresh

Use Cancel in the refresh window and wait until it stops before editing. Preserve
the PBIX and all existing queries. Keep the two previously added helper functions
and the Timeline Session ID column in SessionReview.

## 2. Replace and rename the existing drawing query

In Transform data:

1. Select the old **TimelineIntervals** query.
2. In Advanced Editor, replace ALL its contents with **01-TimelineOperations.pq**.
3. Rename this query to **TimelineOperations**.
4. Keep Enable load and Include in report refresh ON.
5. Keep SessionReview loaded and included in refresh.
6. Close & Apply.

This query now returns valid operation intervals only: four columns. It has no
SessionReview reference. It reuses fxTimelineOperations and fxTimelineSessionKey,
preserving the original conflict, duplicate, missing and overnight timing rules.
Do not create another query that still contains the old TimelineIntervals code.

## 3. Build the drawing table in the model

After loading finishes, select Modeling > New table (not New measure, and not a
Power Query blank query).

Open **02-Model-Timeline.dax.txt**. Copy only expression A, beginning
TimelineIntervals = and ending immediately before comment B. Paste and commit it.

The DAX table combines the loaded planned slots and run spans from SessionReview
with loaded operation intervals. It does not reread source workbooks. It is
recalculated automatically when its imported dependencies refresh.

## 4. Create the relationship

SessionReview[Timeline Session ID] (1) -> TimelineIntervals[Timeline Session ID] (*).

Active, Single direction from SessionReview. Check existing relationships rather
than duplicating them. TimelineOperations does not need another relationship for
this drawing calculation. If auto-detection creates an unused relationship to it,
remove that extra relationship; only the one above is required for the visual.

## 5. Add four calculated columns

Select TimelineIntervals in the model. Use New column for each expression in
section C of the DAX file separately:

- Session Row
- Start Minute
- End Minute
- Timing Notes

The relationship must exist before RELATED can resolve these expressions. Set
Start Minute and End Minute to Decimal number and Don't summarize.

## 6. Continue the previous Deneb setup

Use the Timeline Visible Rows PQ measure in section D (or retain the existing
measure if it already refers to TimelineIntervals). Bind the SAME six columns
and measure as before. Keep the existing Vega-Lite JSON unchanged.

All slicers/page filters come from SessionReview. Keep the day single-selected,
exclude Emergency Surgery and Maternity as previously instructed, and apply the
visual filter Timeline Visible Rows PQ > 0.

Session totals and planned/run/op measures must continue to use SessionReview,
not the drawing table. Grey planned slots remain when actual timings are absent;
blue is the usable recorded run span; green overlays valid operation intervals
without visually double-counting concurrent occupied theatre minutes.

## Verification scope

The replacement M branch is checked against the previous native timing fixtures
and the original timeline's native-M operation output. The DAX expressions are
reviewed against the existing model fields; Power BI Desktop model creation and
filter behaviour must be checked on the user's device. No guaranteed refresh-time
claim is made. The previously incomplete full-folder check is not a speed baseline.

References:

- https://learn.microsoft.com/en-us/power-bi/guidance/power-query-referenced-queries
- https://learn.microsoft.com/en-us/power-bi/transform-model/desktop-calculated-tables
