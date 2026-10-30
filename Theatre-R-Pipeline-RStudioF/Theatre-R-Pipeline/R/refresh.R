# Optional service-principal integration. Disabled in both shipped configs.
# The secret is read from an environment variable and is never logged.
http_json <- function(url,method="GET",token=NULL,body=NULL) {
  h<-curl::new_handle();headers<-c(Accept="application/json")
  if(!is.null(token)) headers<-c(headers,Authorization=paste("Bearer",token))
  if(!is.null(body)) headers<-c(headers,`Content-Type`="application/json")
  curl::handle_setheaders(h,.list=as.list(headers))
  curl::handle_setopt(h,customrequest=method,timeout=120L)
  if(!is.null(body)) curl::handle_setopt(h,postfields=body)
  response<-curl::curl_fetch_memory(url,h)
  if(response$status_code<200||response$status_code>=300) stop("Power BI HTTP ",response$status_code," (credentials and response body omitted from log)")
  content<-rawToChar(response$content)
  list(data=if(nzchar(content)) jsonlite::fromJSON(content,simplifyVector=FALSE) else list(),headers=rawToChar(response$headers),status=response$status_code)
}
pbi_token <- function(p) {
  for(n in c("tenant_id","client_id","workspace_id","semantic_model_id")) if(!grepl("^[0-9a-fA-F-]{36}$",p[[n]])) stop("Configure Power BI ",n," as a GUID")
  secret<-Sys.getenv(p$client_secret_env,unset="");if(!nzchar(secret)) stop("Power BI client-secret environment variable is not set")
  h<-curl::new_handle();curl::handle_setheaders(h,`Content-Type`="application/x-www-form-urlencoded")
  fields<-c(grant_type="client_credentials",client_id=p$client_id,client_secret=secret,scope="https://analysis.windows.net/powerbi/api/.default")
  form<-paste(names(fields),vapply(fields,curl::curl_escape,character(1)),sep="=",collapse="&")
  curl::handle_setopt(h,postfields=form,timeout=60L)
  r<-curl::curl_fetch_memory(paste0("https://login.microsoftonline.com/",p$tenant_id,"/oauth2/v2.0/token"),h)
  if(r$status_code!=200) stop("Power BI authentication failed: HTTP ",r$status_code," (response body omitted)")
  token<-jsonlite::fromJSON(rawToChar(r$content))$access_token
  if(is.null(token)||!nzchar(token)) stop("Power BI authentication returned no token")
  token
}
assert_power_bi_idle <- function(cfg) {
  if(!isTRUE(cfg$power_bi$enabled)) return(invisible(TRUE))
  p<-cfg$power_bi;token<-pbi_token(p)
  url<-paste0("https://api.powerbi.com/v1.0/myorg/groups/",p$workspace_id,"/datasets/",p$semantic_model_id,"/refreshes?$top=60")
  history<-http_json(url,token=token)$data$value
  if(any(vapply(history,function(x)x$status %in% c("Unknown","InProgress","NotStarted"),logical(1)))) stop("Power BI is refreshing. Existing publication retained; retry later.")
  invisible(TRUE)
}
refresh_power_bi <- function(cfg,state,manifest) {
  p<-cfg$power_bi;if(!isTRUE(p$enabled)) return(list(status="Disabled - prepared outputs only"))
  pending_path<-file.path(state,"pending_refresh.json")
  pending<-if(file.exists(pending_path)) jsonlite::read_json(pending_path,simplifyVector=TRUE) else list(run_id=manifest$run_id,requested_utc=NULL,request_id=NULL)
  if(!identical(pending$run_id,manifest$run_id)) stop("A previous batch still awaits Power BI refresh; do not publish another batch")
  token<-pbi_token(p)
  endpoint<-paste0("https://api.powerbi.com/v1.0/myorg/groups/",p$workspace_id,"/datasets/",p$semantic_model_id,"/refreshes")
  get_history<-function() http_json(paste0(endpoint,"?$top=60"),token=token)$data$value
  history<-get_history()
  active<-Filter(function(x) x$status %in% c("Unknown","InProgress","NotStarted"),history)
  if(is.null(pending$requested_utc)) {
    if(length(active)) stop("Power BI has an active refresh. Retrying will wait for it before requesting this batch.")
    ledger_path<-file.path(state,"refresh_requests.json")
    ledger<-if(file.exists(ledger_path)) unlist(jsonlite::read_json(ledger_path)) else character()
    recent<-as.POSIXct(ledger,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")>Sys.time()-86400
    if(sum(recent,na.rm=TRUE)>=p$max_requests_per_24h) stop("Configured Power BI request budget reached; retry later")
    # Persist request intent before POST. A crash after submission is reconciled
    # to refresh history, never followed by a blind duplicate refresh request.
    pending$requested_utc<-utc_now();pending$history_before<-vapply(history,function(x)x$requestId,character(1))
    write_json(pending,pending_path)
    r<-http_json(endpoint,method="POST",token=token,body="{}")
    lines<-strsplit(r$headers,"\r?\n")[[1]];loc<-sub("^[Ll]ocation: *","",grep("^[Ll]ocation:",lines,value=TRUE))
    if(length(loc)) pending$request_id<-tail(strsplit(loc[length(loc)],"/",fixed=TRUE)[[1]],1)
    write_json(pending,pending_path);write_json(as.list(c(ledger,pending$requested_utc)),ledger_path)
  }
  start<-Sys.time()
  repeat {
    history<-get_history()
    if(!is.null(pending$request_id)) match<-Filter(function(x) identical(x$requestId,pending$request_id),history) else {
      # An uncertain POST is resolved only when exactly one new API refresh can
      # be identified. An administrator must review any ambiguity.
      before<-unlist(pending$history_before)
      since<-as.POSIXct(strptime(pending$requested_utc,"%Y-%m-%dT%H:%M:%OSZ",tz="UTC"))
      match<-Filter(function(x) {
        when<-as.POSIXct(strptime(x$startTime,"%Y-%m-%dT%H:%M:%OSZ",tz="UTC"))
        !x$requestId %in% before && identical(x$refreshType,"ViaApi") && !is.na(when) && when>=since
      },history)
      if(length(match)>1L) stop("Ambiguous Power BI refresh history; administrator review required")
      if(length(match)==1L) {pending$request_id<-match[[1]]$requestId;write_json(pending,pending_path)}
    }
    if(length(match)==1L) {
      status<-match[[1]]$status
      if(identical(status,"Completed")) {
        result<-list(status="Completed",run_id=manifest$run_id,request_id=pending$request_id,completed_utc=utc_now())
        write_json(result,file.path(state,"last_power_bi_refresh.json"));unlink(pending_path);return(result)
      }
      if(status %in% c("Failed","Cancelled","Disabled")) stop("Power BI refresh ",status,"; previous report data may still be displayed. Review refresh history and reset pending_refresh.json only after investigation.")
    }
    if(as.numeric(difftime(Sys.time(),start,units="secs"))>=p$timeout_seconds) stop("Power BI refresh not confirmed within timeout; pending request retained for next run")
    Sys.sleep(p$poll_seconds)
  }
}
