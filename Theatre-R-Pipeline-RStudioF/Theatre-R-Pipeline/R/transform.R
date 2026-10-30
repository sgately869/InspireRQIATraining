SESSION_KEYS <- c("Service Area","Location","Operating Theatre","Procedure Date","Slot Start Time","Slot End Time")
DATETIME_FIELDS <- c("Slot Start Time","Slot End Time","First Actual Start","Last Actual End","First Procedure Start","Last Procedure End","Actual Start","Actual End","Trusted Start","Trusted End","Scheduled Start","Scheduled End")
DATE_FIELDS <- c("Procedure Date","Month")

prepare_data <- function(raw) {
  d<-data.table::copy(raw)
  for(n in c("Service Area","Location","Operating Theatre","Session","Procedure Specialty","Patient CSN","Log ID")) {
    d[[n]]<-vapply(d[[n]],clean_text,character(1))
    if(n %in% c("Operating Theatre","Session","Procedure Specialty")) d[[n]]<-strip_code(d[[n]])
  }
  d[["Procedure Date"]]<-vapply(d[["Procedure Date"]],parse_date,character(1))
  ds<-d[["Procedure Date"]]
  ss<-mapply(parse_dt,d[["Slot Start Time"]],ds)
  ee<-mapply(parse_dt,d[["Slot End Time"]],ds)
  roll<-!is.na(ss)&!is.na(ee)&ee<ss&vapply(d[["Slot End Time"]],is_clock,logical(1))
  ee[roll]<-ee[roll]+86400
  d[["Slot Start Time"]]<-ss;d[["Slot End Time"]]<-ee
  issues<-vapply(seq_len(nrow(d)),function(i) {
    p<-character()
    for(n in c("Service Area","Location","Operating Theatre")) if(is.na(d[[n]][i])) p<-c(p,paste("Missing",n))
    if(is.na(ds[i])) p<-c(p,"Missing or invalid Procedure Date")
    if(is.na(ss[i])) p<-c(p,"Missing or invalid Slot Start Time")
    if(is.na(ee[i])) p<-c(p,"Missing or invalid Slot End Time")
    if(!is.na(ss[i])&&!is.na(ee[i])&&ee[i]<=ss[i]) p<-c(p,"Slot End Time must be after Slot Start Time")
    paste(p,collapse="; ")
  },character(1))
  d[["Include in Sessions"]]<-issues=="";d[["Missing Patient ID"]]<-is.na(d[["Patient CSN"]])
  d[["Issue Type"]]<-ifelse(issues!="","Excluded from sessions",ifelse(d[["Missing Patient ID"]],"Patient ID warning",NA_character_))
  d[["Issue Detail"]]<-ifelse(d[["Missing Patient ID"]],paste0(issues,ifelse(issues=="","","; "),"Missing Patient CSN: excluded from patient count"),issues)
  d[["Issue Detail"]][d[["Issue Detail"]]==""]<-NA_character_
  txt<-toupper(paste(d[["Location"]],d[["Operating Theatre"]]))
  d[["Hospital"]]<-ifelse(grepl("CAH|CRAIGAVON",txt),"Craigavon",ifelse(grepl("DHH|DAISY HILL",txt),"Daisy Hill",ifelse(grepl("STY|SOUTH TYRONE",txt),"South Tyrone","Unmapped")))
  d[["Theatre Type"]]<-ifelse(grepl("MATERNITY",txt),"Maternity",ifelse(grepl("PAEDS|PAEDIATRIC",txt),"Paediatric",ifelse(grepl("DPU|DAY PROCEDURE",txt),"DPU",ifelse(grepl("MAIN",txt),"Main","Unmapped"))))
  d[["Month"]]<-ifelse(is.na(ds),NA_character_,paste0(substr(ds,1,7),"-01"))
  yy<-suppressWarnings(as.integer(substr(ds,1,4)))-(suppressWarnings(as.integer(substr(ds,6,7)))<4)
  d[["Financial Year"]]<-ifelse(is.na(yy),NA_character_,sprintf("%02d/%02d",yy%%100,(yy+1)%%100))
  d[["Session ID"]]<-vapply(seq_len(nrow(d)),function(i) if(d[["Include in Sessions"]][i]) stable_id(unlist(d[i,..SESSION_KEYS],use.names=FALSE)) else NA_character_,character(1))
  aa<-lapply(seq_len(nrow(d)),function(i) if(d[["Include in Sessions"]][i]) align_pair(d[["Start Time"]][[i]],d[["End Time"]][[i]],ds[i],ss[i],ee[i]) else list(start=NA_real_,end=NA_real_))
  d[[".actualStart"]]<-vapply(aa,`[[`,numeric(1),"start");d[[".actualEnd"]]<-vapply(aa,`[[`,numeric(1),"end")
  # Patient eligibility intentionally matches the workbook's independent bounds.
  ps<-mapply(parse_dt,d[["Start Time"]],ds);pe<-mapply(parse_dt,d[["End Time"]],ds)
  proll<-!is.na(ps)&!is.na(pe)&pe<ps&vapply(d[["End Time"]],is_clock,logical(1));pe[proll]<-pe[proll]+86400
  d[[".patientStart"]]<-ps;d[[".patientEnd"]]<-pe
  d
}

