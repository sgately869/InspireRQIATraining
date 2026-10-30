validate_config <- function(cfg,root) {
  for(n in c("input_dir","state_dir","output_dir","snapshot_mode","filename_pattern","stable_seconds","start_finish_allowance_minutes","power_bi")) if(is.null(cfg[[n]])) stop("Missing config setting: ",n)
  if(cfg$snapshot_mode!="monthly_latest") stop("Only monthly_latest full-month/month-to-date snapshots are supported. Seven-day-only deltas need a different reconciliation policy.")
  if(cfg$start_finish_allowance_minutes!=10) stop("This validated version requires the agreed inclusive ten-minute allowance")
  if(!is.numeric(cfg$stable_seconds)||cfg$stable_seconds<0) stop("stable_seconds must be nonnegative")
  paths<-vapply(c(cfg$input_dir,cfg$state_dir,cfg$output_dir),absolute_path,character(1),root=root)
  canonical<-tolower(normalizePath(paths,winslash="/",mustWork=FALSE))
  if(anyDuplicated(canonical)) stop("Input, state and output directories must differ")
  if(!dir.exists(paths[1])) stop("Input directory does not exist: ",paths[1])
  invisible(TRUE)
}
export_table <- function(d,path) {
  x<-data.table::copy(d)
  for(n in names(x)) {
    if(n %in% DATETIME_FIELDS&&is.numeric(x[[n]])) {
      v<-x[[n]];x[[n]]<-ifelse(is.na(v),NA_character_,format(as.POSIXct(v,origin="1970-01-01",tz="UTC"),"%Y-%m-%dT%H:%M:%OS6",tz="UTC"))
    } else if(is.list(x[[n]])) x[[n]]<-vapply(x[[n]],clean_text,character(1))
  }
  x<-x[,!startsWith(names(x),"."),with=FALSE]
  data.table::fwrite(x,path,na="",quote="auto",bom=TRUE,logical01=FALSE)
}
summarise_sessions <- function(s,frequency="Month") {
  d<-data.table::copy(s)
  if(frequency=="Week") {
    dates<-as.Date(d[["Procedure Date"]]);d[["Period"]]<-as.character(dates-(as.integer(format(dates,"%u"))-1L))
  } else d[["Period"]]<-d[["Month"]]
  dimensions<-c("Period","Hospital","Theatre Type","Session Specialty","Responsible Consultant","Consultant Attribution")
  measures<-c("No of Sessions","No of Patients","Patients Excluded - Missing Times","Session Duration","Run Minutes","Op Minutes",
    "Session Duration Used for Run Time","Session Duration Used for Op Time","Sessions Used for Run Time","Sessions Used for Op Time",
    "Partial Run Time Sessions","Partial Op Time Sessions","Starts Assessed","Finishes Assessed","Early Starts","On-Time Starts","Late Starts","Early Finishes","On-Time Finishes","Late Finishes",
    "Scheduled Minutes","Sessions Used for Scheduling","Session Duration Used for Scheduling","Below Planned Load","At Planned Load","Above Planned Load")
  out<-d[,lapply(.SD,function(x) sum(x,na.rm=TRUE)),by=dimensions,.SDcols=measures]
  out[["Run Utilisation"]]<-ifelse(out[["Session Duration Used for Run Time"]]>0,out[["Run Minutes"]]/out[["Session Duration Used for Run Time"]],NA_real_)
  out[["Op Utilisation"]]<-ifelse(out[["Session Duration Used for Op Time"]]>0,out[["Op Minutes"]]/out[["Session Duration Used for Op Time"]],NA_real_)
  out[["Start On-Time Rate"]]<-ifelse(out[["Starts Assessed"]]>0,out[["On-Time Starts"]]/out[["Starts Assessed"]],NA_real_)
  out[["Finish On-Time Rate"]]<-ifelse(out[["Finishes Assessed"]]>0,out[["On-Time Finishes"]]/out[["Finishes Assessed"]],NA_real_)
  out
}
publish_batch <- function(result,scan,cfg,root,state,output,elapsed) {
  run_id<-paste0(format(Sys.time(),"%Y%m%dT%H%M%SZ",tz="UTC"),"-",substr(scan$signature,1,10))
  batches<-file.path(output,"batches");dir.create(batches,recursive=TRUE,showWarnings=FALSE)
  staging<-file.path(batches,paste0(".staging-",run_id));dest<-file.path(batches,run_id)
  if(dir.exists(dest)||dir.exists(staging)) stop("Batch directory already exists; retry on the next scheduler run")
  dir.create(staging)
  quality<-build_quality(result$sessions,result$procedures)
  provenance<-result$procedures[,.(SourceFile=`Source File`,InputRow=`Input Row`,SessionID=`Session ID`)]
  procedures<-data.table::copy(result$procedures)
  # Source values accompany normalised columns. The exact originals are also
  # retained in the content-addressed XLSX archive and typed RDS import cache.
  original<-data.table::copy(scan$raw)
  raw_names<-setdiff(names(original),c("Source File","Input Row"))
  for(n in raw_names) procedures[[paste0("Raw: ",n)]]<-vapply(original[[n]],clean_text,character(1))
  tables<-list(sessions=result$sessions,patients=result$patients,procedures=procedures,operations=result$operations,
    data_quality_issues=quality,input_inventory=scan$inventory,monthly_summary=summarise_sessions(result$sessions,"Month"),weekly_summary=summarise_sessions(result$sessions,"Week"))
  schema<-lapply(tables,function(d) lapply(names(d)[!startsWith(names(d),".")],function(n) list(name=n,type=if(n %in% DATETIME_FIELDS&&is.numeric(d[[n]])) "datetime" else if(n %in% DATE_FIELDS || n=="Period") "date" else if(is.logical(d[[n]])) "logical" else if(is.numeric(d[[n]])) "number" else "text")))
  row_counts<-vapply(tables,nrow,integer(1));row_counts<-as.list(row_counts)
  for(n in names(tables)) export_table(tables[[n]],file.path(staging,paste0(n,".csv")))
  manifest<-list(schema_version=1,pipeline_version=PIPELINE_VERSION,run_id=run_id,input_signature=scan$signature,
    processed_utc=utc_now(),batch_relative_path=paste0("batches/",run_id),selected_inputs=as.data.frame(scan$selected),
    row_counts=row_counts,transform_elapsed_seconds=elapsed,source_timing_assumption="Start/End Time provisionally represent anaesthesia/procedure commencement and theatre discharge-ready time. Clinical datetimes use naive Excel wall-clock arithmetic.",
    coverage_note="Extract coverage is declared by timestamped filename. Missing coverage is unknown, not inferred from the latest patient date.",
    metric_note="Run and op rates use their separate assessed planned-minute denominators. Planned session duration includes every valid represented session.")
  write_json(schema,file.path(staging,"schema.json"));write_json(manifest,file.path(staging,"batch.json"))
  if(!file.rename(staging,dest)) stop("Could not publish completed batch directory")
  # All CSVs are immutable and complete before the single pointer is changed.
  # One pipeline job owns publishing and refresh; do not schedule an independent
  # Power BI refresh across a publication boundary in this file-based design.
  atomic_json(manifest,file.path(output,"current.json"))
  if(isTRUE(cfg$power_bi$enabled)) write_json(list(run_id=run_id,requested_utc=NULL,request_id=NULL),file.path(state,"pending_refresh.json"))
  manifest
}
run_pipeline <- function(cfg,root,force=FALSE) {
  validate_config(cfg,root)
  state<-absolute_path(cfg$state_dir,root);output<-absolute_path(cfg$output_dir,root)
  dir.create(state,recursive=TRUE,showWarnings=FALSE);dir.create(output,recursive=TRUE,showWarnings=FALSE)
  lock<-file.path(state,"pipeline.lock")
  if(!dir.create(lock,showWarnings=FALSE)) stop("Another run is active, or a previous interrupted run left pipeline.lock. Confirm the owner process has stopped before removing that lock.")
  write_json(list(pid=Sys.getpid(),host=Sys.info()[["nodename"]],started_utc=utc_now()),file.path(lock,"owner.json"))
  on.exit({
    expected<-normalizePath(file.path(state,"pipeline.lock"),winslash="/",mustWork=FALSE)
    if(identical(normalizePath(lock,winslash="/",mustWork=FALSE),expected)&&basename(lock)=="pipeline.lock") unlink(lock,recursive=TRUE)
  },add=TRUE)
  logdir<-file.path(state,"logs");dir.create(logdir,showWarnings=FALSE)
  logpath<-file.path(logdir,paste0(format(Sys.time(),"%Y%m%dT%H%M%SZ",tz="UTC"),"-",Sys.getpid(),".json"))
  started<-Sys.time();status<-list(started_utc=utc_now(),pipeline_version=PIPELINE_VERSION)
  tryCatch({
    current_path<-file.path(output,"current.json")
    current<-if(file.exists(current_path)) jsonlite::read_json(current_path,simplifyVector=TRUE) else NULL
    # A published-but-unconfirmed refresh is completed before any later batch
    # can overwrite the publication pointer. No changed input is lost.
    if(file.exists(file.path(state,"pending_refresh.json"))) {
      if(!isTRUE(cfg$power_bi$enabled)) stop("A Power BI refresh is pending. Re-enable its integration or investigate before continuing.")
      status$refresh_recovery<-refresh_power_bi(cfg,state,current)
    }
    scan<-scan_inputs(cfg,root,force)
    if(!force&&!is.null(current)&&identical(scan$signature,current$input_signature)) {
      status$status<-"No input changes";status$run_id<-current$run_id
      saveRDS(scan$inventory,scan$catalog_path)
    } else {
      begin<-Sys.time();result<-transform_theatres(scan$raw,cfg$start_finish_allowance_minutes)
      if(!nrow(result$sessions)) stop("No valid sessions remain; previous successful output retained")
      elapsed<-as.numeric(difftime(Sys.time(),begin,units="secs"))
      assert_power_bi_idle(cfg)
      manifest<-publish_batch(result,scan,cfg,root,state,output,elapsed)
      saveRDS(scan$inventory,scan$catalog_path)
      status$status<-"Published";status$run_id<-manifest$run_id;status$row_counts<-manifest$row_counts
      status$power_bi<-refresh_power_bi(cfg,state,manifest)
    }
    status$finished_utc<-utc_now();status$elapsed_seconds<-as.numeric(difftime(Sys.time(),started,units="secs"))
    write_json(status,logpath);write_json(status,file.path(state,"last_run.json"));status
  },error=function(e) {
    status$status<-"Failed";status$error<-conditionMessage(e);status$finished_utc<-utc_now()
    write_json(status,logpath);write_json(status,file.path(state,"last_run.json"));stop(conditionMessage(e),call.=FALSE)
  })
}
