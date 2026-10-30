# Prepared data in Power BI

Create text parameter **pRPublishedFolder** pointing to the output directory, then
create a blank query **fxLoadTheatreTable** containing `fxLoadTheatreTable.pq`.
Create these queries, replacing each query's entire Advanced Editor text:

```powerquery
// Sessions
fxLoadTheatreTable("sessions")
```

Repeat for `patients`, `procedures`, `operations`, `data_quality_issues`,
`input_inventory`, `monthly_summary` and `weekly_summary` as needed. The function
uses the publication schema, retaining CSNs/Log IDs as text and importing dates,
datetimes, counts and rates correctly, including when the quality table is empty.

Use Sessions as the primary one-row-per-session fact. Patients has one row per
identified patient/session, including ineligible patients with Counted Patient=0.
Procedures retains every input row, including rows excluded from sessions, raw
source values and source-row references. Operations contains deduplicated timing
identities and their trusted/excluded endpoints.

Prefer shared Date, Hospital, Theatre, Specialty and Consultant dimensions for
filtering. If relating Sessions to Patients/Operations, Session ID is the unique
session key, with single-direction filtering from session to detail. Do not sum
session minutes from a patient/procedure join. Review mixed/incomplete consultant
attribution instead of assigning a whole session to every named consultant.

Example DAX (adjust the Power BI table name if needed):

```dax
No of Sessions = SUM(Sessions[No of Sessions])
No of Patients = SUM(Sessions[No of Patients])
Session Duration (Mins) = SUM(Sessions[Session Duration])
Run Time (Mins) = SUM(Sessions[Run Minutes])
Op Time (Mins) = SUM(Sessions[Op Minutes])
% Run Time = DIVIDE([Run Time (Mins)], SUM(Sessions[Session Duration Used for Run Time]))
% Op Time = DIVIDE([Op Time (Mins)], SUM(Sessions[Session Duration Used for Op Time]))
% On-Time Starts = DIVIDE(SUM(Sessions[On-Time Starts]), SUM(Sessions[Starts Assessed]))
% On-Time Finishes = DIVIDE(SUM(Sessions[On-Time Finishes]), SUM(Sessions[Finishes Assessed]))
Workload Coverage = DIVIDE(SUM(Sessions[Sessions Used for Scheduling]), [No of Sessions])
Recorded Scheduled Load = DIVIDE(SUM(Sessions[Scheduled Minutes]), SUM(Sessions[Session Duration Used for Scheduling]))
```

Do not average row-level percentages. The summaries retain numerators and matched
denominators so totals remain weighted correctly. Weekly summaries include partial
weeks; apply an explicitly declared extract-through date before presenting a
complete-week comparison. Absence of patients on a date does not prove an extract
is incomplete or complete. Coverage is unknown for the legacy dummy filenames.

This package supplies transformations and import queries, not a `.pbix` report or
new SPC implementation. The validated workbook remains the presentation reference.
Rebuilding Making Data Count SPCs in Power BI requires separate baseline, signal
and slicer-behaviour validation.

Show Reporting Batch and processed/coverage metadata on the report. Power BI
refresh success and Encompass extract freshness are separate facts.
