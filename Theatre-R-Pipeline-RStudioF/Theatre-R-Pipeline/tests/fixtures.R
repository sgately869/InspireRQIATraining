make_row <- function(room,patient="P",log="A",start="2026-09-01T09:00:00",end="2026-09-01T10:00:00",changes=list()) {
  b<-setNames(as.list(rep(NA_character_,length(REQUIRED_HEADERS))),REQUIRED_HEADERS)
  b[c("Service Area","Location","Operating Theatre","Procedure Date","Patient CSN","Log ID","Start Time","End Time","Session","Slot Start Time","Slot End Time","Session [Responsible Consultant]","Operation Time minutes (Scheduled)","Start Time (Scheduled)","End Time (Scheduled)")]<-list("Hsc Southern Trust","St Cah Main Theatre",room,"2026-09-01",patient,log,start,end,"General Surgery","2026-09-01T09:00:00","2026-09-01T13:00:00","Dr Fixture",60,"2026-09-01T09:00:00","2026-09-01T10:00:00")
  for(n in names(changes)) b[n]<-list(changes[[n]])
  d<-data.table::as.data.table(lapply(b,function(x) list(x)));d[["Source File"]]<-"Independent R fixtures";d[["Input Row"]]<-2L;d
}
fixture_tests <- function(root) {
  rows<-list();checks<-list()
  add<-function(name,r,expected) {rows[[length(rows)+1L]]<<-r;checks[[name]]<<-expected}
  dt<-function(h,m=0,s=0) sprintf("2026-09-01T%02d:%02d:%02d",h,m,s)
  add("Seconds",make_row("Seconds",start=dt(9,18),end=dt(10,33,37),changes=list(`Operation Time Minutes (Performed)`=75,`Non-Overlap Operation Time Minutes (Performed)`=75,`Overlap Minutes (Performed)`=0)),list(`Run Minutes`=75+37/60,`Op Minutes`=75+37/60,`Supplied Performed Op Minutes`=75))
  add("DistinctOverlap",rbindlist(list(make_row("DistinctOverlap","A","A"),make_row("DistinctOverlap","B","B",dt(9,30),dt(10,30)))),list(`Run Minutes`=90,`Op Minutes`=90,`Recorded Patient Op Minutes`=120,`Concurrent Patient Minutes`=30))
  add("SameOverlap",rbindlist(list(make_row("SameOverlap","A","A"),make_row("SameOverlap","A","B",dt(9,30),dt(10,30)))),list(`Op Minutes`=90,`Recorded Patient Op Minutes`=90,`Same-Patient Overlap Minutes Removed`=30,`No of Patients`=1))
  add("Disjoint",rbindlist(list(make_row("Disjoint","A","A"),make_row("Disjoint","A","B",dt(11),dt(12)))),list(`Run Minutes`=180,`Op Minutes`=120))
  add("Duplicate",rbindlist(rep(list(make_row("Duplicate")),3)),list(`Op Minutes`=60,`Repeated Timing Rows`=2,`Repeated Scheduled Rows`=2,`Scheduled Minutes`=60))
  add("Conflict",rbindlist(list(make_row("Conflict","A","A"),make_row("Conflict","A","A",dt(8),dt(11)))),list(`Run Minutes`=NA_real_,`Op Minutes`=NA_real_,`Conflicting Timing Operations`=1,`Starts Assessed`=0,`Finishes Assessed`=0))
  add("Reversed",make_row("Reversed",start=dt(9),end=dt(8)),list(`Run Minutes`=NA_real_,`Op Minutes`=NA_real_,`Reversed Timing Operations`=1,`Session Duration`=240,`No of Patients`=1))
  add("MissingMiddle",rbindlist(list(make_row("MissingMiddle","A","A"),make_row("MissingMiddle","B","B",dt(10,30),NA_character_),make_row("MissingMiddle","C","C",dt(11),dt(12)))),list(`Run Minutes`=180,`Op Minutes`=120,`Partial Run Time Sessions`=1,`Partial Op Time Sessions`=1,`No of Patients`=2,`Patients Excluded - Missing Times`=1))
  add("OnlyStart",make_row("OnlyStart",end=NA_character_),list(`Run Minutes`=NA_real_,`Op Minutes`=NA_real_,`Starts Assessed`=1,`Finishes Assessed`=0,`Start Type`="On Time",`No of Patients`=0))
  add("OnlyEnd",make_row("OnlyEnd",start=NA_character_),list(`Starts Assessed`=0,`Finishes Assessed`=1,`Finish Type`="Early Finish",`Op Minutes`=NA_real_))
  add("Cross",rbindlist(list(make_row("Cross","A","A",dt(9),NA_character_),make_row("Cross","B","B",NA_character_,dt(12)))),list(`Run Minutes`=180,`Op Minutes`=NA_real_,`Starts Assessed`=1,`Finishes Assessed`=1,`No of Patients`=0,`Session Duration`=240))
  add("NegativeAggregate",rbindlist(list(make_row("NegativeAggregate","A","A",dt(12),NA_character_),make_row("NegativeAggregate","B","B",NA_character_,dt(11)))),list(`Run Minutes`=NA_real_,`Op Minutes`=NA_real_,`Starts Assessed`=0,`Finishes Assessed`=0))
  add("MissingBoth",make_row("MissingBoth",start=NA_character_,end=NA_character_),list(`Session Duration`=240,`No of Sessions`=1,`No of Patients`=0,`Patients Excluded - Missing Times`=1))
  add("UnknownIDs",rbindlist(list(make_row("UnknownIDs",NA_character_,"A"),make_row("UnknownIDs",NA_character_,"B",dt(9,30),dt(10,30)))),list(`Op Minutes`=90,`Missing Patient ID Op Intervals`=2,`No of Patients`=0))
  add("Zero",make_row("Zero",end=dt(9)),list(`Run Minutes`=0,`Op Minutes`=0,`Sessions Used for Op Time`=1,`No of Patients`=1))
  add("Night",make_row("Night",start="23:30:00",end="00:30:00",changes=list(`Slot Start Time`="2026-09-01T23:00:00",`Slot End Time`="2026-09-02T03:00:00")),list(`Run Minutes`=60,`Op Minutes`=60,`Session Duration`=240))
  add("NightOrphan",rbindlist(list(make_row("NightOrphan","A","A","23:00:00","23:30:00",list(`Slot Start Time`="2026-09-01T23:00:00",`Slot End Time`="2026-09-02T03:00:00")),make_row("NightOrphan","B","B",NA_character_,"00:30:00",list(`Slot Start Time`="2026-09-01T23:00:00",`Slot End Time`="2026-09-02T03:00:00")))),list(`Run Minutes`=90,`Op Minutes`=30,`Partial Finish Sessions`=1))
  add("ClockSlot",make_row("ClockSlot",start="23:30:00",end="00:30:00",changes=list(`Slot Start Time`="23:00:00",`Slot End Time`="03:00:00")),list(`Session Duration`=240,`Op Minutes`=60))
  for(z in list(c("StartEarly",dt(8,49,59),"Early Start"),c("StartLower",dt(8,50),"On Time"),c("StartUpper",dt(9,10),"On Time"),c("StartLate",dt(9,10,1),"Late Start"))) add(z[1],make_row(z[1],start=z[2]),list(`Start Type`=z[3]))
  for(z in list(c("FinishEarly",dt(12,49,59),"Early Finish"),c("FinishLower",dt(12,50),"On Time"),c("FinishUpper",dt(13,10),"On Time"),c("FinishLate",dt(13,10,1),"Late Finish"))) add(z[1],make_row(z[1],end=z[2]),list(`Finish Type`=z[3]))
  add("ScheduledConflict",rbindlist(list(make_row("ScheduledConflict"),make_row("ScheduledConflict",changes=list(`Operation Time minutes (Scheduled)`=61)))),list(`Scheduled Minutes`=NA_real_,`Scheduling Issues`=1,`Session Duration Used for Scheduling`=0))
  add("ScheduledWarn",make_row("ScheduledWarn",changes=list(`Operation Time minutes (Scheduled)`=55)),list(`Scheduled Minutes`=55,`Scheduling Issues`=0,`Sessions Used for Scheduling`=1))
  add("MissingScheduled",make_row("MissingScheduled",changes=list(`Operation Time minutes (Scheduled)`=NA_character_)),list(`Scheduled Minutes`=NA_real_,`Scheduling Issues`=1))
  add("MixedConsultants",rbindlist(list(make_row("MixedConsultants","A","A"),make_row("MixedConsultants","B","B",dt(10),dt(11),list(`Session [Responsible Consultant]`="Dr Other")))),list(`Responsible Consultant`="Mixed / multiple",`Consultant Attribution`="Multiple consultants"))
  add("IncompleteConsultant",rbindlist(list(make_row("IncompleteConsultant","A","A"),make_row("IncompleteConsultant","B","B",dt(10),dt(11),list(`Session [Responsible Consultant]`=NA_character_)))),list(`Responsible Consultant`="Incomplete attribution"))
  add("MixedSpecialty",rbindlist(list(make_row("MixedSpecialty","A","A"),make_row("MixedSpecialty","B","B",dt(10),dt(11),list(Session="ENT")))),list(`Session Specialty`="Mixed / multiple",`Mixed Session Specialty`=TRUE))
  add("SuppliedConflict",rbindlist(list(make_row("SuppliedConflict",changes=list(`Operation Time Minutes (Performed)`=60)),make_row("SuppliedConflict",changes=list(`Operation Time Minutes (Performed)`=61)))),list(`Supplied Performed Op Minutes`=NA_real_,`Supplied Op Value Issues`=1,`Op Minutes`=60))
  add("Fallback",rbindlist(rep(list(make_row("Fallback",log=NA_character_)),2)),list(`Timed Operations`=1,`Repeated Timing Rows`=1,`Scheduled Operations`=1))
  pain<-list(c(16,26,16,41),c(13,47,14,43),c(15,35,15,56),c(14,10,15,5),c(14,21,15,26),c(14,5,14,42))
  add("Pain",rbindlist(lapply(seq_along(pain),function(i){z<-pain[[i]];make_row("Pain",paste0("P",i),paste0("L",i),dt(z[1],z[2]),dt(z[3],z[4]))})),list(`Run Minutes`=174,`Op Minutes`=135,`Recorded Patient Op Minutes`=249,`Concurrent Patient Minutes`=114,`No of Patients`=6))
  data<-rbindlist(rows);data[["Input Row"]]<-seq_len(nrow(data))+1L
  r<-transform_theatres(data,10);assertions<-0L
  for(case in names(checks)) {
    row<-r$sessions[`Operating Theatre`==case];stopifnot(nrow(row)==1)
    for(n in names(checks[[case]])) {
      expected<-checks[[case]][[n]];actual<-row[[n]]
      ok<-if(is.na(expected)) is.na(actual) else if(is.numeric(expected)) abs(actual-expected)<1e-6 else identical(as.character(actual),as.character(expected))
      if(!isTRUE(ok)) stop("Fixture ",case," / ",n,": expected ",expected,"; actual ",actual)
      assertions<-assertions+1L
    }
  }
  q<-build_quality(r$sessions,r$procedures)
  stopifnot(any(q$Issue=="Concurrent patient timing"),any(q$Issue=="Patients excluded for missing times"),any(q$Issue=="Reversed actual intervals"))
  # Parse clock meridiem and numeric Excel serials independently of fixtures.
  stopifnot(parse_dt("12:00 AM","2026-09-01")==parse_dt("2026-09-01T00:00:00",NA_character_),parse_dt("12:00 PM","2026-09-01")==parse_dt("2026-09-01T12:00:00",NA_character_),abs(parse_dt(0.5,"2026-09-01")-parse_dt("12:00","2026-09-01"))<1e-6)
  # Thirteen retained months plus two current-month snapshots must select
  # fourteen months, with only the later November snapshot active.
  inv<-data.table(file=paste0("historical-",1:13),month=format(seq(as.Date("2025-10-01"),by="month",length.out=13),"%Y-%m"),exported_utc=rep("20261031T120000Z",13),sha256=paste0("h",1:13))
  inv<-rbindlist(list(inv,data.table(file=c("nov-week1","nov-week2"),month="2026-11",exported_utc=c("20261107T120000Z","20261114T120000Z"),sha256=c("n1","n2"))))
  selected<-select_snapshots(inv);stopifnot(nrow(selected)==14,selected[month=="2026-11"]$file=="nov-week2")
  bad<-copy(inv);bad[file=="nov-week1",exported_utc:=NA_character_];stopifnot(inherits(try(select_snapshots(bad),silent=TRUE),"try-error"))
  bad<-copy(inv);bad[file=="nov-week1",exported_utc:="20261114T120000Z"];stopifnot(inherits(try(select_snapshots(bad),silent=TRUE),"try-error"))
  list(passed=TRUE,cases=length(checks),metric_assertions=assertions,quality_issue_rows=nrow(q),snapshot_scenario="13 historical months + 2 November snapshots -> 14 selected months",result=r,quality=q)
}
