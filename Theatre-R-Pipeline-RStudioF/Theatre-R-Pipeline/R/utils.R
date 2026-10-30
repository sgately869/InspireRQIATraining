# Clinical datetimes are naive wall-clock values, as in Excel/Power Query.
# UTC is only the storage convention for these values, avoiding a DST conversion.
# Audit/run timestamps, separately labelled UTC, are real UTC instants.
clean_text <- function(x) {
  if (length(x)==0L || is.null(x) || is.na(x[1])) return(NA_character_)
  z <- if (inherits(x,"POSIXt")) format(x,tz="UTC",format="%Y-%m-%dT%H:%M:%OS6") else if (inherits(x,"Date")) format(x,"%Y-%m-%d") else if (is.numeric(x)) format(x, scientific=FALSE, trim=TRUE, digits=16) else as.character(x)
  z <- trimws(z[1]); if (!nzchar(z)) NA_character_ else z
}
strip_code <- function(x) sub("\\s*\\[[0-9]+\\]$", "", x)
join_text <- function(x) {z<-sort(unique(na.omit(vapply(as.list(x), clean_text, character(1))))); if(length(z)) paste(z,collapse="; ") else NA_character_}
num <- function(x) {z<-clean_text(x); if(is.na(z)) return(NA_real_); suppressWarnings(as.numeric(gsub(",","",z,fixed=TRUE)))}
min_na <- function(x) if(all(is.na(x))) NA_real_ else min(x,na.rm=TRUE)
max_na <- function(x) if(all(is.na(x))) NA_real_ else max(x,na.rm=TRUE)
sum_na <- function(x) if(all(is.na(x))) NA_real_ else sum(x,na.rm=TRUE)
same_values <- function(d, cols) nrow(unique(d[, ..cols])) == 1L
is_clock <- function(x) {
  if(length(x)==0L || is.null(x) || anyNA(x)) return(FALSE)
  if(inherits(x,c("POSIXt","Date"))) return(FALSE)
  if(is.numeric(x)) return(is.finite(x) && x>=0 && x<1)
  z<-trimws(as.character(x))
  grepl("^([01]?[0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9](\\.[0-9]+)?)?$",z) || grepl("^(0?[1-9]|1[0-2]):[0-5][0-9](:[0-5][0-9](\\.[0-9]+)?)? ?[AaPp][Mm]$",z)
}
parse_date <- function(x) {
  if(length(x)==0L || is.null(x) || anyNA(x)) return(NA_character_)
  if(inherits(x,"POSIXt")) return(format(x,tz="UTC",format="%Y-%m-%d"))
  if(inherits(x,"Date")) return(format(x,"%Y-%m-%d"))
  if(is.numeric(x)) return(format(as.Date(floor(x),origin="1899-12-30"),"%Y-%m-%d"))
  s<-trimws(as.character(x))
  for(f in c("%Y-%m-%d","%d/%m/%Y","%d/%m/%y","%d-%b-%Y")) {
    y<-suppressWarnings(as.Date(s,format=f)); if(!is.na(y)) return(format(y,"%Y-%m-%d"))
  }; NA_character_
}
parse_dt <- function(x, date) {
  if(length(x)==0L || is.null(x) || anyNA(x)) return(NA_real_)
  if(inherits(x,"POSIXt")) return(round(as.numeric(x),6))
  if(inherits(x,"Date")) return(as.numeric(as.POSIXct(x,tz="UTC")))
  if(is.numeric(x)) {
    if(!is.finite(x)) return(NA_real_)
    if(is_clock(x)) return(if(is.na(date)) NA_real_ else as.numeric(as.POSIXct(date,tz="UTC"))+x*86400)
    return(round((x-25569)*86400,6))
  }
  s<-trimws(as.character(x))
  if(is_clock(x)) {
    if(is.na(date)) return(NA_real_)
    ampm<-grepl("[AaPp][Mm]$",s)
    if(ampm) s<-sub(" ?([AaPp][Mm])$"," \\1",s)
    formats<-if(ampm) c("%I:%M:%OS %p","%I:%M %p") else c("%H:%M:%OS","%H:%M")
    for(f in formats) {
      y<-suppressWarnings(as.POSIXct(strptime(paste(date,s),paste("%Y-%m-%d",f),tz="UTC")))
      if(!is.na(y)) return(round(as.numeric(y),6))
    }; return(NA_real_)
  }
  # Offset-bearing timestamps need an explicit source timezone policy.
  if(grepl("(Z|[+-][0-9]{2}:?[0-9]{2})$",s)) return(NA_real_)
  for(f in c("%Y-%m-%dT%H:%M:%OS","%Y-%m-%d %H:%M:%OS","%d/%m/%Y %H:%M:%OS","%d/%m/%Y %H:%M","%Y-%m-%d")) {
    y<-suppressWarnings(as.POSIXct(strptime(s,f,tz="UTC"))); if(!is.na(y)) return(round(as.numeric(y),6))
  }; NA_real_
}
dt_date <- function(x) if(is.na(x)) NA_character_ else format(as.POSIXct(x,origin="1970-01-01",tz="UTC"),"%Y-%m-%d",tz="UTC")
align_pair <- function(raw_start,raw_end,date,slot_start,slot_end,align_orphan_end=TRUE) {
  s<-parse_dt(raw_start,date); e<-NA_real_
  distance<-function(x) max(slot_start-x, x-slot_end,0)
  overnight<-!is.na(slot_start)&&!is.na(slot_end)&&dt_date(slot_end)>dt_date(slot_start)
  if(!is.na(s)&&is_clock(raw_start)&&overnight&&s<slot_start&&distance(s+86400)<distance(s)) s<-s+86400
  e<-parse_dt(raw_end,if(is.na(s)) date else dt_date(s))
  if(!is.na(s)&&!is.na(e)&&e<s&&is_clock(raw_end)) e<-e+86400
  else if(align_orphan_end&&is.na(s)&&!is.na(e)&&is_clock(raw_end)&&overnight&&distance(e+86400)<distance(e)) e<-e+86400
  list(start=s,end=e)
}
union_minutes <- function(s,e) {
  ok<-!is.na(s)&!is.na(e)&e>=s; s<-s[ok];e<-e[ok]
  if(!length(s)) return(NA_real_)
  o<-order(s,e);s<-s[o];e<-e[o];last<-e[1];first<-s[1];total<-0
  if(length(s)>1) for(i in 2:length(s)) {
    if(s[i]<=last) last<-max(last,e[i]) else {total<-total+last-first;first<-s[i];last<-e[i]}
  }; (total+last-first)/60
}
stable_id <- function(x) digest::digest(jsonlite::toJSON(as.list(x),auto_unbox=TRUE,na="null",null="null",digits=NA),algo="sha256",serialize=FALSE)
utc_now <- function() format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC")
write_json <- function(x,path) jsonlite::write_json(x,path,auto_unbox=TRUE,pretty=TRUE,na="null",null="null",digits=NA)
absolute_path <- function(path,root) if(grepl("^([A-Za-z]:[/\\\\]|/|\\\\\\\\)",path)) path else file.path(root,path)
atomic_json <- function(x,path) {
  tmp<-paste0(path,".new"); write_json(x,tmp)
  # Native R file operations only: no PowerShell, command shell or subprocess.
  # The new file lives beside the destination so publication uses one same-folder
  # rename. If the filesystem refuses replacement, fail without deleting current.
  if(file.exists(path)&&!file.copy(path,paste0(path,".previous"),overwrite=TRUE)) stop("Could not preserve the previous manifest")
  if(!file.rename(tmp,path)) stop("Could not publish the manifest by same-folder rename; previous publication retained. Check destination permissions/locks.")
}