build_patients <- function(d) {
  p<-d[`Include in Sessions` & !is.na(`Patient CSN`), {
    s<-min_na(.patientStart);e<-max_na(.patientEnd)
    list(`Patient Session ID`=stable_id(c(.BY[[1]],.BY[[2]])),`First Procedure Start`=s,`Last Procedure End`=e,
      `Counted Patient`=as.integer(!is.na(s)&&!is.na(e)),`Log IDs`=join_text(`Log ID`),
      `Primary Procedures`=join_text(`Primary Procedure`),`Other Procedures`=join_text(`Other Procedures`),
      `Procedure Specialty`=join_text(`Procedure Specialty`),`Responsible Consultants`=join_text(`Session [Responsible Consultant]`),
      `Procedure Rows`=.N,`Source Files`=join_text(`Source File`))
  },by=c("Session ID","Patient CSN")]
  p
}

build_operations <- function(rows) {
  t<-data.table::copy(rows)
  t[[".problem"]]<-ifelse(is.na(t$.actualStart)|is.na(t$.actualEnd),"Missing or invalid actual Start Time / End Time",ifelse(t$.actualEnd<t$.actualStart,"Actual End Time is before Start Time",NA_character_))
  t[[".operationKey"]]<-vapply(seq_len(nrow(t)),function(i) if(!is.na(t[["Log ID"]][i])) paste0("Log:",t[["Log ID"]][i]) else paste0("Timing:",stable_id(c(t[["Patient CSN"]][i],t$.actualStart[i],t$.actualEnd[i]))),character(1))
  result<-t[, {
    conflict<-nrow(unique(.SD[,c("Patient CSN",".actualStart",".actualEnd",".problem"),with=FALSE]))!=1
    r<-.SD[1];s<-r$.actualStart;e<-r$.actualEnd
    reversed<-!is.na(s)&&!is.na(e)&&e<s
    problem<-if(conflict) "Conflicting patient or timing values for the same Log ID" else r$.problem
    sid<-is.na(r[["Patient CSN"]]); vals<-list();value_issues<-logical()
    for(n in c("Operation Time Minutes (Performed)","Non-Overlap Operation Time Minutes (Performed)","Overlap Minutes (Performed)")) {
      raw<-.SD[[n]];raw<-raw[!vapply(raw,function(z)is.na(clean_text(z)),logical(1))]
      v<-vapply(raw,num,numeric(1));good<-v[is.finite(v)&v>=0];distinct<-unique(good)
      bad<-length(good)!=length(raw)||length(distinct)>1
      vals[[n]]<-if(!conflict&&!bad&&length(distinct)==1) distinct else NA_real_
      value_issues<-c(value_issues,bad)
    }
    c(list(`Actual Start`=s,`Actual End`=e,`Timing Problem`=problem,
      `Trusted Start`=if(conflict||reversed) NA_real_ else s,`Trusted End`=if(conflict||reversed) NA_real_ else e,
      `Patient CSN`=r[["Patient CSN"]],`Log ID`=r[["Log ID"]],`Patient Key`=if(sid) paste0("Operation:",.BY[[1]]) else paste0("Patient:",r[["Patient CSN"]]),
      `Missing Patient ID`=sid,`Valid Op Interval`=is.na(problem),Conflict=conflict,Reversed=!conflict&&reversed,
      Missing=!conflict&&!reversed&&(is.na(s)||is.na(e)),`Source Rows`=.N,`Source Files`=join_text(`Source File`),
      `Input Rows`=paste(paste0(`Source File`,":",`Input Row`),collapse="; "),`Supplied Value Issue`=conflict||any(value_issues)),
      setNames(vals,c("Supplied Performed","Supplied Non-Overlap","Supplied Overlap")))
  },by=".operationKey"]
  data.table::setnames(result,".operationKey","Operation Key")
  result
}

