# Theatre data processing in R

This project transforms monthly Encompass theatre extracts into prepared tables
for Power BI or Excel. The dummy example contains June–August 2026: 4,050 source
rows and 1,014 inferred sessions. No source workbook is modified.

The R implementation reproduces the current workbook's session and patient
definitions. Scheduling and Power BI integration are supplied as templates; no
scheduled task, tenant connection, gateway or Power BI report has been deployed.

## Quick start with the dummy data

**Using RStudio without PowerShell:** start with `RSTUDIO-START-HERE.md`.
Open the `.Rproj`, then run these lines in the RStudio Console:

```r
source("install_dependencies.R") # one-time package setup
source("rstudio.R")
theatre_run()                    # supplied dummy data
```

The version 1.0.1 core uses native R file operations, including publication.
Loading `rstudio.R` only loads functions; processing starts when `theatre_run()`
is called. The package installer can also be sourced safely within RStudio.

The following command-line route is optional for a future server scheduler:

Extract the entire ZIP to a writable local directory. Install R, then run these
commands from that directory, replacing the R installation path if needed:

```powershell
& 'C:\Program Files\R\R-4.6.1\bin\Rscript.exe' --vanilla install_dependencies.R
& 'C:\Program Files\R\R-4.6.1\bin\Rscript.exe' --vanilla run_pipeline.R config.demo.json
& 'C:\Program Files\R\R-4.6.1\bin\Rscript.exe' --vanilla tests/run_tests.R
```

The installer writes only to this project's `.Rlibrary` and records package
versions. For a Trust-managed package mirror, set THEATRE_CRAN_REPO before
installation. Packages are not installed or upgraded by the unattended job.

The first run imports Excel files and builds the tables. Subsequent unchanged
runs return **No input changes**. `--force` rebuilds outputs for investigation:

```powershell
& 'C:\Program Files\R\R-4.6.1\bin\Rscript.exe' --vanilla run_pipeline.R config.demo.json --force
```

Open `demo/output/current.json` to find the active batch under
`demo/output/batches/<run-id>/`. The package includes a precomputed dummy batch.
The original Excel workbook is not refreshed or edited by this script.

## Output tables

| File | Grain and purpose |
|---|---|
| sessions.csv | One row per inferred session; all 90 existing review fields, stable Session ID and convenience rates |
| patients.csv | One row per identified patient/session; Counted Patient marks reporting eligibility; excluded patients remain visible |
| procedures.csv | Every source row, including excluded rows; source references, original values and prepared session mapping |
| operations.csv | One deduplicated timing identity per session; valid/conflicting/reversed/incomplete intervals and trusted boundaries |
| data_quality_issues.csv | One issue per affected session or import row; explicit treatment, affected counts/minutes and source references |
| monthly_summary.csv / weekly_summary.csv | Additive metrics and weighted rates by period, site, theatre type, specialty and consultant attribution |
| input_inventory.csv | Known source snapshots, content hashes, selection, declared coverage and current input-folder presence |
| schema.json / batch.json | Import types, batch ID, row counts, provenance, processing time and assumptions |

The weekly summaries include partial weeks. Apply declared extract coverage
before showing complete-week comparisons or SPCs. No coverage date is invented
from the last patient/procedure date. Coverage for the legacy dummy filenames is
explicitly unknown.

## Rules retained from the workbook

- Session key: Service Area, Location, Operating Theatre, Procedure Date, Slot
  Start Time and Slot End Time. This is inferred identity, not an Encompass session
  identifier. Changes to those fields create a different session identity.
- Session duration includes every session with valid identifying/planned fields,
  independently of actual-timing completeness and patient-count eligibility.
- Patients are distinct CSNs within a session with a recorded first procedure
  start and last procedure end. Missing IDs do not contribute to patient counts.
  Presence of these bounds, as in the workbook, does not prove a valid interval;
  reversed/conflicting intervals are handled separately for timing.
- Run minutes use earliest trusted start to latest trusted end, retaining partial
  spans. Conflicting Log IDs and reversed operation intervals supply neither end.
  A missing end does not automatically invalidate a recorded start, or vice versa.
- Op minutes are the union of usable operation intervals across the theatre
  session: concurrent patients cannot count the same theatre minute twice.
  Recorded Patient Op Minutes retains each patient's union before that theatre
  union. Raw/same-patient/concurrent differences remain available for audit.
- Seconds are retained. Supplied performed/non-overlap/overlap minutes remain
  separate comparison measures; they are not substituted for timestamp results.
- Start/finish classification is independent at each boundary. Exactly ten
  minutes early or late is **On Time**. Contradictory session boundaries are not
  classified. Partial classifications remain flagged.
- Run and op utilisation have separate assessed planned-minute denominators;
  overall Planned Time still includes all valid represented sessions.
- Scheduled workload uses supplied scheduled operation minutes, grouping repeat
  identities and rejecting conflicts. It is recorded load, not proof of the
  original booking plan, available capacity or absence of backfilling.
- Mixed, incomplete and unknown consultant/specialty attribution remain explicit.
  A responsible consultant is not assumed to be the sole operating clinician.
