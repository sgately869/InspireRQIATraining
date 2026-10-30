# Unattended execution

This package does not create a scheduled task or contact Power BI automatically.
Test the configuration under the intended service account before enabling it.

1. Extract the project to a fixed local directory on a Trust-managed Windows server/VM.
2. Install R and run `Rscript --vanilla install_dependencies.R` once. It installs
   packages into the project's `.Rlibrary`, independent of your interactive RStudio library.
3. Copy `config.production.example.json` to `config.production.json` and configure
   approved folders, or use `theatre_configure()` in the supplied RStudio launcher.
   Test processing once under the intended account.
4. In Windows Task Scheduler, create a task under the approved unattended account:
   - Program: `C:\Program Files\R\R-4.6.1\bin\Rscript.exe` (adjust to installed R)
   - Arguments: `--vanilla "C:\TheatrePipeline\run_pipeline.R" "C:\TheatrePipeline\config.production.json"`
   - Start in: `C:\TheatrePipeline`
   - Trigger: daily, repeat every 15 minutes indefinitely.
   - Run whether the user is logged on or not; do not start a new instance if one is running.
   - Set a time limit longer than the Power BI confirmation timeout and normal processing.
   - Configure missed-run/retry handling and central monitoring according to local policy.
5. The account needs read access to input and write access to state/published folders.
   Use UNC paths, not mapped drive letters. A machine that is asleep/off cannot run a job.
6. Review `state/last_run.json`, per-run logs, and Task Scheduler's nonzero exit codes.
   A crash can leave `pipeline.lock/owner.json`; confirm that process is no longer
   running before manually removing only that lock directory.

## Power BI integration

- Publish an Import-mode semantic model that reads the prepared batch through the supplied M function.
- Configure a standard on-premises gateway and its data-source credentials to read the published UNC folder.
- Have the Power BI administrator configure an Entra service principal, enable its permitted Power BI API access, and grant the required workspace/model access.
- Configure tenant/client/workspace/model IDs and an approved secret environment variable for the task account. Do not put the secret in JSON, scripts, arguments or source control.
- Set `power_bi.enabled` to true only after a successful local processing/reconciliation review.
- This job requests refresh after publication and waits for that request's completion. Disable independent scheduled refresh for this file-manifest design. Do not publish a second batch while the preceding refresh is pending.
- The local request budget defaults to six per rolling 24 hours; this does not account for other administrators' requests. Power BI shared capacity permits eight requests per day including scheduled refreshes.
- A request failure/timeout retains `pending_refresh.json` so the next job reconciles the same request. For a confirmed failed request or ambiguous POST, review service refresh history before clearing the pending state and retrying. Never clear it merely to make the job look successful.
- API authentication, gateway connectivity, tenant policy and actual report refresh need an integration test inside the Trust. They have not been exercised by the dummy-data tests.

PowerShell is not required by the core or by these direct Rscript task settings.
If the Trust already has Posit Connect or an enterprise job scheduler, schedule
the same `run_pipeline.R` there instead. RStudio does not need to be open.
