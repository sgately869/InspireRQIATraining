args<-commandArgs(trailingOnly=FALSE);script<-sub("^--file=","",args[grepl("^--file=",args)])
ROOT<-dirname(dirname(normalizePath(script[1],winslash="/",mustWork=TRUE)))
.libPaths(c(file.path(ROOT,".Rlibrary"),.libPaths()))
suppressPackageStartupMessages(library(data.table));setDTthreads(2)
PIPELINE_VERSION<-"1.0.1"
for(f in c("utils.R","import.R","transform.R","quality.R","refresh.R","pipeline.R")) source(file.path(ROOT,"R",f))
source(file.path(ROOT,"tests/fixtures.R"));source(file.path(ROOT,"tests/reconcile_workbook.R"))
source(file.path(ROOT,"tests/refresh_mock.R"))
start<-Sys.time();fx<-fixture_tests(ROOT)
cfg<-jsonlite::read_json(file.path(ROOT,"config.demo.json"),simplifyVector=TRUE)
scan<-scan_inputs(cfg,ROOT);begin<-Sys.time();result<-transform_theatres(scan$raw,10)
transform_seconds<-as.numeric(difftime(Sys.time(),begin,units="secs"))
recon<-reconcile_workbook(result,ROOT)
stopifnot(nrow(build_quality(result$sessions,result$procedures))==0)
# Integration checks use a new isolated output/state, retaining all fixtures.
test_root<-file.path(ROOT,"tests","integration")
dir.create(test_root,recursive=TRUE,showWarnings=FALSE)
icfg<-cfg;icfg$state_dir<-file.path(test_root,"state");icfg$output_dir<-file.path(test_root,"output")
a<-run_pipeline(icfg,ROOT,force=TRUE)
current_path<-file.path(icfg$output_dir,"current.json");before<-digest::digest(file=current_path,algo="sha256")
b<-run_pipeline(icfg,ROOT)
stopifnot(identical(b$status,"No input changes"),identical(before,digest::digest(file=current_path,algo="sha256")))
# Concurrent runs fail safely, and the successful manifest is untouched.
lock<-file.path(icfg$state_dir,"pipeline.lock");dir.create(lock)
locked<-try(run_pipeline(icfg,ROOT),silent=TRUE)
stopifnot(inherits(locked,"try-error"),identical(before,digest::digest(file=current_path,algo="sha256")))
unlink(lock,recursive=TRUE)
# A structural source failure retains the last publication.
broken<-icfg;broken$sheet<-"Nonexistent worksheet"
failed<-try(run_pipeline(broken,ROOT),silent=TRUE)
stopifnot(inherits(failed,"try-error"),identical(before,digest::digest(file=current_path,algo="sha256")),!dir.exists(lock))
# A file still being copied is retried, rather than imported partially.
unstable<-icfg;unstable$stable_seconds<-1e10
failed<-try(run_pipeline(unstable,ROOT),silent=TRUE)
stopifnot(inherits(failed,"try-error"),identical(before,digest::digest(file=current_path,algo="sha256")))
# Once sources are archived/catalogued, an empty incoming directory must not
# erase historical months or trigger a different reporting batch.
empty_input<-file.path(test_root,"empty-input");dir.create(empty_input,showWarnings=FALSE)
retained<-icfg;retained$input_dir<-empty_input
c<-run_pipeline(retained,ROOT)
stopifnot(identical(c$status,"No input changes"),identical(before,digest::digest(file=current_path,algo="sha256")))
m<-jsonlite::read_json(current_path,simplifyVector=TRUE);batch<-file.path(icfg$output_dir,m$batch_relative_path)
for(n in names(m$row_counts)) {
  csv<-data.table::fread(file.path(batch,paste0(n,".csv")),colClasses="character",na.strings="",showProgress=FALSE)
  stopifnot(nrow(csv)==m$row_counts[[n]])
}
mock<-refresh_mock_tests(ROOT)
report<-list(passed=TRUE,workbook_reconciliation=recon,fixtures=fx[setdiff(names(fx),c("result","quality"))],
  integration_checks=c("CSV row counts and typed schema","No-change run does not republish","Concurrent-run lock","Failed input preserves successful publication","Unstable download is not imported","Empty incoming folder retains archived historical months"),power_bi_mock=mock,
  dummy_transform_seconds=transform_seconds,total_test_seconds=as.numeric(difftime(Sys.time(),start,units="secs")),
  power_bi_api="Not called: no Trust tenant credentials or gateway are configured")
write_json(report,file.path(ROOT,"tests","validation_results.json"));export_table(fx$quality,file.path(ROOT,"tests","fixture_quality_issues.csv"))
print(report)
