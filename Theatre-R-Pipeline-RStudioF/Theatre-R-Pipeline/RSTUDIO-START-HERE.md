# Running on a Trust device using RStudio

Version 1.0.1 runs the data processing and publication entirely inside R. It does
not launch PowerShell, cmd.exe, Rscript or another subprocess from RStudio.

## One-time setup

1. Extract the complete ZIP into a writable, Trust-approved project folder.
2. Double-click `Theatre-R-Pipeline.Rproj`, or use RStudio **File > Open Project**.
   The project folder becomes the working directory.
3. In the **Console** pane of RStudio, run:

```r
source("install_dependencies.R")
```

This checks `readxl`, `data.table`, `jsonlite`, `digest` and `curl`, installing
missing packages into the project's `.Rlibrary`. It honours the package
repository already configured in RStudio, or THEATRE_CRAN_REPO if set. If package
downloads are restricted, ask the Trust's R administrator to provide these
packages through the approved repository. No PowerShell or admin installer is
used by this R script. Do not disable Trust controls to install packages.

4. Load the RStudio functions and run the supplied dummy example:

```r
source("rstudio.R")
theatre_run()
```

The console should report **Published** or **No input changes**. The demo reads
only `demo/input` and writes to `demo/state` and `demo/output`.

## Point at the real extracts

Use a dedicated folder containing the raw monthly Excel extracts. Keep reporting
workbooks and generated outputs elsewhere. Each source workbook must have the
expected headings in row 1 and contain one month of activity. The script accepts
the previously agreed heading aliases and preserves original source values.

In RStudio, run this once, adjusting the input path to your approved folder:

```r
theatre_configure(
  input_dir = "//svrfile11/users6$/stephen.gately/My Documents/Projects/Power Queries/THEATRES",
  output_dir = "real-output",
  state_dir = "real-state"
)
```

Forward slashes avoid R's backslash-escaping rules. Relative output/state paths
are inside the extracted project folder, so put the project in an approved
location for patient-level data. You can instead supply approved absolute/UNC
paths for output and state. They must differ from the input folder.

This saves `config.production.json`, keeping real-data history/output separate
from the dummy example. The input files are read and archived, not edited. Power
BI API refresh remains disabled. To change an existing configuration, edit its
three folder settings in RStudio or explicitly call `theatre_configure(...,
overwrite=TRUE)`.

Process the real extracts:

```r
theatre_run("config.production.json")
theatre_status("config.production.json")
```

If a file has just been downloaded, the job can ask you to retry after the
30-second settling period. If it finds multiple undated versions of the same
month or a workbook without the required source sheet, correct the input rather
than suppressing the error. If a file has multiple matching sheets, set `sheet`
in the JSON configuration to the intended sheet name.

## Each subsequent week

1. Save the fresh month-to-date extract into the input folder, replacing that
   month's file (e.g. `NOVEMBER-26.xlsx`). Keep one file per month, or use the
   documented timestamped naming convention when retaining multiple versions.
2. Open the RStudio project if it is not already open, then run:

```r
source("rstudio.R")
theatre_run("config.production.json")
```

R retains the historical months, replaces the updated monthly snapshot, and
publishes prepared CSV tables. It skips processing when inputs have not changed.
This is a **full-month/month-to-date replacement** workflow. Seven-day-only delta
extracts require a different merge policy. Do not place those into this pipeline.

`theatre_status()` prints the absolute published-folder path, latest batch and
last processing result. Operational logs are in the configured state directory.
Do not clear that directory: it contains the retained history and original
archives. Native same-folder file replacement must be permitted by the selected
filesystem; a failed replacement leaves the previous publication in place.

## Power BI

In Power BI Desktop, create the text parameter `pRPublishedFolder` using the
published-folder path printed by `theatre_status()`. Follow
`powerbi/queries-and-measures.md` to add `fxLoadTheatreTable` and import Sessions,
Patients, Procedures and the other prepared tables. The demo workbook's existing
queries are not automatically repointed by this script, and this package is not
a completed Power BI report.

With API refresh disabled, run R first, then use **Refresh** in Power BI Desktop.
An existing published report can instead use the Trust's configured refresh
arrangement after processing. Power BI Desktop being installed alone does not
provide an unattended published-report refresh.

For fully unattended operation, the Trust's team would schedule the same R code
on an available server/VM (or Posit Connect) and configure the Power BI service,
gateway and credentials. They can launch Rscript directly; PowerShell is not
required. Until then, saving the extract and running the RStudio command are two
manual steps. Nothing runs after RStudio/R is closed unless another scheduler
has been configured.