build_scheduling <- function(rows) {
  cv<-vapply(rows[["Session [Responsible Consultant]"]],clean_text,character(1));known<-sort(unique(cv[!is.na(cv)]),method="radix")
  known<-known[!duplicated(tolower(known))];miss<-sum(is.na(cv))
  attribution<-if(!length(known)) "Unspecified" else if(miss>0) "Incomplete attribution" else if(length(known)>1) "Multiple consultants" else "Single consultant"
  consultant<-if(attribution=="Single consultant") known[1] else if(attribution=="Multiple consultants") "Mixed / multiple" else attribution
  d<-data.table::copy(rows);d[[".scheduledValue"]]<-vapply(d[["Operation Time minutes (Scheduled)"]],num,numeric(1))
  d[[".minuteProblem"]]<-ifelse(is.na(d$.scheduledValue),"Missing or invalid scheduled operation minutes",ifelse(!is.finite(d$.scheduledValue),"Invalid non-finite scheduled operation minutes",ifelse(d$.scheduledValue<0,"Negative scheduled operation minutes",NA_character_)))
  d$.scheduledValue[!is.na(d$.minuteProblem)]<-NA_real_
  pairs<-lapply(seq_len(nrow(d)),function(i) align_pair(d[["Start Time (Scheduled)"]][[i]],d[["End Time (Scheduled)"]][[i]],d[["Procedure Date"]][i],d[["Slot Start Time"]][i],d[["Slot End Time"]][i],FALSE))
  d[[".s"]]<-vapply(pairs,`[[`,numeric(1),"start");d[[".e"]]<-vapply(pairs,`[[`,numeric(1),"end")
  d[[".timingProblem"]]<-ifelse(is.na(d$.s)|is.na(d$.e),"Missing or invalid scheduled Start Time / End Time",ifelse(d$.e<d$.s,"Scheduled End Time is before Start Time",NA_character_))
  d[[".durationWarning"]]<-ifelse(is.na(d$.timingProblem)&is.na(d$.minuteProblem)&abs((d$.e-d$.s)/60-d$.scheduledValue)>1e-6,"Supplied scheduled minutes differ from scheduled start/end duration",NA_character_)
  ambiguous<-is.na(d[["Log ID"]])&(is.na(d[["Patient CSN"]])|!is.na(d$.timingProblem))
  d[[".identityWarning"]]<-ifelse(ambiguous,"Missing Log ID and incomplete identity: source rows retained separately",NA_character_)
  d[[".key"]]<-vapply(seq_len(nrow(d)),function(i) if(!is.na(d[["Log ID"]][i])) paste0("Log:",d[["Log ID"]][i]) else if(ambiguous[i]) paste0("SourceRow:",i) else stable_id(c(d[["Patient CSN"]][i],d$.s[i],d$.e[i])),character(1))
  ops<-d[, {
    conflict<-nrow(unique(.SD[,c("Patient CSN",".scheduledValue",".minuteProblem"),with=FALSE]))!=1
    problem<-if(conflict) "Conflicting patient or scheduled minutes for the same operation" else .minuteProblem[1]
    warnings<-unique(na.omit(c(.timingProblem,.durationWarning,.identityWarning,if(nrow(unique(.SD[,c(".s",".e"),with=FALSE]))>1) "Conflicting scheduled timestamps for the same operation; supplied minutes retained")))
    list(Minutes=.scheduledValue[1],Problem=problem,Warnings=list(warnings))
  },by=".key"]
  problems<-na.omit(ops$Problem);notes<-unique(c(problems,unlist(ops$Warnings)))
  list(`Responsible Consultant`=consultant,`Consultant Names`=if(length(known)) paste(known,collapse="; ") else NA_character_,
    `Consultant Attribution`=attribution,`Missing Consultant Rows`=miss,`Scheduled Minutes`=if(length(problems)) NA_real_ else sum_na(ops$Minutes),
    `Scheduled Operations`=nrow(ops),`Repeated Scheduled Rows`=nrow(rows)-nrow(ops),`Scheduling Issues`=length(problems),
    `Scheduling Notes`=if(length(notes)) paste(notes,collapse="; ") else NA_character_)
}

