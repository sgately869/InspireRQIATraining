REQUIRED_HEADERS <- c("Service Area","Location","Operating Theatre","Procedure Date","Patient CSN","Log ID","Primary Procedure","Other Procedures","Start Time","End Time","Operation Time Minutes (Performed)","Overlap Minutes (Performed)","Non-Overlap Operation Time Minutes (Performed)","Start Time (Scheduled)","End Time (Scheduled)","Operation Time minutes (Scheduled)","Procedure Specialty","Session","Slot Start Time","Slot End Time","Session Period","Emergency?","Funding Stream","Performed in Session","Session [Responsible Consultant]")
HEADER_ALIASES <- c("Primary Procedures"="Primary Procedure","Operation Time Minutes (Scheduled)"="Operation Time minutes (Scheduled)","Performed in Session?"="Performed in Session","Session (Responsible Consultant)"="Session [Responsible Consultant]")

read_theatre_file <- function(path,sheet=NULL) {
  sheets<-if(is.null(sheet)) readxl::excel_sheets(path) else sheet
  matches<-list()
  for(sn in sheets) {
    headers<-names(readxl::read_excel(path,sheet=sn,n_max=0,.name_repair="minimal"))
    headers<-trimws(headers);alias<-headers %in% names(HEADER_ALIASES);headers[alias]<-unname(HEADER_ALIASES[headers[alias]])
    if(all(REQUIRED_HEADERS %in% headers)) matches[[sn]]<-headers
  }
  if(length(matches)!=1L) stop(basename(path),": expected one sheet with the 25 required headers in row 1; found ",length(matches),". Set config.sheet if needed.")
  headers<-matches[[1]]
  if(anyDuplicated(headers)||any(!nzchar(headers))) stop("Blank or duplicate headings in ",basename(path))
  # List columns retain each cell's type, preserving numeric IDs and mixed Excel
  # clock times/full datetimes rather than guessing from the first 1000 rows.
  x<-readxl::read_excel(path,sheet=names(matches)[1],col_types="list",.name_repair="minimal",trim_ws=FALSE)
  names(x)<-headers;d<-data.table::as.data.table(x)
  d[["Input Row"]]<-seq_len(nrow(d))+1L
  nonempty<-vapply(seq_len(nrow(d)),function(i) any(vapply(REQUIRED_HEADERS,function(n) !is.na(clean_text(d[[n]][[i]])),logical(1))),logical(1))
  d<-d[nonempty];d[["Source File"]]<-basename(path)
  d
}

file_metadata <- function(path,raw) {
  name<-basename(path)
  periods<-unique(na.omit(vapply(raw[["Procedure Date"]],parse_date,character(1))))
  months<-unique(substr(periods,1,7))
  # The timestamped production naming convention is unambiguous and supports
  # multiple retained monthly snapshots without relying on file-copy timestamps.
  pattern<-"^THEATRES_([0-9]{4}-[0-9]{2})_through_([0-9]{4}-[0-9]{2}-[0-9]{2})_exported_([0-9]{8}T[0-9]{6}Z)\\.xlsx$"
  m<-regmatches(name,regexec(pattern,name,ignore.case=TRUE))[[1]]
  if(length(m)) {
    month<-m[2];through<-m[3];stamp<-m[4]
    parsed_through<-parse_date(through);parsed_stamp<-as.POSIXct(strptime(stamp,"%Y%m%dT%H%M%SZ",tz="UTC"))
    if(is.na(parsed_through)||is.na(parsed_stamp)||substr(through,1,7)!=month) stop("Invalid snapshot filename: ",name)
    if(length(months)&&any(months!=month)) stop("Procedure dates outside the filename's month: ",name)
    if(any(periods>through)) stop("Procedure dates after declared extract coverage: ",name)
  } else {
    if(length(months)!=1L) stop("Cannot infer exactly one snapshot month in ",name,"; use timestamped production naming.")
    month<-months[1];through<-NA_character_;stamp<-NA_character_
  }
  list(file=name,month=month,coverage_through=through,exported_utc=stamp,rows=nrow(raw))
}

select_snapshots <- function(inv) {
  selected<-inv[, {
    if(.N>1L) {
      if(anyNA(exported_utc)) stop("Multiple snapshots for ",.BY[[1]]," require timestamped production filenames; do not choose by file modified time.")
      latest<-max(exported_utc);pick<-which(exported_utc==latest)
      if(length(pick)>1&&data.table::uniqueN(sha256[pick])>1) stop("Conflicting exports with the same timestamp for ",.BY[[1]])
      .SD[pick[1]]
    } else .SD
  },by="month"]
  selected
}

