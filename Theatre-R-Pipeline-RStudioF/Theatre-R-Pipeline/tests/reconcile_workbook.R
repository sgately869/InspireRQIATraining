reconcile_workbook <- function(result,root) {
  ref<-data.table::fread(file.path(root,"tests/reference/SessionReviewTable.csv"),colClasses="character",na.strings="")
  actual<-data.table::copy(result$sessions)
  missing<-setdiff(names(ref),names(actual));if(length(missing)) stop("Missing reference fields: ",paste(missing,collapse=", "))
  for(n in intersect(DATETIME_FIELDS,names(ref))) ref[[n]]<-vapply(ref[[n]],parse_dt,numeric(1),date=NA_character_)
  key<-function(d,fields) vapply(seq_len(nrow(d)),function(i) paste(vapply(fields,function(n) if(n %in% DATETIME_FIELDS) sprintf("%.3f",d[[n]][i]) else as.character(d[[n]][i]),character(1)),collapse="\037"),character(1))
  ix<-match(key(ref,SESSION_KEYS),key(actual,SESSION_KEYS));stopifnot(!anyNA(ix),nrow(ref)==nrow(actual))
  actual<-actual[ix];checks<-0L;fail<-list()
  for(n in names(ref)) {
    a<-actual[[n]];b<-ref[[n]]
    if(is.numeric(a)) {
      b<-suppressWarnings(as.numeric(b));equal<-is.na(a)&is.na(b)|!is.na(a)&!is.na(b)&if(is.integer(a)) a==b else abs(a-b)<if(n %in% DATETIME_FIELDS) 0.001 else 1e-5
    } else if(is.logical(a)) equal<-is.na(a)&is.na(b)|!is.na(a)&!is.na(b)&as.character(a)==b
    else equal<-is.na(a)&is.na(b)|!is.na(a)&!is.na(b)&as.character(a)==b
    if(any(!equal)) {bad<-which(!equal);fail[[n]]<-list(rows=head(bad,4),actual=head(a[bad],4),expected=head(b[bad],4))}
    checks<-checks+length(a)
  }
  if(length(fail)) {print(fail);stop("Workbook session reconciliation failed")}
  p_ref<-data.table::fread(file.path(root,"tests/reference/DrilldownTable.csv"),colClasses="character",na.strings="")
  p_ref<-p_ref[`Record Type`=="No. of patients"]
  for(n in intersect(DATETIME_FIELDS,names(p_ref))) p_ref[[n]]<-vapply(p_ref[[n]],parse_dt,numeric(1),date=NA_character_)
  p<-result$patients[`Counted Patient`==1]
  ix<-match(key(p_ref,c(SESSION_KEYS,"Patient CSN")),key(p,c(SESSION_KEYS,"Patient CSN")))
  stopifnot(!anyNA(ix),nrow(p_ref)==nrow(p));p<-p[ix]
  for(n in c("Log IDs","Primary Procedures","Other Procedures","Procedure Specialty","Responsible Consultants","First Procedure Start","Last Procedure End","Procedure Rows","Source Files")) {
    a<-p[[n]];b<-p_ref[[n]]
    if(is.numeric(a)) b<-suppressWarnings(as.numeric(b))
    equal<-is.na(a)&is.na(b)|!is.na(a)&!is.na(b)&if(is.integer(a)) a==b else if(is.numeric(a)) abs(a-b)<if(n %in% DATETIME_FIELDS) 0.001 else 1e-5 else as.character(a)==b
    if(any(!equal)) stop("Patient drilldown reconciliation failed: ",n)
    checks<-checks+length(a)
  }
  list(passed=TRUE,session_rows=nrow(actual),session_fields=ncol(ref),patient_rows=nrow(p),cell_comparisons=checks,
    sessions=sum(actual[["No of Sessions"]]),patients=sum(actual[["No of Patients"]]),planned_minutes=sum(actual[["Session Duration"]]),
    run_minutes=sum(actual[["Run Minutes"]],na.rm=TRUE),op_minutes=sum(actual[["Op Minutes"]],na.rm=TRUE))
}