session_record <- function(rows, patients, allowance) {
  r<-as.list(rows[1,..SESSION_KEYS]);r[["Session ID"]]<-rows[["Session ID"]][1]
  p<-patients[patients[["Session ID"]]==r[["Session ID"]]]
  specialty<-sort(unique(na.omit(rows$Session)))
  r<-c(r,list(`No of Sessions`=1L,`No of Patients`=sum(p[["Counted Patient"]]),`Patients Excluded - Missing Times`=sum(p[["Counted Patient"]]==0),
    `Session Specialty`=if(!length(specialty)) "Unspecified" else if(length(specialty)==1) specialty else "Mixed / multiple",
    `Mixed Session Specialty`=length(specialty)>1,`Source Files`=join_text(rows[["Source File"]]),`Procedure Rows`=nrow(rows),
    `Missing Patient IDs`=sum(rows[["Missing Patient ID"]]),Hospital=rows$Hospital[1],`Theatre Type`=rows[["Theatre Type"]][1],
    Month=rows$Month[1],`Financial Year`=rows[["Financial Year"]][1],`Session Duration`=round((r[["Slot End Time"]]-r[["Slot Start Time"]])/60),
    Trust=if(toupper(trimws(r[["Service Area"]]))=="HSC SOUTHERN TRUST") "Southern" else r[["Service Area"]]))
  o<-build_operations(rows);issue_count<-sum(!is.na(o[["Timing Problem"]]));starts<-o[["Trusted Start"]];ends<-o[["Trusted End"]]
  first<-min_na(starts);last<-max_na(ends);run<-if(is.na(first)||is.na(last)||last<first) NA_real_ else (last-first)/60
  valid<-o[o[["Valid Op Interval"]]];nvalid<-nrow(valid);excluded<-nrow(o)-nvalid
  raw_minutes<-if(!nvalid) NA_real_ else sum((valid[["Actual End"]]-valid[["Actual Start"]])/60)
  patient_minutes<-if(!nvalid) NA_real_ else sum(valid[,.(M=union_minutes(`Actual Start`,`Actual End`)),by="Patient Key"]$M)
  op<-union_minutes(valid[["Actual Start"]],valid[["Actual End"]]);same_removed<-if(nvalid) max(0,raw_minutes-patient_minutes) else NA_real_
  concurrent<-if(nvalid) max(0,patient_minutes-op) else NA_real_
  sc<-vapply(c("Supplied Performed","Supplied Non-Overlap","Supplied Overlap"),function(n) sum(!is.na(o[[n]])),integer(1))
  supplied_status<-if(!sum(sc)) "Unavailable" else if(all(sc==nrow(o))) "Complete" else "Partial recorded values"
  fmt<-function(x) format(round(x,6),scientific=FALSE,trim=TRUE)
  notes<-unique(na.omit(o[["Timing Problem"]]))
  if(!is.na(run)&&issue_count>0) notes<-c(notes,"Partial recorded run span: earliest usable start to latest usable end; incomplete or excluded patient intervals may understate actual run time")
  if(is.na(run)) notes<-c(notes,"Run time unavailable: usable start and end boundaries do not establish a nonnegative interval")
  if(nvalid>0&&excluded>0) notes<-c(notes,"Partial recorded theatre time: valid operation intervals included; missing, reversed or conflicting intervals excluded")
  if(!nvalid) notes<-c(notes,"Op time unavailable: no complete valid operation interval")
  if(!is.na(same_removed)&&same_removed>1e-6) notes<-c(notes,paste0("Same-patient overlapping log intervals merged: ",fmt(same_removed)," minutes removed from Op Minutes"))
  if(!is.na(concurrent)&&concurrent>1e-6) notes<-c(notes,paste0("Concurrent patient intervals: ",fmt(concurrent)," overlapping patient-minutes excluded from Op Minutes to count each occupied theatre minute once; retained in Recorded Patient Op Minutes"))
  mid<-sum(valid[["Missing Patient ID"]]);sissues<-sum(o[["Supplied Value Issue"]])
  if(mid>0) notes<-c(notes,"Missing patient ID on valid op intervals: included in theatre union; patient-time audit retains operation identity, so same-patient overlap cannot be assessed")
  if(sissues>0) notes<-c(notes,"Invalid or conflicting supplied op-minute comparison values excluded")
  r<-c(r,list(`Run Minutes`=run,`Op Minutes`=op,`Run Timing Issues`=issue_count,`Op Timing Issues`=issue_count,
    `First Actual Start`=first,`Last Actual End`=last,`Timed Operations`=nrow(o),`Repeated Timing Rows`=nrow(rows)-nrow(o),
    `Timing Notes`=if(length(notes)) paste(notes,collapse="; ") else NA_character_,
    `Valid Op Intervals`=nvalid,`Excluded Op Intervals`=excluded,`Raw Valid Op Minutes`=raw_minutes,`Same-Patient Overlap Minutes Removed`=same_removed,
    `Theatre Non-Overlap Minutes`=op,`Concurrent Patient Minutes`=concurrent,`Missing Patient ID Op Intervals`=mid,
    `Conflicting Timing Operations`=sum(o$Conflict),`Reversed Timing Operations`=sum(o$Reversed),`Missing Timing Operations`=sum(o$Missing),
    `Supplied Performed Op Minutes`=sum_na(o[["Supplied Performed"]]),`Supplied Non-Overlap Op Minutes`=sum_na(o[["Supplied Non-Overlap"]]),
    `Supplied Overlap Minutes`=sum_na(o[["Supplied Overlap"]]),`Supplied Performed Op Intervals`=sc[1],`Supplied Non-Overlap Op Intervals`=sc[2],
    `Supplied Overlap Op Intervals`=sc[3],`Supplied Op Comparison Status`=supplied_status,`Supplied Op Value Issues`=sissues,`Recorded Patient Op Minutes`=patient_minutes))
  r[["Sessions Used for Timing"]]<-as.integer(issue_count==0&&!is.na(run)&&!is.na(op));r[["Sessions Excluded from Timing"]]<-1L-r[["Sessions Used for Timing"]]
  r[["Session Duration Used for Timing"]]<-r[["Sessions Used for Timing"]]*r[["Session Duration"]]
  for(metric in c("Run","Op")) {
    usable<-as.integer(!is.na(r[[paste(metric,"Minutes")]]));partial<-as.integer(usable==1&&issue_count>0)
    r[[paste("Sessions Used for",metric,"Time")]]<-usable;r[[paste("Session Duration Used for",metric,"Time")]]<-usable*r[["Session Duration"]]
    r[[paste("Partial",metric,"Time Sessions")]]<-partial
    r[[paste(metric,"Time Status")]]<-if(!usable) "Unavailable" else if(partial) if(metric=="Run") "Partial recorded span" else "Partial recorded theatre time" else "Complete"
  }
  r<-c(r,build_scheduling(rows));sched<-as.integer(r[["Scheduling Issues"]]==0&&!is.na(r[["Scheduled Minutes"]]))
  r[["Sessions Used for Scheduling"]]<-sched;r[["Sessions Excluded from Scheduling"]]<-1L-sched
  r[["Session Duration Used for Scheduling"]]<-sched*r[["Session Duration"]]
  difference<-r[["Scheduled Minutes"]]-r[["Session Duration"]]
  r[["Below Planned Load"]]<-as.integer(sched==1&&!is.na(difference)&&difference < -1e-6)
  r[["At Planned Load"]]<-as.integer(sched==1&&!is.na(difference)&&abs(difference)<=1e-6)
  r[["Above Planned Load"]]<-as.integer(sched==1&&!is.na(difference)&&difference>1e-6)
  r[["Scheduled Load Status"]]<-if(!sched) "Unclassified" else if(r[["Below Planned Load"]]) "Below planned" else if(r[["Above Planned Load"]]) "Above planned" else "At planned"
  contradictory<-!is.na(first)&&!is.na(last)&&last<first
  for(phase in c("Start","Finish")) {
    actual<-if(phase=="Start") first else last;planned<-r[[if(phase=="Start") "Slot Start Time" else "Slot End Time"]]
    eligible<-!is.na(actual)&&!is.na(planned)&&!contradictory
    delta<-if(eligible) (actual-planned)/60 else NA_real_
    label<-if(!eligible) "Unclassified" else if(delta < -allowance-1e-8) paste("Early",phase) else if(delta>allowance+1e-8) paste("Late",phase) else "On Time"
    r[[paste(phase,"Difference Minutes")]]<-delta;r[[paste(phase,"Type")]]<-label
    plural<-if(phase=="Start") "Starts" else "Finishes"
    r[[paste(plural,"Assessed")]]<-as.integer(eligible);r[[paste("Partial",phase,"Sessions")]]<-as.integer(eligible&&issue_count>0)
    for(status in c("Early","On-Time","Late")) r[[paste(status,plural)]]<-as.integer(label==if(status=="On-Time") "On Time" else paste(status,phase))
  }
  r[["Classification Status"]]<-if(r[["Starts Assessed"]]&&r[["Finishes Assessed"]]) "Classified" else if(r[["Starts Assessed"]]||r[["Finishes Assessed"]]) "Partially classified" else "Unclassified"
  for(metric in c("Run","Op")) {
    den<-r[[paste("Session Duration Used for",metric,"Time")]];r[[paste(metric,"Utilisation")]]<-if(den>0) r[[paste(metric,"Minutes")]]/den else NA_real_
  }
  r[["Scheduled Load"]]<-if(sched) r[["Scheduled Minutes"]]/r[["Session Duration"]] else NA_real_
  o[["Session ID"]]<-r[["Session ID"]]
  list(session=data.table::as.data.table(r),operations=o)
}

transform_theatres <- function(raw,allowance=10) {
  d<-prepare_data(raw);patients<-build_patients(d);valid<-d[d[["Include in Sessions"]]]
  groups<-split(seq_len(nrow(valid)),valid[["Session ID"]]);results<-lapply(groups,function(ix) session_record(valid[ix],patients,allowance))
  sessions<-data.table::rbindlist(lapply(results,`[[`,"session"),fill=TRUE)
  operations<-data.table::rbindlist(lapply(results,`[[`,"operations"),fill=TRUE)
  stopifnot(nrow(sessions)==data.table::uniqueN(valid[["Session ID"]]),sum(sessions[["No of Patients"]])==sum(patients[["Counted Patient"]]))
  if(nrow(patients)) {
    dims<-sessions[,c("Session ID",SESSION_KEYS,"Hospital","Theatre Type","Session Specialty","Month","Financial Year"),with=FALSE]
    patients<-merge(patients,dims,by="Session ID",all.x=TRUE,sort=FALSE)
  }
  list(procedures=d,patients=patients,sessions=sessions,operations=operations)
}
