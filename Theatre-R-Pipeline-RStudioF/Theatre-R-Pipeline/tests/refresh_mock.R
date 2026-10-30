refresh_mock_tests <- function(root) {
  old_token<-pbi_token;old_http<-http_json
  on.exit({assign("pbi_token",old_token,envir=.GlobalEnv);assign("http_json",old_http,envir=.GlobalEnv)},add=TRUE)
  assign("pbi_token",function(p) "MOCK-NOT-A-CREDENTIAL",envir=.GlobalEnv)
  p<-list(enabled=TRUE,workspace_id="mock-workspace",semantic_model_id="mock-model",poll_seconds=0,timeout_seconds=1,max_requests_per_24h=6)
  cfg<-list(power_bi=p);manifest<-list(run_id="mock-batch")
  state<-file.path(root,"tests","mock-refresh",paste0("test-",Sys.getpid(),"-",format(Sys.time(),"%H%M%S")))
  dir.create(state,recursive=TRUE,showWarnings=FALSE)
  write_json(list(run_id=manifest$run_id,requested_utc=NULL,request_id=NULL),file.path(state,"pending_refresh.json"))
  posts<-0L;history_calls<-0L
  assign("http_json",function(url,method="GET",token=NULL,body=NULL) {
    if(method=="POST") {posts<<-posts+1L;return(list(data=list(),headers="Location: https://example.invalid/refreshes/mock-request\r\n",status=202))}
    history_calls<<-history_calls+1L
    list(data=list(value=if(posts==0) list() else list(list(requestId="mock-request",status="Completed",refreshType="ViaApi",startTime=utc_now()))),headers="",status=200)
  },envir=.GlobalEnv)
  answer<-refresh_power_bi(cfg,state,manifest)
  stopifnot(answer$status=="Completed",posts==1L,!file.exists(file.path(state,"pending_refresh.json")))
  # Retrying an accepted request must not submit another POST.
  write_json(list(run_id=manifest$run_id,requested_utc=utc_now(),request_id="mock-request"),file.path(state,"pending_refresh.json"))
  answer<-refresh_power_bi(cfg,state,manifest);stopifnot(posts==1L,answer$status=="Completed")
  # A failed service refresh remains pending and never looks successful.
  write_json(list(run_id=manifest$run_id,requested_utc=utc_now(),request_id="mock-request"),file.path(state,"pending_refresh.json"))
  assign("http_json",function(...) list(data=list(value=list(list(requestId="mock-request",status="Failed")))),envir=.GlobalEnv)
  failed<-try(refresh_power_bi(cfg,state,manifest),silent=TRUE)
  stopifnot(inherits(failed,"try-error"),file.exists(file.path(state,"pending_refresh.json")))
  # Preflight prevents publishing across another active refresh.
  assign("http_json",function(...) list(data=list(value=list(list(requestId="other",status="Unknown")))),envir=.GlobalEnv)
  stopifnot(inherits(try(assert_power_bi_idle(cfg),silent=TRUE),"try-error"))
  list(passed=TRUE,checks=c("POST then confirm completion","Accepted request resumed without duplicate POST","Failed refresh retained as pending","Active refresh blocks publication"),live_calls=0)
}
