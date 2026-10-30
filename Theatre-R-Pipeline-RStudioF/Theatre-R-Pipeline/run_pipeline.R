if(sys.nframe()>0L) stop("In RStudio, open the project and use source('rstudio.R'), then theatre_run(). This file is the command-line launcher.",call.=FALSE)
args0<-commandArgs(trailingOnly=FALSE)
file_arg<-sub("^--file=","",args0[grepl("^--file=",args0)])
ROOT<-dirname(normalizePath(file_arg[1],winslash="/",mustWork=TRUE))
.libPaths(c(file.path(ROOT,".Rlibrary"),.libPaths()))
packages<-c("readxl","data.table","jsonlite","digest","curl")
missing<-packages[!vapply(packages,requireNamespace,logical(1),quietly=TRUE)]
if(length(missing)) stop("Missing packages: ",paste(missing,collapse=", "),". Run install_dependencies.R first.")
suppressPackageStartupMessages(library(data.table))
data.table::setDTthreads(2L)
PIPELINE_VERSION<-"1.0.1"
for(f in c("utils.R","import.R","transform.R","quality.R","refresh.R","pipeline.R")) source(file.path(ROOT,"R",f),local=FALSE)
args<-commandArgs(trailingOnly=TRUE)
config_path<-if(length(args)&&!startsWith(args[1],"--")) absolute_path(args[1],ROOT) else file.path(ROOT,"config.demo.json")
cfg<-jsonlite::read_json(config_path,simplifyVector=TRUE)
result<-tryCatch(run_pipeline(cfg,ROOT,force="--force" %in% args),error=function(e) {
  message("FAILED: ",conditionMessage(e));quit(save="no",status=1L)
})
print(result)
