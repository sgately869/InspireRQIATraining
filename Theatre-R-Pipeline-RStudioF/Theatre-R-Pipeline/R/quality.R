# One record per issue, with the treatment explicit. Counts across issue types
# overlap: issue totals are not a distinct count of affected sessions/patients.
build_quality <- function(sessions,procedures) {
  out<-list();k<-0L
  add<-function(base,condition,group,issue,treatment,metric,detail,count=NA_real_,minutes=NA_real_) {
    if(!isTRUE(condition)) return(invisible(NULL))
    k<<-k+1L
    out[[k]]<<-c(base,list(`Issue Group`=group,Issue=issue,`Reporting Treatment`=treatment,Metric=metric,Detail=detail,
      `Affected Records`=count,`Affected Minutes`=minutes,`Issue Count`=1L))
  }
  for(i in seq_len(nrow(sessions))) {
    r<-as.list(sessions[i]);get<-function(n,default=NA) if(is.null(r[[n]])) default else r[[n]]
    base<-r[c("Session ID","Hospital","Month","Procedure Date","Operating Theatre","Session Specialty","Responsible Consultant","Slot Start Time","Slot End Time","Source Files")]
    base<-c(base,list(`Source Row`=NA_integer_,`Record Level`="Session",`Patient CSN`=NA_character_,`Log ID`=NA_character_))
    emit<-function(condition,group,issue,treatment,metric,detail,count=NA_real_,minutes=NA_real_) add(base,condition,group,issue,treatment,metric,detail,count,minutes)
    emit(get("Partial Run Time Sessions")>0,"Actual timing","Partial recorded run span","Included with warning","Run time",get("Timing Notes"),1,get("Run Minutes"))
    emit(get("Sessions Used for Run Time")==0,"Actual timing","Run time unavailable","Excluded from run time","Run time","No nonnegative span from trusted start/end boundaries. Planned session minutes remain included.",1)
    emit(get("Partial Op Time Sessions")>0,"Actual timing","Partial recorded op minutes","Included with warning","Op time",get("Timing Notes"),get("Excluded Op Intervals"),get("Op Minutes"))
    emit(get("Sessions Used for Op Time")==0,"Actual timing","Op time unavailable","Excluded from op time","Op time","No complete usable operation interval. Planned session minutes remain included.",get("Excluded Op Intervals"))
    for(rule in list(
      c("Missing Timing Operations","Actual timing","Missing or invalid actual timestamps","Usable records retained","Run / op / punctuality","Known endpoints can still contribute to run or punctuality. Incomplete intervals do not contribute op minutes."),
      c("Reversed Timing Operations","Actual timing","Reversed actual intervals","Invalid intervals excluded","Run / op / punctuality","Both endpoints of reversed operation intervals are excluded."),
      c("Conflicting Timing Operations","Overlap and duplicates","Conflicting operation records","Conflicting records excluded","Run / op / punctuality","A Log ID has conflicting patient or timing values. No arbitrary record is selected."),
      c("Repeated Timing Rows","Overlap and duplicates","Repeated timing rows grouped","Grouped before calculation","Run / op","Identical operation identities count once. Conflicts are separately excluded."),
      c("Missing Patient ID Op Intervals","Overlap and duplicates","Op intervals without patient identity","Included with warning","Op time","Theatre union includes valid intervals; same-patient overlap attribution is unavailable."),
      c("Supplied Op Value Issues","Actual timing","Invalid or conflicting supplied op values","Comparison values omitted","Op reconciliation","Supplied comparison values are not substituted for timestamp-based op minutes."),
      c("Patients Excluded - Missing Times","Patient counts","Patients excluded for missing times","Excluded from patient count","Patient count","Patient lacks a first procedure start or last procedure end. Planned duration and represented sessions remain included."),
      c("Missing Patient IDs","Patient counts","Source rows without Patient CSN","Excluded from patient count","Patient count","Valid session/timing records remain usable; source rows are retained."),
      c("Scheduling Issues","Scheduling","Scheduled workload unavailable","Excluded from assessed workload","Scheduled workload","Supplied scheduled minutes are missing, invalid or conflicting; planned duration remains included."),
      c("Repeated Scheduled Rows","Overlap and duplicates","Repeated scheduled rows grouped","Grouped before calculation","Scheduled workload","Identical scheduled operation identities count once."))) {
      emit(get(rule[1],0)>0,rule[2],rule[3],rule[4],rule[5],rule[6],get(rule[1],0))
    }
    emit(get("Same-Patient Overlap Minutes Removed")>1e-6,"Overlap and duplicates","Overlapping intervals for the same patient","Overlap removed","Op time","Same-patient intervals are merged before the patient-time audit is totalled.",minutes=get("Same-Patient Overlap Minutes Removed"))
    emit(get("Concurrent Patient Minutes")>1e-6,"Overlap and duplicates","Concurrent patient timing","Excluded from op total","Op time","Concurrent patients can be valid activity. Occupied theatre time counts once; patient minutes remain in the audit measure.",minutes=get("Concurrent Patient Minutes"))
    emit(get("Supplied Op Comparison Status")=="Partial recorded values","Actual timing","Partial supplied op comparison","Information","Op reconciliation","Available source comparison values cover only some operation identities.",1)
    emit(get("Supplied Op Comparison Status")=="Unavailable","Actual timing","Supplied op comparison unavailable","Information","Op reconciliation","No supplied op-minute comparison total is available; timestamp op minutes can still be valid.",1)
    for(rule in list(c("Supplied Performed Op Minutes","Timestamp / supplied performed-minute difference"),c("Supplied Non-Overlap Op Minutes","Reported / supplied non-overlap-minute difference"))) {
      delta<-get("Op Minutes")-get(rule[1]);emit(get("Supplied Op Comparison Status")=="Complete"&&!is.na(delta)&&abs(delta)>1e-6,"Actual timing",rule[2],"Information","Op reconciliation","Retained seconds, interval coverage and overlap treatment can explain differences; a difference alone is not proof of over-reporting.",1,delta)
    }
    for(phase in c("Start","Finish")) {
      emit(get(paste("Partial",phase,"Sessions"))>0,"Punctuality",paste(phase,"classified from partial timing data"),"Included with warning",paste(phase,"classification"),"Classification uses an independently trusted boundary and the inclusive ten-minute allowance. Missing outer records may change the true boundary.",1,get(paste(phase,"Difference Minutes")))
      emit(get(paste(if(phase=="Start") "Starts" else "Finishes","Assessed"))==0,"Punctuality",paste(phase,"could not be classified"),"Unclassified",paste(phase,"classification"),"Boundary unavailable or observed session boundaries contradictory.",1)
    }
    emit(get("Consultant Attribution")!="Single consultant","Attribution","Consultant attribution requires review","Shared or unknown attribution","Consultant utilisation",paste("Attribution:",get("Consultant Attribution"),"Recorded:",get("Consultant Names")),1)
    emit(get("Mixed Session Specialty"),"Attribution","Mixed session specialty","Shared attribution retained","Specialty utilisation","Different specialties occur in the same inferred session; no arbitrary specialty is assigned.",1)
    emit(get("Hospital")=="Unmapped"||get("Theatre Type")=="Unmapped","Attribution","Unmapped hospital or theatre type","Included as Unmapped","Site / theatre analysis","Review location/theatre mapping.",1)
    emit(get("Scheduling Issues")==0&&!is.na(get("Scheduling Notes")),"Scheduling","Scheduled workload warning","Included with warning","Scheduled workload",get("Scheduling Notes"),1,get("Scheduled Minutes"))
  }
  for(i in which(!is.na(procedures[["Issue Type"]]))) {
    r<-as.list(procedures[i]);base<-r[c("Session ID","Hospital","Month","Procedure Date","Operating Theatre","Slot Start Time","Slot End Time","Patient CSN","Log ID")]
    base<-c(base,list(`Session Specialty`=r$Session,`Responsible Consultant`=clean_text(r[["Session [Responsible Consultant]"]]),`Source Files`=r[["Source File"]],`Source Row`=r[["Input Row"]],`Record Level`="Source row"))
    add(base,TRUE,"Source import",r[["Issue Type"]],if(r[["Include in Sessions"]]) "Session retained; patient excluded" else "Excluded from sessions","Source import / patient count",r[["Issue Detail"]],1)
  }
  if(!length(out)) {
    cols<-c("Session ID","Hospital","Month","Procedure Date","Operating Theatre","Session Specialty","Responsible Consultant","Slot Start Time","Slot End Time","Source Files","Source Row","Record Level","Patient CSN","Log ID","Issue Group","Issue","Reporting Treatment","Metric","Detail","Affected Records","Affected Minutes","Issue Count")
    d<-data.table::as.data.table(setNames(lapply(cols,function(x) character()),cols))
    for(n in c("Slot Start Time","Slot End Time","Source Row","Affected Records","Affected Minutes","Issue Count")) d[[n]]<-numeric()
  } else d<-data.table::rbindlist(out,fill=TRUE)
  d
}