scan_inputs <- function(cfg,root,force=FALSE) {
  input<-absolute_path(cfg$input_dir,root);state<-absolute_path(cfg$state_dir,root)
  cache<-file.path(state,"cache");archive<-file.path(state,"archive")
  dir.create(cache,recursive=TRUE,showWarnings=FALSE);dir.create(archive,recursive=TRUE,showWarnings=FALSE)
  paths<-list.files(input,pattern=cfg$filename_pattern,full.names=TRUE,ignore.case=TRUE)
  paths<-paths[!grepl("^~\\$",basename(paths))]
  catalog_path<-file.path(state,"catalog.rds")
  previous<-if(file.exists(catalog_path)) readRDS(catalog_path) else NULL
  if(!length(paths)&&is.null(previous)) stop("No input Excel files matched in ",input)
  importer_version<-stable_id(c(PIPELINE_VERSION,digest::digest(file=file.path(root,"R","import.R"),algo="sha256"),digest::digest(file=file.path(root,"R","utils.R"),algo="sha256"),cfg$sheet))
  inventory<-list();data<-list()
  for(path in sort(paths)) {
    info<-file.info(path)
    if(as.numeric(difftime(Sys.time(),info$mtime,units="secs"))<cfg$stable_seconds) stop("Input file is too recent; retry after it finishes copying: ",basename(path))
    hash<-digest::digest(file=path,algo="sha256");cp<-file.path(cache,paste0(hash,".rds"))
    # Cached imports are versioned by the importer as well as source contents.
    if(file.exists(cp)&&!force) {cached<-readRDS(cp);raw<-if(identical(cached$import_version,importer_version)) cached$raw else NULL} else raw<-NULL
    if(is.null(raw)) {
      raw<-read_theatre_file(path,cfg$sheet)
      if(!identical(hash,digest::digest(file=path,algo="sha256"))||file.info(path)$size!=info$size) stop("File changed while being read: ",basename(path))
      saveRDS(list(import_version=importer_version,raw=raw),cp)
    }
    raw[["Source File"]]<-basename(path)
    meta<-file_metadata(path,raw);meta$sha256<-hash;meta$bytes<-info$size
    if(!is.null(previous)&&any(previous$file==meta$file & previous$month!=meta$month)) stop("An existing source filename was reused for a different month: ",meta$file,". Include the reporting month in its filename.")
    ap<-file.path(archive,paste0(hash,".xlsx"));if(!file.exists(ap)&&!file.copy(path,ap)) stop("Could not archive ",basename(path))
    if(!identical(digest::digest(file=ap,algo="sha256"),hash)) stop("Archived source does not match the imported contents: ",basename(path))
    inventory[[length(inventory)+1L]]<-meta;data[[basename(path)]]<-raw
  }
  observed<-data.table::rbindlist(inventory,fill=TRUE)
  inv<-if(is.null(previous)) observed else if(!nrow(observed)) previous else data.table::rbindlist(list(previous[!file %in% observed$file],observed),fill=TRUE)
  inv<-data.table::copy(inv)
  if("Selected" %in% names(inv)) inv[,Selected:=NULL]
  selected<-select_snapshots(inv)
  if(any(selected$rows==0)&&!isTRUE(cfg$allow_empty_month)) stop("An empty monthly snapshot would erase a month. Review before enabling allow_empty_month.")
  inv[["Selected"]]<-inv$file %in% selected$file
  inv[["Present in Input"]]<-inv$file %in% basename(paths)
  # Historical months are retained from their exact archived source, even if
  # someone later clears the incoming folder. Missing files are not deletions.
  for(i in seq_len(nrow(selected))) {
    name<-selected$file[i]
    if(is.null(data[[name]])) {
      hash<-selected$sha256[i];cp<-file.path(cache,paste0(hash,".rds"));ap<-file.path(archive,paste0(hash,".xlsx"))
      cached<-if(file.exists(cp)&&!force) readRDS(cp) else NULL
      raw<-if(!is.null(cached)&&identical(cached$import_version,importer_version)) cached$raw else NULL
      if(is.null(raw)) {
        if(!file.exists(ap)||!identical(digest::digest(file=ap,algo="sha256"),hash)) stop("Archived historical source is missing or changed: ",name)
        raw<-read_theatre_file(ap,cfg$sheet);raw[["Source File"]]<-name
        saveRDS(list(import_version=importer_version,raw=raw),cp)
      }
      raw[["Source File"]]<-name;data[[name]]<-raw
    }
  }
  code_files<-sort(list.files(file.path(root,"R"),pattern="\\.R$",full.names=TRUE))
  code_hashes<-vapply(code_files,function(p)digest::digest(file=p,algo="sha256"),character(1))
  signature<-stable_id(c(PIPELINE_VERSION,code_hashes,cfg$start_finish_allowance_minutes,unlist(selected[order(month),c("file","sha256","coverage_through","exported_utc"),with=FALSE],use.names=FALSE)))
  list(raw=data.table::rbindlist(data[selected$file],fill=TRUE),inventory=inv,selected=selected,signature=signature,catalog_path=catalog_path)
}
