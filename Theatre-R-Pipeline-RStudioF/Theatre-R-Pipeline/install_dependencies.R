if(sys.nframe()>0L) {
  source_file<-tryCatch(sys.frame(1)$ofile,error=function(e)NULL)
  root<-if(!is.null(source_file)) dirname(normalizePath(source_file,winslash="/",mustWork=TRUE)) else normalizePath(getwd(),winslash="/",mustWork=TRUE)
} else {
  args <- commandArgs(trailingOnly=FALSE)
  file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
  root <- dirname(normalizePath(file_arg[1], winslash="/", mustWork=TRUE))
}
lib <- file.path(root, ".Rlibrary")
dir.create(lib, recursive=TRUE, showWarnings=FALSE)
.libPaths(c(lib, .libPaths()))
mirror<-Sys.getenv("THEATRE_CRAN_REPO",unset="")
if(nzchar(mirror)) options(repos=c(CRAN=mirror)) else if(is.null(getOption("repos"))||any(getOption("repos")=="@CRAN@")) options(repos=c(CRAN="https://cloud.r-project.org"))
options(timeout=max(300,getOption("timeout",60)))
packages <- c("readxl", "data.table", "jsonlite", "digest", "curl")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly=TRUE)]
if (length(missing)) install.packages(missing, lib=lib)
stopifnot(all(vapply(packages, requireNamespace, logical(1), quietly=TRUE)))
versions <- data.frame(Package=packages, Version=vapply(packages, function(p) as.character(packageVersion(p)), character(1)))
write.csv(versions, file.path(root, "package_versions.csv"), row.names=FALSE)
message("Dependencies available. Production package upgrades should be tested before deployment.")