- Actual Start/End fields provisionally represent the clinical boundaries agreed
  in the earlier workbook discussion. The extracts do not establish that meaning
  independently. Datetimes use Excel's naive wall-clock arithmetic, internally
  represented as UTC-valued numbers without a timezone conversion. Offset-bearing
  timestamp strings are invalid until an explicit source timezone policy exists.
- Overnight clock-only times follow the workbook's documented rollover rules.
  Full datetimes with an end before start are flagged, not automatically moved to
  the next day.

## Weekly snapshots and retained history

Only full-month or month-to-date snapshots are supported by this version. Do not
feed seven-day-only deltas into the monthly replacement process.

The simplest routine is to keep one file per month, for example `NOVEMBER-26.xlsx`,
and save each fresh month-to-date export over that same file. R archives the prior
contents automatically and replaces November's reporting data. The default input
pattern accepts `.xlsx` files in the dedicated input folder. Extract coverage is
unknown unless explicitly supplied, so this route cannot certify complete weeks.

If you want to retain multiple visible snapshots or declare extract coverage,
use these explicit filenames:

```
THEATRES_2026-11_through_2026-11-07_exported_20261107T120000Z.xlsx
THEATRES_2026-11_through_2026-11-14_exported_20261114T120000Z.xlsx
```

The later export replaces the earlier November snapshot in reporting. It does
not add a second copy of 1–7 November. Coverage and export timestamp must describe
the actual export; the script cannot infer them reliably. The timestamp is UTC.
The latest export can also replace a historic month to incorporate corrections.
No fixed list of months is maintained in the code.

For existing historical files, the reporting month can be inferred from their
procedure dates if each file contains exactly one month. Use one filename per
month, or the timestamped naming convention when keeping multiple snapshots.
Multiple undated versions for one month stop the job for review. File-copy
modification times are not used to decide which clinical snapshot is newest.
An optional stricter filename pattern is:

```json
"filename_pattern": "^THEATRES_[0-9]{4}-[0-9]{2}_through_[0-9]{4}-[0-9]{2}-[0-9]{2}_exported_[0-9]{8}T[0-9]{6}Z\\.xlsx$"
```

Every observed source is hashed and archived by content. The persistent catalogue
retains known months even after their incoming files are removed. Clearing Input
is not a request to delete history. Do not clear State: it holds the history
catalogue, original archives and pending refresh state. If an export filename is
reused for a different reporting month, the job stops rather than dropping the
old month. An empty replacement month is blocked by default for review.

## Publication and failures

Completed batches are immutable. The CSVs and schema are written together before
`current.json` is atomically replaced (its previous version is retained). A failed import/transformation does not
replace the last successful publication. The exclusive lock prevents overlapping
pipeline jobs. No-change runs avoid both recalculation and Power BI refresh.

Each run writes structured logs and `State/last_run.json`. Real record issues
remain visible in the quality table and retain the documented usable data. A
missing header, ambiguous source/snapshot, changed download or publication error
fails the job with a nonzero exit code. No patient records or credentials are
written into the operational error log; row-level data remains in the controlled
output and archived sources.

The script does not remove old batches or archived sources. Agree retention and
backups with the Trust before long-term deployment. Set folder access for these
patient-level outputs accordingly.

## Power BI and unattended operation

Read `RSTUDIO-START-HERE.md` for the RStudio workflow with real data.
Read `powerbi/queries-and-measures.md` for the prepared-table M function, model
grain and example measures. Read `automation/task-scheduler-settings.md` for
Windows scheduling directly through Rscript, service-account access and the optional Power BI refresh API.
Those are one-time infrastructure steps. RStudio need not be open afterwards.

Power BI API calls are disabled in both supplied configurations. Their sequence
is tested with mock responses; live authentication, tenant permissions, gateway
access and report refresh must be tested in the Trust environment. Credentials
are read from the task account's environment, never stored in the project.

Use this pipeline as the sole refresh orchestrator for the file-based design.
Do not independently refresh Power BI during publication. A published batch is
held while its requested refresh is confirmed; failed or uncertain refresh state
is retained for investigation rather than reported as success.

## Validation and scope

`tests/validation_results.json` records the executed checks. The reconciliation
compares all 90 session-review fields across 1,014 sessions and nine patient-detail
fields across 4,050 patients against the saved workbook. Datetime comparison
tolerance is one millisecond (the reference export uses rounded Excel date
serials); minute measures use 0.00001 minutes. Counts, flags, labels and identities
must match exactly. Independent fixtures exercise seconds, overlaps, gaps,
duplicates, missing/reversed/conflicting intervals, night sessions, scheduling,
attribution, threshold boundaries and the confirmed Pain Management example.

These are dummy-data results, not a benchmark of the Trust network or live data.
The output deliberately retains the workbook's 90-field calculation contract.
This project does not build a Power BI `.pbix`, replace the existing workbook's
visuals or implement new SPC charts. Those can use the prepared tables in a
subsequent presentation build.

## Technical references

- Rscript: https://stat.ethz.ch/R-manual/R-devel/library/utils/html/Rscript.html
- readxl: https://readxl.tidyverse.org/reference/read_excel.html
- data.table: https://rdatatable.gitlab.io/data.table/
- Power BI refresh: https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/refresh-dataset-in-group
- Power BI refresh history: https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/get-refresh-history-in-group
- Power BI gateway: https://learn.microsoft.com/en-us/power-bi/connect-data/service-gateway-onprem
