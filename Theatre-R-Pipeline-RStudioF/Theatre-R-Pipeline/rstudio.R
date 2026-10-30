# Open Theatre-R-Pipeline.Rproj, then enter source("rstudio.R") in the R console.
# Loading this file does not process or publish any data.
ROOT<-normalizePath(getwd(),winslash="/",mustWork=TRUE)
if(!file.exists(file.path(ROOT,"Theatre-R-Pipeline.Rproj"))) stop("Open Theatre-R-Pipeline.Rproj first so the working directory is the project folder.",call.=FALSE)
.libPaths(c(file.path(ROOT,".Rlibrary"),.libPaths()))
packages<-c("readxl","data.table","jsonlite","digest","curl")
missing<-packages[!vapply(packages,requireNamespace,logical(1),quietly=TRUE)]
if(length(missing)) stop("Missing packages: ",paste(missing,collapse=", "),". Run source('install_dependencies.R') first, or ask the Trust R administrator to supply them.",call.=FALSE)
suppressPackageStartupMessages(library(data.table))
data.table::setDTthreads(2L)
PIPELINE_VERSION<-"1.0.1"
for(f in c("utils.R","import.R","transform.R","quality.R","refresh.R","pipeline.R")) source(file.path(ROOT,"R",f),local=FALSE)

theatre_run <- function(config="config.demo.json",force=FALSE) {
  config_path<-absolute_path(config,ROOT)
  if(!file.exists(config_path)) stop("Configuration not found: ",config_path,call.=FALSE)
  cfg<-jsonlite::read_json(config_path,simplifyVector=TRUE)
  answer<-run_pipeline(cfg,ROOT,force=force)
  print(answer)
  invisible(answer)
}

theatre_configure <- function(input_dir,output_dir="real-output",state_dir="real-state",overwrite=FALSE) {
  target<-file.path(ROOT,"config.production.json")
  if(file.exists(target)&&!overwrite) stop("config.production.json already exists. Edit it or explicitly set overwrite=TRUE.",call.=FALSE)
  cfg<-jsonlite::read_json(file.path(ROOT,"config.production.example.json"),simplifyVector=TRUE)
  cfg$input_dir<-input_dir;cfg$output_dir<-output_dir;cfg$state_dir<-state_dir
  cfg$power_bi$enabled<-FALSE
  validate_config(cfg,ROOT)
  write_json(cfg,target)
  message("Saved config.production.json. Power BI refresh remains disabled. Input Excel files will not be changed.")
  invisible(cfg)
}

theatre_status <- function(config="config.production.json") {
  cfg<-jsonlite::read_json(absolute_path(config,ROOT),simplifyVector=TRUE)
  state<-absolute_path(cfg$state_dir,ROOT);output<-absolute_path(cfg$output_dir,ROOT)
  status_path<-file.path(state,"last_run.json");manifest_path<-file.path(output,"current.json")
  answer<-list(last_run=if(file.exists(status_path)) jsonlite::read_json(status_path,simplifyVector=TRUE) else NULL,
    publication=if(file.exists(manifest_path)) jsonlite::read_json(manifest_path,simplifyVector=TRUE) else NULL,
    published_folder=output)
  print(answer);invisible(answer)
}
message("Ready. Demo: theatre_run(). Real data: theatre_configure(input_dir='//server/share/Theatres'); theatre_run('config.production.json').")
