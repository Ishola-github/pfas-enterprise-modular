# PFAS Enterprise 5.0 — Standards-compliant predictive toxicology Shiny application
# SQLite-backed data collection, curation, audit logging, ML export scaffold, and Cloud API screening.

suppressPackageStartupMessages({
  library(shiny)
  library(shinydashboard)
  library(shinymanager)
  library(DT)
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(purrr)
  library(stringr)
  library(scales)
  library(jsonlite)
  library(httr)
  library(digest)
  library(DBI)
  library(RSQLite)
})

options(shiny.sanitize.errors = FALSE)
max_upload_mb <- suppressWarnings(as.numeric(Sys.getenv("PFAS_MAX_UPLOAD_MB", "512")))
if (is.na(max_upload_mb) || max_upload_mb <= 0) max_upload_mb <- 512
options(shiny.maxRequestSize = max_upload_mb * 1024^2)

APP_TITLE <- "PFAS Enterprise 5.0 — Standards-Compliant Toxicology & Regulatory Screening"
APP_VERSION <- "5.0.0"
# Portable project root: shiny::runApp() uses the application directory as working directory
PROJECT_DIR <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
MAPPING_ENGINE_VERSION <- "2026-05-02-autodetect-identifier-hardblock-3"
# Shown in External ML upload panel. Grep LatestPFAS.R for UPLOAD_READER_VERSION or substring
# delimited-base-only (no readr); substring e.g. utf16-unquoted indicates encoding/quote-escape hardening.
UPLOAD_READER_VERSION <- "2026-06-06-upload-nrows-nulsanitize-fix"
ICIS_NPDES_UI_VERSION <- "2026-05-07-icis-npdes-echo-bulk"
DB_PATH <- file.path(PROJECT_DIR, "pfas_collection.sqlite")
LOCAL_PYTHON_DEFAULT <- file.path("C:", "pfasenv", "Scripts", "python.exe")
LINK_SHINY_DEMO <- Sys.getenv("PFAS_LINK_SHINY_DEMO", "https://demo.yourcompany.com/request-access")
LINK_GITHUB_REPO <- Sys.getenv("PFAS_LINK_GITHUB_REPO", "https://github.com/your-org/private-pfas-repo")
PFAS_INTAKE_API_URL <- trimws(Sys.getenv("PFAS_INTAKE_API_URL", ""))
# Cloud screening API (FastAPI /predict, e.g. Render). Same env as thin app.R / README.
PFAS_API_URL <- trimws(Sys.getenv("PFAS_API_URL", "https://pfas-enterprise-5.onrender.com"))
PFAS_INTAKE_API_ENDPOINT <- if (nzchar(PFAS_INTAKE_API_URL)) {
  paste0(sub("/+$", "", PFAS_INTAKE_API_URL), "/upload")
} else {
  "null"
}
LINK_DATASET_FORM <- Sys.getenv("PFAS_LINK_DATASET_FORM", PFAS_INTAKE_API_ENDPOINT)
LINK_COLLAB <- Sys.getenv("PFAS_LINK_COLLAB", "mailto:techjoyadisco@yahoo.com")
PFAS_INTAKE_STAGING_TOKEN <- trimws(Sys.getenv("PFAS_INTAKE_STAGING_TOKEN", ""))
PFAS_PARTNER_AUDIT_SQLITE_TABLE <- trimws(Sys.getenv("PFAS_PARTNER_AUDIT_SQLITE_TABLE", "partner_intake_audit_mirror"))
PFAS_PARTNER_AUDIT_MIRROR_CSV <- trimws(Sys.getenv("PFAS_PARTNER_AUDIT_MIRROR_CSV", file.path(PROJECT_DIR, "data", "external", "partner_intake_audit_mirror.csv")))
DATASET_FORM_CONFIRMATION_MESSAGE <- Sys.getenv(
  "PFAS_DATASET_FORM_CONFIRMATION_MESSAGE",
  "Thank you for submitting your PFAS dataset inquiry. Your submission has been received for confidential commercial review."
)

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
}

safe_pattern <- function(p) {
  if (is.null(p) || length(p) == 0) {
    return(NA_character_)
  }
  pc <- trimws(as.character(p)[[1]])
  if (length(pc) < 1 || is.na(pc) || !nzchar(pc)) {
    return(NA_character_)
  }
  pc
}

safe_detect <- function(string, pattern, negate = FALSE, ...) {
  p <- safe_pattern(pattern)
  if (is.na(p)) {
    out <- rep(FALSE, length(string))
    return(if (isTRUE(negate)) !out else out)
  }
  stringr::str_detect(string, p, negate = negate, ...)
}

safe_matches <- function(pattern, ...) {
  p <- safe_pattern(pattern)
  if (is.na(p)) {
    return(dplyr::matches("$^"))
  }
  dplyr::matches(p, ...)
}

is_placeholder_link <- function(url) {
  if (is.null(url) || length(url) == 0) {
    return(TRUE)
  }
  candidate <- trimws(as.character(url)[1])
  if (!nzchar(candidate)) {
    return(FALSE)
  }
  if (is_disabled_link(candidate)) {
    return(FALSE)
  }
  bad_tokens <- c(
    "REPLACE_WITH_YOUR_FORM",
    "yourcompany.com",
    "your-org",
    "example.com"
  )
  any(vapply(bad_tokens, function(tok) {
    tok <- trimws(as.character(tok))
    nzchar(tok) && grepl(tok, candidate, fixed = TRUE)
  }, logical(1)))
}

is_disabled_link <- function(url) {
  if (is.null(url) || length(url) == 0) {
    return(TRUE)
  }
  candidate <- trimws(as.character(url)[1])
  if (!nzchar(candidate)) {
    return(TRUE)
  }
  tolower(candidate) %in% c("null", "na", "none", "disabled")
}

is_configured_link <- function(url) {
  !is_placeholder_link(url) && !is_disabled_link(url)
}

featured_stack_button <- function(url, btn_class, label) {
  enabled <- is_configured_link(url)
  disabled <- is_disabled_link(url)
  tags$a(
    href = if (enabled) url else "#",
    target = if (enabled) "_blank" else NULL,
    class = paste("btn", btn_class, if (!enabled) "disabled"),
    `aria-disabled` = if (!enabled) "true" else NULL,
    style = if (!enabled) "pointer-events:none; opacity:0.65;" else NULL,
    title = if (!enabled) {
      if (disabled) "Disabled pending verification" else "Link pending configuration"
    } else NULL,
    label
  )
}

featured_link_status <- function(url) {
  enabled <- is_configured_link(url)
  disabled <- is_disabled_link(url)
  tags$span(
    class = paste("label", if (enabled) "label-success" else if (disabled) "label-warning" else "label-default"),
    style = "margin-left:8px;",
    if (enabled) "Configured" else if (disabled) "Disabled" else "Pending configuration"
  )
}

run_intake_api_smoke_test <- function(url, bearer_token) {
  candidate <- trimws(as.character(url %||% "")[1])
  token <- trimws(as.character(bearer_token %||% "")[1])
  if (!nzchar(token)) {
    return(list(
      status = "skipped",
      summary = "Smoke test skipped: PFAS_INTAKE_STAGING_TOKEN is not set.",
      http_status = NA_integer_,
      detail = "Set PFAS_INTAKE_STAGING_TOKEN to run authenticated POST /upload checks."
    ))
  }
  if (!requireNamespace("httr", quietly = TRUE)) {
    return(list(
      status = "error",
      summary = "Smoke test failed: required package 'httr' is not available.",
      http_status = NA_integer_,
      detail = "Install with install.packages('httr') in this runtime."
    ))
  }

  body <- list(
    filename = paste0("smoke-", format(Sys.time(), "%Y%m%d%H%M%S"), ".csv"),
    content_type = "text/csv"
  )
  resp <- tryCatch(
    httr::POST(
      url = candidate,
      httr::add_headers(
        Authorization = paste("Bearer", token),
        `Content-Type` = "application/json"
      ),
      body = jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"),
      encode = "raw",
      httr::timeout(12)
    ),
    error = function(e) e
  )

  if (inherits(resp, "error")) {
    return(list(
      status = "fail",
      summary = "Smoke test failed: request error.",
      http_status = NA_integer_,
      detail = conditionMessage(resp)
    ))
  }

  status_code <- httr::status_code(resp)
  body_text <- tryCatch(httr::content(resp, as = "text", encoding = "UTF-8"), error = function(e) "")
  looks_ok <- status_code >= 200 && status_code < 300 && grepl("upload_url|object_key|expires_in_seconds", body_text)
  if (looks_ok) {
    return(list(
      status = "pass",
      summary = "Smoke test passed: authenticated POST /upload returned expected payload.",
      http_status = status_code,
      detail = "Token auth and upload-init response are working."
    ))
  }

  snippet <- if (nzchar(body_text)) substr(gsub("[\r\n\t]+", " ", body_text), 1, 220) else "<empty>"
  list(
    status = "fail",
    summary = "Smoke test failed: endpoint response did not match expected upload-init payload.",
    http_status = status_code,
    detail = paste("HTTP", status_code, "|", snippet)
  )
}

check_intake_api_health <- function(url, bearer_token = "") {
  checked_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  candidate <- trimws(as.character(url %||% "")[1])

  if (is_disabled_link(candidate)) {
    return(list(
      level = "disabled",
      summary = "Disabled. No public endpoint resolves.",
      detail = "Will remain disabled until Cognito SSO + Macie PII scan + audit logging pass 7.11.2 OQ.",
      endpoint = "<disabled>",
      checked_at = checked_at,
      smoke = list(
        status = "skipped",
        summary = "Smoke test skipped.",
        http_status = 503L,
        detail = "{\"status\":\"disabled_pending_7.11.3\"}"
      )
    ))
  }

  if (is_placeholder_link(candidate)) {
    return(list(
      level = "pending",
      summary = "Intake endpoint is pending configuration.",
      detail = "Placeholder URL detected; keep submission disabled until access controls are verified.",
      endpoint = candidate,
      checked_at = checked_at,
      smoke = list(status = "skipped", summary = "Smoke test skipped.", http_status = NA_integer_, detail = "Endpoint is placeholder.")
    ))
  }

  if (!grepl("^https?://", candidate, ignore.case = TRUE)) {
    return(list(
      level = "error",
      summary = "Endpoint URL format is invalid.",
      detail = "URL must begin with http:// or https://.",
      endpoint = candidate,
      checked_at = checked_at,
      smoke = list(status = "skipped", summary = "Smoke test skipped.", http_status = NA_integer_, detail = "Endpoint format invalid.")
    ))
  }

  host <- sub("^https?://([^/:?#]+).*$", "\\1", candidate, perl = TRUE)
  port <- if (grepl("^https://", candidate, ignore.case = TRUE)) 443L else 80L
  reachable <- tryCatch(
    {
      con <- socketConnection(host = host, port = port, open = "r+", blocking = TRUE, timeout = 3)
      on.exit(close(con), add = TRUE)
      TRUE
    },
    error = function(e) FALSE
  )

  if (!reachable) {
    return(list(
      level = "warning",
      summary = "Endpoint is configured but host is not reachable from this runtime.",
      detail = "Verify DNS/network path, API gateway deployment, and security group/ACL rules.",
      endpoint = candidate,
      checked_at = checked_at,
      smoke = list(status = "skipped", summary = "Smoke test skipped.", http_status = NA_integer_, detail = "Host unreachable.")
    ))
  }

  smoke <- run_intake_api_smoke_test(candidate, bearer_token)
  overall_level <- if (identical(smoke$status, "pass")) "ok" else if (identical(smoke$status, "skipped")) "warning" else "error"
  overall_summary <- if (identical(smoke$status, "pass")) {
    "Endpoint is reachable and authenticated POST /upload smoke test passed."
  } else if (identical(smoke$status, "skipped")) {
    "Endpoint is reachable; authenticated smoke test is skipped until staging token is set."
  } else {
    "Endpoint is reachable but authenticated POST /upload smoke test failed."
  }

  list(
    level = overall_level,
    summary = overall_summary,
    detail = "Network reachability check passed (port-level).",
    endpoint = candidate,
    checked_at = checked_at,
    smoke = smoke
  )
}

# -------------------------------------------------------------------
# SQLite setup
# -------------------------------------------------------------------

dir.create(PROJECT_DIR, showWarnings = FALSE, recursive = TRUE)
con <- DBI::dbConnect(RSQLite::SQLite(), DB_PATH)

# Re-open SQLite if the handle was invalidated (browser refresh after bad disconnect,
# OneDrive sync, etc.). Assigned with <<- so the same binding server() closes over updates.
ensure_valid_db_connection <- function() {
  ok <- tryCatch(
    inherits(con, "DBIConnection") && DBI::dbIsValid(con),
    error = function(e) FALSE
  )
  if (!ok) {
    con <<- DBI::dbConnect(RSQLite::SQLite(), DB_PATH)
  }
  invisible(con)
}

glp_audit_file <- file.path(PROJECT_DIR, "utils", "glp_audit.R")
if (file.exists(glp_audit_file)) {
  source(glp_audit_file, local = FALSE)
}
if (exists("glp_ensure_audit_table")) {
  glp_ensure_audit_table(con)
}

iso17025_file <- file.path(PROJECT_DIR, "utils", "iso17025_schema.R")
if (file.exists(iso17025_file)) {
  source(iso17025_file, local = FALSE)
}
if (exists("iso17025_ensure_tables")) {
  iso17025_ensure_tables(con)
  if (exists("iso17025_seed_epa1633_tests")) {
    iso17025_seed_epa1633_tests(con)
  }
}

ensure_table <- function(con, table_name, create_sql) {
  if (!DBI::dbExistsTable(con, table_name)) {
    DBI::dbExecute(con, create_sql)
  }
}

ensure_table(con, "compound_registry", "
CREATE TABLE compound_registry (
  compound_id TEXT PRIMARY KEY,
  compound_name TEXT NOT NULL,
  smiles TEXT NOT NULL,
  cas TEXT,
  pfas_subclass TEXT,
  source_type TEXT,
  source_reference TEXT,
  created_at TEXT NOT NULL,
  created_by TEXT NOT NULL,
  review_status TEXT NOT NULL DEFAULT 'draft'
);
")

ensure_table(con, "sample_registry", "
CREATE TABLE sample_registry (
  sample_id TEXT PRIMARY KEY,
  project_id TEXT,
  client_id TEXT,
  matrix TEXT NOT NULL,
  sample_type TEXT,
  collection_date TEXT,
  batch_id TEXT,
  instrument_id TEXT,
  method_id TEXT,
  operator TEXT,
  notes TEXT
);
")

ensure_table(con, "analytical_measurements", "
CREATE TABLE analytical_measurements (
  measurement_id TEXT PRIMARY KEY,
  compound_id TEXT NOT NULL,
  sample_id TEXT NOT NULL,
  retention_time REAL,
  precursor_mz REAL,
  product_mz REAL,
  peak_area REAL,
  signal_to_noise REAL,
  concentration REAL,
  concentration_unit TEXT,
  lod REAL,
  loq REAL,
  internal_standard TEXT,
  result_flag TEXT,
  qc_flag TEXT,
  created_at TEXT NOT NULL,
  created_by TEXT NOT NULL
);
")

ensure_table(con, "endpoint_labels", "
CREATE TABLE endpoint_labels (
  label_id TEXT PRIMARY KEY,
  compound_id TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  label_value INTEGER NOT NULL,
  label_source TEXT NOT NULL,
  assay_id TEXT,
  source_reference TEXT,
  confidence_score REAL,
  curator TEXT NOT NULL,
  review_status TEXT NOT NULL DEFAULT 'draft',
  notes TEXT,
  created_at TEXT NOT NULL
);
")

ensure_table(con, "audit_log", "
CREATE TABLE audit_log (
  audit_id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  action_type TEXT NOT NULL,
  changed_by TEXT NOT NULL,
  changed_at TEXT NOT NULL,
  change_notes TEXT
);
")

ensure_table(con, "app_login_users", "
CREATE TABLE app_login_users (
  user TEXT PRIMARY KEY,
  password TEXT NOT NULL,
  admin INTEGER NOT NULL DEFAULT 0,
  full_name TEXT,
  active INTEGER NOT NULL DEFAULT 1
);
")

ensure_table(con, "upload_validation_run", "
CREATE TABLE upload_validation_run (
  run_id TEXT PRIMARY KEY,
  phase TEXT NOT NULL,
  schema_version TEXT NOT NULL,
  status TEXT NOT NULL,
  validated_at TEXT NOT NULL,
  validated_by TEXT NOT NULL,
  file_name TEXT,
  raw_sha256 TEXT,
  dataset_type TEXT,
  row_count INTEGER,
  rows_pass INTEGER,
  rows_fail INTEGER,
  metrics_json TEXT NOT NULL,
  mapping_engine_version TEXT
);
")

nu_login <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM app_login_users")$n[[1]]
if (is.na(nu_login) || nu_login == 0) {
  DBI::dbExecute(
    con,
    "INSERT INTO app_login_users (user, password, admin, full_name, active) VALUES (?, ?, ?, ?, ?)",
    params = list("admin", "admin123", 1L, "QA Administrator", 1L)
  )
  DBI::dbExecute(
    con,
    "INSERT INTO app_login_users (user, password, admin, full_name, active) VALUES (?, ?, ?, ?, ?)",
    params = list("analyst", "analyst123", 0L, "Laboratory Analyst", 1L)
  )
}

worm_src <- file.path(PROJECT_DIR, "utils", "glp_audit_archive.R")
if (file.exists(worm_src)) {
  source(worm_src, local = FALSE)
}

login_credentials_df <- DBI::dbGetQuery(
  con,
  "SELECT user, password, admin, full_name FROM app_login_users WHERE active = 1"
)
login_credentials_df$admin <- as.logical(as.integer(login_credentials_df$admin))
login_credentials_df$full_name <- ifelse(
  is.na(login_credentials_df$full_name) | login_credentials_df$full_name == "",
  login_credentials_df$user,
  login_credentials_df$full_name
)

make_id <- function(prefix) {
  ts <- gsub("[^0-9]", "", format(Sys.time(), "%Y%m%d%H%M%OS3"))
  nonce <- substr(
    digest::digest(
      paste(prefix, ts, Sys.getpid(), runif(1), sep = "|"),
      algo = "xxhash64",
      serialize = FALSE
    ),
    1,
    8
  )
  paste0(prefix, "-", ts, "-", nonce)
}

default_external_upload_schema <- function() {
  list(
    schema_version = "external_normalized_v1",
    max_rows = 5000000,
    allowed_result_units = c(
      "", "ng/l", "ug/l", "mg/l", "ng/ml", "ug/ml", "mg/ml",
      "ppb", "ppt", "pg/l"
    ),
    analyte_max_chars = 512L,
    sample_id_max_chars = 256L,
    enforce_lat_lon_range = TRUE
  )
}

load_external_upload_schema <- function(project_dir = PROJECT_DIR) {
  path <- file.path(project_dir, "data", "config", "external_upload_schema.json")
  base <- default_external_upload_schema()
  if (!file.exists(path)) {
    return(base)
  }
  js <- tryCatch(jsonlite::fromJSON(path, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(js) || !is.list(js)) {
    return(base)
  }
  for (nm in names(js)) {
    base[[nm]] <- js[[nm]]
  }
  base
}

external_upload_raw_digest <- function(datapath) {
  if (is.null(datapath)) {
    return("")
  }
  dp <- trimws(as.character(datapath)[1])
  if (!nzchar(dp) || !file.exists(dp)) {
    return("")
  }
  digest::digest(file = dp, algo = "sha256", serialize = FALSE)
}

strict_validate_normalized_external <- function(norm_df, schema = NULL) {
  sch <- schema %||% default_external_upload_schema()
  sv <- as.character(sch$schema_version %||% "external_normalized_v1")
  violations <- list()
  metrics <- list(schema_version = sv, n_rows = 0L)

  if (is.null(norm_df) || !is.data.frame(norm_df)) {
    return(list(
      ok = FALSE,
      schema_version = sv,
      row_count = 0L,
      rows_pass = 0L,
      rows_fail = 0L,
      metrics = metrics,
      violations = c(violations, list(list(rule = "NO_DATAFRAME"))),
      run_id = NA_character_
    ))
  }

  nr <- nrow(norm_df)
  metrics$n_rows <- nr
  max_r <- suppressWarnings(as.numeric(sch$max_rows %||% 5e6))
  if (!is.finite(max_r) || max_r <= 0) {
    max_r <- 5e6
  }

  if (nr == 0L) {
    violations <- c(violations, list(list(rule = "ZERO_ROWS", detail = "Normalized table has zero rows")))
    return(list(
      ok = FALSE,
      schema_version = sv,
      row_count = 0L,
      rows_pass = 0L,
      rows_fail = 0L,
      metrics = metrics,
      violations = violations,
      run_id = NA_character_
    ))
  }

  if (nr > max_r) {
    violations <- c(violations, list(list(
      rule = "SCHEMA_MAX_ROWS",
      detail = sprintf("rows=%s max=%s", nr, max_r)
    )))
    return(list(
      ok = FALSE,
      schema_version = sv,
      row_count = nr,
      rows_pass = 0L,
      rows_fail = nr,
      metrics = metrics,
      violations = violations,
      run_id = NA_character_
    ))
  }

  reqc <- c("analyte", "result_value")
  miss_col <- setdiff(reqc, names(norm_df))
  if (length(miss_col)) {
    violations <- c(violations, list(list(
      rule = "MISSING_REQUIRED_COLUMNS",
      detail = paste(miss_col, collapse = ",")
    )))
    return(list(
      ok = FALSE,
      schema_version = sv,
      row_count = nr,
      rows_pass = 0L,
      rows_fail = nr,
      metrics = metrics,
      violations = violations,
      run_id = NA_character_
    ))
  }

  mx <- suppressWarnings(as.integer(sch$analyte_max_chars %||% 512L))
  if (is.na(mx) || mx < 1L) {
    mx <- 512L
  }
  smx <- suppressWarnings(as.integer(sch$sample_id_max_chars %||% 256L))
  if (is.na(smx) || smx < 1L) {
    smx <- 256L
  }

  analyte <- trimws(as.character(norm_df$analyte))
  analyte[is.na(analyte)] <- ""

  result_num <- suppressWarnings(as.numeric(norm_df$result_value))

  allowed_u <- sch$allowed_result_units %||% default_external_upload_schema()$allowed_result_units
  allowed_u <- unique(tolower(trimws(as.character(allowed_u))))

  ru <- if ("result_unit" %in% names(norm_df)) norm_df$result_unit else rep(NA_character_, nr)
  ru <- tolower(trimws(as.character(ru)))
  ru[is.na(ru)] <- ""

  row_bad <- (analyte == "") | is.na(result_num) | !is.finite(result_num) |
    (nzchar(ru) & !(ru %in% allowed_u))

  an_len <- nchar(analyte, type = "chars", allowNA = TRUE)
  an_len[is.na(an_len)] <- 0L
  row_bad <- row_bad | (an_len > mx)

  if ("sample_id" %in% names(norm_df)) {
    sid <- trimws(as.character(norm_df$sample_id))
    sid[is.na(sid)] <- ""
    sid_len <- nchar(sid, type = "chars", allowNA = TRUE)
    sid_len[is.na(sid_len)] <- 0L
    row_bad <- row_bad | (sid_len > smx)
  }

  if (isTRUE(sch$enforce_lat_lon_range %||% TRUE)) {
    if ("latitude" %in% names(norm_df)) {
      latv <- suppressWarnings(as.numeric(norm_df$latitude))
      row_bad <- row_bad | (!is.na(latv) & (latv < -90 | latv > 90))
    }
    if ("longitude" %in% names(norm_df)) {
      lonv <- suppressWarnings(as.numeric(norm_df$longitude))
      row_bad <- row_bad | (!is.na(lonv) & (lonv < -180 | lonv > 180))
    }
  }

  rows_fail <- sum(row_bad, na.rm = TRUE)
  rows_pass <- nr - rows_fail

  metrics$n_analyte_blank <- sum(analyte == "", na.rm = TRUE)
  metrics$n_analyte_too_long <- sum(an_len > mx, na.rm = TRUE)
  metrics$n_result_nonfinite <- sum(is.na(result_num) | !is.finite(result_num), na.rm = TRUE)
  metrics$n_unit_invalid <- sum(nzchar(ru) & !(ru %in% allowed_u), na.rm = TRUE)
  if ("sample_id" %in% names(norm_df)) {
    sid <- trimws(as.character(norm_df$sample_id))
    sid[is.na(sid)] <- ""
    metrics$n_sample_id_too_long <- sum(nchar(sid, type = "chars", allowNA = TRUE) > smx, na.rm = TRUE)
  }
  metrics$n_rows_fail <- rows_fail
  metrics$n_rows_pass <- rows_pass

  ok <- rows_fail == 0L && length(violations) == 0L

  list(
    ok = ok,
    schema_version = sv,
    row_count = nr,
    rows_pass = rows_pass,
    rows_fail = rows_fail,
    metrics = metrics,
    violations = violations,
    run_id = NA_character_
  )
}

persist_upload_validation_run <- function(con, phase, sch_res, validated_by, file_name, raw_sha256, dataset_type) {
  ensure_valid_db_connection()
  rid <- make_id("UVR")
  sch_res$run_id <- rid
  payload <- jsonlite::toJSON(
    list(
      metrics = sch_res$metrics,
      violations = sch_res$violations,
      phase = phase,
      strict_ok = isTRUE(sch_res$ok)
    ),
    auto_unbox = TRUE,
    null = "null"
  )
  tryCatch(
    DBI::dbExecute(
      con,
      paste0(
        "INSERT INTO upload_validation_run ",
        "(run_id, phase, schema_version, status, validated_at, validated_by, file_name, raw_sha256, dataset_type, ",
        "row_count, rows_pass, rows_fail, metrics_json, mapping_engine_version) ",
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
      ),
      params = list(
        rid,
        as.character(phase %||% "unknown"),
        as.character(sch_res$schema_version %||% ""),
        if (isTRUE(sch_res$ok)) "PASS" else "FAIL",
        as.character(Sys.time()),
        as.character(validated_by %||% "unknown"),
        as.character(file_name %||% ""),
        as.character(raw_sha256 %||% ""),
        as.character(dataset_type %||% ""),
        as.integer(sch_res$row_count %||% 0L),
        as.integer(sch_res$rows_pass %||% 0L),
        as.integer(sch_res$rows_fail %||% 0L),
        as.character(payload),
        as.character(MAPPING_ENGINE_VERSION)
      )
    ),
    error = function(e) {
      warning("upload_validation_run insert failed: ", conditionMessage(e))
      sch_res$run_id <- NA_character_
    }
  )
  sch_res
}

# write_audit() is defined inside server() so GLP hash-chained trail receives Shiny session context.

safe_table <- function(table_name) {
  ensure_valid_db_connection()
  if (DBI::dbExistsTable(con, table_name)) {
    DBI::dbReadTable(con, table_name) |> tibble::as_tibble()
  } else {
    tibble::tibble()
  }
}

# -------------------------------------------------------------------
# Placeholder data builders
# Replace these with real endpoint datasets, descriptors, fingerprints,
# external/prospective validation assets, and audited model metadata.
# -------------------------------------------------------------------

build_compound_registry <- function() {
  tibble::tribble(
    ~compound_id, ~compound_name, ~CAS, ~SMILES, ~pfas_subclass,
    "CMP-001", "PFOA", "335-67-1", "C(C(C(C(C(C(C(F)(F)F)(F)F)(F)F)(F)F)(F)F)(F)F)(=O)O", "PFCA",
    "CMP-002", "PFOS", "1763-23-1", "OS(=O)(=O)C(C(C(C(C(C(C(C(F)(F)F)(F)F)(F)F)(F)F)(F)F)(F)F)(F)F", "PFSA",
    "CMP-003", "PFNA", "375-95-1", "C(C(C(C(C(C(C(C(F)(F)F)(F)F)(F)F)(F)F)(F)F)(F)F)(F)F)(=O)O", "PFCA",
    "CMP-004", "PFHxS", "355-46-4", "OS(=O)(=O)C(C(C(C(C(C(F)(F)F)(F)F)(F)F)(F)F)(F)F", "PFSA",
    "CMP-005", "HFPO-DA", "13252-13-6", "OC(=O)C(OCC(F)(F)C(F)(F)F)(F)F", "Ether-acid",
    "CMP-006", "GenX", "13252-13-6", "OC(=O)C(OCC(F)(F)C(F)(F)F)(F)F", "Ether-acid"
  ) |>
    dplyr::mutate(
      molecular_weight = c(414.07, 500.13, 464.08, 400.12, 330.05, 330.05),
      log_Kow = c(4.5, 5.3, 5.4, 4.0, 3.0, 3.0),
      tpsa = c(37.3, 42.5, 37.3, 42.5, 44.8, 44.8),
      hba = c(2L, 3L, 2L, 3L, 4L, 4L),
      hbd = c(1L, 0L, 1L, 0L, 1L, 1L),
      rotatable_bonds = c(7L, 8L, 8L, 6L, 4L, 4L),
      aromatic_ring_count = 0L,
      formal_charge = 0L,
      fluorine_count = c(15L, 17L, 17L, 13L, 9L, 9L),
      carbon_chain = c(8L, 8L, 9L, 6L, 6L, 6L),
      acid_class = c("PFCA-family", "PFSA-family", "PFCA-family", "PFSA-family", "Ether-acid", "Ether-acid"),
      acid_class_code = c(1, 2, 1, 2, 3, 3),
      ether_flag = c(0L, 0L, 0L, 0L, 1L, 1L),
      sulfonate_flag = c(0L, 1L, 0L, 1L, 0L, 0L),
      carboxylate_flag = c(1L, 0L, 1L, 0L, 1L, 1L),
      precursor_flag = 0L,
      structural_alerts = c("Perfluoroalkyl acid", "Perfluoroalkyl sulfonate", "Long-chain PFCA", "PFSA alert", "Ether PFAS", "Ether PFAS")
    )
}

build_dataset_registry <- function() {
  tibble::tribble(
    ~dataset_id, ~dataset_name, ~source, ~endpoint, ~endpoint_type, ~human_relevance, ~assay_domain, ~n_total, ~n_positive, ~n_negative, ~missing_rate_pct, ~duplicate_rate_pct, ~version, ~provenance,
    "DS-HEP-001", "HepG2 Viability Benchmark", "Public curated benchmark", "hepatotoxicity_proxy", "Binary", "Proxy for human hepatotoxicity", "in vitro", 5000, 1800, 3200, 1.8, 0.6, "2025.1", "Placeholder metadata: replace with actual dataset card",
    "DS-CARD-001", "hERG Cardiotoxicity Benchmark", "Public curated benchmark", "cardiotoxicity_proxy", "Binary", "Proxy for QT/cardiac risk", "in vitro", 7200, 2100, 5100, 2.1, 0.9, "2025.1", "Placeholder metadata: replace with actual dataset card",
    "DS-GENO-001", "Ames / Genotox Benchmark", "Public curated benchmark", "genotoxicity_proxy", "Binary", "Proxy for mutagenicity/genotoxicity", "in vitro", 8400, 2900, 5500, 1.2, 0.4, "2025.1", "Placeholder metadata: replace with actual dataset card",
    "DS-ENDO-001", "Endocrine Screening Benchmark", "Public curated benchmark", "endocrine_disruption_proxy", "Binary", "Proxy for endocrine activity", "in vitro", 4300, 1100, 3200, 3.5, 1.0, "2025.1", "Placeholder metadata: replace with actual dataset card"
  )
}

build_endpoint_definitions <- function() {
  tibble::tribble(
    ~endpoint_id, ~endpoint_name, ~clinical_meaning, ~label_definition, ~proxy_assay, ~intended_decision_context, ~limitations,
    "EP-HEP", "hepatotoxicity_proxy", "Potential liver toxicity risk", "Positive if assay-defined toxic class", "HepG2 viability / CYP-related proxy", "Early deprioritization / follow-up assay selection", "Proxy endpoint; not equivalent to confirmed human DILI",
    "EP-CARD", "cardiotoxicity_proxy", "Potential cardiac liability", "Positive if cardiotoxicity proxy class", "hERG / cardiac electrophysiology proxy", "Early cardiac liability triage", "Proxy endpoint; not full human cardiotoxicity severity",
    "EP-GENO", "genotoxicity_proxy", "Potential genotoxicity / mutagenicity", "Positive if benchmark label positive", "Ames / micronucleus proxy", "Mutagenicity screening / escalation", "Requires confirmatory evidence for regulatory use",
    "EP-ENDO", "endocrine_disruption_proxy", "Potential endocrine activity", "Positive if endocrine-active class", "Reporter / endocrine assay proxy", "Prioritization / assay follow-up", "Proxy endpoint with uncertain translation across contexts"
  )
}

build_proxy_assay_table <- function() {
  tibble::tribble(
    ~toxicity_domain, ~proxy_assay, ~mechanistic_relevance, ~human_translation_note, ~recommended_next_step,
    "Hepatotoxicity", "HepG2 viability / CYP inhibition", "Moderate", "Useful early proxy but incomplete for human liver injury", "Confirm with higher-content hepatic assay / human-relevant system",
    "Cardiotoxicity", "hERG / cardiomyocyte proxy", "High for selected mechanisms", "Captures some cardiac liabilities but not whole-clinical severity", "Confirm with broader cardiac panel / exposure context",
    "Genotoxicity", "Ames / micronucleus", "High", "Well-established screening proxies for mutagenicity/genotoxicity", "Escalate to confirmatory genotox review",
    "Endocrine disruption", "Reporter gene / endocrine assay", "Moderate", "Assay positive does not guarantee in vivo endocrine outcome", "Review receptor specificity and orthogonal evidence"
  )
}

build_descriptor_schema <- function() {
  tibble::tribble(
    ~feature_name, ~type, ~category, ~source, ~used_in_models,
    "molecular_weight", "numeric", "Descriptor", "RDKit placeholder", TRUE,
    "log_Kow", "numeric", "Descriptor", "RDKit placeholder", TRUE,
    "tpsa", "numeric", "Descriptor", "RDKit placeholder", TRUE,
    "hba", "integer", "Descriptor", "RDKit placeholder", TRUE,
    "hbd", "integer", "Descriptor", "RDKit placeholder", TRUE,
    "rotatable_bonds", "integer", "Descriptor", "RDKit placeholder", TRUE,
    "aromatic_ring_count", "integer", "Descriptor", "RDKit placeholder", TRUE,
    "formal_charge", "integer", "Descriptor", "RDKit placeholder", TRUE,
    "fluorine_count", "integer", "PFAS descriptor", "Rule-based placeholder", TRUE,
    "carbon_chain", "integer", "PFAS descriptor", "Rule-based placeholder", TRUE,
    "pfas_subclass", "categorical", "PFAS descriptor", "Rule-based placeholder", TRUE,
    "structural_alerts", "text", "Structural alerts", "Rule-based placeholder", FALSE
  )
}

build_fingerprint_schema <- function() {
  tibble::tribble(
    ~fingerprint_type, ~radius_or_length, ~mode, ~tool, ~included_for_endpoints,
    "MACCS", "166 bits", "binary", "RDKit placeholder", "All",
    "Morgan/ECFP", "radius 2 / 2048 bits", "binary", "RDKit placeholder", "All"
  )
}

build_structural_alert_table <- function() {
  tibble::tribble(
    ~alert_id, ~alert_name, ~mechanistic_relevance, ~endpoint_relevance, ~rule_source,
    "AL-001", "Perfluoroalkyl acid motif", "General persistence / PFAS identity", "All PFAS endpoints", "Placeholder SMARTS",
    "AL-002", "Long-chain PFCA alert", "Bioaccumulation concern", "Bioaccumulation / chronic concern", "Placeholder SMARTS",
    "AL-003", "PFSA alert", "PFSA subclass mechanistic grouping", "Cardio / bioaccumulation context", "Placeholder SMARTS",
    "AL-004", "Ether PFAS alert", "Emerging PFAS subclass", "New chemistry monitoring", "Placeholder SMARTS"
  )
}

build_model_registry <- function() {
  tibble::tribble(
    ~model_id, ~endpoint, ~algorithm, ~representation, ~training_n, ~class_handling, ~calibration, ~version, ~deployment_status,
    "MDL-HEP-RF", "hepatotoxicity_proxy", "Random Forest", "Descriptors + MACCS + Morgan", 5000, "Class weights", "Platt/Isotonic placeholder", "1.0", "Prototype",
    "MDL-CARD-SVM", "cardiotoxicity_proxy", "SVM", "Descriptors + MACCS + Morgan", 7200, "Class weights", "Platt/Isotonic placeholder", "1.0", "Prototype",
    "MDL-GENO-XGB", "genotoxicity_proxy", "XGBoost", "Descriptors + MACCS + Morgan", 8400, "Class weights", "Platt/Isotonic placeholder", "1.0", "Prototype",
    "MDL-ENDO-RF", "endocrine_disruption_proxy", "Random Forest", "Descriptors + MACCS + Morgan", 4300, "Class weights", "Platt/Isotonic placeholder", "1.0", "Prototype"
  )
}

build_hyperparameter_summary <- function() {
  tibble::tribble(
    ~model_id, ~parameter, ~value, ~tuning_method,
    "MDL-HEP-RF", "mtry", "auto placeholder", "Nested CV placeholder",
    "MDL-HEP-RF", "ntree", "500", "Nested CV placeholder",
    "MDL-CARD-SVM", "cost", "auto placeholder", "Nested CV placeholder",
    "MDL-CARD-SVM", "gamma", "auto placeholder", "Nested CV placeholder",
    "MDL-GENO-XGB", "max_depth", "6", "Nested CV placeholder",
    "MDL-GENO-XGB", "eta", "0.05", "Nested CV placeholder",
    "MDL-ENDO-RF", "mtry", "auto placeholder", "Nested CV placeholder"
  )
}

build_baseline_comparison <- function() {
  tibble::tribble(
    ~endpoint, ~baseline_model, ~production_candidate, ~delta_auc, ~delta_balanced_accuracy, ~delta_sensitivity, ~delta_specificity,
    "hepatotoxicity_proxy", "Logistic Regression", "Random Forest", 0.07, 0.06, 0.04, 0.05,
    "cardiotoxicity_proxy", "Logistic Regression", "SVM", 0.05, 0.05, 0.03, 0.04,
    "genotoxicity_proxy", "Logistic Regression", "XGBoost", 0.08, 0.07, 0.05, 0.06,
    "endocrine_disruption_proxy", "Logistic Regression", "Random Forest", 0.04, 0.03, 0.02, 0.03
  )
}

build_validation_summary <- function() {
  tibble::tribble(
    ~model_id, ~endpoint, ~split_strategy, ~train_n, ~validation_n, ~test_n, ~external_set_n, ~prospective_set_n, ~leakage_check, ~status,
    "MDL-HEP-RF", "hepatotoxicity_proxy", "5-fold CV + hold-out", 4000, 500, 500, 700, 0, "Pass", "Needs prospective validation",
    "MDL-CARD-SVM", "cardiotoxicity_proxy", "5-fold CV + hold-out", 5760, 720, 720, 500, 0, "Pass", "Needs prospective validation",
    "MDL-GENO-XGB", "genotoxicity_proxy", "5-fold CV + hold-out", 6720, 840, 840, 600, 0, "Pass", "Needs prospective validation",
    "MDL-ENDO-RF", "endocrine_disruption_proxy", "5-fold CV + hold-out", 3440, 430, 430, 350, 0, "Pass", "Needs prospective validation"
  )
}

build_performance_metrics <- function() {
  tibble::tribble(
    ~model_id, ~AUC, ~Accuracy, ~Balanced_Accuracy, ~Sensitivity, ~Specificity, ~Precision, ~Recall, ~F1, ~MCC, ~Brier,
    "MDL-HEP-RF", 0.84, 0.79, 0.78, 0.75, 0.81, 0.72, 0.75, 0.74, 0.55, 0.16,
    "MDL-CARD-SVM", 0.82, 0.77, 0.76, 0.73, 0.79, 0.70, 0.73, 0.71, 0.51, 0.18,
    "MDL-GENO-XGB", 0.86, 0.80, 0.79, 0.77, 0.81, 0.75, 0.77, 0.76, 0.58, 0.15,
    "MDL-ENDO-RF", 0.78, 0.74, 0.72, 0.68, 0.77, 0.63, 0.68, 0.65, 0.44, 0.20
  )
}

build_error_buckets <- function() {
  tibble::tribble(
    ~endpoint, ~false_positives, ~false_negatives, ~likely_causes, ~high_risk_failure_mode,
    "hepatotoxicity_proxy", 55, 70, "Sparse chemotypes, proxy mismatch", "False negative hepatic liability",
    "cardiotoxicity_proxy", 63, 78, "Exposure context not modeled", "False negative cardiac risk",
    "genotoxicity_proxy", 49, 61, "Assay label inconsistency", "False negative mutagenicity",
    "endocrine_disruption_proxy", 52, 67, "Weak receptor transferability", "False negative endocrine activity"
  )
}

build_ad_registry <- function() {
  tibble::tribble(
    ~endpoint, ~ad_method, ~training_space_basis, ~distance_metric, ~threshold, ~status,
    "hepatotoxicity_proxy", "Distance to training chemical space", "Descriptors + fingerprints", "z-score / NN hybrid placeholder", "1.5 / 2.5", "Prototype",
    "cardiotoxicity_proxy", "Distance to training chemical space", "Descriptors + fingerprints", "z-score / NN hybrid placeholder", "1.5 / 2.5", "Prototype",
    "genotoxicity_proxy", "Distance to training chemical space", "Descriptors + fingerprints", "z-score / NN hybrid placeholder", "1.5 / 2.5", "Prototype",
    "endocrine_disruption_proxy", "Distance to training chemical space", "Descriptors + fingerprints", "z-score / NN hybrid placeholder", "1.5 / 2.5", "Prototype"
  )
}

build_prediction_table <- function(compounds) {
  endpoints <- c("hepatotoxicity_proxy", "cardiotoxicity_proxy", "genotoxicity_proxy", "endocrine_disruption_proxy")
  expand.grid(compound_id = compounds$compound_id, endpoint = endpoints, stringsAsFactors = FALSE) |>
    tibble::as_tibble() |>
    dplyr::left_join(compounds, by = "compound_id") |>
    dplyr::mutate(
      predicted_probability = c(0.61, 0.72, 0.44, 0.31, 0.28, 0.28, 0.67, 0.80, 0.36, 0.22, 0.24, 0.24,
                                0.58, 0.64, 0.51, 0.34, 0.26, 0.26, 0.62, 0.74, 0.40, 0.30, 0.27, 0.27),
      predicted_class = ifelse(predicted_probability >= 0.50, "Positive", "Negative"),
      ad_distance = c(1.1, 1.3, 1.7, 1.4, 2.8, 2.8, 1.2, 1.6, 1.5, 1.4, 2.6, 2.6,
                      1.3, 1.2, 1.8, 1.5, 2.4, 2.4, 1.0, 1.1, 1.9, 1.7, 2.3, 2.3),
      ad_status = dplyr::case_when(
        ad_distance <= 1.5 ~ "Inside",
        ad_distance <= 2.5 ~ "Borderline",
        TRUE ~ "Outside"
      ),
      confidence = dplyr::case_when(
        ad_status == "Outside" ~ "Low",
        predicted_probability >= 0.80 ~ "High",
        predicted_probability >= 0.60 ~ "Medium",
        TRUE ~ "Low"
      ),
      similar_compound_support = c("Moderate", "High", "Moderate", "Low", "Low", "Low", "Moderate", "High", "Moderate", "Low", "Low", "Low",
                                   "Moderate", "Moderate", "Moderate", "Low", "Low", "Low", "High", "High", "Moderate", "Low", "Low", "Low"),
      recommended_action = dplyr::case_when(
        ad_status == "Outside" ~ "Out-of-domain: do not rely",
        predicted_class == "Positive" & confidence %in% c("High", "Medium") ~ "Confirm with assay",
        predicted_class == "Positive" ~ "Needs human review",
        TRUE ~ "Advance with caution"
      )
    )
}

build_feature_importance <- function() {
  tibble::tribble(
    ~endpoint, ~feature, ~importance, ~interpretation,
    "hepatotoxicity_proxy", "log_Kow", 0.23, "Exposure/partitioning-related contribution",
    "hepatotoxicity_proxy", "fluorine_count", 0.19, "PFAS burden proxy",
    "hepatotoxicity_proxy", "molecular_weight", 0.14, "Global size signal",
    "cardiotoxicity_proxy", "sulfonate_flag", 0.21, "Subclass-associated alert contribution",
    "cardiotoxicity_proxy", "log_Kow", 0.17, "Lipophilicity-related signal",
    "genotoxicity_proxy", "structural_alerts", 0.18, "Structural-risk proxy placeholder",
    "genotoxicity_proxy", "molecular_weight", 0.11, "Weak size contribution",
    "endocrine_disruption_proxy", "ether_flag", 0.20, "Subclass-associated pattern",
    "endocrine_disruption_proxy", "carbon_chain", 0.14, "Chain-length contribution"
  )
}

build_analog_support <- function(compounds) {
  tibble::tribble(
    ~query_compound, ~nearest_analog, ~similarity, ~known_label, ~source_dataset, ~relevance,
    "PFOA", "PFNA", 0.89, "Positive in hepatotoxicity proxy", "DS-HEP-001", "High",
    "PFOS", "PFHxS", 0.87, "Positive in cardiotoxicity proxy", "DS-CARD-001", "High",
    "HFPO-DA", "GenX", 0.95, "Negative/Borderline mixed", "DS-ENDO-001", "Moderate"
  )
}

build_mechanistic_rationale <- function() {
  tibble::tribble(
    ~endpoint, ~evidence_type, ~description, ~strength, ~source,
    "hepatotoxicity_proxy", "Proxy assay rationale", "Hepatic proxy endpoint used for early screening", "Moderate", "Internal model card placeholder",
    "cardiotoxicity_proxy", "Mechanistic proxy", "Cardiac proxy informed by electrophysiology-related assay logic", "Moderate", "Internal model card placeholder",
    "genotoxicity_proxy", "Assay benchmark", "Mutagenicity proxy from benchmark screening context", "High", "Internal model card placeholder",
    "endocrine_disruption_proxy", "Assay benchmark", "Endocrine-active proxy from reporter-style endpoint logic", "Moderate", "Internal model card placeholder"
  )
}

build_model_cards <- function() {
  tibble::tribble(
    ~model_id, ~endpoint, ~dataset_source, ~representation, ~algorithm, ~training_date, ~validation_strategy, ~external_validation, ~prospective_validation, ~ad_method, ~intended_use, ~limitations, ~owner_version,
    "MDL-HEP-RF", "hepatotoxicity_proxy", "DS-HEP-001", "Descriptors + MACCS + Morgan", "Random Forest", "2026-04-07", "5-fold CV + hold-out + external set", "Available", "Not yet", "Distance + nearest neighbors", "Screening / prioritization", "Proxy endpoint, no prospective validation yet", "Owner A / v1.0",
    "MDL-CARD-SVM", "cardiotoxicity_proxy", "DS-CARD-001", "Descriptors + MACCS + Morgan", "SVM", "2026-04-07", "5-fold CV + hold-out + external set", "Available", "Not yet", "Distance + nearest neighbors", "Screening / prioritization", "Proxy endpoint, exposure context incomplete", "Owner A / v1.0",
    "MDL-GENO-XGB", "genotoxicity_proxy", "DS-GENO-001", "Descriptors + MACCS + Morgan", "XGBoost", "2026-04-07", "5-fold CV + hold-out + external set", "Available", "Not yet", "Distance + nearest neighbors", "Screening / prioritization", "No prospective validation yet", "Owner A / v1.0",
    "MDL-ENDO-RF", "endocrine_disruption_proxy", "DS-ENDO-001", "Descriptors + MACCS + Morgan", "Random Forest", "2026-04-07", "5-fold CV + hold-out + external set", "Available", "Not yet", "Distance + nearest neighbors", "Screening / prioritization", "Proxy endpoint, mechanism depends on assay context", "Owner A / v1.0"
  )
}

build_oecd_checklist <- function() {
  tibble::tribble(
    ~principle, ~requirement, ~evidence_in_app, ~status, ~notes,
    "Defined endpoint", "Endpoint must be clearly defined", "Endpoint Definitions table", "Partial", "Needs real production endpoint cards",
    "Unambiguous algorithm", "Algorithm and configuration explicit", "Model registry + hyperparameters", "Partial", "Needs production-training provenance",
    "Applicability domain", "AD clearly defined", "AD registry + compound AD summary", "Partial", "Prototype AD only",
    "Goodness-of-fit / robustness / predictivity", "Performance and validation reported", "Validation summary + metrics", "Partial", "Needs real external/prospective runs",
    "Mechanistic interpretation", "Interpretability where possible", "Feature importance + alerts + analog support", "Partial", "Needs endpoint-specific mechanistic evidence"
  )
}

build_system_readiness <- function() {
  tibble::tribble(
    ~component, ~status, ~notes,
    "Endpoint definitions", "Present", "Placeholder endpoint cards loaded",
    "Descriptor generation", "Present", "Placeholder descriptor schema",
    "Fingerprints generation", "Present", "Schema only; connect real generator",
    "Validation metrics", "Present", "Placeholder tables",
    "External validation", "Present", "Placeholder metadata only",
    "Prospective validation", "Missing", "Add prospective test assets",
    "Applicability domain", "Present", "Prototype AD tables",
    "Mechanistic interpretation", "Present", "Placeholder evidence tables",
    "Weight-of-evidence engine", "Present", "Rule-based skeleton",
    "Model cards", "Present", "Placeholder cards"
  )
}

# -------------------------------------------------------------------
# Materialize app data
# -------------------------------------------------------------------

compounds <- build_compound_registry()
dataset_registry <- build_dataset_registry()
endpoint_definitions <- build_endpoint_definitions()
proxy_assay_table <- build_proxy_assay_table()
descriptor_schema <- build_descriptor_schema()
fingerprint_schema <- build_fingerprint_schema()
structural_alert_table <- build_structural_alert_table()
model_registry <- build_model_registry()
hyperparameter_summary <- build_hyperparameter_summary()
baseline_comparison <- build_baseline_comparison()
validation_summary <- build_validation_summary()
performance_metrics <- build_performance_metrics()
error_buckets <- build_error_buckets()
ad_registry <- build_ad_registry()
predictions <- build_prediction_table(compounds)
feature_importance <- build_feature_importance()
analog_support <- build_analog_support(compounds)
mechanistic_rationale <- build_mechanistic_rationale()
model_cards <- build_model_cards()
oecd_checklist <- build_oecd_checklist()
system_readiness <- build_system_readiness()

compound_ad_summary <- predictions |>
  dplyr::select(compound_id, compound_name, endpoint, ad_distance, ad_status, confidence) |>
  dplyr::arrange(endpoint, compound_name)

weight_of_evidence <- predictions |>
  dplyr::mutate(
    structural_alert_count = dplyr::if_else(structural_alerts == "", 0L, 1L),
    evidence_grade = dplyr::case_when(
      ad_status == "Outside" ~ "Weak",
      predicted_class == "Positive" & confidence == "High" ~ "Strong",
      predicted_class == "Positive" ~ "Moderate",
      TRUE ~ "Moderate"
    ),
    woe_score = dplyr::case_when(
      evidence_grade == "Strong" ~ 3,
      evidence_grade == "Moderate" ~ 2,
      TRUE ~ 1
    ),
    suggested_action = recommended_action,
    escalation_priority = dplyr::case_when(
      predicted_class == "Positive" & ad_status != "Outside" ~ "High",
      ad_status == "Outside" ~ "High",
      TRUE ~ "Medium"
    )
  ) |>
  dplyr::select(
    compound_id, compound_name, endpoint, predicted_class, predicted_probability,
    confidence, ad_status, structural_alert_count, similar_compound_support,
    evidence_grade, woe_score, suggested_action, escalation_priority
  )

# -------------------------------------------------------------------
# Reusable plotting helpers
# -------------------------------------------------------------------

plot_class_balance <- function() {
  df <- dataset_registry |>
    dplyr::select(endpoint, n_positive, n_negative) |>
    tidyr::pivot_longer(cols = c(n_positive, n_negative), names_to = "class", values_to = "n")
  
  ggplot(df, aes(x = endpoint, y = n, fill = class)) +
    geom_col(position = "stack") +
    coord_flip() +
    labs(x = NULL, y = "Count", title = "Class balance by endpoint") +
    theme_minimal(base_size = 12)
}

plot_missingness <- function() {
  df <- dataset_registry |>
    dplyr::select(dataset_name, missing_rate_pct)
  
  ggplot(df, aes(x = reorder(dataset_name, missing_rate_pct), y = missing_rate_pct)) +
    geom_col() +
    coord_flip() +
    labs(x = NULL, y = "Missing rate (%)", title = "Dataset missingness") +
    theme_minimal(base_size = 12)
}

plot_validation_metrics <- function(metric_name) {
  df <- performance_metrics |>
    dplyr::select(model_id, all_of(metric_name))
  
  ggplot(df, aes(x = reorder(model_id, .data[[metric_name]]), y = .data[[metric_name]])) +
    geom_col() +
    coord_flip() +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
    labs(x = NULL, y = metric_name, title = paste(metric_name, "by model")) +
    theme_minimal(base_size = 12)
}

plot_ad_distribution <- function() {
  ggplot(compound_ad_summary, aes(x = ad_status)) +
    geom_bar() +
    labs(x = NULL, y = "Count", title = "Applicability-domain status") +
    theme_minimal(base_size = 12)
}

plot_prediction_risk <- function() {
  df <- weight_of_evidence |>
    dplyr::count(endpoint, predicted_class)
  
  ggplot(df, aes(x = endpoint, y = n, fill = predicted_class)) +
    geom_col(position = "stack") +
    coord_flip() +
    labs(x = NULL, y = "Count", title = "Predicted class distribution by endpoint") +
    theme_minimal(base_size = 12)
}

plot_feature_importance <- function(endpoint_pick) {
  df <- feature_importance |>
    dplyr::filter(endpoint == endpoint_pick)
  
  ggplot(df, aes(x = reorder(feature, importance), y = importance)) +
    geom_col() +
    coord_flip() +
    labs(x = NULL, y = "Importance", title = paste("Top features:", endpoint_pick)) +
    theme_minimal(base_size = 12)
}

# -------------------------------------------------------------------
# UI
# -------------------------------------------------------------------

ui_dashboard <- dashboardPage(
  dashboardHeader(title = APP_TITLE),
  dashboardSidebar(
    sidebarMenu(
      menuItem("Home / Overview", tabName = "home", icon = icon("home")),
      menuItem("Data & Endpoints", tabName = "data", icon = icon("database")),
      menuItem("Data Collection", tabName = "collection", icon = icon("edit")),
      menuItem("Representations", tabName = "representations", icon = icon("project-diagram")),
      menuItem("Modeling", tabName = "modeling", icon = icon("cogs")),
      menuItem("Validation", tabName = "validation", icon = icon("check-circle")),
      menuItem("Predictions", tabName = "predictions", icon = icon("table")),
      menuItem("Enterprise 5.0 (Cloud API)", tabName = "enterprise5", icon = icon("cloud")),
      menuItem("Applicability Domain", tabName = "ad", icon = icon("bullseye")),
      menuItem("Mechanistic Interpretation", tabName = "mechanistic", icon = icon("microscope")),
      menuItem("Decision Support", tabName = "decision", icon = icon("balance-scale")),
      menuItem("Compliance / Model Cards", tabName = "compliance", icon = icon("clipboard-check")),
      menuItem("Reports / Export", tabName = "reports", icon = icon("file-export")),
      menuItem("ISO 17025 / GLP", tabName = "glp", icon = icon("certificate"))
    )
  ),
  dashboardBody(
    tags$head(tags$style(HTML(".small-box h3 {font-size: 26px;} .content {padding: 15px;} .box .dataTables_wrapper {overflow-x:auto;}"))),
    tabItems(
      tabItem(
        tabName = "home",
        fluidRow(
          valueBoxOutput("vb_compounds", width = 2),
          valueBoxOutput("vb_datasets", width = 2),
          valueBoxOutput("vb_models", width = 2),
          valueBoxOutput("vb_inside_ad", width = 2),
          valueBoxOutput("vb_outside_ad", width = 2),
          valueBoxOutput("vb_high_concern", width = 2)
        ),
        fluidRow(
          box(width = 6, title = "Intended Use", status = "primary", solidHeader = TRUE,
              p("Use this system for screening, prioritization, transparency review, and weight-of-evidence support. Do not treat this scaffold as a standalone regulatory submission engine until it is backed by validated production endpoint models and audited datasets.")),
          box(width = 6, title = "Current Limitations", status = "warning", solidHeader = TRUE,
              p("This version is a standards-oriented skeleton. Replace placeholder datasets, placeholder validation statistics, and placeholder model cards with real endpoint assets, external validation results, and prospective testing evidence."))
        ),
        fluidRow(
          box(width = 6, title = "System Readiness", status = "info", solidHeader = TRUE, DTOutput("tbl_system_readiness")),
          box(width = 6, title = "OECD / QSAR Principles Checklist", status = "info", solidHeader = TRUE, DTOutput("tbl_oecd_home"))
        ),
        fluidRow(
          box(
            width = 12,
            title = "Final Professional Featured Stack",
            status = "success",
            solidHeader = TRUE,
            tags$p(tags$em("For qualified partners under NDA. All systems must be validated for ISO/IEC 17025:2017 controls before production release.")),
            tags$div(
              style = "display:flex; flex-wrap:wrap; gap:10px;",
              featured_stack_button(LINK_SHINY_DEMO, "btn-primary", "1) Technical Review & Demo"),
              featured_stack_button(LINK_GITHUB_REPO, "btn-info", "2) Code & Validation Package"),
              featured_stack_button(LINK_DATASET_FORM, "btn-warning", "3) Data Submission"),
              featured_stack_button(LINK_COLLAB, "btn-success", "4) Collaboration & Partnership")
            ),
            tags$hr(),
            tags$p(
              tags$strong("1) Technical Review & Demo: "),
              featured_link_status(LINK_SHINY_DEMO),
              tags$br(),
              "Private staging environment. Request access through controlled onboarding. ",
              tags$em("SSO required; sessions logged per ISO 17025 clause 7.11.3.")
            ),
            tags$p(
              tags$strong("2) Code & Validation Package: "),
              featured_link_status(LINK_GITHUB_REPO),
              tags$br(),
              "Private repository access granted after required agreements are executed. ",
              tags$em("Supports software validation evidence and change-control traceability per 7.11.2 and 7.11.4.")
            ),
            tags$p(
              tags$strong("3) Data Submission: "),
              featured_link_status(LINK_DATASET_FORM),
              tags$br(),
              "Secured intake with PII/PHI scan + chemist review planned. ",
              tags$em("Aligns to 8.4.2 + 7.11.6. No public endpoint active.")
            ),
            tags$p(
              tags$strong("Current intake endpoint: "),
              tags$code(if (is_disabled_link(LINK_DATASET_FORM)) "No public endpoint active." else LINK_DATASET_FORM)
            ),
            tags$p(
              tags$strong("Confirmation message after form receipt: "),
              DATASET_FORM_CONFIRMATION_MESSAGE
            ),
            tags$p(
              tags$strong("4) Collaboration & Partnership: "),
              featured_link_status(LINK_COLLAB),
              tags$br(),
              "Partnership intake with QA and legal review prior to project activation. ",
              tags$em("Includes impartiality and confidentiality governance aligned to 4.1.5 and 8.4.2.")
            ),
            tags$hr(),
            tags$div(
              class = "well well-sm",
              style = "margin-bottom:12px;",
              tags$strong("Intake API health"),
              tags$span(" ", style = "display:inline-block; width:6px;"),
              actionButton("btn_check_intake_api_health", "Check now", class = "btn btn-default btn-xs"),
              tags$div(style = "margin-top:8px;", verbatimTextOutput("intake_api_health_status", placeholder = TRUE))
            ),
            tags$hr(),
            tags$small(
              "Optional env overrides: PFAS_LINK_SHINY_DEMO, PFAS_LINK_GITHUB_REPO, PFAS_INTAKE_API_URL, PFAS_LINK_DATASET_FORM, PFAS_LINK_COLLAB, PFAS_DATASET_FORM_CONFIRMATION_MESSAGE, PFAS_INTAKE_STAGING_TOKEN, PFAS_PARTNER_AUDIT_SQLITE_TABLE, PFAS_PARTNER_AUDIT_MIRROR_CSV. PFAS_LINK_DATASET_FORM defaults to PFAS_INTAKE_API_URL + /upload when not explicitly set. In production, set PFAS_INTAKE_API_URL, PFAS_LINK_DATASET_FORM, and PFAS_INTAKE_STAGING_TOKEN to null until 7.11.3 verification is complete."
            )
          )
        )
      ),
      tabItem(
        tabName = "data",
        fluidRow(
          box(width = 12, title = "Datasets", status = "primary", solidHeader = TRUE, DTOutput("tbl_dataset_registry"))
        ),
        fluidRow(
          box(width = 6, title = "Endpoint Definitions", status = "warning", solidHeader = TRUE, DTOutput("tbl_endpoint_definitions")),
          box(width = 6, title = "Proxy Endpoints", status = "warning", solidHeader = TRUE, DTOutput("tbl_proxy_assays"))
        ),
        fluidRow(
          box(width = 6, title = "Dataset Missingness", status = "info", solidHeader = TRUE, plotOutput("plot_missingness", height = 300)),
          box(width = 6, title = "Class Balance", status = "info", solidHeader = TRUE, plotOutput("plot_class_balance", height = 300))
        )
      ),
      tabItem(
        tabName = "collection",
        fluidRow(
          box(
            width = 12, title = "Data Collection Hub", status = "primary", solidHeader = TRUE,
            tabsetPanel(
              tabPanel(
                "Compound Intake",
                fluidRow(
                  box(width = 6,
                      textInput("compound_name", "Compound Name"),
                      textInput("smiles", "SMILES"),
                      textInput("cas", "CAS"),
                      selectInput("pfas_subclass", "PFAS Subclass",
                                  choices = c("PFCA", "PFSA", "Ether-acid", "Precursor", "Other")),
                      selectInput("source_type", "Source Type",
                                  choices = c("client", "literature", "standard", "curated", "inferred")),
                      textInput("source_reference", "Source Reference"),
                      selectInput("compound_review_status", "Review Status",
                                  choices = c("draft", "review", "approved", "rejected")),
                      textInput("compound_created_by", "Created By"),
                      actionButton("save_compound", "Save Compound", class = "btn-primary")
                  )
                )
              ),
              tabPanel(
                "Sample / Batch Intake",
                fluidRow(
                  box(width = 6,
                      textInput("sample_id", "Sample ID"),
                      textInput("project_id", "Project ID"),
                      textInput("client_id", "Client ID"),
                      selectInput("matrix", "Matrix",
                                  choices = c("water", "soil", "serum", "sludge", "biosolids", "tissue", "other")),
                      selectInput("sample_type", "Sample Type",
                                  choices = c("raw", "extract", "standard", "blank", "spike")),
                      dateInput("collection_date", "Collection Date"),
                      textInput("batch_id", "Batch ID"),
                      textInput("instrument_id", "Instrument ID"),
                      textInput("method_id", "Method ID"),
                      textInput("operator", "Operator"),
                      textAreaInput("sample_notes", "Notes"),
                      actionButton("save_sample", "Save Sample", class = "btn-primary")
                  )
                )
              ),
              tabPanel(
                "Measurement Entry",
                fluidRow(
                  box(width = 6,
                      uiOutput("compound_select_ui"),
                      uiOutput("sample_select_ui"),
                      numericInput("retention_time", "Retention Time", value = NA),
                      numericInput("precursor_mz", "Precursor m/z", value = NA),
                      numericInput("product_mz", "Product m/z", value = NA),
                      numericInput("peak_area", "Peak Area", value = NA),
                      numericInput("signal_to_noise", "Signal-to-Noise", value = NA),
                      numericInput("concentration", "Concentration", value = NA),
                      selectInput("concentration_unit", "Concentration Unit",
                                  choices = c("ng/L", "ug/L", "mg/L", "ng/g", "ug/kg")),
                      numericInput("lod", "LOD", value = NA),
                      numericInput("loq", "LOQ", value = NA),
                      textInput("internal_standard", "Internal Standard"),
                      selectInput("result_flag", "Result Flag",
                                  choices = c("detected", "nondetect", "estimated", "rejected")),
                      selectInput("qc_flag", "QC Flag",
                                  choices = c("pass", "fail", "review")),
                      textInput("measurement_created_by", "Created By"),
                      actionButton("save_measurement", "Save Measurement", class = "btn-primary")
                  )
                )
              ),
              tabPanel(
                "Label Curation",
                fluidRow(
                  box(width = 6,
                      uiOutput("label_compound_select_ui"),
                      selectInput("endpoint", "Endpoint",
                                  choices = c("hepatotoxicity_proxy", "cardiotoxicity_proxy",
                                              "genotoxicity_proxy", "endocrine_disruption_proxy",
                                              "SR-ARE", "NR-PPAR-gamma")),
                      selectInput("label_value", "Label Value", choices = c("0", "1")),
                      selectInput("label_source", "Label Source",
                                  choices = c("Tox21", "ToxCast", "literature", "curated", "client")),
                      textInput("assay_id", "Assay ID"),
                      textInput("label_reference", "Source Reference"),
                      sliderInput("confidence_score", "Confidence Score", min = 0, max = 1, value = 0.8, step = 0.05),
                      textInput("curator", "Curator"),
                      selectInput("label_review_status", "Review Status",
                                  choices = c("draft", "review", "approved", "rejected")),
                      textAreaInput("label_notes", "Notes"),
                      actionButton("save_label", "Save Label", class = "btn-primary")
                  )
                )
              )
            )
          )
        ),
        fluidRow(
          box(width = 12, title = "Recent Entries", status = "info", solidHeader = TRUE,
              DTOutput("tbl_recent_entries"))
        ),
        fluidRow(
          box(width = 12, title = "Export Training Data", status = "warning", solidHeader = TRUE,
              downloadButton("download_ml_export", "Download ML Training CSV"))
        )
      ),
      tabItem(
        tabName = "representations",
        fluidRow(
          box(width = 6, title = "Descriptor Schema", status = "primary", solidHeader = TRUE, DTOutput("tbl_descriptor_schema")),
          box(width = 6, title = "Fingerprint Schema", status = "primary", solidHeader = TRUE, DTOutput("tbl_fingerprint_schema"))
        ),
        fluidRow(
          box(width = 12, title = "Structural Alerts", status = "warning", solidHeader = TRUE, DTOutput("tbl_structural_alerts"))
        ),
        fluidRow(
          box(width = 12, title = "Compound Registry", status = "info", solidHeader = TRUE, DTOutput("tbl_compounds"))
        )
      ),
      tabItem(
        tabName = "modeling",
        fluidRow(
          box(width = 8, title = "Model Registry", status = "primary", solidHeader = TRUE, DTOutput("tbl_model_registry")),
          box(width = 4, title = "Baseline Comparison", status = "info", solidHeader = TRUE, DTOutput("tbl_baseline_comparison"))
        ),
        fluidRow(
          box(width = 12, title = "Hyperparameter Summary", status = "warning", solidHeader = TRUE, DTOutput("tbl_hyperparameters"))
        )
      ),
      tabItem(
        tabName = "validation",
        fluidRow(
          box(width = 8, title = "Validation Summary", status = "primary", solidHeader = TRUE, DTOutput("tbl_validation_summary")),
          box(width = 4, title = "Error Buckets", status = "warning", solidHeader = TRUE, DTOutput("tbl_error_buckets"))
        ),
        fluidRow(
          box(width = 6, title = "Performance Metrics", status = "info", solidHeader = TRUE, DTOutput("tbl_performance_metrics")),
          box(width = 6, title = "Balanced Accuracy by Model", status = "info", solidHeader = TRUE, plotOutput("plot_bal_acc", height = 300))
        )
      ),
      tabItem(
        tabName = "predictions",
        fluidRow(
          box(width = 12, title = "Compound-Level Predictions", status = "primary", solidHeader = TRUE, DTOutput("tbl_predictions"))
        ),
        fluidRow(
          box(width = 12, title = "Prediction Distribution", status = "info", solidHeader = TRUE, plotOutput("plot_prediction_risk", height = 300))
        )
      ),
      tabItem(
        tabName = "ad",
        fluidRow(
          box(width = 6, title = "Applicability Domain Registry", status = "primary", solidHeader = TRUE, DTOutput("tbl_ad_registry")),
          box(width = 6, title = "AD Status Distribution", status = "info", solidHeader = TRUE, plotOutput("plot_ad_distribution", height = 300))
        ),
        fluidRow(
          box(width = 12, title = "Compound AD Summary", status = "warning", solidHeader = TRUE, DTOutput("tbl_ad_summary"))
        )
      ),
      tabItem(
        tabName = "mechanistic",
        fluidRow(
          box(width = 4, title = "Endpoint", status = "primary", solidHeader = TRUE,
              selectInput("mechanistic_endpoint", "Choose endpoint", choices = unique(feature_importance$endpoint), selected = unique(feature_importance$endpoint)[1])),
          box(width = 8, title = "Top Feature Contributions", status = "info", solidHeader = TRUE, plotOutput("plot_feature_importance", height = 300))
        ),
        fluidRow(
          box(width = 6, title = "Feature Importance Table", status = "primary", solidHeader = TRUE, DTOutput("tbl_feature_importance")),
          box(width = 6, title = "Analog / Read-Across Support", status = "warning", solidHeader = TRUE, DTOutput("tbl_analog_support"))
        ),
        fluidRow(
          box(width = 12, title = "Mechanistic Rationale", status = "info", solidHeader = TRUE, DTOutput("tbl_mechanistic_rationale"))
        )
      ),
      tabItem(
        tabName = "decision",
        fluidRow(
          box(width = 12, title = "Weight-of-Evidence / Decision Summary", status = "primary", solidHeader = TRUE, DTOutput("tbl_woe"))
        )
      ),
      tabItem(
        tabName = "compliance",
        fluidRow(
          box(width = 5, title = "OECD / QSAR Checklist", status = "warning", solidHeader = TRUE, DTOutput("tbl_oecd_checklist")),
          box(width = 7, title = "Model Cards", status = "primary", solidHeader = TRUE, DTOutput("tbl_model_cards"))
        )
      ),
      tabItem(
        tabName = "reports",
        fluidRow(
          box(width = 12, title = "Export / Reporting Specification", status = "info", solidHeader = TRUE,
              tags$ul(
                tags$li(tags$strong("ML validation (live): "), "after training, run step ", tags$code("16) Generate ML validation report (HTML)"), " below; artifact ", tags$code("results/ISO17025_ML_Validation_Report.html"), " plus ", tags$code("results/ml_validation_report_summary.txt"), "."),
                tags$li(tags$strong("Download: "), tags$code("Download ML validation report (HTML)"), " (same tab, pipeline runner row)."),
                tags$li("Prediction CSV — ", tags$code("results/nhanes_test_predictions.csv"), " when prediction step completes."),
                tags$li("ISO compliance narrative — ", tags$code("results/iso_compliance_report.json"), " / ", tags$code(".txt"), " from step 15."),
                tags$li("EPA ICIS-NPDES PFAS DMR slice — ", tags$code("data/processed/npdes_dmr_pfas_fy*.csv"), " from ", tags$code("scripts/filter_npdes_dmr_pfas.py"), " (effluent monitoring; not biosolids analytical chemistry)."),
                tags$li("Model cards / WoE exports — tables under Modeling / Compliance tabs (CSV exports where wired).")
              ),
              p(tags$em("Regulator / investor pack: archive HTML report, summary text, model_metadata.json, metrics JSON, leakage CSV, and split audit alongside your QMS validation record."))
          )
        ),
        fluidRow(
          box(
            width = 12,
            title = "PFAS External Data + Training Pipeline Runner",
            status = "warning",
            solidHeader = TRUE,
            textInput("pfas_python_exec", "Python executable", value = Sys.getenv("PFAS_PYTHON", if (file.exists(LOCAL_PYTHON_DEFAULT)) LOCAL_PYTHON_DEFAULT else "python"), placeholder = "python or your venv python path"),
            actionButton("btn_validate_python_exec", "Validate Python path", class = "btn-default"),
            checkboxInput("pfas_train_strict", "Training passes --strict (fail on leakage / unrealistic hold-out / TP=0 when positives exist / below min recall)", value = TRUE),
            checkboxInput("pfas_train_verbose", "Training verbose logging (-v)", value = FALSE),
            textInput(
              "pfas_train_min_recall_positive",
              "Optional minimum hold-out recall for class 1 (blank = omit; passes --min-recall-positive)",
              value = "",
              placeholder = "e.g. 0.05"
            ),
            numericInput(
              "pfas_holdout_threshold",
              "Hold-out decision threshold P≥ (confusion matrix / recall; screening default 0.25)",
              value = 0.25,
              min = 0.01,
              max = 0.99,
              step = 0.05
            ),
            helpText(
              "0.5 often yields TP=0 when probabilities sit below 0.5 (misleading accuracy on rare positives). ",
              "Lower tau improves recall but cuts precision (more negatives flagged per true positive — see flags per 10k in Reports). ",
              "Use ~0.25 as a recall-first screening default; open the training log probability summary and tune tau to match review capacity."
            ),
            verbatimTextOutput("pfas_python_status", placeholder = TRUE),
            textInput("epa_echo_urls", "EPA ECHO URL(s)", value = Sys.getenv("PFAS_ECHO_URLS", Sys.getenv("PFAS_ECHO_URL", "")), placeholder = "semicolon-separated direct URL(s)"),
            textInput("sdwis_urls", "SDWIS URL(s)", value = Sys.getenv("PFAS_SDWIS_URLS", Sys.getenv("PFAS_SDWIS_URL", "")), placeholder = "semicolon-separated direct URL(s)"),
            checkboxInput(
              "pfas_show_lab_artifact_schema_badges",
              "Show wet-lab / QMS schema badges (green/red) beside reference, method, QC, and PT paths",
              value = FALSE
            ),
            helpText(
              "Default OFF for screening / field / consultant workflows (no wet lab): paths stay informational — not an ISO 17025 readiness claim. ",
              "Turn ON only if you intentionally want template CSV schema checks next to each folder."
            ),
            textInput("pfas_ref_path", "PFAS Reference Data Path", value = file.path(PROJECT_DIR, "data", "external", "method_validation"), placeholder = "File or folder path for PFAS reference / validation datasets"),
            uiOutput("pfas_ref_path_badge"),
            textInput("pfas_method_path", "PFAS Method Data Path", value = file.path(PROJECT_DIR, "data", "external", "method_data"), placeholder = "File or folder path for EPA 533 / 537.1 / 1633 method data"),
            uiOutput("pfas_method_path_badge"),
            textInput("pfas_qc_path", "PFAS QC Data Path", value = file.path(PROJECT_DIR, "data", "external", "qc_datasets"), placeholder = "File or folder path for QC datasets"),
            uiOutput("pfas_qc_path_badge"),
            textInput("pfas_pt_path", "PFAS Proficiency Test Path", value = file.path(PROJECT_DIR, "data", "external", "proficiency_testing"), placeholder = "File or folder path for PT datasets"),
            uiOutput("pfas_pt_path_badge"),
            helpText("These fields are optional. If set, they are passed to downloader scripts as PFAS_ECHO_URLS and PFAS_SDWIS_URLS."),
            helpText(
              tags$strong("EPA ICIS-NPDES (ECHO bulk downloads): "),
              "Facility/compliance + DMR fiscal-year ZIPs + outfalls + ",
              tags$code("REF_Parameter.csv"),
              ". ",
              tags$a(href = "https://echo.epa.gov/tools/data-downloads", "ECHO Data Downloads", target = "_blank", rel = "noopener"),
              ". ",
              tags$em("Biosolids ZIP is program metadata, not national PFAS sludge concentrations; DMR is effluent monitoring — do not merge with NHANES serum rows."),
              " UI tag: ", tags$code(ICIS_NPDES_UI_VERSION), "."
            ),
            fluidRow(
              column(4, textInput("epa_icis_dmr_years", "ICIS DMR fiscal years (comma-separated)", value = "2024,2025")),
              column(
                4,
                checkboxInput("epa_icis_include_limits", "Also download national permit limits ZIP (~459 MB)", value = FALSE)
              ),
              column(4, textInput("epa_icis_filter_fy", "Python DMR filter FY", value = "2024", placeholder = "e.g. 2024"))
            ),
            actionButton("btn_bootstrap_source_folders", "Bootstrap source folders", class = "btn-default"),
            actionButton("btn_iso_preflight", "ISO Preflight (strict gate)", class = "btn-danger"),
            verbatimTextOutput("source_bootstrap_status", placeholder = TRUE),
            verbatimTextOutput("iso_data_paths_status", placeholder = TRUE),
            verbatimTextOutput("iso_preflight_status", placeholder = TRUE),
            fluidRow(
              column(12,
                actionButton("btn_pfas_download", "1) Download baseline NHANES + ECHO note", class = "btn-primary"),
                actionButton("btn_epa_ucmr5_download", "2) Download EPA UCMR5", class = "btn-info"),
                actionButton("btn_epa_icis_npdes_download", "2b) ICIS-NPDES (ECHO bulk)", class = "btn-info"),
                actionButton("btn_epa_icis_filter_dmr", "2c) DMR→PFAS CSV", class = "btn-info"),
                actionButton("btn_epa_echo_download", "3) Download EPA ECHO source", class = "btn-info"),
                actionButton("btn_epa_sdwis_download", "4) Download SDWIS source", class = "btn-info"),
                actionButton("btn_pfas_prepare", "5) Prepare baseline training table", class = "btn-info"),
                actionButton("btn_pfas_multisource", "6) Build multi-source training table", class = "btn-info"),
                actionButton("btn_pfas_matrix", "7) Build model matrix", class = "btn-info"),
                actionButton("train_pfas_model", "9) Train PFAS Exceedance Model", class = "btn-success"),
                actionButton("run_pfas_prediction", "10) Run PFAS Prediction", class = "btn-success"),
                actionButton("btn_validate_reference_dataset", "11) Load reference dataset", class = "btn-info"),
                actionButton("btn_qc_validation_check", "12) QC validation check", class = "btn-info"),
                actionButton("btn_applicability_domain_check", "13) Applicability domain check", class = "btn-info"),
                actionButton("btn_external_pt_validation", "14) External validation (PT)", class = "btn-info"),
                actionButton("btn_generate_iso_compliance_report", "15) Generate ISO compliance report", class = "btn-warning"),
                actionButton("btn_generate_ml_validation_report", "16) Generate ML validation report (HTML)", class = "btn-warning"),
                downloadButton("dl_ml_validation_report", "Download ML validation report (HTML)", class = "btn-default"),
                actionButton("btn_pfas_run_all", "Run all steps", class = "btn-warning")
              )
            ),
            br(),
            fluidRow(
              column(
                6,
                fileInput(
                  "qc_dataset_file",
                  "QC dataset input (lab QC results)",
                  accept = c(".csv", ".tsv", ".txt", ".xlsx", ".xls", ".json")
                )
              ),
              column(
                6,
                fileInput(
                  "pt_dataset_file",
                  "PT dataset input (proficiency testing)",
                  accept = c(".csv", ".tsv", ".txt", ".xlsx", ".xls", ".json")
                )
              )
            ),
            br(),
            verbatimTextOutput("qc_pt_upload_status", placeholder = TRUE),
            br(),
            verbatimTextOutput("pfas_pipeline_log", placeholder = TRUE),
            hr(),
            tags$strong("Schema & folder readiness (not lab validation)"),
            tags$div(
              class = "alert",
              style = "background:#fff8e1;border:1px solid #ffcc80;color:#4e342e;padding:10px 14px;border-radius:4px;margin:10px 0 12px 0;",
              tags$p(
                style = "margin:0 0 8px 0;",
                tags$strong("What a check means: "),
                "file exists and a non-template dataset matches the expected column header pattern (and you are not looking at data quality, provenance, traceability, or ISO/IEC 17025 laboratory validation)."
              ),
              tags$p(
                style = "margin:0;",
                tags$strong("What it does not mean: "),
                "certified reference materials, real QC/PT performance, method fitness-for-purpose, regulator-ready evidence, or “ISO compliant” analytics."
              ),
              tags$p(
                style = "margin:8px 0 0 0;font-style:italic;",
                "Public framing: the platform supports ISO-",
                tags$em("aligned"), " structures and workflow hooks; it is ",
                tags$strong("not"), " a replacement for accredited laboratory validation."
              )
            ),
            helpText(
              "Preflight template CSVs are ignored for these rows. Screening-only / desk workflows may leave QC, PT, or reference rows unchecked unless you add real exports."
            ),
            DTOutput("tbl_pipeline_component_status")
          )
        ),
        fluidRow(
          box(
            width = 12,
            title = "External ML Data Upload (Upload -> Preview -> Map -> Validate -> Normalize -> Save -> Train)",
            status = "primary",
            solidHeader = TRUE,
            fileInput(
              # Server must use input$external_ml_file (same id everywhere; not external_upload).
              "external_ml_file",
              "Upload data file",
              accept = c(".csv", ".tsv", ".txt", ".xlsx", ".xls", ".json", ".parquet", ".rds", ".xpt")
            ),
            helpText(
              tags$strong("UCMR5 / EPA text: "),
              "This panel expects a ",
              tags$em("single, uniform delimited table"),
              " (comma, tab, pipe, or semicolon). For PFAS drinking-water occurrence rows, prefer method result files such as ",
              code("UCMR5_533.txt"), ", ", code("UCMR5_537_1.txt"), ", or ", code("UCMR5_200_7.txt"),
              " from the EPA zip—not supplemental/reference extracts (e.g. ",
              code("UCMR5_AddtlDataElem.txt"), ", ", code("UCMR5_ZIPCodes.txt"), "), which are not ML measurement tables. ",
              "Some aggregated EPA ", code(".txt"), " exports are ragged or wide; if upload fails, inspect with ",
              code("readLines(..., n = 20)"), " and pre-convert to CSV (e.g. ", code("read.delim"), " + ", code("write.csv"), "). ",
              "Smoke test: ", code("data/test_upload/test_upload.csv"), ". ",
              "If R ", code("read.delim"), " errors on ", code("µg/L"), ", use ", code("fileEncoding = \"latin1\""),
              " then ", code("write.csv(..., fileEncoding = \"UTF-8\")"), " (matches this app’s read order: Latin-1 before UTF-8 after BOM). ",
              "Delimited uploads are read with all columns as text (no ", code("type.convert"), ") so messy EPA rows still preview. ",
              "Huge CSVs (>~200MB) need enough RAM for a single ", code("read.table"), " pass; use a 1–5k-row sample for Snappy UI preview."
            ),
            helpText(
              tags$strong("Suggested inputs by role: "),
              code("PFASSTRUCT.csv"), " (CompTox ", tags$em("PFASSTRUCT"), " export) for registry / QSAR-style chemical tables; ",
              code("UCMR5_533_sample.csv"), " (or equivalent small CSV) for environmental-occurrence upload tests; ",
              "NHANES PFAS lab + linked demographics when ", tags$strong("Dataset type"), " is ",
              tags$em("human biomonitoring"), "."
            ),
            selectInput(
              "external_dataset_type",
              "Dataset type",
              choices = c(
                "human biomonitoring",
                "environmental occurrence",
                "facility enrichment",
                "method validation",
                "unknown/custom"
              ),
              selected = "environmental occurrence"
            ),
            verbatimTextOutput("external_file_meta", placeholder = TRUE),
            DTOutput("tbl_external_preview"),
            hr(),
            uiOutput("external_map_ui"),
            br(),
            actionButton("btn_external_validate", "Validate"),
            actionButton("btn_external_normalize", "Normalize"),
            actionButton("btn_external_save", "Save"),
            actionButton("btn_external_train", "Train"),
            br(), br(),
            verbatimTextOutput("external_quality_status", placeholder = TRUE),
            tags$strong("Strict schema validation (ISO ingest gate)"),
            verbatimTextOutput("external_strict_schema_status", placeholder = TRUE),
            verbatimTextOutput("external_save_status", placeholder = TRUE)
          )
        ),
        fluidRow(
          box(
            width = 12,
            title = "Label integrity dashboard",
            status = "warning",
            solidHeader = TRUE,
            p(
              tags$strong("Purpose: "), "Judge whether ",
              code("PFAS_Risk_Flag"), " labels are trustworthy before trusting model metrics."
            ),
            p(
              "Primary source: ",
              code("results/label_derivation_audit.json"),
              ". Row-drop total is aligned with ",
              code("dataset_builder_stages"),
              " in ",
              code("results/python_training_row_reconciliation.json"),
              "."
            ),
            uiOutput("pfas_label_integrity_banner"),
            verbatimTextOutput("pfas_label_integrity_summary", placeholder = TRUE),
            h4(style = "margin-top:16px;", "Top analytes with numeric result but no joined limit"),
            DTOutput("tbl_pfas_label_integrity_missing")
          )
        ),
        fluidRow(
          box(
            width = 12,
            title = "PFAS Exceedance ML Results (scripts outputs)",
            status = "primary",
            solidHeader = TRUE,
            p("Reads artifacts from ", code("results/"), " generated by ", code("python scripts/train_pfas_model.py"), " (PFAS exceedance pipeline)."),
            p(
              tags$em(
                "Screening-level decision support only. Do not replace ISO/IEC 17025 laboratory analytical reporting, analyst review, or validated method release."
              )
            ),
            verbatimTextOutput("pfas_metrics_status", placeholder = TRUE),
            hr(),
            p("Multi-source training target tracker (100,000,000 rows):"),
            verbatimTextOutput("pfas_target_status", placeholder = TRUE)
          )
        ),
        fluidRow(
          box(
            width = 12,
            title = "Training Freshness Status",
            status = "info",
            solidHeader = TRUE,
            verbatimTextOutput("pfas_last_training_status", placeholder = TRUE)
          )
        ),
        fluidRow(
          box(
            width = 12,
            title = "Task Rows Currently Available (pre-train check)",
            status = "primary",
            solidHeader = TRUE,
            DTOutput("tbl_task_row_availability")
          )
        ),
        fluidRow(
          box(width = 4, title = "Human Health Task", status = "success", solidHeader = TRUE, verbatimTextOutput("pfas_task_human_status", placeholder = TRUE)),
          box(width = 4, title = "Environmental Task", status = "info", solidHeader = TRUE, verbatimTextOutput("pfas_task_environment_status", placeholder = TRUE)),
          box(width = 4, title = "Facility Enrichment Task", status = "warning", solidHeader = TRUE, verbatimTextOutput("pfas_task_facility_status", placeholder = TRUE))
        ),
        fluidRow(
          box(
            width = 12,
            title = "Task Comparison (AUC / Accuracy / Train / Test)",
            status = "primary",
            solidHeader = TRUE,
            DTOutput("tbl_pfas_task_comparison")
          )
        ),
        fluidRow(
          box(width = 6, title = "Feature Importance", status = "info", solidHeader = TRUE, DTOutput("tbl_pfas_feature_importance")),
          box(width = 6, title = "Test Predictions", status = "warning", solidHeader = TRUE, DTOutput("tbl_pfas_test_predictions"))
        )
      ),
      tabItem(
        tabName = "glp",
        fluidRow(
          box(
            width = 12,
            title = "PFAS Enterprise 5.0 — ISO 17025 / on-prem GLP mode",
            status = "primary",
            solidHeader = TRUE,
            p(
              "The public demo at ", tags$a(href = "https://ishola-github.shinyapps.io/pfas-epa-method/", "shinyapps.io"),
              " is for prototyping only. For regulated studies, deploy ",
              strong("on qualified infrastructure"), " (access control, backups, NTP, monitored storage) and execute IQ/OQ/PQ per your QMS."
            ),
            p(
              "Artifacts: ",
              code("validation/IQ/Installation_Qualification_Template.md"), ", ",
              code("validation/test_cases/EPA_Method_1633_Test_Cases.csv"), ", ",
              code("validation/test_cases/EPA_Method_1633_Validation_Protocol.md"), "."
            ),
            checkboxInput("iso17025_strict_ui", "ISO 17025 mode: emphasize required QC fields in forms", value = TRUE)
          )
        ),
        fluidRow(
          box(
            width = 4, title = "Operator identity (audit)", status = "warning", solidHeader = TRUE,
            p("Sign in with ", strong("shinymanager"), ". Default accounts: ", code("admin"), " / ", code("admin123"), ", ", code("analyst"), " / ", code("analyst123"), "."),
            checkboxInput("use_login_as_operator", "Use authenticated user for audit, QC, CAPA, and exports (recommended)", value = TRUE),
            textInput("glp_operator_id", "Override operator ID (break-glass / testing only)", value = "", placeholder = "leave blank if using login"),
            helpText("In production, keep the checkbox on and manage users via the ", code("app_login_users"), " table or shinymanager admin."),
            verbatimTextOutput("auth_user_display", placeholder = TRUE)
          ),
          box(
            width = 8, title = "Audit trail integrity (SHA-256 chain)", status = "info", solidHeader = TRUE,
            verbatimTextOutput("glp_chain_status", placeholder = TRUE),
            actionButton("glp_verify_chain_btn", "Re-verify hash chain", class = "btn-info"),
            helpText("Append-only hash chain is stored in table ", code("glp_audit_trail"), ".")
          )
        ),
        fluidRow(
          box(
            width = 12, title = "Quality system modules", status = "primary", solidHeader = TRUE,
            tabsetPanel(
              id = "iso_tabset",
              tabPanel(
                title = "IQ & validation pack",
                icon = icon("file-alt"),
                fluidRow(
                  box(
                    width = 12, status = "info", solidHeader = TRUE,
                    title = "Installation Qualification (IQ)",
                    p("Complete the IQ checklist in the template, then archive signed PDFs per your document control procedure."),
                    downloadButton("dl_iq_template_md", "Download IQ template (.md)"),
                    downloadButton("dl_epa1633_protocol_md", "Download EPA 1633 validation protocol (.md)"),
                    downloadButton("dl_epa1633_tests_csv", "Download EPA 1633 test case list (.csv)")
                  )
                )
              ),
              tabPanel(
                title = "Audit trails",
                icon = icon("history"),
                fluidRow(
                  box(width = 12, title = "GLP hash-chained audit", DTOutput("tbl_glp_audit")),
                  box(width = 12, title = "Legacy audit_log", DTOutput("tbl_legacy_audit")),
                  box(
                    width = 12, title = "Partner intake admin view (operational review)",
                    helpText("Reads recent partner_intake_submit records from a local SQLite mirror table or CSV mirror file."),
                    fluidRow(
                      column(3, numericInput("partner_audit_limit", "Rows", value = 50, min = 10, max = 500, step = 10)),
                      column(3, br(), actionButton("btn_partner_audit_refresh", "Refresh partner intake", class = "btn-default")),
                      column(6, br(), verbatimTextOutput("partner_audit_status", placeholder = TRUE))
                    ),
                    DTOutput("tbl_partner_intake_admin")
                  ),
                  box(
                    width = 12, title = "Exports & WORM archive",
                    downloadButton("dl_glp_audit_csv", "Download GLP audit CSV (controlled copy)"),
                    hr(),
                    verbatimTextOutput("worm_dir_status", placeholder = TRUE),
                    actionButton("btn_worm_archive", "Write timestamped snapshot to WORM directory (PFAS_GLP_WORM_DIR)", class = "btn-warning"),
                    helpText("Creates CSV + .sha256 + .meta.json. Point ", code("PFAS_GLP_WORM_DIR"), " at secured, monitored storage; enforce immutability with IT controls.")
                  )
                )
              ),
              tabPanel(
                title = "EPA 1633 tests",
                icon = icon("flask"),
                fluidRow(
                  box(width = 12, title = "Test case library (database)", DTOutput("tbl_epa1633_cases")),
                  box(
                    width = 6, title = "Record test run",
                    selectInput("v_test_case_id", "Test case ID", choices = NULL),
                    textInput("v_protocol_ref", "Protocol / SOP reference", value = "EPA 1633 / LAB-SOP-1633"),
                    selectInput("v_pass_fail", "Result", choices = c("Pass", "Fail", "N/A")),
                    textAreaInput("v_evidence_notes", "Evidence / deviation notes"),
                    actionButton("btn_save_validation_result", "Save validation result", class = "btn-primary")
                  ),
                  box(width = 6, title = "Recorded runs", DTOutput("tbl_validation_results"))
                )
              ),
              tabPanel(
                title = "CAPA",
                icon = icon("wrench"),
                fluidRow(
                  box(
                    width = 5, title = "Open CAPA",
                    textInput("capa_title", "Title"),
                    textAreaInput("capa_description", "Description"),
                    selectInput("capa_priority", "Priority", choices = c("Low", "Medium", "High", "Critical")),
                    textInput("capa_linked_type", "Linked entity type (optional)", placeholder = "measurement / batch / instrument"),
                    textInput("capa_linked_id", "Linked entity ID (optional)"),
                    actionButton("btn_save_capa", "Open CAPA", class = "btn-warning")
                  ),
                  box(width = 7, title = "CAPA register", DTOutput("tbl_capa"))
                )
              ),
              tabPanel(
                title = "Approvals & e-sign",
                icon = icon("pen-fancy"),
                fluidRow(
                  box(
                    width = 5, title = "Approval request",
                    textInput("apr_object_type", "Object type", value = "analytical_batch"),
                    textInput("apr_object_id", "Object ID"),
                    selectInput("apr_step", "Step", choices = c("QC review", "Technical review", "QA release")),
                    actionButton("btn_request_approval", "Submit for approval", class = "btn-primary")
                  ),
                  box(
                    width = 4, title = "Decide approval",
                    uiOutput("apr_select_ui"),
                    selectInput("apr_decision", "Decision", choices = c("approved", "rejected")),
                    textAreaInput("apr_rationale", "Rationale"),
                    actionButton("btn_decide_approval", "Record decision", class = "btn-success")
                  ),
                  box(
                    width = 3, title = "Electronic signature",
                    textInput("esig_record_type", "Record type"),
                    textInput("esig_record_id", "Record ID"),
                    textInput("esig_meaning", "Signature meaning", value = "I approve this record."),
                    actionButton("btn_esig", "Apply e-signature (intent + user ID)", class = "btn-danger")
                  ),
                  box(width = 12, title = "Approval queue", DTOutput("tbl_approvals")),
                  box(width = 12, title = "Signatures", DTOutput("tbl_esig"))
                )
              ),
              tabPanel(
                title = "QC batches",
                icon = icon("vials"),
                fluidRow(
                  box(
                    width = 4, title = "QC batch log",
                    textInput("qc_batch_id", "Batch / run ID"),
                    textInput("qc_matrix", "Matrix"),
                    dateInput("qc_run_date", "Run date", value = Sys.Date()),
                    checkboxInput("qc_blanks_ok", "Method blanks acceptable", value = TRUE),
                    checkboxInput("qc_checks_ok", "LCS/MS checks acceptable", value = TRUE),
                    checkboxInput("qc_cal_ok", "Calibration / ICV / CCV acceptable", value = TRUE),
                    selectInput("qc_overall", "Overall status", choices = c("Accept", "Hold", "Reject")),
                    textAreaInput("qc_notes", "Notes"),
                    actionButton("btn_save_qc", "Save QC batch", class = "btn-primary")
                  ),
                  box(width = 8, title = "QC history", DTOutput("tbl_qc_batch"))
                )
              ),
              tabPanel(
                title = "Training",
                icon = icon("graduation-cap"),
                fluidRow(
                  box(
                    width = 4, title = "Training record",
                    textInput("tr_user", "User ID"),
                    textInput("tr_topic", "Topic", value = "EPA Method 1633"),
                    dateInput("tr_completed", "Completed", value = Sys.Date()),
                    textInput("tr_trainer", "Trainer"),
                    dateInput("tr_expiry", "Expiry (re-train by)", value = Sys.Date() + 365),
                    textInput("tr_evidence", "Evidence reference (SOP quiz, certificate #)"),
                    actionButton("btn_save_training", "Save training", class = "btn-primary")
                  ),
                  box(width = 8, title = "Training log", DTOutput("tbl_training"))
                )
              ),
              tabPanel(
                title = "Calibration",
                icon = icon("tachometer-alt"),
                fluidRow(
                  box(
                    width = 4, title = "Calibration entry",
                    textInput("cal_instrument", "Instrument ID"),
                    textInput("cal_parameter", "Parameter (e.g. mass axis, flow)"),
                    numericInput("cal_nominal", "Nominal", value = NA),
                    numericInput("cal_measured", "As-found / as-left", value = NA),
                    numericInput("cal_tol_pct", "Tolerance %", value = 5),
                    selectInput("cal_pass", "Within tolerance", choices = c("Pass" = "pass", "Fail" = "fail"), selected = "pass"),
                    dateInput("cal_next", "Next due", value = Sys.Date() + 180),
                    textInput("cal_cert", "Certificate reference"),
                    actionButton("btn_save_cal", "Save calibration", class = "btn-primary")
                  ),
                  box(width = 8, title = "Calibration log", DTOutput("tbl_calibration"))
                )
              )
            )
          )
        )
      ),
      tabItem(
        tabName = "enterprise5",
        fluidRow(
          box(
            width = 12,
            title = "PFAS Enterprise 5.0 — Cloud screening API",
            status = "primary",
            solidHeader = TRUE,
            tags$p(
              "Screening decision-support only. ",
              tags$strong(
                "PFAS Enterprise 5.0 is a screening decision-support platform, not a certified laboratory replacement."
              )
            ),
            tags$p(
              "POST target: ",
              tags$code(PFAS_API_URL),
              ". Override with ",
              tags$code("PFAS_API_URL"),
              " (environment variable) before starting the app."
            )
          )
        ),
        fluidRow(
          box(
            width = 4,
            title = "Request",
            status = "info",
            solidHeader = TRUE,
            textInput("e5_sample_id", "Sample ID", "DEMO_001"),
            textInput("e5_dtxsid", "DTXSID", "DTXSID8030271"),
            selectInput("e5_method_id", "Method", c("EPA_533", "EPA_1633")),
            selectInput("e5_matrix", "Matrix", c("water", "sludge", "serum")),
            actionButton("e5_run", "Run screening", class = "btn-primary")
          ),
          box(
            width = 8,
            title = "Response",
            status = "success",
            solidHeader = TRUE,
            tabsetPanel(
              tabPanel(
                title = "Prediction",
                verbatimTextOutput("e5_result", placeholder = TRUE)
              ),
              tabPanel(
                title = "Sustainability",
                verbatimTextOutput("e5_sustainability", placeholder = TRUE)
              ),
              tabPanel(
                title = "Raw JSON",
                verbatimTextOutput("e5_raw", placeholder = TRUE)
              )
            )
          )
        )
      )
    )
  )
)

ui <- shinymanager::secure_app(
  ui_dashboard,
  enable_admin = TRUE,
  tags_top = NULL,
  language = "en"
)

# -------------------------------------------------------------------
# Server
# -------------------------------------------------------------------

server <- function(input, output, session) {
  ensure_valid_db_connection()
  auth <- shinymanager::secure_server(
    check_credentials = shinymanager::check_credentials(login_credentials_df),
    timeout = 60 * 12
  )

  op_id <- function() {
    use_login <- tryCatch(isolate(input$use_login_as_operator), error = function(e) TRUE)
    if (!isFALSE(use_login)) {
      uu <- tryCatch(isolate(auth$user), error = function(e) NULL)
      fn <- tryCatch(isolate(auth$full_name), error = function(e) NULL)
      if (!is.null(fn) && nzchar(as.character(fn))) return(as.character(fn))
      if (!is.null(uu) && nzchar(as.character(uu))) return(as.character(uu))
    }
    tryCatch(isolate(input$glp_operator_id), error = function(e) NULL) %||% "unknown"
  }

  observe({
    req(auth$user)
    updateTextInput(session, "glp_operator_id", value = as.character(auth$user))
  })

  output$auth_user_display <- renderPrint({
    req(auth$user)
    cat("Session user:", auth$user, "\n")
    if (!is.null(auth$full_name)) cat("Display name:", auth$full_name, "\n")
    if (!is.null(auth$admin)) cat("Administrator:", auth$admin, "\n")
  })

  output$worm_dir_status <- renderPrint({
    d <- Sys.getenv("PFAS_GLP_WORM_DIR", "")
    if (!nzchar(d)) {
      cat("PFAS_GLP_WORM_DIR is not set. Set it to a secured archive folder before using WORM export.\n")
    } else {
      cat("WORM archive directory:\n ", normalizePath(d, winslash = "/", mustWork = FALSE), "\n")
    }
  })

  observeEvent(input$btn_worm_archive, {
    req(auth$user)
    arc <- Sys.getenv("PFAS_GLP_WORM_DIR", "")
    if (!nzchar(arc)) {
      showNotification("Set PFAS_GLP_WORM_DIR to a dedicated archive path.", type = "error")
      return(invisible(NULL))
    }
    if (!exists("glp_worm_export_audit", mode = "function")) {
      showNotification("glp_audit_archive.R not loaded.", type = "error")
      return(invisible(NULL))
    }
    tryCatch(
      {
        res <- glp_worm_export_audit(con, arc, op_id())
        write_audit(
          "glp_audit_trail",
          basename(res$csv),
          "worm_archive",
          op_id(),
          "WORM audit snapshot",
          list(sha256 = res$digest, rows = res$rows, path = res$csv)
        )
        showNotification(paste("WORM export:", res$csv), type = "message")
      },
      error = function(e) {
        showNotification(conditionMessage(e), type = "error")
      }
    )
  })

  # Do not dbDisconnect(con) in session onStop: that runs on every browser refresh/tab
  # close and leaves the global SQLite handle invalid for the next Shiny session.

  # Dual audit: legacy audit_log + GLP hash-chained glp_audit_trail (session-aware)
  write_audit <- function(entity_type, entity_id, action_type, changed_by, change_notes = "", details = NULL, message = NULL) {
    ensure_valid_db_connection()
    notes_out <- if (!is.null(message)) as.character(message) else change_notes
    audit_row <- tibble::tibble(
      audit_id = make_id("AUD"),
      entity_type = entity_type,
      entity_id = as.character(entity_id),
      action_type = action_type,
      changed_by = changed_by %||% "unknown",
      changed_at = as.character(Sys.time()),
      change_notes = notes_out
    )
    tryCatch(
      DBI::dbWriteTable(con, "audit_log", audit_row, append = TRUE),
      error = function(e) {
        warning("audit_log write failed: ", conditionMessage(e))
        invisible(NULL)
      }
    )
    if (exists("glp_audit_append", mode = "function")) {
      try(
        glp_audit_append(
          con,
          session,
          APP_VERSION,
          entity_type,
          as.character(entity_id),
          action_type,
          changed_by %||% "unknown",
          notes_out,
          details %||% list(),
          regulatory_method = "EPA Method 1633"
        ),
        silent = TRUE
      )
    }
  }

  observe({
    req(auth$user)
    if (isTRUE(session$userData$glp_session_open_logged)) {
      return(invisible(NULL))
    }
    session$userData$glp_session_open_logged <- TRUE
    tok <- tryCatch(session$token, error = function(e) NULL)
    sid <- if (!is.null(tok)) {
      substr(digest::digest(tok, algo = "sha256", serialize = FALSE), 1, 16)
    } else {
      substr(digest::digest(as.character(Sys.time()), algo = "sha256", serialize = FALSE), 1, 16)
    }
    oid <- op_id()
    try(
      write_audit("session", sid, "session_open", oid, "Shiny session established", list(version = APP_VERSION)),
      silent = TRUE
    )
  })

  session$onSessionEnded(function() {
    try(
      {
        ensure_valid_db_connection()
        audit_row <- tibble::tibble(
          audit_id = make_id("AUD"),
          entity_type = "session",
          entity_id = "end",
          action_type = "session_close",
          changed_by = "system",
          changed_at = as.character(Sys.time()),
          change_notes = "Shiny session closed"
        )
        DBI::dbWriteTable(con, "audit_log", audit_row, append = TRUE)
        if (exists("glp_audit_append", mode = "function")) {
          glp_audit_append(
            con,
            NULL,
            APP_VERSION,
            "session",
            "end",
            "session_close",
            "system",
            "Shiny session closed",
            list(),
            regulatory_method = "EPA Method 1633"
          )
        }
      },
      silent = TRUE
    )
  })
  
  output$vb_compounds <- renderValueBox({
    valueBox(nrow(compounds), "Compounds", icon = icon("flask"), color = "aqua")
  })
  
  output$vb_datasets <- renderValueBox({
    valueBox(nrow(dataset_registry), "Endpoint Datasets", icon = icon("database"), color = "yellow")
  })
  
  output$vb_models <- renderValueBox({
    valueBox(nrow(model_registry), "Models", icon = icon("cubes"), color = "purple")
  })
  
  output$vb_inside_ad <- renderValueBox({
    valueBox(sum(compound_ad_summary$ad_status == "Inside"), "Inside AD", icon = icon("check"), color = "green")
  })
  
  output$vb_outside_ad <- renderValueBox({
    valueBox(sum(compound_ad_summary$ad_status == "Outside"), "Outside AD", icon = icon("exclamation-triangle"), color = "red")
  })
  
  output$vb_high_concern <- renderValueBox({
    valueBox(sum(weight_of_evidence$predicted_class == "Positive"), "Positive Flags", icon = icon("radiation"), color = "maroon")
  })
  
  render_dt <- function(df, pageLength = 8) {
    DT::datatable(df, options = list(pageLength = pageLength, scrollX = TRUE), rownames = FALSE)
  }

  read_results_csv <- function(file_name) {
    p <- file.path(PROJECT_DIR, "results", file_name)
    if (!file.exists(p)) return(NULL)
    tryCatch(
      read.csv(p, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e) NULL
    )
  }

  read_results_json <- function(file_name) {
    p <- file.path(PROJECT_DIR, "results", file_name)
    if (!file.exists(p)) return(NULL)
    tryCatch(
      {
        txt <- paste(readLines(p, warn = FALSE), collapse = "\n")
        # Be tolerant to non-standard NaN/Infinity tokens from legacy runs.
        txt <- gsub("\\bNaN\\b", "null", txt)
        txt <- gsub("\\bInfinity\\b", "null", txt)
        txt <- gsub("\\b-Infinity\\b", "null", txt)
        jsonlite::fromJSON(txt)
      },
      error = function(e) NULL
    )
  }

  read_training_json <- function(file_name) {
    p <- file.path(PROJECT_DIR, "data", "training", file_name)
    if (!file.exists(p)) return(NULL)
    tryCatch(
      jsonlite::fromJSON(p),
      error = function(e) NULL
    )
  }

  read_training_csv <- function(file_name) {
    p <- file.path(PROJECT_DIR, "data", "training", file_name)
    if (!file.exists(p)) return(NULL)
    tryCatch(
      read.csv(p, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e) NULL
    )
  }

  read_label_derivation_audit_payload <- function() {
    read_results_json("label_derivation_audit.json")
  }

  read_label_integrity_report_payload <- function() {
    read_results_json("label_integrity_report.json")
  }

  reconciliation_dataset_builder_stages <- function() {
    rec <- read_results_json("python_training_row_reconciliation.json")
    if (is.null(rec) || is.null(rec$dataset_builder_stages)) return(NULL)
    rec$dataset_builder_stages
  }

  cat_iso_holdout_metrics <- function(im, n_test_align = NA_integer_) {
    if (is.null(im) || !is.list(im)) return(invisible(NULL))
    if (!is.null(im$error)) {
      cat("\niso_holdout_metrics:", im$error, "\n")
      return(invisible(NULL))
    }
    # JSON fields may be null or length-0 vectors; if (is.finite(x)) must not see logical(0).
    iso_scalar_num <- function(x, default = NA_real_) {
      if (is.null(x)) return(default)
      v <- suppressWarnings(as.numeric(unlist(x, use.names = FALSE)))
      if (length(v) < 1L) return(default)
      v[[1L]]
    }
    iso_scalar_int <- function(x, default = NA_integer_) {
      n <- iso_scalar_num(x, NA_real_)
      if (!is.finite(n)) return(default)
      suppressWarnings(as.integer(round(n)))
    }
    fmt_int_or_na <- function(x) {
      xi <- iso_scalar_int(x, NA_integer_)
      if (is.na(xi)) "NA" else as.character(xi)
    }
    thr <- iso_scalar_num(im$probability_threshold, NA_real_)
    if (!is.finite(thr)) thr <- 0.25
    cat("\nHold-out decision metrics (positive class vs negative), P >= ", thr, "\n", sep = "")
    cat(
      " Confusion counts  TN FP | FN TP:",
      fmt_int_or_na(im$tn), fmt_int_or_na(im$fp), "|",
      fmt_int_or_na(im$fn), fmt_int_or_na(im$tp), "\n",
      sep = " "
    )
    tpv <- iso_scalar_int(im$tp, NA_integer_)
    fpv <- iso_scalar_int(im$fp, NA_integer_)
    tnv <- iso_scalar_int(im$tn, NA_integer_)
    fnv <- iso_scalar_int(im$fn, NA_integer_)
    na_pos <- iso_scalar_int(im$n_actual_positive, NA_integer_)
    na_neg <- iso_scalar_int(im$n_actual_negative, NA_integer_)
    if (!is.na(na_pos) || !is.na(na_neg)) {
      cat(
        " Actual class dist.  neg / pos:",
        if (is.na(na_neg)) "NA" else na_neg, "/",
        if (is.na(na_pos)) "NA" else na_pos, "\n",
        sep = ""
      )
    }
    rp <- iso_scalar_num(im$recall_positive, NA_real_)
    if (is.finite(rp)) {
      cat(" Recall (sensitivity, class 1):", round(rp, 4), "\n")
    } else {
      cat(" Recall (sensitivity, class 1): N/A (no positive labels in hold-out)\n")
    }
    pp <- iso_scalar_num(im$precision_positive, NA_real_)
    if (is.finite(pp)) {
      cat(" Precision (PPV, class 1)    :", round(pp, 4), "\n")
    } else {
      cat(" Precision (PPV, class 1)    : N/A (no positive predictions)\n")
    }
    sp <- iso_scalar_num(im$specificity, NA_real_)
    if (is.finite(sp)) cat(" Specificity (class 0)       :", round(sp, 4), "\n")
    npv <- iso_scalar_num(im$npv, NA_real_)
    if (is.finite(npv)) cat(" NPV (among pred. negative)   :", round(npv, 4), "\n")
    pred_pos <- iso_scalar_int(im$predicted_positive_count, NA_integer_)
    if (is.na(pred_pos) && !is.na(tpv) && !is.na(fpv)) pred_pos <- tpv + fpv
    cs <- iso_scalar_int(im$cm_sum, NA_integer_)
    if ((is.na(cs) || cs < 1L) && all(is.finite(c(tpv, fpv, tnv, fnv)))) {
      cs <- tpv + fpv + tnv + fnv
    }
    pred_frac_json <- iso_scalar_num(im$predicted_positive_fraction, NA_real_)
    f10k_json <- iso_scalar_num(im$flags_per_10k_holdout, NA_real_)
    fpr_json <- iso_scalar_num(im$false_positive_rate_negative, NA_real_)
    if (!is.na(pred_pos) && !is.na(cs) && cs > 0L) {
      frac_use <- pred_pos / cs
      if (is.finite(pred_frac_json)) frac_use <- pred_frac_json
      f10k_use <- if (is.finite(f10k_json)) f10k_json else pred_pos / cs * 10000
      cat(
        " Predicted positives (P>=tau):", pred_pos, "of", cs,
        sprintf(" (~%.2f%% flagged;", 100 * frac_use),
        sprintf(" ~%.1f per 10k hold-out scored)\n", f10k_use)
      )
    }
    fpr_use <- NA_real_
    if (is.finite(fpr_json)) {
      fpr_use <- fpr_json
    } else if (!is.na(na_neg) && na_neg > 0L && !is.na(fpv)) {
      fpr_use <- fpv / na_neg
    }
    if (is.finite(fpr_use)) {
      cat(" FP rate among true negatives (review burden on negatives):", round(fpr_use, 4), "\n")
    }
    nt <- iso_scalar_int(n_test_align, NA_integer_)
    if (!is.na(cs) && !is.na(nt)) {
      ok <- isTRUE(cs == nt)
      cat(
        " Confusion_matrix cell sum:", cs, "| n_test:", nt,
        if (ok) " (aligned)\n" else " (MISMATCH)\n",
        sep = ""
      )
    }
    invisible(NULL)
  }

  print_holdout_probability_debug <- function(hp) {
    if (is.null(hp) || !is.list(hp)) return(invisible(NULL))
    cat("\n--- Hold-out probability debug (results/holdout_probability_debug.json) ---\n")
    pe <- hp[["probability_exceedance_holdout"]]
    if (is.list(pe)) {
      cat(
        " P exceedance (hold-out): min=", pe$min %||% NA, " max=", pe$max %||% NA,
        " median=", pe$median %||% NA, " peak-to-trough=", pe$peak_to_trough %||% NA, "\n",
        sep = ""
      )
    }
    fc <- hp[["fraction_scores_ge_cutoff"]]
    if (is.list(fc)) {
      cat(
        " Fraction scores ≥ cutoff: 0.15=", fc[["0.15"]] %||% NA,
        " 0.25=", fc[["0.25"]] %||% NA, " 0.50=", fc[["0.50"]] %||% NA, "\n",
        sep = ""
      )
    }
    hints <- hp[["interpretation_hints"]]
    if (is.list(hints)) {
      if (isTRUE(hints[["all_hard_predictions_negative"]])) {
        cat(" Collapse: TP=0 with positives at current τ — model predicts all negative.\n")
      }
      if (isTRUE(hints[["max_score_below_threshold"]])) {
        cat(" Collapse: max(P) < τ — lower Hold-out threshold in Reports or --holdout-threshold.\n")
      }
      if (isTRUE(hints[["auc_near_random_or_worse"]])) {
        cat(" Signal: AUC < 0.56 — discrimination weak; fixing τ alone may not restore screening value.\n")
      }
      acts <- hints[["suggested_actions"]]
      if (length(acts) > 0L) {
        cat(" Next steps:\n")
        for (a in acts) cat("  - ", as.character(a), "\n", sep = "")
      }
    }
    invisible(NULL)
  }

  pfas_pipeline_log <- reactiveVal("Pipeline idle. Click a step or 'Run all steps'.")
  pfas_results_nonce <- reactiveVal(0L)
  source_bootstrap_note <- reactiveVal("Source folder bootstrap not run yet.")
  qc_pt_upload_status_note <- reactiveVal("QC/PT uploads not run yet.")
  iso_preflight_note <- reactiveVal("ISO preflight not run yet.")
  external_upload_raw <- reactiveVal(NULL)
  external_upload_name <- reactiveVal("")
  external_upload_report <- reactiveVal(NULL)
  external_upload_normalized <- reactiveVal(NULL)
  external_upload_save_note <- reactiveVal("No normalized upload saved yet.")
  external_upload_read_error <- reactiveVal("")
  external_upload_strict_result <- reactiveVal(NULL)
  pipeline_last_error <- reactiveVal("")

  allowed_upload_ext <- c("csv", "tsv", "txt", "xlsx", "xls", "json", "parquet", "rds", "xpt")

  normalize_shiny_file_upload <- function(f) {
    if (is.null(f)) return(NULL)
    if (inherits(f, "data.frame")) {
      if (nrow(f) < 1L) return(NULL)
      f <- f[1L, , drop = FALSE]
    }
    nm <- suppressWarnings(trimws(as.character(f$name %||% "")[1]))
    if (length(nm) < 1L || is.na(nm)) nm <- ""
    dp <- suppressWarnings(trimws(as.character(f$datapath %||% "")[1]))
    if (length(dp) < 1L || is.na(dp)) dp <- ""
    sz_raw <- suppressWarnings((f$size %||% NA_integer_)[1])
    sz <- suppressWarnings(as.integer(sz_raw))
    if (length(sz) < 1L || is.na(sz)) sz <- NA_integer_
    list(name = nm, datapath = dp, size = sz)
  }
  upload_schema_cols <- c(
    "source", "source_dataset", "sample_id", "matrix", "sample_date",
    "analyte", "cas", "result_value", "result_unit", "qualifier",
    "mdl", "rl", "detect_flag", "state", "county", "latitude", "longitude",
    "region", "facility_water_type", "sample_point_type", "method_id",
    "collection_year", "collection_month", "pws_size", "facility_id", "sample_point_id",
    "health_endpoint", "health_value", "dataset_type", "upload_id", "uploaded_at"
  )

  read_delimited_robust <- function(path, sep, header = TRUE, nrows = NA_integer_) {
    if (!nzchar(path %||% "") || !file.exists(path)) return(NULL)
    # latin1/CP1252 before UTF-8: EPA/Windows exports often use byte 0xB5 for µ in Units (e.g. µg/L);
    # read.table as UTF-8 can throw "invalid multibyte string" on those files.
    enc_candidates <- c("UTF-8-BOM", "latin1", "CP1252", "UTF-8", "UTF-16LE", "UTF-16BE")
    # Do not pass read.table(..., nrows = NA_integer_) — scan() errors internally ("missing TRUE/FALSE").
    nr_limit <- NA_integer_
    if (is.finite(nrows) && !is.na(nrows) && nrows > 0L) nr_limit <- as.integer(nrows)
    quote_modes <- list(
      default = "\"",
      none = ""
    )
    for (enc in enc_candidates) {
      for (qm in quote_modes) {
        qch <- qm
        args <- list(
          file = path,
          sep = sep,
          header = header,
          stringsAsFactors = FALSE,
          colClasses = "character",
          check.names = FALSE,
          quote = qch,
          comment.char = "",
          fill = TRUE,
          blank.lines.skip = TRUE,
          allowEscapes = FALSE,
          skipNul = TRUE,
          fileEncoding = enc,
          dec = ".",
          strip.white = TRUE
        )
        if (!is.na(nr_limit)) args$nrows <- nr_limit
        df <- tryCatch(
          suppressWarnings(do.call(utils::read.table, args)),
          error = function(e) NULL
        )
        if (!is.null(df) && is.data.frame(df) && ncol(df) >= 1L) return(df)
      }
    }
    NULL
  }

  read_first_line_robust <- function(path) {
    if (!nzchar(path %||% "") || !file.exists(path)) return("")
    read_one <- function(enc_raw) {
      tryCatch(
        suppressWarnings(readLines(path, n = 1L, warn = FALSE, encoding = enc_raw)),
        error = function(e) character(0)
      )
    }
    for (enc in c("latin1", "CP1252", "UTF-8")) {
      ln <- read_one(enc)
      if (length(ln) > 0 && nzchar(ln[[1]])) return(ln[[1]])
    }
    for (enc in c("UTF-16LE", "UTF-16BE")) {
      ln <- read_one(enc)
      if (length(ln) > 0 && nzchar(ln[[1]])) return(ln[[1]])
    }
    ln <- tryCatch(suppressWarnings(readLines(path, n = 1L, warn = FALSE)), error = function(e) "")
    if (length(ln) > 0) ln[[1]] else ""
  }

  # light=TRUE: skip per-cell iconv (huge uploads); UTF-8/latin1 CSV exports stay usable; colnames still normalized.
  sanitize_utf8_df <- function(df, light = FALSE) {
    strip_embedded_nul_chars <- function(v) {
      if (!is.character(v) || !length(v)) return(v)
      z <- intToUtf8(0L)
      hit <- !is.na(v) & nzchar(v) & grepl(z, v, fixed = TRUE)
      if (!any(hit, na.rm = TRUE)) return(v)
      out <- v
      out[hit] <- vapply(
        out[hit],
        function(s) paste(strsplit(s, z, fixed = TRUE)[[1]], collapse = ""),
        FUN.VALUE = "",
        USE.NAMES = FALSE
      )
      out
    }
    df <- as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)

    names(df) <- iconv(names(df), from = "", to = "UTF-8", sub = "")
    names(df) <- trimws(names(df))
    nn <- names(df)
    empty_nm <- is.na(nn) | !nzchar(nn)
    if (any(empty_nm)) nn[empty_nm] <- paste0("__unnamed_col_", which(empty_nm))
    nn <- make.unique(nn, sep = "__dup__")
    names(df) <- nn

    do_iconv <- !isTRUE(light)
    for (nm in names(df)) {
      col <- df[[nm]]
      if (is.character(col)) {
        if (do_iconv) {
          df[[nm]] <- iconv(col, from = "", to = "UTF-8", sub = "")
        }
        df[[nm]] <- strip_embedded_nul_chars(df[[nm]])
        df[[nm]] <- trimws(df[[nm]])
      } else if (is.factor(col)) {
        ch <- as.character(col)
        if (do_iconv) {
          ch <- iconv(ch, from = "", to = "UTF-8", sub = "")
        }
        ch <- strip_embedded_nul_chars(ch)
        df[[nm]] <- trimws(ch)
      }
    }

    df
  }

  stage_delimited_upload_file <- function(path, ext, peek_max_raw = 4L * 1024^2) {
    ext <- tolower(ext %||% "")
    sz <- suppressWarnings(as.integer(file.info(path)$size %||% 0))
    peek_n <- max(0L, min(sz, as.integer(peek_max_raw)))
    peek_has_nul <- FALSE
    if (peek_n > 0L) {
      buf <- tryCatch(readBin(path, what = "raw", n = peek_n), error = function(e) raw())
      peek_has_nul <- length(buf) > 0L && any(buf == as.raw(0L))
    }
    need_strip <- ext == "txt" && isTRUE(peek_has_nul)
    tmp <- tempfile(fileext = paste0(".", ext))
    # Caller unlinks tmp after read_upload_delimited_base (do not schedule on.exit here).
    if (need_strip && sz > 0L) {
      rawf <- tryCatch(readBin(path, what = "raw", n = sz), error = function(e) NULL)
      if (!is.null(rawf) && length(rawf) > 0L) {
        rawf <- rawf[rawf != as.raw(0L)]
        writeBin(rawf, tmp)
        return(tmp)
      }
      return("")
    }
    if (isTRUE(file.copy(path, tmp, overwrite = TRUE))) {
      return(tmp)
    }
    ""
  }

  read_upload_delimited_base <- function(path_clean, ext) {
    read_try_best <- function(order) {
      best <- NULL
      best_ncol <- -1L
      for (sep in order) {
        if (!nzchar(sep %||% "")) next
        df <- read_delimited_robust(path_clean, sep = sep)
        if (is.null(df) || !is.data.frame(df) || ncol(df) < 1L) next
        nc <- ncol(df)
        if (nc > best_ncol) {
          best <- df
          best_ncol <- as.integer(nc)
        }
        if (nc >= 2L) {
          return(df)
        }
      }
      best
    }

    sniff_order <- function() {
      first <- read_first_line_robust(path_clean)
      if (!nzchar(first)) {
        return(c(",", "\t", "|", ";"))
      }
      counts <- c(
        comma = lengths(regmatches(first, gregexpr(",", first, fixed = TRUE))),
        tab = lengths(regmatches(first, gregexpr("\t", first, fixed = TRUE))),
        semi = lengths(regmatches(first, gregexpr(";", first, fixed = TRUE))),
        pipe = lengths(regmatches(first, gregexpr("|", first, fixed = TRUE)))
      )
      mx <- suppressWarnings(max(counts, na.rm = TRUE))
      if (!is.finite(mx) || mx < 1L) {
        return(c(",", "\t", "|", ";"))
      }
      hits <- names(counts)[counts == mx]
      sep_map <- c(comma = ",", tab = "\t", semi = ";", pipe = "|")
      sniffed <- unname(sep_map[hits])
      unique(c(sniffed, ",", "\t", "|", ";"))
    }

    ext <- tolower(ext %||% "")
    all_seps <- c(",", "\t", "|", ";")
    if (ext == "csv") {
      return(read_try_best(unique(c(",", all_seps))))
    }
    if (ext == "tsv") {
      return(read_try_best(unique(c("\t", all_seps))))
    }
    if (identical(ext, "txt")) {
      return(read_try_best(sniff_order()))
    }
    read_try_best(all_seps)
  }

  safe_read_upload <- function(path, filename = NULL) {
    tryCatch(
      {
        cat("SAFE_READ_UPLOAD START\n")
        cat("PATH:", path %||% "", "\n")

        fn <- filename %||% basename(path %||% "")
        cat("FILE:", fn, "\n")

        ext <- tolower(tools::file_ext(fn))

        if (!nzchar(path %||% "") || !file.exists(path) || file.size(path) == 0L) {
          stop("Uploaded file is empty or missing.")
        }

        if (ext %in% c("csv", "txt", "tsv")) {
      # Do not readBin() the whole file: doubles RAM (fatal for multi-hundred-MB CSV). Copy to temp; skipNul in read.table.
      tmp <- stage_delimited_upload_file(path, ext)
      if (is.null(tmp) || !nzchar(tmp) || !file.exists(tmp)) {
        stop("Could not stage uploaded file for parsing (disk or permission).")
      }
      on.exit(unlink(tmp), add = TRUE)

      # CSV/TSV/TXT: utils::read.table only — readr/stringi paths removed (fixes 'zero-length pattern' crashes).
      df <- read_upload_delimited_base(tmp, ext)

      if (is.null(df) || !is.data.frame(df) || ncol(df) < 1L) {
        stop(
          paste0(
            "Could not parse delimited upload as a table. ",
            "Expected a delimited text table (comma/tab/pipe/semicolon), UTF-8 or UTF-16. ",
            "UCMR supplemental/metadata files that are not uniform delimited tables will not load here; use occurrence files (e.g. UCMR5_ZIPs) for measurements. ",
            "Very large files need enough free RAM for one full in-memory parse; prefer a sampled CSV for Upload preview.",
            ifelse(ext %in% c("csv"), " Try read.csv(nrows=5000) in R to confirm the file parses.", "")
          )
        )
      }

      ncell <- nrow(df) * ncol(df)
      lite <- is.finite(ncell) && ncell > 1e6L
      return(sanitize_utf8_df(as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE), light = lite))
    }

    if (ext %in% c("xlsx", "xls")) {
      if (!requireNamespace("readxl", quietly = TRUE)) {
        stop("Package 'readxl' is required. Run install.packages('readxl').")
      }

      df <- tryCatch(
        readxl::read_excel(path, sheet = 1L),
        error = function(e) {
          stop(paste0("Excel read failed: ", conditionMessage(e)))
        }
      )
      return(sanitize_utf8_df(as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)))
    }

    if (ext == "json") {
      x <- jsonlite::fromJSON(path, flatten = TRUE)
      df <- if (is.data.frame(x)) x else as.data.frame(x, stringsAsFactors = FALSE, check.names = FALSE)
      return(sanitize_utf8_df(df))
    }

    if (ext == "parquet") {
      if (!requireNamespace("arrow", quietly = TRUE)) {
        stop("Package 'arrow' is required. Run install.packages('arrow').")
      }

      df <- arrow::read_parquet(path)
      return(sanitize_utf8_df(as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)))
    }

    if (ext == "rds") {
      df <- readRDS(path)
      if (!is.data.frame(df)) stop("RDS file must contain a data.frame.")
      return(sanitize_utf8_df(as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)))
    }

    if (ext == "xpt") {
      df <- if (requireNamespace("haven", quietly = TRUE)) {
        haven::read_xpt(path)
      } else if (requireNamespace("foreign", quietly = TRUE)) {
        foreign::read.xport(path)
      } else {
        stop("Install 'haven' or 'foreign' to read .xpt files.")
      }
      return(sanitize_utf8_df(as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)))
    }

        stop(paste("Unsupported file type:", ext))
      },
      error = function(e) {
        cat("SAFE_READ_UPLOAD ERROR:\n")
        cat(conditionMessage(e), "\n")
        traceback()
        flush.console()
        stop(conditionMessage(e), call. = FALSE)
      }
    )
  }

  normalize_upload_schema <- function(df, mapping, dataset_type) {
    parse_numeric_value <- function(x) {
      y <- trimws(as.character(x))
      y[y %in% c("", "NA", "N/A", "na", "n/a", "NULL", "null")] <- NA_character_
      y <- gsub(",", "", y, fixed = TRUE)
      y <- gsub("^<\\s*", "", y)
      y <- gsub("^>\\s*", "", y)
      direct <- suppressWarnings(as.numeric(y))
      need_extract <- is.na(direct) & !is.na(y) & nzchar(y)
      if (any(need_extract, na.rm = TRUE)) {
        # Extract first numeric token from mixed strings like "<0.5 ng/L" or "ND (0.02)".
        tok <- stringr::str_extract(y[need_extract], "[-+]?[0-9]*\\.?[0-9]+(?:[eE][-+]?[0-9]+)?")
        direct[need_extract] <- suppressWarnings(as.numeric(tok))
      }
      direct
    }
    normalize_name <- function(x) {
      tolower(gsub("[^a-z0-9]+", "", trimws(as.character(x))))
    }
    pfas_like <- function(x) {
      y <- tolower(trimws(as.character(x)))
      y <- gsub("[^a-z0-9]+", " ", y)
      safe_detect(
        y,
        "\\bpf[a-z0-9]{2,}\\b|perfluoro|polyfluoro|fluorotelomer|genx|hfpo|adona|fosa|fosaa|fts|pfas"
      )
    }
    col_names <- names(df)
    col_norm <- normalize_name(col_names)
    field_aliases <- list(
      source_dataset = c("source_dataset", "source dataset", "dataset", "source", "source_name", "methodid", "method_id"),
      sample_id = c("sample_id", "sample id", "sample", "id", "seqn", "station", "pwsid", "pws_id", "samplepointid", "sample_point_id"),
      matrix = c("matrix", "sample_matrix", "sample type", "facilitywatertype", "facility_water_type", "samplepointtype", "sample_point_type"),
      date = c("sample_date", "sample date", "collection_date", "collection date", "date"),
      analyte = c("analyte", "analyte_name", "parameter", "parameter_name", "constituent", "contaminant", "chemical", "chemical_name", "compound"),
      cas = c("cas", "casrn", "cas_number"),
      result_value = c(
        "result_value", "result value", "result", "result_clean", "resultclean", "result_ngl", "result ngl",
        "concentration", "concentration_ng_l", "concentration_ngl", "value", "value_ngl", "reported", "reported_result"
      ),
      unit = c("result_unit", "result unit", "unit", "units", "uom"),
      qualifier = c("qualifier", "flag", "result_flag", "censor"),
      mdl = c("mdl", "method_detection_limit", "detection_limit"),
      rl = c("rl", "reporting_limit", "report_limit"),
      detect_flag = c("detect_flag", "detect", "detected"),
      state = c("state", "state_abbr"),
      county = c("county"),
      region = c("region"),
      facility_water_type = c("facilitywatertype", "facility_water_type"),
      sample_point_type = c("samplepointtype", "sample_point_type"),
      method_id = c("methodid", "method_id"),
      collection_year = c("collectionyear", "collection_year", "year"),
      collection_month = c("collectionmonth", "collection_month", "month"),
      pws_size = c("pwssize", "pws_size"),
      facility_id = c("facilityid", "facility_id"),
      sample_point_id = c("samplepointid", "sample_point_id"),
      latitude = c("latitude", "lat"),
      longitude = c("longitude", "lon", "lng"),
      health_endpoint = c("health_endpoint", "endpoint"),
      health_value = c("health_value")
    )
    resolve_col <- function(name) {
      mapped <- trimws(as.character(mapping[[name]] %||% ""))
      if (nzchar(mapped)) {
        mapped_norm <- tolower(mapped)
        if (identical(name, "result_value")) {
          bad <- safe_detect(
            mapped_norm,
            "modifier|qualifier|flag|vvl|tract|population|geoid|zip|pesticide|chemical|contaminant|name"
          )
          if (isTRUE(bad)) mapped <- ""
        } else if (identical(name, "analyte")) {
          bad <- safe_detect(
            mapped_norm,
            "modifier|qualifier|result|value|vvl|tract|population|geoid|zip"
          )
          if (isTRUE(bad)) mapped <- ""
        } else if (identical(name, "sample_id")) {
          bad <- safe_detect(
            mapped_norm,
            "pesticide|contaminant|chemical|analyte|result|value|tract|population|geoid|zip"
          )
          if (isTRUE(bad)) mapped <- ""
        }
      }
      if (nzchar(mapped) && mapped %in% col_names) return(mapped)
      aliases <- field_aliases[[name]] %||% name
      alias_norm <- normalize_name(aliases)
      scores <- rep(0, length(col_names))
      scores <- scores + ifelse(col_norm %in% alias_norm, 100, 0)
      for (a in alias_norm) {
        aa <- suppressWarnings(trimws(as.character(a)))
        if (length(aa) != 1L || is.na(aa) || !nzchar(aa)) next
        scores <- scores + ifelse(safe_detect(col_norm, aa), 35, 0)
      }

      if (identical(name, "result_value")) {
        numeric_rate <- vapply(col_names, function(cn) {
          vv <- parse_numeric_value(df[[cn]])
          mean(!is.na(vv))
        }, numeric(1))
        digit_rate <- vapply(col_names, function(cn) {
          vals <- as.character(df[[cn]])
          mean(safe_detect(vals, "[-+]?[0-9]*\\.?[0-9]+"), na.rm = TRUE)
        }, numeric(1))
        scores <- scores + 120 * numeric_rate
        scores <- scores + 45 * digit_rate
        scores <- scores + ifelse(safe_detect(col_norm, "result|concentration|value|ngl|clean"), 30, 0)
        scores <- scores - ifelse(safe_detect(col_norm, "modifier|qualifier|flag|vvl|code|id|tract|population|geoid|zip"), 90, 0)
      } else if (identical(name, "analyte")) {
        scores <- scores + ifelse(safe_detect(col_norm, "analyte|contaminant|parameter|chemical|compound|name"), 40, 0)
        scores <- scores - ifelse(safe_detect(col_norm, "modifier|vvl|id|code|flag"), 80, 0)
        text_pfas_rate <- vapply(col_names, function(cn) {
          col <- df[[cn]]
          if (!(is.character(col) || is.factor(col))) return(0)
          mean(pfas_like(col), na.rm = TRUE)
        }, numeric(1))
        scores <- scores + 120 * text_pfas_rate
      } else if (identical(name, "sample_id")) {
        scores <- scores + ifelse(safe_detect(col_norm, "sample|well|station|pws|^id$|_id$|id_"), 30, 0)
        scores <- scores - ifelse(safe_detect(col_norm, "result|value|concentration"), 40, 0)
        scores <- scores - ifelse(safe_detect(col_norm, "name|contaminant|chemical|pesticide"), 35, 0)
      } else if (identical(name, "state")) {
        scores <- scores + ifelse(safe_detect(col_norm, "^state$|stateabbr|statecode"), 50, 0)
      }

      if (all(!is.finite(scores))) return("")
      idx <- which.max(scores)
      if (length(idx) == 0 || !is.finite(scores[[idx]]) || scores[[idx]] <= 0) return("")
      if (identical(name, "result_value")) {
        best <- col_names[[idx]]
        best_num_rate <- mean(!is.na(parse_numeric_value(df[[best]])))
        best_name_ok <- safe_detect(normalize_name(best), "result|concentration|value|ngl|clean")
        if (!(isTRUE(best_name_ok) || best_num_rate >= 0.6)) return("")
      }
      col_names[[idx]]
    }
    pick <- function(name) {
      col <- resolve_col(name)
      if (!nzchar(col) || !(col %in% names(df))) return(rep(NA_character_, nrow(df)))
      as.character(df[[col]])
    }
    num_pick <- function(name) parse_numeric_value(pick(name))
    qualifier <- pick("qualifier")
    detect_raw <- tolower(trimws(pick("detect_flag")))
    detect_from_q <- !safe_detect(tolower(trimws(qualifier %||% "")), "^<|nd|non.?detect|bdl|u\\b|uj\\b")
    detect <- ifelse(
      nzchar(detect_raw),
      detect_raw %in% c("1", "true", "yes", "y", "detect", "detected"),
      detect_from_q
    )

    tibble::tibble(
      source = "external_upload",
      source_dataset = pick("source_dataset"),
      sample_id = pick("sample_id"),
      matrix = pick("matrix"),
      sample_date = pick("date"),
      analyte = pick("analyte"),
      cas = pick("cas"),
      result_value = num_pick("result_value"),
      result_unit = pick("unit"),
      qualifier = qualifier,
      mdl = num_pick("mdl"),
      rl = num_pick("rl"),
      detect_flag = as.integer(detect),
      state = pick("state"),
      county = pick("county"),
      region = pick("region"),
      facility_water_type = pick("facility_water_type"),
      sample_point_type = pick("sample_point_type"),
      method_id = pick("method_id"),
      collection_year = pick("collection_year"),
      collection_month = pick("collection_month"),
      pws_size = pick("pws_size"),
      facility_id = pick("facility_id"),
      sample_point_id = pick("sample_point_id"),
      latitude = num_pick("latitude"),
      longitude = num_pick("longitude"),
      health_endpoint = pick("health_endpoint"),
      health_value = num_pick("health_value"),
      dataset_type = dataset_type,
      upload_id = NA_character_,
      uploaded_at = NA_character_
    )
  }

  normalize_analyte_key <- function(x) {
    y <- tolower(trimws(as.character(x)))
    y <- gsub("[^a-z0-9]+", " ", y)
    dplyr::case_when(
      safe_detect(y, "pfoa|perfluorooctanoic") ~ "pfoa",
      safe_detect(y, "pfos|perfluorooctane sulfon") ~ "pfos",
      safe_detect(y, "pfna|perfluorononanoic") ~ "pfna",
      safe_detect(y, "pfhxs|perfluorohexane sulfon") ~ "pfhxs",
      safe_detect(y, "pfba|perfluorobutanoic") ~ "pfba",
      safe_detect(y, "pfpea|perfluoropentanoic") ~ "pfpea",
      safe_detect(y, "pfhxa|perfluorohexanoic") ~ "pfhxa",
      safe_detect(y, "pfbs|perfluorobutane sulfon") ~ "pfbs",
      safe_detect(y, "pfda|perfluorodecanoic") ~ "pfda",
      safe_detect(y, "pfuna|pfunda|pfundecanoic|perfluoroundecanoic") ~ "pfuna",
      safe_detect(y, "genx|hfpo|adona") ~ "genx",
      TRUE ~ NA_character_
    )
  }

  is_pfas_like_label <- function(x) {
    y <- tolower(trimws(as.character(x)))
    y <- gsub("[^a-z0-9]+", " ", y)
    safe_detect(
      y,
      "\\bpf[a-z0-9]{2,}\\b|perfluoro|polyfluoro|fluorotelomer|genx|hfpo|adona|fosa|fosaa|fts|pfas"
    )
  }

  normalize_upload_schema_with_wide_fallback <- function(df, mapping, dataset_type) {
    parse_numeric_value <- function(x) {
      y <- trimws(as.character(x))
      y[y %in% c("", "NA", "N/A", "na", "n/a", "NULL", "null")] <- NA_character_
      y <- gsub(",", "", y, fixed = TRUE)
      y <- gsub("^<\\s*", "", y)
      y <- gsub("^>\\s*", "", y)
      suppressWarnings(as.numeric(y))
    }
    base <- normalize_upload_schema(df, mapping, dataset_type)
    usable_base <- sum(
      !is.na(base$analyte) & nzchar(trimws(as.character(base$analyte))) & !is.na(base$result_value),
      na.rm = TRUE
    )
    if (usable_base > 0) return(base)

    canon_from_cols <- normalize_analyte_key(names(df))
    pfas_like_cols <- is_pfas_like_label(names(df))
    analyte_cols <- names(df)[!is.na(canon_from_cols) | pfas_like_cols]
    if (length(analyte_cols) == 0) return(base)
    canon_names <- setNames(canon_from_cols[match(analyte_cols, names(df))], analyte_cols)
    canon_names[is.na(canon_names)] <- gsub("[^a-z0-9]+", "_", tolower(trimws(analyte_cols[is.na(canon_names)])))

    if (nrow(df) == 0) return(base)
    keep_keys <- c(
      "source_dataset", "sample_id", "matrix", "date", "cas", "unit", "qualifier", "mdl",
      "rl", "detect_flag", "state", "county", "region", "facility_water_type", "sample_point_type",
      "method_id", "collection_year", "collection_month", "pws_size", "facility_id", "sample_point_id",
      "latitude", "longitude", "health_endpoint", "health_value"
    )
    key_map <- setNames(lapply(keep_keys, function(k) base[[k]]), keep_keys)
    long_raw <- as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE) %>%
      tibble::as_tibble() %>%
      mutate(.row_id = seq_len(n())) %>%
      tidyr::pivot_longer(
        cols = dplyr::all_of(analyte_cols),
        names_to = "analyte_col",
        values_to = "result_value_raw"
      )
    if (nrow(long_raw) == 0) return(base)

    row_idx <- pmax(1L, pmin(as.integer(long_raw$.row_id), nrow(df)))
    pick_key <- function(k) {
      v <- key_map[[k]]
      if (is.null(v) || length(v) == 0) return(rep(NA_character_, nrow(long_raw)))
      as.character(v[row_idx])
    }
    qualifier_vec <- pick_key("qualifier")
    detect_raw <- tolower(trimws(pick_key("detect_flag")))
    detect_from_q <- !safe_detect(tolower(trimws(qualifier_vec %||% "")), "^<|nd|non.?detect|bdl|u\\b|uj\\b")
    detect <- ifelse(
      nzchar(detect_raw),
      detect_raw %in% c("1", "true", "yes", "y", "detect", "detected"),
      detect_from_q
    )

    out <- tibble::tibble(
      source = "external_upload",
      source_dataset = pick_key("source_dataset"),
      sample_id = pick_key("sample_id"),
      matrix = pick_key("matrix"),
      sample_date = pick_key("date"),
      analyte = as.character(unname(canon_names[long_raw$analyte_col])),
      cas = pick_key("cas"),
      result_value = parse_numeric_value(long_raw$result_value_raw),
      result_unit = pick_key("unit"),
      qualifier = qualifier_vec,
      mdl = parse_numeric_value(pick_key("mdl")),
      rl = parse_numeric_value(pick_key("rl")),
      detect_flag = as.integer(detect),
      state = pick_key("state"),
      county = pick_key("county"),
      region = pick_key("region"),
      facility_water_type = pick_key("facility_water_type"),
      sample_point_type = pick_key("sample_point_type"),
      method_id = pick_key("method_id"),
      collection_year = pick_key("collection_year"),
      collection_month = pick_key("collection_month"),
      pws_size = pick_key("pws_size"),
      facility_id = pick_key("facility_id"),
      sample_point_id = pick_key("sample_point_id"),
      latitude = parse_numeric_value(pick_key("latitude")),
      longitude = parse_numeric_value(pick_key("longitude")),
      health_endpoint = pick_key("health_endpoint"),
      health_value = parse_numeric_value(pick_key("health_value")),
      dataset_type = dataset_type,
      upload_id = NA_character_,
      uploaded_at = NA_character_
    ) %>%
      filter(!is.na(result_value))

    if (nrow(out) > 0) return(out)

    # Fallback for matrix-style uploads where analyte is in rows and sample IDs are column headers.
    char_cols <- names(df)[vapply(df, function(col) is.character(col) || is.factor(col), logical(1))]
    if (length(char_cols) == 0) return(base)
    analyte_hits <- lapply(char_cols, function(cn) {
      raw <- as.character(df[[cn]])
      mapped <- normalize_analyte_key(raw)
      looks <- is_pfas_like_label(raw)
      mapped[is.na(mapped) & looks] <- gsub("[^a-z0-9]+", "_", tolower(trimws(raw[is.na(mapped) & looks])))
      mapped
    })
    hit_counts <- vapply(analyte_hits, function(v) sum(!is.na(v), na.rm = TRUE), integer(1))
    if (length(hit_counts) == 0 || max(hit_counts, na.rm = TRUE) < 2) return(base)
    analyte_col <- char_cols[[which.max(hit_counts)]]
    analyte_key <- analyte_hits[[which.max(hit_counts)]]
    if (all(is.na(analyte_key))) return(base)

    meta_cols <- unique(c(
      analyte_col,
      trimws(as.character(mapping$source_dataset %||% "")),
      trimws(as.character(mapping$sample_id %||% "")),
      trimws(as.character(mapping$matrix %||% "")),
      trimws(as.character(mapping$date %||% "")),
      trimws(as.character(mapping$unit %||% "")),
      trimws(as.character(mapping$state %||% "")),
      trimws(as.character(mapping$county %||% "")),
      trimws(as.character(mapping$region %||% "")),
      trimws(as.character(mapping$facility_water_type %||% "")),
      trimws(as.character(mapping$sample_point_type %||% "")),
      trimws(as.character(mapping$method_id %||% "")),
      trimws(as.character(mapping$collection_year %||% "")),
      trimws(as.character(mapping$collection_month %||% "")),
      trimws(as.character(mapping$pws_size %||% "")),
      trimws(as.character(mapping$facility_id %||% "")),
      trimws(as.character(mapping$sample_point_id %||% ""))
    ))
    meta_cols <- meta_cols[nzchar(meta_cols) & meta_cols %in% names(df)]
    candidate_cols <- setdiff(names(df), meta_cols)
    if (length(candidate_cols) == 0) return(base)
    numeric_like <- candidate_cols[vapply(candidate_cols, function(cn) {
      vals <- parse_numeric_value(df[[cn]])
      sum(!is.na(vals), na.rm = TRUE) >= 1
    }, logical(1))]
    if (length(numeric_like) == 0) return(base)

    long2 <- as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE) %>%
      tibble::as_tibble() %>%
      mutate(.row_id = seq_len(n()), analyte = analyte_key) %>%
      filter(!is.na(analyte)) %>%
      tidyr::pivot_longer(
        cols = dplyr::all_of(numeric_like),
        names_to = "sample_col",
        values_to = "result_value_raw"
      ) %>%
      mutate(result_value = parse_numeric_value(result_value_raw)) %>%
      filter(!is.na(result_value))
    if (nrow(long2) == 0) return(base)

    pick_matrix_meta <- function(col_name, idx) {
      if (!nzchar(col_name) || !(col_name %in% names(df))) return(rep(NA_character_, length(idx)))
      as.character(df[[col_name]][idx])
    }
    sample_map_col <- trimws(as.character(mapping$sample_id %||% ""))
    matrix_map_col <- trimws(as.character(mapping$matrix %||% ""))
    date_map_col <- trimws(as.character(mapping$date %||% ""))
    state_map_col <- trimws(as.character(mapping$state %||% ""))
    county_map_col <- trimws(as.character(mapping$county %||% ""))
    region_map_col <- trimws(as.character(mapping$region %||% ""))
    facility_water_type_map_col <- trimws(as.character(mapping$facility_water_type %||% ""))
    sample_point_type_map_col <- trimws(as.character(mapping$sample_point_type %||% ""))
    method_id_map_col <- trimws(as.character(mapping$method_id %||% ""))
    collection_year_map_col <- trimws(as.character(mapping$collection_year %||% ""))
    collection_month_map_col <- trimws(as.character(mapping$collection_month %||% ""))
    pws_size_map_col <- trimws(as.character(mapping$pws_size %||% ""))
    facility_id_map_col <- trimws(as.character(mapping$facility_id %||% ""))
    sample_point_id_map_col <- trimws(as.character(mapping$sample_point_id %||% ""))
    unit_map_col <- trimws(as.character(mapping$unit %||% ""))
    src_map_col <- trimws(as.character(mapping$source_dataset %||% ""))
    idx2 <- pmax(1L, pmin(as.integer(long2$.row_id), nrow(df)))

    out2 <- tibble::tibble(
      source = "external_upload",
      source_dataset = {
        v <- pick_matrix_meta(src_map_col, idx2)
        ifelse(is.na(v) | !nzchar(v), dataset_type, v)
      },
      sample_id = {
        v <- pick_matrix_meta(sample_map_col, idx2)
        ifelse(is.na(v) | !nzchar(v), as.character(long2$sample_col), v)
      },
      matrix = pick_matrix_meta(matrix_map_col, idx2),
      sample_date = pick_matrix_meta(date_map_col, idx2),
      analyte = as.character(long2$analyte),
      cas = NA_character_,
      result_value = long2$result_value,
      result_unit = pick_matrix_meta(unit_map_col, idx2),
      qualifier = NA_character_,
      mdl = NA_real_,
      rl = NA_real_,
      detect_flag = as.integer(1),
      state = pick_matrix_meta(state_map_col, idx2),
      county = pick_matrix_meta(county_map_col, idx2),
      region = pick_matrix_meta(region_map_col, idx2),
      facility_water_type = pick_matrix_meta(facility_water_type_map_col, idx2),
      sample_point_type = pick_matrix_meta(sample_point_type_map_col, idx2),
      method_id = pick_matrix_meta(method_id_map_col, idx2),
      collection_year = pick_matrix_meta(collection_year_map_col, idx2),
      collection_month = pick_matrix_meta(collection_month_map_col, idx2),
      pws_size = pick_matrix_meta(pws_size_map_col, idx2),
      facility_id = pick_matrix_meta(facility_id_map_col, idx2),
      sample_point_id = pick_matrix_meta(sample_point_id_map_col, idx2),
      latitude = NA_real_,
      longitude = NA_real_,
      health_endpoint = NA_character_,
      health_value = NA_real_,
      dataset_type = dataset_type,
      upload_id = NA_character_,
      uploaded_at = NA_character_
    )
    out2
  }

  append_pipeline_log <- function(...) {
    msg <- paste(..., collapse = "")
    stamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    pfas_pipeline_log(paste0(pfas_pipeline_log(), "\n[", stamp, "] ", msg))
  }

  bool_mark <- function(x) if (isTRUE(x)) "\u2705" else "\u274c"

  is_identifier_like_result_col <- function(col_name) {
    nm <- tolower(gsub("[^a-z0-9]+", "", trimws(as.character(col_name %||% ""))))
    if (!nzchar(nm)) return(FALSE)
    looks_result <- safe_detect(nm, "result|concentration|value|ngl|clean|analyticalresult")
    looks_id <- safe_detect(nm, "pws|well|station|sample|facility|point|(^id$)|id$")
    isTRUE(looks_id) && !isTRUE(looks_result)
  }

  resolve_pipeline_path <- function(raw_value, default_path) {
    p <- trimws(as.character(raw_value %||% ""))
    if (!nzchar(p)) p <- default_path
    p
  }

  path_file_count <- function(path) {
    if (is.null(path) || !nzchar(path)) return(0L)
    if (file.exists(path) && !dir.exists(path)) return(1L)
    if (!dir.exists(path)) return(0L)
    as.integer(length(list.files(path, full.names = TRUE)))
  }

  is_placeholder_preflight_template_basename <- function(bnm) {
    b <- tolower(as.character(bnm %||% ""))
    if (!nzchar(b)) return(FALSE)
    if (grepl("^iso17025_preflight_.*template\\.", b, perl = TRUE)) return(TRUE)
    if (grepl("_template\\.(csv|tsv|txt|xlsx|xls)$", b, perl = TRUE)) return(TRUE)
    if (grepl("preflight", b, fixed = TRUE) && grepl("template", b, fixed = TRUE)) return(TRUE)
    FALSE
  }

  latest_non_placeholder_file <- function(path) {
    if (is.null(path) || !nzchar(trimws(path))) return(NULL)
    path <- trimws(path)
    if (file.exists(path) && !dir.exists(path)) {
      if (is_placeholder_preflight_template_basename(basename(path))) return(NULL)
      return(path)
    }
    if (!dir.exists(path)) return(NULL)
    files <- list.files(path, full.names = TRUE, recursive = FALSE)
    exts <- tolower(tools::file_ext(files))
    files <- files[exts %in% c("csv", "tsv", "txt", "xlsx", "xls")]
    if (length(files) == 0L) return(NULL)
    files <- files[!vapply(basename(files), is_placeholder_preflight_template_basename, logical(1))]
    if (length(files) == 0L) return(NULL)
    info <- suppressWarnings(file.info(files))
    files[[which.max(info$mtime)]]
  }

  check_method_dataset_schema <- function(path_value = NULL) {
    default_method <- file.path(PROJECT_DIR, "data", "external", "method_data")
    method_path <- resolve_pipeline_path(path_value, default_method)
    mf <- latest_non_placeholder_file(method_path)
    if (is.null(mf)) return(list(ok = FALSE, path = method_path, file = NA_character_))
    md <- read_any_table(mf, max_rows = 2000)
    if (is.null(md) || nrow(md) == 0) return(list(ok = FALSE, path = method_path, file = basename(mf)))
    required_aliases <- list(
      method_id = c("Method_ID", "method_id", "MethodID"),
      matrix_type = c("Matrix_Type", "matrix_type", "MatrixType"),
      lod = c("Detection_Limit", "LOD", "detection_limit", "detection_limit_lod"),
      loq = c("Quantification_Limit", "LOQ", "quantification_limit", "reporting_limit")
    )
    found <- vapply(required_aliases, function(a) !is.null(pick_col(md, a)), logical(1))
    list(ok = all(found), path = method_path, file = basename(mf), found = found)
  }

  check_reference_dataset_schema <- function(path_value = NULL) {
    default_ref <- file.path(PROJECT_DIR, "data", "external", "method_validation")
    ref_path <- resolve_pipeline_path(path_value, default_ref)
    rf <- latest_non_placeholder_file(ref_path)
    if (is.null(rf)) return(list(ok = FALSE, path = ref_path, file = NA_character_))
    rd <- read_any_table(rf, max_rows = 2000)
    if (is.null(rd) || nrow(rd) == 0) return(list(ok = FALSE, path = ref_path, file = basename(rf)))
    target_col <- pick_col(rd, c("PFAS_Risk_Flag", "actual", "target", "risk_flag", "expected_pfas_risk_flag"))
    concentration_col <- pick_col(rd, c("result_value", "concentration", "known_concentration", "reference_concentration"))
    list(
      ok = !is.null(target_col) && !is.null(concentration_col),
      path = ref_path,
      file = basename(rf),
      found = c(target = !is.null(target_col), concentration = !is.null(concentration_col))
    )
  }

  check_qc_dataset_schema <- function(path_value = NULL) {
    default_qc <- file.path(PROJECT_DIR, "data", "external", "qc_datasets")
    qc_path <- resolve_pipeline_path(path_value, default_qc)
    qf <- latest_non_placeholder_file(qc_path)
    if (is.null(qf)) return(list(ok = FALSE, path = qc_path, file = NA_character_))
    qd <- read_any_table(qf, max_rows = 2000)
    if (is.null(qd) || nrow(qd) == 0) return(list(ok = FALSE, path = qc_path, file = basename(qf)))
    required_aliases <- list(
      qc_type = c("QC_Type", "qc_type", "qc"),
      recovery_percent = c("Recovery_Percent", "recovery_percent", "recovery_pct", "recovery"),
      rsd = c("RSD", "rsd", "relative_standard_deviation"),
      batch_id = c("Batch_ID", "batch_id", "batch"),
      analyst_id = c("Analyst_ID", "analyst_id", "analyst")
    )
    found <- vapply(required_aliases, function(a) !is.null(pick_col(qd, a)), logical(1))
    list(ok = all(found), path = qc_path, file = basename(qf), found = found)
  }

  check_pt_dataset_schema <- function(path_value = NULL) {
    default_pt <- file.path(PROJECT_DIR, "data", "external", "proficiency_testing")
    pt_path <- resolve_pipeline_path(path_value, default_pt)
    pf <- latest_non_placeholder_file(pt_path)
    if (is.null(pf)) return(list(ok = FALSE, path = pt_path, file = NA_character_))
    pd <- read_any_table(pf, max_rows = 2000)
    if (is.null(pd) || nrow(pd) == 0) return(list(ok = FALSE, path = pt_path, file = basename(pf)))
    expected_col <- pick_col(pd, c("expected_pfas_risk_flag", "expected_flag", "assigned_flag", "target"))
    z_col <- pick_col(pd, c("z_score", "zscore", "pt_zscore"))
    provider_col <- pick_col(pd, c("pt_provider", "provider", "scheme_provider", "program"))
    list(
      ok = (!is.null(expected_col) || !is.null(z_col)) && !is.null(provider_col),
      path = pt_path,
      file = basename(pf),
      found = c(expected_or_z = (!is.null(expected_col) || !is.null(z_col)), provider = !is.null(provider_col))
    )
  }

  run_iso_preflight_check <- function() {
    ref <- check_reference_dataset_schema(input$pfas_ref_path)
    method <- check_method_dataset_schema(input$pfas_method_path)
    qc <- check_qc_dataset_schema(input$pfas_qc_path)
    pt <- check_pt_dataset_schema(input$pfas_pt_path)
    checks <- c(reference = isTRUE(ref$ok), method = isTRUE(method$ok), qc = isTRUE(qc$ok), pt = isTRUE(pt$ok))
    list(
      ok = all(checks),
      checks = checks,
      ref = ref,
      method = method,
      qc = qc,
      pt = pt
    )
  }

  enforce_iso_preflight <- function(action_label = "This action") {
    skip <- trimws(Sys.getenv("PFAS_SKIP_ISO_PREFLIGHT", ""))
    if (nzchar(skip) && tolower(skip) %in% c("1", "true", "yes")) {
      iso_preflight_note(paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " SKIPPED (PFAS_SKIP_ISO_PREFLIGHT)"))
      append_pipeline_log("ISO preflight skipped (PFAS_SKIP_ISO_PREFLIGHT) for ", action_label)
      return(TRUE)
    }
    pf <- run_iso_preflight_check()
    if (isTRUE(pf$ok)) {
      iso_preflight_note(paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " PASS"))
      return(TRUE)
    }
    failed <- names(pf$checks)[!pf$checks]
    iso_preflight_note(paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " BLOCK (", paste(failed, collapse = ", "), ")"))
    showNotification(
      paste0(action_label, " blocked: ISO preflight failed (", paste(failed, collapse = ", "), ")."),
      type = "error",
      duration = 10
    )
    append_pipeline_log("ISO preflight BLOCK for ", action_label, " | failed=", paste(failed, collapse = ", "))
    FALSE
  }

  pipeline_component_status <- reactive({
    pfas_results_nonce()
    has_icis_dmr <- length(Sys.glob(file.path(PROJECT_DIR, "data", "processed", "npdes_dmr_pfas_fy*.csv"))) > 0L
    has_raw_occurrence <- {
      p1 <- file.path(PROJECT_DIR, "data", "training", "pfas_multisource_training.csv")
      p2 <- file.path(PROJECT_DIR, "data", "processed", "pfas_training_master.csv")
      (file.exists(p1) && tryCatch(nrow(read.csv(p1, nrows = 1)) >= 0, error = function(e) FALSE)) ||
        (file.exists(p2) && tryCatch(nrow(read.csv(p2, nrows = 1)) >= 0, error = function(e) FALSE)) ||
        isTRUE(has_icis_dmr)
    }
    has_regulatory <- {
      cfg <- file.path(PROJECT_DIR, "data", "config", "pfas_regulatory_limits.csv")
      file.exists(cfg)
    }
    has_certified_validation <- isTRUE(check_reference_dataset_schema(input$pfas_ref_path)$ok)
    has_qc <- isTRUE(check_qc_dataset_schema(input$pfas_qc_path)$ok)
    has_pt <- isTRUE(check_pt_dataset_schema(input$pfas_pt_path)$ok)
    has_method_structure <- isTRUE(check_method_dataset_schema(input$pfas_method_path)$ok)
    tibble::tibble(
      Component = c(
        "Occurrence / training tables",
        "ICIS-NPDES PFAS-filtered DMR CSV (processed/)",
        "Regulatory limits (config file)",
        "Reference folder: CSV schema (real data, not templates)",
        "QC folder: CSV schema (real lab QC, not templates)",
        "Method metadata folder: CSV schema",
        "PT folder: CSV schema (real PT, not templates)"
      ),
      schema_check = c(
        bool_mark(has_raw_occurrence),
        bool_mark(has_icis_dmr),
        bool_mark(has_regulatory),
        bool_mark(has_certified_validation),
        bool_mark(has_qc),
        bool_mark(has_method_structure),
        bool_mark(has_pt)
      )
    )
  })

  read_any_table <- function(path, max_rows = Inf) {
    ext <- tolower(tools::file_ext(path))
    if (!file.exists(path)) return(NULL)
    nr_limit <- if (is.finite(max_rows) && max_rows > 0) max_rows else NA_integer_
    if (ext %in% c("csv")) {
      return(read_delimited_robust(path, sep = ",", header = TRUE, nrows = nr_limit))
    }
    if (ext %in% c("tsv")) {
      return(read_delimited_robust(path, sep = "\t", header = TRUE, nrows = nr_limit))
    }
    if (ext %in% c("txt")) {
      first <- read_first_line_robust(path)
      sep <- if (!nzchar(first)) "," else {
        counts <- c(
          comma = lengths(regmatches(first, gregexpr(",", first, fixed = TRUE))),
          tab = lengths(regmatches(first, gregexpr("\t", first, fixed = TRUE))),
          semi = lengths(regmatches(first, gregexpr(";", first, fixed = TRUE))),
          pipe = lengths(regmatches(first, gregexpr("|", first, fixed = TRUE)))
        )
        c(comma = ",", tab = "\t", semi = ";", pipe = "|")[names(which.max(counts))]
      }
      return(read_delimited_robust(path, sep = sep, header = TRUE, nrows = nr_limit))
    }
    if (ext %in% c("xlsx", "xls")) {
      if (!requireNamespace("readxl", quietly = TRUE)) return(NULL)
      return(tryCatch(as.data.frame(readxl::read_excel(path, n_max = max_rows)), error = function(e) NULL))
    }
    if (ext %in% c("json")) {
      if (!requireNamespace("jsonlite", quietly = TRUE)) return(NULL)
      return(tryCatch(as.data.frame(jsonlite::fromJSON(path, flatten = TRUE)), error = function(e) NULL))
    }
    NULL
  }

  normalize_names <- function(x) tolower(gsub("[^a-z0-9]+", "", as.character(x %||% "")))

  pick_col <- function(df, aliases) {
    if (is.null(df) || nrow(df) < 0) return(NULL)
    nms <- names(df)
    if (length(nms) == 0) return(NULL)
    nn <- normalize_names(nms)
    aa <- normalize_names(aliases)
    idx <- match(aa, nn)
    idx <- idx[!is.na(idx)]
    if (length(idx) == 0) return(NULL)
    nms[idx[[1]]]
  }

  ensure_uploaded_artifact <- function(file_input, target_dir, fallback_name) {
    if (is.null(file_input) || is.null(file_input$datapath) || !file.exists(file_input$datapath)) return(NULL)
    dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
    safe_name <- gsub("[^A-Za-z0-9._-]", "_", basename(file_input$name %||% fallback_name))
    dest <- file.path(target_dir, paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_", safe_name))
    ok <- tryCatch(file.copy(file_input$datapath, dest, overwrite = TRUE), error = function(e) FALSE)
    if (!isTRUE(ok)) return(NULL)
    dest
  }

  latest_file <- function(path) {
    if (is.null(path) || !nzchar(path)) return(NULL)
    if (file.exists(path) && !dir.exists(path)) return(path)
    if (!dir.exists(path)) return(NULL)
    files <- list.files(path, full.names = TRUE)
    if (length(files) == 0) return(NULL)
    info <- file.info(files)
    files[[which.max(info$mtime)]]
  }

  load_qc_method_thresholds <- function() {
    defaults <- tibble::tibble(
      method_key = c("EPA_533", "EPA_537_1", "EPA_1633", "GENERIC"),
      recovery_min = c(70, 70, 50, 70),
      recovery_max = c(130, 130, 150, 130),
      rpd_max = c(30, 30, 40, 30),
      blank_abs_max = c(1e-3, 1e-3, 1e-3, 1e-3)
    )
    cfg <- file.path(PROJECT_DIR, "data", "config", "qc_method_thresholds.csv")
    if (!file.exists(cfg)) {
      attr(defaults, "threshold_source") <- "built_in_defaults"
      return(defaults)
    }

    raw <- tryCatch(utils::read.csv(cfg, stringsAsFactors = FALSE, check.names = FALSE), error = function(e) NULL)
    required <- c("method_key", "recovery_min", "recovery_max", "rpd_max", "blank_abs_max")
    if (is.null(raw) || !all(required %in% names(raw))) {
      append_pipeline_log("QC thresholds config invalid; using built-in defaults.")
      attr(defaults, "threshold_source") <- "built_in_defaults_invalid_config"
      return(defaults)
    }

    cleaned <- raw[, required, drop = FALSE]
    cleaned$method_key <- toupper(gsub("[^A-Za-z0-9]+", "_", trimws(as.character(cleaned$method_key))))
    cleaned$recovery_min <- suppressWarnings(as.numeric(cleaned$recovery_min))
    cleaned$recovery_max <- suppressWarnings(as.numeric(cleaned$recovery_max))
    cleaned$rpd_max <- suppressWarnings(as.numeric(cleaned$rpd_max))
    cleaned$blank_abs_max <- suppressWarnings(as.numeric(cleaned$blank_abs_max))
    cleaned <- cleaned[
      nzchar(cleaned$method_key) &
        !is.na(cleaned$recovery_min) &
        !is.na(cleaned$recovery_max) &
        !is.na(cleaned$rpd_max) &
        !is.na(cleaned$blank_abs_max),
      ,
      drop = FALSE
    ]
    if (nrow(cleaned) == 0) {
      append_pipeline_log("QC thresholds config has no valid rows; using built-in defaults.")
      attr(defaults, "threshold_source") <- "built_in_defaults_empty_config"
      return(defaults)
    }
    cleaned <- cleaned[!duplicated(cleaned$method_key), , drop = FALSE]
    if (!("GENERIC" %in% cleaned$method_key)) {
      cleaned <- rbind(cleaned, defaults[defaults$method_key == "GENERIC", , drop = FALSE])
    }
    out <- tibble::as_tibble(cleaned)
    attr(out, "threshold_source") <- cfg
    out
  }

  step_validate_reference_dataset <- function() {
    ref_path <- resolve_pipeline_path(input$pfas_ref_path, file.path(PROJECT_DIR, "data", "external", "method_validation"))
    ref_file <- latest_non_placeholder_file(ref_path)
    if (is.null(ref_file)) {
      pipeline_last_error("No reference dataset found at PFAS Reference Data Path.")
      return(FALSE)
    }
    ref_df <- read_any_table(ref_file)
    if (is.null(ref_df) || nrow(ref_df) == 0) {
      pipeline_last_error("Reference dataset could not be read or is empty.")
      return(FALSE)
    }
    pred_file <- file.path(PROJECT_DIR, "results", "prediction_output.csv")
    val_file <- file.path(PROJECT_DIR, "results", "validation_summary.csv")
    model_df <- if (file.exists(pred_file)) read_any_table(pred_file) else read_any_table(val_file)
    if (is.null(model_df) || nrow(model_df) == 0) {
      pipeline_last_error("No model output found (results/prediction_output.csv or validation_summary.csv).")
      return(FALSE)
    }

    ref_target_col <- pick_col(ref_df, c("PFAS_Risk_Flag", "actual", "target", "risk_flag"))
    mdl_pred_col <- pick_col(model_df, c("predicted_PFAS_Risk_Flag", "predicted", "prediction", "pred"))
    mdl_prob_col <- pick_col(model_df, c("probability_exceedance", "prob", "score"))
    if (is.null(ref_target_col) || (is.null(mdl_pred_col) && is.null(mdl_prob_col))) {
      pipeline_last_error("Reference/model files are missing target or prediction columns required for validation.")
      return(FALSE)
    }

    n_eval <- min(nrow(ref_df), nrow(model_df))
    ref_target <- suppressWarnings(as.integer(as.numeric(ref_df[[ref_target_col]][seq_len(n_eval)])))
    if (!is.null(mdl_pred_col)) {
      mdl_pred <- suppressWarnings(as.integer(as.numeric(model_df[[mdl_pred_col]][seq_len(n_eval)])))
    } else {
      mdl_prob <- suppressWarnings(as.numeric(model_df[[mdl_prob_col]][seq_len(n_eval)]))
      mdl_pred <- as.integer(mdl_prob >= 0.5)
    }
    keep <- !(is.na(ref_target) | is.na(mdl_pred))
    eval_rows <- sum(keep)
    if (eval_rows < 10) {
      pipeline_last_error("Insufficient overlap rows for reference validation (<10 comparable rows).")
      return(FALSE)
    }
    accuracy <- mean(ref_target[keep] == mdl_pred[keep])

    summary_df <- tibble::tibble(
      reference_path = ref_path,
      reference_file = basename(ref_file),
      model_file = if (file.exists(pred_file)) basename(pred_file) else basename(val_file),
      evaluated_rows = eval_rows,
      agreement_accuracy = round(accuracy, 4),
      status = ifelse(accuracy >= 0.70, "PASS", "REVIEW")
    )
    out_file <- file.path(PROJECT_DIR, "results", "reference_validation_summary.csv")
    try(utils::write.csv(summary_df, out_file, row.names = FALSE), silent = TRUE)
    append_pipeline_log("Reference dataset loaded/validated: rows=", eval_rows, ", accuracy=", sprintf("%.3f", accuracy), ".")
    pipeline_last_error("")
    TRUE
  }

  step_qc_validation_check <- function() {
    qc_path <- resolve_pipeline_path(input$pfas_qc_path, file.path(PROJECT_DIR, "data", "external", "qc_datasets"))
    qf <- latest_non_placeholder_file(qc_path)
    if (is.null(qf)) {
      pipeline_last_error("No QC dataset found at PFAS QC Data Path.")
      return(FALSE)
    }
    qd <- read_any_table(qf)
    if (is.null(qd) || nrow(qd) == 0) {
      pipeline_last_error("QC dataset could not be read or is empty.")
      return(FALSE)
    }
    qc_required <- list(
      qc_type = c("QC_Type", "qc_type", "qc"),
      recovery_percent = c("Recovery_Percent", "recovery_percent", "recovery_pct", "recovery"),
      rsd = c("RSD", "rsd", "relative_standard_deviation"),
      batch_id = c("Batch_ID", "batch_id", "batch"),
      analyst_id = c("Analyst_ID", "analyst_id", "analyst")
    )
    qc_required_found <- vapply(qc_required, function(a) !is.null(pick_col(qd, a)), logical(1))
    if (!all(qc_required_found)) {
      missing <- names(qc_required_found)[!qc_required_found]
      pipeline_last_error(paste0("QC dataset missing required ISO columns: ", paste(missing, collapse = ", ")))
      return(FALSE)
    }
    rec_col <- pick_col(qd, c("recovery_pct", "recovery", "percent_recovery", "spike_recovery", "lcs_recovery", "ms_recovery"))
    rpd_col <- pick_col(qd, c("duplicate_rpd", "rpd", "relative_percent_difference", "dup_rpd"))
    blank_col <- pick_col(qd, c("blank_result", "method_blank", "blank_ngl", "blank", "mb_result"))
    method_col <- pick_col(qd, c("method_id", "methodid", "method", "epa_method", "analytical_method"))
    rl_col <- pick_col(qd, c("rl", "reporting_limit", "quantitation_limit", "loq"))
    mdl_col <- pick_col(qd, c("mdl", "method_detection_limit", "detection_limit"))

    if (is.null(method_col)) {
      method_key <- rep("GENERIC", nrow(qd))
    } else {
      raw_method <- toupper(trimws(as.character(qd[[method_col]])))
      method_key <- ifelse(grepl("1633", raw_method), "EPA_1633",
                    ifelse(grepl("537\\.1|5371", raw_method), "EPA_537_1",
                    ifelse(grepl("533", raw_method), "EPA_533", "GENERIC")))
    }

    thresholds <- load_qc_method_thresholds()
    threshold_source <- as.character(attr(thresholds, "threshold_source") %||% "built_in_defaults")
    th_map <- thresholds[match(method_key, thresholds$method_key), , drop = FALSE]

    rec <- if (is.null(rec_col)) rep(NA_real_, nrow(qd)) else suppressWarnings(as.numeric(qd[[rec_col]]))
    rpd <- if (is.null(rpd_col)) rep(NA_real_, nrow(qd)) else suppressWarnings(as.numeric(qd[[rpd_col]]))
    b <- if (is.null(blank_col)) rep(NA_real_, nrow(qd)) else suppressWarnings(as.numeric(qd[[blank_col]]))
    rl <- if (is.null(rl_col)) rep(NA_real_, nrow(qd)) else suppressWarnings(as.numeric(qd[[rl_col]]))
    mdl <- if (is.null(mdl_col)) rep(NA_real_, nrow(qd)) else suppressWarnings(as.numeric(qd[[mdl_col]]))
    blank_limit <- ifelse(!is.na(rl), rl, ifelse(!is.na(mdl), mdl, th_map$blank_abs_max))

    rec_ok <- if (is.null(rec_col)) rep(NA, nrow(qd)) else (rec >= th_map$recovery_min & rec <= th_map$recovery_max)
    rpd_ok <- if (is.null(rpd_col)) rep(NA, nrow(qd)) else (rpd <= th_map$rpd_max)
    blank_ok <- if (is.null(blank_col)) rep(NA, nrow(qd)) else (abs(b) <= blank_limit)

    checks_present <- sum(!is.na(c(
      if (all(is.na(rec_ok))) NA else mean(rec_ok, na.rm = TRUE),
      if (all(is.na(rpd_ok))) NA else mean(rpd_ok, na.rm = TRUE),
      if (all(is.na(blank_ok))) NA else mean(blank_ok, na.rm = TRUE)
    )))
    if (checks_present == 0) {
      pipeline_last_error("QC dataset missing recognizable QC metric columns (recovery/rpd/blank).")
      return(FALSE)
    }

    detail <- tibble::tibble(
      method_key = method_key,
      recovery_ok = rec_ok,
      rpd_ok = rpd_ok,
      blank_ok = blank_ok
    )

    summary_by_method <- detail |>
      dplyr::group_by(method_key) |>
      dplyr::summarise(
        rows = dplyr::n(),
        recovery_pass_rate = if (all(is.na(recovery_ok))) NA_real_ else mean(recovery_ok, na.rm = TRUE),
        duplicate_rpd_pass_rate = if (all(is.na(rpd_ok))) NA_real_ else mean(rpd_ok, na.rm = TRUE),
        blank_pass_rate = if (all(is.na(blank_ok))) NA_real_ else mean(blank_ok, na.rm = TRUE),
        .groups = "drop"
      ) |>
      dplyr::left_join(thresholds, by = "method_key") |>
      dplyr::mutate(
        overall_qc_pass_rate = rowMeans(dplyr::across(c(recovery_pass_rate, duplicate_rpd_pass_rate, blank_pass_rate)), na.rm = TRUE),
        status = ifelse(overall_qc_pass_rate >= 0.80, "PASS", "REVIEW"),
        qc_file = basename(qf),
        qc_path = qc_path,
        threshold_source = threshold_source
      ) |>
      dplyr::select(
        qc_file, method_key, rows,
        threshold_source,
        recovery_min, recovery_max, rpd_max, blank_abs_max,
        recovery_pass_rate, duplicate_rpd_pass_rate, blank_pass_rate,
        overall_qc_pass_rate, status
      )

    overall <- weighted.mean(summary_by_method$overall_qc_pass_rate, w = summary_by_method$rows, na.rm = TRUE)
    out <- summary_by_method
    out_file <- file.path(PROJECT_DIR, "results", "qc_validation_summary.csv")
    try(utils::write.csv(out, out_file, row.names = FALSE), silent = TRUE)
    append_pipeline_log(
      "QC validation complete: overall pass rate=", sprintf("%.3f", overall),
      " | methods=", paste(unique(summary_by_method$method_key), collapse = ", "),
      " | thresholds=", threshold_source, "."
    )
    pipeline_last_error("")
    TRUE
  }

  step_applicability_domain_check <- function() {
    pred_file <- file.path(PROJECT_DIR, "results", "prediction_output.csv")
    val_file <- file.path(PROJECT_DIR, "results", "validation_summary.csv")
    df <- if (file.exists(pred_file)) read_any_table(pred_file) else read_any_table(val_file)
    if (is.null(df) || nrow(df) == 0) {
      pipeline_last_error("No prediction/validation output available for applicability-domain check.")
      return(FALSE)
    }
    ad_col <- pick_col(df, c("applicability_domain", "ad_status"))
    unc_col <- pick_col(df, c("uncertainty_score", "uncertainty"))
    review_col <- pick_col(df, c("manual_review_required", "review_required"))

    outside_rate <- NA_real_
    if (!is.null(ad_col)) {
      ad <- tolower(as.character(df[[ad_col]]))
      outside_rate <- mean(grepl("outside|review", ad), na.rm = TRUE)
    }
    high_uncertainty_rate <- NA_real_
    if (!is.null(unc_col)) {
      u <- suppressWarnings(as.numeric(df[[unc_col]]))
      high_uncertainty_rate <- mean(u > 0.50, na.rm = TRUE)
    }
    manual_review_rate <- NA_real_
    if (!is.null(review_col)) {
      mr <- tolower(as.character(df[[review_col]]))
      manual_review_rate <- mean(mr %in% c("true", "1", "yes"), na.rm = TRUE)
    }

    metrics <- c(outside_rate, high_uncertainty_rate, manual_review_rate)
    if (all(is.na(metrics))) {
      pipeline_last_error("Applicability-domain fields missing (need AD, uncertainty, or review columns).")
      return(FALSE)
    }
    risk_rate <- max(metrics, na.rm = TRUE)
    out <- tibble::tibble(
      evaluated_rows = nrow(df),
      outside_ad_rate = outside_rate,
      high_uncertainty_rate = high_uncertainty_rate,
      manual_review_rate = manual_review_rate,
      ad_risk_rate = risk_rate,
      status = ifelse(is.finite(risk_rate) && risk_rate <= 0.30, "PASS", "REVIEW")
    )
    out_file <- file.path(PROJECT_DIR, "results", "applicability_domain_check.csv")
    try(utils::write.csv(out, out_file, row.names = FALSE), silent = TRUE)
    append_pipeline_log("Applicability-domain check complete: risk rate=", sprintf("%.3f", risk_rate), ".")
    pipeline_last_error("")
    TRUE
  }

  step_external_pt_validation <- function() {
    pt_path <- resolve_pipeline_path(input$pfas_pt_path, file.path(PROJECT_DIR, "data", "external", "proficiency_testing"))
    pf <- latest_non_placeholder_file(pt_path)
    if (is.null(pf)) {
      pipeline_last_error("No PT dataset found at PFAS Proficiency Test Path.")
      return(FALSE)
    }
    ptd <- read_any_table(pf)
    if (is.null(ptd) || nrow(ptd) == 0) {
      pipeline_last_error("PT dataset could not be read or is empty.")
      return(FALSE)
    }

    pred_file <- file.path(PROJECT_DIR, "results", "prediction_output.csv")
    val_file <- file.path(PROJECT_DIR, "results", "validation_summary.csv")
    model_df <- if (file.exists(pred_file)) read_any_table(pred_file) else read_any_table(val_file)
    if (is.null(model_df) || nrow(model_df) == 0) {
      pipeline_last_error("No model output available for PT external validation.")
      return(FALSE)
    }

    pt_expected_flag_col <- pick_col(ptd, c("expected_pfas_risk_flag", "expected_flag", "assigned_flag", "target"))
    pt_z_col <- pick_col(ptd, c("z_score", "zscore", "pt_zscore"))
    mdl_pred_col <- pick_col(model_df, c("predicted_PFAS_Risk_Flag", "predicted", "prediction"))
    if (is.null(pt_expected_flag_col) && is.null(pt_z_col)) {
      pipeline_last_error("PT dataset missing expected result columns (expected flag or z-score).")
      return(FALSE)
    }
    if (is.null(mdl_pred_col) && is.null(pt_z_col)) {
      pipeline_last_error("Model output missing predicted flag required for PT concordance.")
      return(FALSE)
    }

    n_eval <- min(nrow(ptd), nrow(model_df))
    concordance <- NA_real_
    if (!is.null(pt_expected_flag_col) && !is.null(mdl_pred_col)) {
      expected <- suppressWarnings(as.integer(as.numeric(ptd[[pt_expected_flag_col]][seq_len(n_eval)])))
      pred <- suppressWarnings(as.integer(as.numeric(model_df[[mdl_pred_col]][seq_len(n_eval)])))
      keep <- !(is.na(expected) | is.na(pred))
      if (sum(keep) > 0) concordance <- mean(expected[keep] == pred[keep])
    }
    z_pass_rate <- NA_real_
    if (!is.null(pt_z_col)) {
      z <- suppressWarnings(as.numeric(ptd[[pt_z_col]][seq_len(n_eval)]))
      z_pass_rate <- mean(abs(z) <= 2, na.rm = TRUE)
    }
    metrics <- c(concordance, z_pass_rate)
    if (all(is.na(metrics))) {
      pipeline_last_error("PT external validation has no evaluable rows.")
      return(FALSE)
    }
    score <- max(metrics, na.rm = TRUE)
    out <- tibble::tibble(
      pt_path = pt_path,
      pt_file = basename(pf),
      evaluated_rows = n_eval,
      concordance_rate = concordance,
      zscore_pass_rate = z_pass_rate,
      external_validation_score = score,
      status = ifelse(is.finite(score) && score >= 0.80, "PASS", "REVIEW")
    )
    out_file <- file.path(PROJECT_DIR, "results", "pt_external_validation_summary.csv")
    try(utils::write.csv(out, out_file, row.names = FALSE), silent = TRUE)
    append_pipeline_log("PT external validation complete: score=", sprintf("%.3f", score), ".")
    pipeline_last_error("")
    TRUE
  }

  step_generate_iso_compliance_report <- function() {
    ref_file <- file.path(PROJECT_DIR, "results", "reference_validation_summary.csv")
    qc_file <- file.path(PROJECT_DIR, "results", "qc_validation_summary.csv")
    ad_file <- file.path(PROJECT_DIR, "results", "applicability_domain_check.csv")
    pt_file <- file.path(PROJECT_DIR, "results", "pt_external_validation_summary.csv")
    ref_df <- if (file.exists(ref_file)) read_any_table(ref_file) else NULL
    qc_df <- if (file.exists(qc_file)) read_any_table(qc_file) else NULL
    ad_df <- if (file.exists(ad_file)) read_any_table(ad_file) else NULL
    pt_df <- if (file.exists(pt_file)) read_any_table(pt_file) else NULL
    comp <- pipeline_component_status()
    component_pass <- all(comp$schema_check == "\u2705")
    method_ok <- isTRUE(check_method_dataset_schema(input$pfas_method_path)$ok)
    ref_ok <- !is.null(ref_df) && nrow(ref_df) > 0 && toupper(as.character(ref_df$status[[1]] %||% "REVIEW")) == "PASS"
    qc_ok <- !is.null(qc_df) && nrow(qc_df) > 0 && all(toupper(as.character(qc_df$status %||% "REVIEW")) == "PASS")
    ad_ok <- !is.null(ad_df) && nrow(ad_df) > 0 && toupper(as.character(ad_df$status[[1]] %||% "REVIEW")) == "PASS"
    pt_ok <- !is.null(pt_df) && nrow(pt_df) > 0 && toupper(as.character(pt_df$status[[1]] %||% "REVIEW")) == "PASS"
    overall <- component_pass && method_ok && ref_ok && qc_ok && ad_ok && pt_ok

    out_json <- list(
      generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
      iso_mode = TRUE,
      pipeline_components_complete = component_pass,
      method_dataset_schema = if (method_ok) "PASS" else "REVIEW",
      reference_validation = if (ref_ok) "PASS" else "REVIEW",
      qc_validation = if (qc_ok) "PASS" else "REVIEW",
      applicability_domain = if (ad_ok) "PASS" else "REVIEW",
      proficiency_testing_validation = if (pt_ok) "PASS" else "REVIEW",
      overall_status = if (overall) "READY_FOR_REVIEW" else "ACTION_REQUIRED"
    )
    json_path <- file.path(PROJECT_DIR, "results", "iso_compliance_report.json")
    txt_path <- file.path(PROJECT_DIR, "results", "iso_compliance_report.txt")
    if (requireNamespace("jsonlite", quietly = TRUE)) {
      try(jsonlite::write_json(out_json, json_path, pretty = TRUE, auto_unbox = TRUE), silent = TRUE)
    } else {
      try(utils::write.csv(as.data.frame(out_json, stringsAsFactors = FALSE), file.path(PROJECT_DIR, "results", "iso_compliance_report_fallback.csv"), row.names = FALSE), silent = TRUE)
    }
    lines <- c(
      "PFAS Enterprise 4.0 - ISO Compliance Report",
      paste0("Generated: ", out_json$generated_at),
      "",
      paste0("Schema / folder row checks (not lab validation): ", if (component_pass) "all pass" else "gaps remain"),
      paste0("Method dataset schema: ", out_json$method_dataset_schema),
      paste0("Reference dataset validation: ", out_json$reference_validation),
      paste0("QC validation check: ", out_json$qc_validation),
      paste0("Applicability-domain check: ", out_json$applicability_domain),
      paste0("External validation (PT): ", out_json$proficiency_testing_validation),
      "",
      paste0("Overall status: ", out_json$overall_status),
      "Note: Screening-level decision support only; ISO/IEC 17025 accredited analytical release still requires laboratory validation and analyst approval."
    )
    try(writeLines(lines, con = txt_path), silent = TRUE)
    append_pipeline_log("ISO compliance report generated: ", normalizePath(txt_path, winslash = "/", mustWork = FALSE))
    pipeline_last_error("")
    TRUE
  }

  run_local_cmd <- function(exec, args, step_name, extra_env = NULL) {
    append_pipeline_log("START ", step_name, ": ", exec, " ", paste(args, collapse = " "))
    old_wd <- getwd()
    on.exit(setwd(old_wd), add = TRUE)

    if (!is.null(extra_env) && length(extra_env) > 0) {
      env_names <- names(extra_env)
      old_env <- Sys.getenv(env_names, unset = NA_character_)
      restore_env <- function() {
        for (i in seq_along(env_names)) {
          nm <- env_names[[i]]
          oldv <- old_env[[i]]
          if (is.na(oldv)) {
            Sys.unsetenv(nm)
          } else {
            do.call(Sys.setenv, setNames(list(oldv), nm))
          }
        }
      }
      on.exit(restore_env(), add = TRUE)
      do.call(Sys.setenv, as.list(extra_env))
    }

    setwd(PROJECT_DIR)
    out <- tryCatch(
      system2(exec, args = args, stdout = TRUE, stderr = TRUE),
      error = function(e) structure(paste("ERROR:", conditionMessage(e)), status = 999L)
    )
    status <- as.integer(attr(out, "status") %||% 0L)
    if (length(out) > 0) append_pipeline_log(paste(out, collapse = "\n"))
    if (status == 0L) {
      pipeline_last_error("")
      append_pipeline_log("DONE ", step_name)
      write_audit(
        "pfas_pipeline",
        step_name,
        "execute_success",
        op_id(),
        "PFAS pipeline step completed",
        list(step = step_name, status = status, command = exec, args = args)
      )
      TRUE
    } else {
      pipeline_last_error(paste0(step_name, " exited with code ", status))
      append_pipeline_log("FAIL ", step_name, " (exit ", status, ")")
      write_audit(
        "pfas_pipeline",
        step_name,
        "execute_failure",
        op_id(),
        "PFAS pipeline step failed",
        list(step = step_name, status = status, command = exec, args = args)
      )
      FALSE
    }
  }

  pipeline_env <- function() {
    out <- c(
      PFAS_ECHO_URLS = trimws(input$epa_echo_urls %||% ""),
      PFAS_SDWIS_URLS = trimws(input$sdwis_urls %||% "")
    )
    out[nzchar(out)]
  }

  run_r_script_step <- function(script_name, label, extra_env = NULL) {
    rscript_exec <- "Rscript"
    on_path <- Sys.which(rscript_exec)
    if (!nzchar(on_path)) {
      r_bin <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
      if (file.exists(r_bin)) rscript_exec <- r_bin
    } else {
      rscript_exec <- on_path
    }
    run_local_cmd(rscript_exec, c(file.path("scripts", script_name)), label, extra_env = extra_env)
  }

  run_r_script_in_process <- function(script_name, label) {
    append_pipeline_log("START ", label, " (in-process source)")
    old_wd <- getwd()
    on.exit(setwd(old_wd), add = TRUE)
    setwd(PROJECT_DIR)
    script_path <- file.path("scripts", script_name)
    ok <- tryCatch(
      {
        local_env <- new.env(parent = .GlobalEnv)
        source(script_path, local = local_env, echo = FALSE, chdir = FALSE)
        pipeline_last_error("")
        TRUE
      },
      error = function(e) {
        pipeline_last_error(conditionMessage(e))
        append_pipeline_log("ERROR ", label, ": ", conditionMessage(e))
        FALSE
      }
    )
    if (ok) {
      append_pipeline_log("DONE ", label, " (in-process)")
      write_audit(
        "pfas_pipeline",
        label,
        "execute_success",
        op_id(),
        "PFAS pipeline step completed (in-process)",
        list(step = label, mode = "in_process")
      )
      TRUE
    } else {
      append_pipeline_log("FAIL ", label, " (in-process)")
      write_audit(
        "pfas_pipeline",
        label,
        "execute_failure",
        op_id(),
        "PFAS pipeline step failed (in-process)",
        list(step = label, mode = "in_process")
      )
      FALSE
    }
  }

  resolve_python_exec <- function(py_exec_raw) {
    py_exec <- trimws(py_exec_raw %||% "")
    if (!nzchar(py_exec)) {
      py_exec <- if (file.exists(LOCAL_PYTHON_DEFAULT)) LOCAL_PYTHON_DEFAULT else "python"
    }
    # Direct path (Windows/local) or command on PATH.
    if (file.exists(py_exec)) return(py_exec)
    on_path <- Sys.which(py_exec)
    if (nzchar(on_path)) return(on_path)
    ""
  }

  run_python_step <- function() {
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    train_script <- file.path("scripts", "train_pfas_model.py")
    if (!file.exists(file.path(PROJECT_DIR, train_script))) {
      train_script <- file.path("scripts", "train_nhanes_model.py")
    }
    # Remove stale per-task artifacts before retrain so freshness/status reflects current run.
    res_dir <- file.path(PROJECT_DIR, "results")
    stale_files <- c(
      "nhanes_model_metrics_by_task.json",
      "nhanes_model_metrics.json",
      "nhanes_feature_importance.csv",
      "nhanes_test_predictions.csv"
    )
    stale_paths <- file.path(res_dir, stale_files)
    for (sp in stale_paths[file.exists(stale_paths)]) {
      try(unlink(sp, force = TRUE), silent = TRUE)
    }
    stale_task <- list.files(
      res_dir,
      pattern = "^nhanes_model_metrics_task_.*\\.json$",
      full.names = TRUE
    )
    if (length(stale_task) > 0) {
      for (sp in stale_task) {
        try(unlink(sp, force = TRUE), silent = TRUE)
      }
    }
    step_label <- basename(train_script)
    if (!nzchar(py_exec)) {
      append_pipeline_log(
        "SKIP ", step_label, ": Python executable not found in this runtime. ",
        "Run training locally (desktop R session), then redeploy results/ artifacts."
      )
      return(FALSE)
    }
    train_extra <- character(0)
    if (isTRUE(input$pfas_train_strict %||% TRUE)) train_extra <- c(train_extra, "--strict")
    if (isTRUE(input$pfas_train_verbose %||% FALSE)) train_extra <- c(train_extra, "-v")
    mr_txt <- trimws(input$pfas_train_min_recall_positive %||% "")
    if (nzchar(mr_txt)) {
      mv <- suppressWarnings(as.numeric(mr_txt))
      if (is.finite(mv) && mv >= 0 && mv <= 1) {
        train_extra <- c(train_extra, "--min-recall-positive", as.character(mv))
      }
    }
    ht <- suppressWarnings(as.numeric(input$pfas_holdout_threshold %||% 0.25))
    if (!is.finite(ht) || ht < 0.01 || ht > 0.99) ht <- 0.25
    train_extra <- c(train_extra, "--holdout-threshold", sprintf("%.6g", ht))
    run_local_cmd(py_exec, c(train_script, train_extra), step_label)
  }

  run_ml_validation_report_step <- function() {
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    report_script <- file.path("scripts", "generate_validation_report.py")
    if (!nzchar(py_exec)) {
      append_pipeline_log(
        "SKIP generate_validation_report.py: Python executable not found in this runtime."
      )
      return(FALSE)
    }
    if (!file.exists(file.path(PROJECT_DIR, report_script))) {
      append_pipeline_log("SKIP generate_validation_report.py: scripts/generate_validation_report.py not found.")
      return(FALSE)
    }
    pr_arg <- normalizePath(PROJECT_DIR, winslash = "/", mustWork = FALSE)
    run_local_cmd(py_exec, c(report_script, "--project-root", pr_arg), "generate_validation_report.py")
  }

  run_pfas_prediction_step <- function() {
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    pred_script <- file.path("scripts", "predict_pfas.py")
    if (!nzchar(py_exec)) {
      append_pipeline_log(
        "SKIP predict_pfas.py: Python executable not found in this runtime."
      )
      return(FALSE)
    }
    if (!file.exists(file.path(PROJECT_DIR, pred_script))) {
      append_pipeline_log("SKIP predict_pfas.py: scripts/predict_pfas.py not found.")
      return(FALSE)
    }
    run_local_cmd(py_exec, c(pred_script), "predict_pfas.py")
  }

  run_icis_dmr_filter_step <- function() {
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    filt_script <- file.path("scripts", "filter_npdes_dmr_pfas.py")
    if (!nzchar(py_exec)) {
      append_pipeline_log("SKIP filter_npdes_dmr_pfas.py: Python executable not found.")
      return(FALSE)
    }
    if (!file.exists(file.path(PROJECT_DIR, filt_script))) {
      append_pipeline_log("SKIP filter_npdes_dmr_pfas.py: script missing.")
      return(FALSE)
    }
    fy <- trimws(input$epa_icis_filter_fy %||% "2024")
    if (!grepl("^[0-9]{4}$", fy)) {
      append_pipeline_log("SKIP filter_npdes_dmr_pfas.py: invalid fiscal year (need 4 digits).")
      showNotification("DMR filter FY must be four digits (e.g. 2024).", type = "error")
      return(FALSE)
    }
    out_rel <- file.path("data", "processed", sprintf("npdes_dmr_pfas_fy%s.csv", fy))
    dir.create(file.path(PROJECT_DIR, "data", "processed"), recursive = TRUE, showWarnings = FALSE)
    args <- c(
      filt_script,
      "--fiscal-year", fy,
      "--out-csv", out_rel
    )
    run_local_cmd(py_exec, args, sprintf("filter_npdes_dmr_pfas.py FY%s", fy))
  }

  output$pfas_pipeline_log <- renderPrint({
    cat(pfas_pipeline_log(), "\n")
  })

  output$source_bootstrap_status <- renderPrint({
    cat(source_bootstrap_note(), "\n")
  })

  iso_badge <- function(ok, label_ok = "READY", label_bad = "MISSING / INVALID") {
    if (isTRUE(ok)) {
      tags$span(
        style = "display:inline-block;padding:3px 10px;border-radius:999px;background:#2e7d32;color:#fff;font-size:12px;font-weight:600;",
        paste0("\u2705 ", label_ok)
      )
    } else {
      tags$span(
        style = "display:inline-block;padding:3px 10px;border-radius:999px;background:#c62828;color:#fff;font-size:12px;font-weight:600;",
        paste0("\u274c ", label_bad)
      )
    }
  }

  iso_path_badge_screening_optional <- function(short_label) {
    tags$span(
      style = "display:inline-block;padding:3px 10px;border-radius:999px;background:#757575;color:#fff;font-size:12px;font-weight:500;",
      paste0("\u2014 ", short_label, " (optional \u2014 screening / desk use)")
    )
  }

  lab_schema_badges_enabled <- function() {
    isTRUE(input$pfas_show_lab_artifact_schema_badges %||% FALSE)
  }

  output$pfas_ref_path_badge <- renderUI({
    if (!lab_schema_badges_enabled()) {
      return(iso_path_badge_screening_optional("Reference pack"))
    }
    chk <- check_reference_dataset_schema(input$pfas_ref_path)
    iso_badge(chk$ok, "Reference ready", "Reference missing/invalid")
  })

  output$pfas_method_path_badge <- renderUI({
    if (!lab_schema_badges_enabled()) {
      return(iso_path_badge_screening_optional("Method pack"))
    }
    chk <- check_method_dataset_schema(input$pfas_method_path)
    iso_badge(chk$ok, "Method schema ready", "Method schema missing")
  })

  output$pfas_qc_path_badge <- renderUI({
    if (!lab_schema_badges_enabled()) {
      return(iso_path_badge_screening_optional("QC pack"))
    }
    chk <- check_qc_dataset_schema(input$pfas_qc_path)
    iso_badge(chk$ok, "QC schema ready", "QC schema missing")
  })

  output$pfas_pt_path_badge <- renderUI({
    if (!lab_schema_badges_enabled()) {
      return(iso_path_badge_screening_optional("PT pack"))
    }
    chk <- check_pt_dataset_schema(input$pfas_pt_path)
    iso_badge(chk$ok, "PT schema ready", "PT schema missing")
  })

  output$iso_data_paths_status <- renderPrint({
    ref_path <- resolve_pipeline_path(input$pfas_ref_path, file.path(PROJECT_DIR, "data", "external", "method_validation"))
    method_path <- resolve_pipeline_path(input$pfas_method_path, file.path(PROJECT_DIR, "data", "external", "method_data"))
    qc_path <- resolve_pipeline_path(input$pfas_qc_path, file.path(PROJECT_DIR, "data", "external", "qc_datasets"))
    pt_path <- resolve_pipeline_path(input$pfas_pt_path, file.path(PROJECT_DIR, "data", "external", "proficiency_testing"))
    method_check <- check_method_dataset_schema(method_path)
    cat("ISO data paths\n")
    cat("Reference :", ref_path, "| files:", path_file_count(ref_path), "\n")
    cat("Method    :", method_path, "| files:", path_file_count(method_path), "| schema:", bool_mark(method_check$ok), "\n")
    cat("QC        :", qc_path, "| files:", path_file_count(qc_path), "\n")
    cat("PT        :", pt_path, "| files:", path_file_count(pt_path), "\n")
    if (!isTRUE(method_check$ok)) {
      cat("Method path requirement: Method_ID, Matrix_Type, Detection_Limit (LOD), Quantification_Limit (LOQ)\n")
    }
  })

  output$iso_preflight_status <- renderPrint({
    pf <- run_iso_preflight_check()
    cat("Strict ISO preflight gate\n")
    cat("Overall:", if (isTRUE(pf$ok)) "PASS" else "BLOCK", "\n")
    cat("Reference dataset :", bool_mark(pf$checks[["reference"]]), "\n")
    cat("Method dataset    :", bool_mark(pf$checks[["method"]]), "\n")
    cat("QC dataset        :", bool_mark(pf$checks[["qc"]]), "\n")
    cat("PT dataset        :", bool_mark(pf$checks[["pt"]]), "\n")
    cat("\nLast preflight run:\n", iso_preflight_note(), "\n", sep = "")
  })

  output$qc_pt_upload_status <- renderPrint({
    cat(qc_pt_upload_status_note(), "\n")
  })

  output$tbl_pipeline_component_status <- DT::renderDT({
    st <- pipeline_component_status()
    DT::datatable(
      st,
      colnames = c("Component", "Structure / schema (not scientific validation)"),
      rownames = FALSE,
      options = list(
        dom = "t",
        paging = FALSE,
        ordering = FALSE,
        searching = FALSE,
        info = FALSE
      )
    )
  })

  observeEvent(input$btn_iso_preflight, {
    pf <- run_iso_preflight_check()
    failed <- names(pf$checks)[!pf$checks]
    if (isTRUE(pf$ok)) {
      iso_preflight_note(paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " PASS"))
      append_pipeline_log("ISO preflight PASS (reference, method, qc, pt).")
      showNotification("ISO preflight passed.", type = "message")
      write_audit(
        "pfas_pipeline",
        "iso_preflight",
        "execute_success",
        op_id(),
        "ISO preflight passed",
        list(checks = as.list(pf$checks))
      )
    } else {
      iso_preflight_note(paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " BLOCK (", paste(failed, collapse = ", "), ")"))
      append_pipeline_log("ISO preflight BLOCK: ", paste(failed, collapse = ", "))
      showNotification(paste0("ISO preflight blocked: ", paste(failed, collapse = ", ")), type = "error")
      write_audit(
        "pfas_pipeline",
        "iso_preflight",
        "execute_failure",
        op_id(),
        "ISO preflight blocked",
        list(checks = as.list(pf$checks), failed = failed)
      )
    }
    pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$btn_bootstrap_source_folders, {
    src_root <- file.path(PROJECT_DIR, "data", "external")
    src_dirs <- c(
      "nhanes", "epa_ucmr5", "epa_echo_pfas", "sdwis", "external_uploads",
      "method_validation", "method_data", "qc_datasets", "proficiency_testing",
      "ca_waterboards", "mi_egle", "epa_1633_mdl", "echo",
      "echo_epa_gov", "epa_gov_water", "data_ca_gov", "michigan_gov", "nj_gov", "denix_osd_mil",
      "epa_gov_sludge_soil", "sciencebase_gov", "pca_state_mn_us", "data_nal_usda_gov",
      "wwwn_cdc_gov", "atsdr_cdc_gov", "biomonitoring_ca_gov", "nyc_gov", "nist_gov", "hbm4eu_eu",
      "epa_gov_air", "ww2_arb_ca_gov", "norman_network_net"
    )
    created <- character(0)
    for (d in src_dirs) {
      p <- file.path(src_root, d)
      if (!dir.exists(p)) {
        dir.create(p, recursive = TRUE, showWarnings = FALSE)
        created <- c(created, d)
      }
      readme <- file.path(p, "README_DROP_HERE.txt")
      if (!file.exists(readme)) {
        writeLines(
          c(
            paste("Source folder:", d),
            "",
            "Drop source files here (CSV preferred).",
            "Then run: 6) Build multi-source training table.",
            "Reference schema hints: data/external/SOURCE_INTAKE_TEMPLATE.csv"
          ),
          con = readme
        )
      }
    }
    template_path <- file.path(src_root, "SOURCE_INTAKE_TEMPLATE.csv")
    note <- paste0(
      "Bootstrap complete.\n",
      "Root: ", normalizePath(src_root, winslash = "/", mustWork = FALSE), "\n",
      "New folders created: ", length(created), if (length(created) > 0) paste0(" [", paste(created, collapse = ", "), "]") else "", "\n",
      "Template: ", normalizePath(template_path, winslash = "/", mustWork = FALSE)
    )
    source_bootstrap_note(note)
    write_audit(
      "external_sources",
      "bootstrap_folders",
      "execute_success",
      op_id(),
      "External source folders bootstrapped",
      list(created_folders = created, total_folders = length(src_dirs))
    )
    showNotification("External source folders bootstrapped.", type = "message")
    raw_icis <- file.path(PROJECT_DIR, "data", "raw", "epa_icis_npdes")
    if (!dir.exists(raw_icis)) {
      dir.create(raw_icis, recursive = TRUE, showWarnings = FALSE)
    }
    ricis_readme <- file.path(raw_icis, "README_ICIS_NPDES.txt")
    if (!file.exists(ricis_readme)) {
      writeLines(
        c(
          "EPA ICIS-NPDES bulk downloads land here (see scripts/download_epa_icis_npdes.R).",
          "Mirror: download_epa_icis_npdes_ml.ps1 in project root.",
          "ECHO index: https://echo.epa.gov/tools/data-downloads",
          "PFAS DMR slice: python scripts/filter_npdes_dmr_pfas.py --fiscal-year YYYY"
        ),
        con = ricis_readme
      )
    }
  })

  observeEvent(input$external_ml_file, {
    # Must match UI fileInput id "external_ml_file".
    f <- normalize_shiny_file_upload(input$external_ml_file)
    external_upload_raw(NULL)
    external_upload_report(NULL)
    external_upload_normalized(NULL)
    external_upload_read_error("")
    external_upload_strict_result(NULL)
    # Reset any sticky prior mappings so new uploads re-run auto-detection.
    map_keys <- c(
      "source_dataset", "sample_id", "matrix", "date", "analyte", "cas",
      "result_value", "unit", "qualifier", "mdl", "rl", "detect_flag",
      "state", "county", "region", "facility_water_type", "sample_point_type",
      "method_id", "collection_year", "collection_month", "pws_size", "facility_id", "sample_point_id",
      "latitude", "longitude", "health_endpoint", "health_value"
    )
    for (k in map_keys) {
      try(updateSelectInput(session, paste0("map_", k), selected = ""), silent = TRUE)
    }
    if (is.null(f)) return(invisible(NULL))
    ext <- tolower(tools::file_ext(f$name))
    external_upload_name(f$name)
    if (!(ext %in% allowed_upload_ext)) {
      msg <- paste0("Unsafe/unsupported file type: .", ext)
      external_upload_read_error(msg)
      showNotification(msg, type = "error")
      return(invisible(NULL))
    }
    if (!nzchar(f$datapath) || !isTRUE(file.exists(f$datapath))) {
      msg <- "No file uploaded yet (server temp path missing or expired)."
      external_upload_read_error(msg)
      showNotification(msg, type = "error")
      return(invisible(NULL))
    }
    dat <- tryCatch(
      safe_read_upload(f$datapath, f$name),
      error = function(e) {
        msg <- paste("Upload read failed:", conditionMessage(e))
        external_upload_read_error(msg)
        external_upload_raw(NULL)
        showNotification(msg, type = "error")
        NULL
      }
    )
    if (is.null(dat)) return(invisible(NULL))
    if (!is.data.frame(dat) || nrow(dat) == 0) {
      msg <- "Upload rejected: file has no rows or unreadable table structure."
      external_upload_read_error(msg)
      showNotification(msg, type = "error")
      return(invisible(NULL))
    }
    external_upload_read_error("")
    external_upload_raw(dat)
    showNotification(paste("Loaded upload:", f$name %||% "", "rows:", nrow(dat)), type = "message")
  })

  output$external_file_meta <- renderPrint({
    cat("Upload reader:", UPLOAD_READER_VERSION, "\n")
    cat("ICIS-NPDES UI:", ICIS_NPDES_UI_VERSION, "\n")
    cat("Mapping engine version:", MAPPING_ENGINE_VERSION, "\n")
    cat("(Delimited files) SAFE_READ_UPLOAD diagnostics go to the R console, not this panel.\n")
    cat("\n")
    f <- normalize_shiny_file_upload(input$external_ml_file)
    df <- external_upload_raw()
    read_err <- external_upload_read_error() %||% ""
    if (nzchar(read_err)) {
      cat("Upload error:", read_err, "\n")
      if (grepl("zero-length pattern", read_err, fixed = TRUE)) {
        cat(
          "Hint: redeploy LatestPFAS.R — delimited uploads use base R read.table only.\n",
          "Console must show SAFE_READ_UPLOAD START; Upload reader line must contain 'delimited-base-only'.\n",
          "Smoke file: data/test_upload/test_upload.csv . UCMR5_AddtlDataElem is supplemental metadata, not occurrence results.\n"
        )
      }
    }
    if (is.null(f) || is.null(df)) {
      if (is.null(f)) {
        cat("No file selected.\n")
      } else if (nzchar(read_err)) {
        cat("Preview not available (read failed; see error above).\n")
      } else {
        cat("No data in preview yet.\n")
      }
      return(invisible(NULL))
    }
    ext <- tolower(tools::file_ext(f$name))
    cat("File:", f$name %||% "", "\n")
    cat("Size (bytes):", f$size %||% NA, "\n")
    cat("Extension:", ext, "\n")
    cat("Rows:", nrow(df), "\n")
    cat("Columns:", ncol(df), "\n")
  })

  output$tbl_external_preview <- renderDT({
    df <- external_upload_raw()
    if (is.null(df) || nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "Upload a supported file to preview first 20 rows."), rownames = FALSE))
    }
    render_dt(utils::head(df, 20), 20)
  })

  output$external_map_ui <- renderUI({
    df <- external_upload_raw()
    if (is.null(df)) {
      return(tags$p("Upload a file to configure column mapping."))
    }
    cols <- names(df)
    norm_name <- function(x) tolower(gsub("[^a-z0-9]+", "", trimws(as.character(x))))
    parse_num <- function(x) {
      y <- trimws(as.character(x))
      y[y %in% c("", "NA", "N/A", "na", "n/a", "NULL", "null")] <- NA_character_
      y <- gsub(",", "", y, fixed = TRUE)
      y <- gsub("^<\\s*", "", y)
      y <- gsub("^>\\s*", "", y)
      direct <- suppressWarnings(as.numeric(y))
      need_extract <- is.na(direct) & !is.na(y) & nzchar(y)
      if (any(need_extract, na.rm = TRUE)) {
        tok <- stringr::str_extract(y[need_extract], "[-+]?[0-9]*\\.?[0-9]+(?:[eE][-+]?[0-9]+)?")
        direct[need_extract] <- suppressWarnings(as.numeric(tok))
      }
      direct
    }
    is_bad_result_col <- function(cname) {
      if (!nzchar(cname) || !(cname %in% cols)) return(TRUE)
      key <- norm_name(cname)
      vals <- as.character(df[[cname]])
      vals <- vals[!is.na(vals)]
      if (length(vals) == 0) return(TRUE)
      vals <- utils::head(vals, 250)
      numeric_rate <- mean(!is.na(parse_num(vals)), na.rm = TRUE)
      letter_rate <- mean(safe_detect(vals, "[A-Za-z]"), na.rm = TRUE)
      looks_result_name <- safe_detect(key, "result|concentration|value|ngl|clean|meas|amount")
      looks_id_name <- safe_detect(key, "pws|well|station|sample|_id$|^id$|id")
      if (looks_id_name && !looks_result_name) return(TRUE)
      if (numeric_rate < 0.20) return(TRUE)
      if (letter_rate > 0.70 && !looks_result_name) return(TRUE)
      FALSE
    }
    choose_col <- function(field_name, aliases) {
      if (length(cols) == 0) return("")
      cn <- cols
      cn_norm <- norm_name(cn)
      al_norm <- norm_name(aliases)
      scores <- rep(0, length(cn))
      scores <- scores + ifelse(cn_norm %in% al_norm, 100, 0)
      for (a in al_norm) {
        aa <- suppressWarnings(trimws(as.character(a)))
        if (length(aa) != 1L || is.na(aa) || !nzchar(aa)) next
        scores <- scores + ifelse(safe_detect(cn_norm, aa), 35, 0)
      }
      if (identical(field_name, "result_value")) {
        numeric_rate <- vapply(cn, function(cname) mean(!is.na(parse_num(df[[cname]]))), numeric(1))
        digit_rate <- vapply(cn, function(cname) {
          vv <- as.character(df[[cname]])
          mean(safe_detect(vv, "[-+]?[0-9]*\\.?[0-9]+"), na.rm = TRUE)
        }, numeric(1))
        scores <- scores + 120 * numeric_rate
        scores <- scores + 45 * digit_rate
        scores <- scores + ifelse(safe_detect(cn_norm, "result|concentration|value|ngl|clean"), 30, 0)
        scores <- scores - ifelse(safe_detect(cn_norm, "modifier|qualifier|flag|vvl|code|id|pws|well|station|sample|tract|population|geoid|zip"), 120, 0)
      } else if (identical(field_name, "analyte")) {
        scores <- scores + ifelse(safe_detect(cn_norm, "analyte|contaminant|parameter|chemical|compound|name"), 40, 0)
        scores <- scores - ifelse(safe_detect(cn_norm, "modifier|vvl|id|code|flag"), 80, 0)
        pfas_rate <- vapply(cn, function(cname) {
          col <- df[[cname]]
          if (!(is.character(col) || is.factor(col))) return(0)
          mean(pfas_like(col), na.rm = TRUE)
        }, numeric(1))
        scores <- scores + 120 * pfas_rate
      } else if (identical(field_name, "sample_id")) {
        scores <- scores + ifelse(safe_detect(cn_norm, "sample|well|station|pws|^id$|_id$|id_"), 30, 0)
        scores <- scores - ifelse(safe_detect(cn_norm, "result|value|concentration"), 40, 0)
        scores <- scores - ifelse(safe_detect(cn_norm, "name|contaminant|chemical|pesticide"), 35, 0)
      }
      idx <- which.max(scores)
      if (length(idx) == 0 || !is.finite(scores[[idx]]) || scores[[idx]] <= 0) return("")
      if (identical(field_name, "result_value")) {
        best <- cn[[idx]]
        best_num_rate <- mean(!is.na(parse_num(df[[best]])))
        best_name_ok <- safe_detect(norm_name(best), "result|concentration|value|ngl|clean")
        if (isTRUE(is_bad_result_col(best))) return("")
        if (!(isTRUE(best_name_ok) || best_num_rate >= 0.6)) return("")
      }
      cn[[idx]]
    }
    pfas_like <- function(x) {
      y <- tolower(trimws(as.character(x)))
      y <- gsub("[^a-z0-9]+", " ", y)
      safe_detect(
        y,
        "\\bpf[a-z0-9]{2,}\\b|perfluoro|polyfluoro|fluorotelomer|genx|hfpo|adona|fosa|fosaa|fts|pfas"
      )
    }
    opts <- c("(not mapped)" = "", stats::setNames(cols, cols))
    fields <- c(
      "source_dataset", "sample_id", "matrix", "date", "analyte", "cas",
      "result_value", "unit", "qualifier", "mdl", "rl", "detect_flag",
      "state", "county", "region", "facility_water_type", "sample_point_type",
      "method_id", "collection_year", "collection_month", "pws_size", "facility_id", "sample_point_id",
      "latitude", "longitude", "health_endpoint", "health_value"
    )
    labels <- c(
      source_dataset = "source_dataset",
      sample_id = "sample_id",
      matrix = "matrix",
      date = "sample_date/date",
      analyte = "analyte",
      cas = "cas",
      result_value = "result_value",
      unit = "result_unit",
      qualifier = "qualifier",
      mdl = "mdl",
      rl = "rl",
      detect_flag = "detect_flag",
      state = "state",
      county = "county",
      region = "region",
      facility_water_type = "FacilityWaterType",
      sample_point_type = "SamplePointType",
      method_id = "MethodID",
      collection_year = "CollectionYear",
      collection_month = "CollectionMonth",
      pws_size = "PWSSize",
      facility_id = "FacilityID",
      sample_point_id = "SamplePointID",
      latitude = "latitude",
      longitude = "longitude",
      health_endpoint = "health_endpoint",
      health_value = "health_value"
    )
    aliases <- list(
      source_dataset = c("source_dataset", "source dataset", "dataset", "source", "source_name"),
      sample_id = c("sample_id", "sample id", "sample", "id", "seqn", "station", "pwsid", "pws_id", "samplepointid"),
      matrix = c("matrix", "sample_matrix", "sample type"),
      date = c("sample_date", "sample date", "collection_date", "collection date", "date"),
      analyte = c("analyte", "analyte_name", "parameter", "parameter_name", "constituent", "contaminant", "chemical", "chemical_name", "compound"),
      cas = c("cas", "casrn", "cas_number"),
      result_value = c(
        "result_value", "result value", "result", "result_clean", "resultclean", "result_ngl", "result ngl",
        "concentration", "concentration_ng_l", "concentration_ngl", "value", "value_ngl", "reported", "reported_result"
      ),
      unit = c("result_unit", "result unit", "unit", "units", "uom"),
      qualifier = c("qualifier", "flag", "result_flag", "censor"),
      mdl = c("mdl", "method_detection_limit", "detection_limit"),
      rl = c("rl", "reporting_limit", "report_limit"),
      detect_flag = c("detect_flag", "detect", "detected"),
      state = c("state", "state_abbr"),
      county = c("county"),
      region = c("region"),
      facility_water_type = c("facilitywatertype", "facility_water_type"),
      sample_point_type = c("samplepointtype", "sample_point_type"),
      method_id = c("methodid", "method_id"),
      collection_year = c("collectionyear", "collection_year", "year"),
      collection_month = c("collectionmonth", "collection_month", "month"),
      pws_size = c("pwssize", "pws_size"),
      facility_id = c("facilityid", "facility_id"),
      sample_point_id = c("samplepointid", "sample_point_id"),
      latitude = c("latitude", "lat"),
      longitude = c("longitude", "lon", "lng"),
      health_endpoint = c("health_endpoint", "endpoint"),
      health_value = c("health_value")
    )
    guessed <- setNames(lapply(fields, function(k) choose_col(k, aliases[[k]] %||% k)), fields)
    # Schema-specific fallback for common GAMA/GM-style exports (case-insensitive).
    col_by_norm <- function(nm) {
      hit <- which(norm_name(cols) == norm_name(nm))
      if (length(hit) > 0) cols[[hit[[1]]]] else ""
    }
    if (!nzchar(guessed$analyte)) {
      x <- col_by_norm("gm_chemical_name")
      if (nzchar(x)) guessed$analyte <- x
    }
    if (!nzchar(guessed$result_value)) {
      x <- col_by_norm("gm_result")
      if (nzchar(x) && !isTRUE(is_bad_result_col(x))) guessed$result_value <- x
    }
    if (!nzchar(guessed$sample_id)) {
      x <- col_by_norm("gm_well_id")
      if (nzchar(x)) guessed$sample_id <- x
    }
    if (!nzchar(guessed$state)) {
      x <- col_by_norm("gm_state")
      if (!nzchar(x)) x <- col_by_norm("state")
      if (nzchar(x)) guessed$state <- x
    }
    if (!nzchar(guessed$unit)) {
      x <- col_by_norm("gm_result_unit")
      if (nzchar(x)) guessed$unit <- x
    }
    if (!nzchar(guessed$qualifier)) {
      x <- col_by_norm("gm_result_modifier")
      if (nzchar(x)) guessed$qualifier <- x
    }
    # If analyte column name isn't obvious, infer from PFAS-like values in character columns.
    if (!nzchar(guessed$analyte)) {
      char_cols <- cols[vapply(df, function(col) is.character(col) || is.factor(col), logical(1))]
      if (length(char_cols) > 0) {
        hit_counts <- vapply(char_cols, function(cn) sum(pfas_like(df[[cn]]), na.rm = TRUE), integer(1))
        if (length(hit_counts) > 0 && max(hit_counts, na.rm = TRUE) >= 2) {
          guessed$analyte <- char_cols[[which.max(hit_counts)]]
        }
      }
    }
    # If result column name isn't obvious, infer first numeric-like column not used as analyte.
    if (!nzchar(guessed$result_value)) {
      candidate_cols <- setdiff(cols, guessed$analyte)
      if (length(candidate_cols) > 0) {
        candidate_cols <- candidate_cols[!vapply(candidate_cols, is_bad_result_col, logical(1))]
        numeric_like <- vapply(candidate_cols, function(cn) sum(!is.na(parse_num(df[[cn]])), na.rm = TRUE), integer(1))
        if (length(numeric_like) > 0 && max(numeric_like, na.rm = TRUE) >= 1) {
          guessed$result_value <- candidate_cols[[which.max(numeric_like)]]
        } else {
          # Final fallback: choose column with highest count of numeric-like tokens.
          token_like <- vapply(candidate_cols, function(cn) {
            vals <- as.character(df[[cn]])
            sum(safe_detect(vals, "[-+]?[0-9]*\\.?[0-9]+"), na.rm = TRUE)
          }, integer(1))
          if (length(token_like) > 0 && max(token_like, na.rm = TRUE) >= 1) {
            guessed$result_value <- candidate_cols[[which.max(token_like)]]
          }
        }
      }
    }
    # Never auto-select identifier-like columns as result_value (e.g., PWSID may parse as numeric).
    if (nzchar(guessed$result_value %||% "") && isTRUE(is_identifier_like_result_col(guessed$result_value))) {
      guessed$result_value <- ""
    }
    tagList(
      tags$h4("Column mapping"),
      lapply(fields, function(k) {
        selected_now <- input[[paste0("map_", k)]] %||% ""
        # Auto-correct clearly wrong sticky mappings for key fields.
        if (identical(k, "result_value")) {
          if (nzchar(selected_now) && isTRUE(is_identifier_like_result_col(selected_now))) {
            selected_now <- ""
          }
          bad_result_pick <- safe_detect(
            tolower(selected_now),
            "modifier|qualifier|flag|vvl|tract|population|geoid|zip"
          )
          if (isTRUE(bad_result_pick)) selected_now <- ""
        }
        if (identical(k, "analyte")) {
          bad_analyte_pick <- safe_detect(
            tolower(selected_now),
            "modifier|qualifier|result|value|vvl|id|code|tract|population|geoid|zip"
          )
          if (isTRUE(bad_analyte_pick)) selected_now <- ""
        }
        if (identical(k, "sample_id")) {
          bad_sample_pick <- safe_detect(
            tolower(selected_now),
            "pesticide|contaminant|chemical|analyte|result|value|tract|population|geoid|zip"
          )
          if (isTRUE(bad_sample_pick)) selected_now <- ""
        }
        if (!nzchar(selected_now) || !(selected_now %in% cols)) {
          g <- guessed[[k]] %||% ""
          if (identical(k, "result_value")) {
            if (nzchar(g) && !isTRUE(is_identifier_like_result_col(g)) && !isTRUE(is_bad_result_col(g))) {
              selected_now <- g
            } else {
              selected_now <- ""
            }
          } else {
            selected_now <- g
          }
        }
        selectInput(paste0("map_", k), labels[[k]], choices = opts, selected = selected_now)
      })
    )
  })

  observeEvent(input$map_result_value, {
    rv <- trimws(as.character(input$map_result_value %||% ""))
    if (!nzchar(rv)) return(invisible(NULL))
    if (!isTRUE(is_identifier_like_result_col(rv))) return(invisible(NULL))
    updateSelectInput(session, "map_result_value", selected = "")
    showNotification(
      "result_value reset: that column is identifier-like (not a PFAS measurement). Pick a numeric result column.",
      type = "warning",
      duration = 8
    )
  }, ignoreNULL = TRUE)

  output$pfas_python_status <- renderPrint({
    py_exec_raw <- trimws(input$pfas_python_exec %||% "")
    if (!nzchar(py_exec_raw)) {
      cat("Python path is empty.\n")
      return(invisible(NULL))
    }
    py_exec <- resolve_python_exec(py_exec_raw)
    exists_exec <- nzchar(py_exec)
    cat("Configured path:", py_exec_raw, "\n")
    cat("Exists:", if (exists_exec) "yes" else "no", "\n")
    if (!exists_exec) {
      cat("Python is not available in this runtime.\n")
      cat("For hosted server: run step 9 (Train PFAS Exceedance Model) locally and redeploy results/ artifacts.\n")
      return(invisible(NULL))
    }
    ver <- tryCatch(
      system2(py_exec, args = "--version", stdout = TRUE, stderr = TRUE),
      error = function(e) {
        paste("ERROR:", conditionMessage(e))
      }
    )
    if (length(ver) > 0) cat(paste(ver, collapse = "\n"), "\n")
  })

  intake_api_health <- reactiveVal(check_intake_api_health(LINK_DATASET_FORM, PFAS_INTAKE_STAGING_TOKEN))

  output$intake_api_health_status <- renderPrint({
    h <- intake_api_health()
    cat("Status:", h$summary, "\n")
    cat("Endpoint:", h$endpoint, "\n")
    cat("Detail:", h$detail, "\n")
    cat("Smoke test:", h$smoke$summary, "\n")
    if (!is.null(h$smoke$http_status) && !is.na(h$smoke$http_status)) {
      cat("Smoke HTTP status:", h$smoke$http_status, "\n")
    }
    cat("Smoke detail:", h$smoke$detail, "\n")
    cat("Checked:", h$checked_at, "\n")
  })
  
  compound_choices <- reactive({
    df <- safe_table("compound_registry")
    if (nrow(df) == 0) return(setNames("", "No compounds yet"))
    setNames(df$compound_id, paste(df$compound_name, df$compound_id, sep = " | "))
  })
  
  sample_choices <- reactive({
    df <- safe_table("sample_registry")
    if (nrow(df) == 0) return(setNames("", "No samples yet"))
    setNames(df$sample_id, paste(df$sample_id, df$matrix, sep = " | "))
  })
  
  output$compound_select_ui <- renderUI({
    selectInput("measurement_compound_id", "Compound", choices = compound_choices())
  })
  
  output$sample_select_ui <- renderUI({
    selectInput("measurement_sample_id", "Sample", choices = sample_choices())
  })
  
  output$label_compound_select_ui <- renderUI({
    selectInput("label_compound_id", "Compound", choices = compound_choices())
  })
  
  observeEvent(input$save_compound, {
    req(input$compound_name, input$smiles, input$compound_created_by)
    
    existing <- safe_table("compound_registry")
    dup <- existing |>
      dplyr::filter(
        tolower(compound_name) == tolower(input$compound_name) |
          (!is.na(smiles) & smiles == input$smiles) |
          (!is.na(cas) & cas == input$cas & input$cas != "")
      )
    
    if (nrow(dup) > 0) {
      showNotification("Possible duplicate compound found. Review before saving.", type = "warning")
      return(NULL)
    }
    
    compound_id <- make_id("CMP")
    
    compound_row <- tibble::tibble(
      compound_id = compound_id,
      compound_name = input$compound_name,
      smiles = input$smiles,
      cas = input$cas,
      pfas_subclass = input$pfas_subclass,
      source_type = input$source_type,
      source_reference = input$source_reference,
      created_at = as.character(Sys.time()),
      created_by = input$compound_created_by,
      review_status = input$compound_review_status
    )
    
    DBI::dbWriteTable(con, "compound_registry", compound_row, append = TRUE)
    write_audit("compound", compound_id, "create", input$compound_created_by, "Compound saved")
    showNotification("Compound saved.", type = "message")
  })
  
  observeEvent(input$save_sample, {
    req(input$sample_id, input$matrix)
    
    existing <- safe_table("sample_registry")
    if (input$sample_id %in% existing$sample_id) {
      showNotification("Sample ID already exists.", type = "error")
      return(NULL)
    }
    
    sample_row <- tibble::tibble(
      sample_id = input$sample_id,
      project_id = input$project_id,
      client_id = input$client_id,
      matrix = input$matrix,
      sample_type = input$sample_type,
      collection_date = as.character(input$collection_date),
      batch_id = input$batch_id,
      instrument_id = input$instrument_id,
      method_id = input$method_id,
      operator = input$operator,
      notes = input$sample_notes
    )
    
    DBI::dbWriteTable(con, "sample_registry", sample_row, append = TRUE)
    write_audit("sample", input$sample_id, "create", input$operator %||% "unknown", "Sample saved")
    showNotification("Sample saved.", type = "message")
  })
  
  observeEvent(input$save_measurement, {
    req(input$measurement_compound_id, input$measurement_sample_id, input$measurement_created_by)
    
    measurement_id <- make_id("MSR")
    
    measurement_row <- tibble::tibble(
      measurement_id = measurement_id,
      compound_id = input$measurement_compound_id,
      sample_id = input$measurement_sample_id,
      retention_time = input$retention_time,
      precursor_mz = input$precursor_mz,
      product_mz = input$product_mz,
      peak_area = input$peak_area,
      signal_to_noise = input$signal_to_noise,
      concentration = input$concentration,
      concentration_unit = input$concentration_unit,
      lod = input$lod,
      loq = input$loq,
      internal_standard = input$internal_standard,
      result_flag = input$result_flag,
      qc_flag = input$qc_flag,
      created_at = as.character(Sys.time()),
      created_by = input$measurement_created_by
    )
    
    DBI::dbWriteTable(con, "analytical_measurements", measurement_row, append = TRUE)
    write_audit("measurement", measurement_id, "create", input$measurement_created_by, "Measurement saved")
    showNotification("Measurement saved.", type = "message")
  })
  
  observeEvent(input$save_label, {
    req(input$label_compound_id, input$endpoint, input$label_value, input$curator)
    
    existing <- safe_table("endpoint_labels")
    dup <- existing |>
      dplyr::filter(
        compound_id == input$label_compound_id,
        endpoint == input$endpoint
      )
    
    if (nrow(dup) > 0) {
      showNotification("A label for this compound + endpoint already exists.", type = "error")
      return(NULL)
    }
    
    label_id <- make_id("LBL")
    
    label_row <- tibble::tibble(
      label_id = label_id,
      compound_id = input$label_compound_id,
      endpoint = input$endpoint,
      label_value = as.integer(input$label_value),
      label_source = input$label_source,
      assay_id = input$assay_id,
      source_reference = input$label_reference,
      confidence_score = input$confidence_score,
      curator = input$curator,
      review_status = input$label_review_status,
      notes = input$label_notes,
      created_at = as.character(Sys.time())
    )
    
    DBI::dbWriteTable(con, "endpoint_labels", label_row, append = TRUE)
    write_audit("label", label_id, "create", input$curator, "Endpoint label saved")
    showNotification("Label saved.", type = "message")
  })
  
  recent_entries <- reactive({
    compounds_df <- safe_table("compound_registry") |> dplyr::mutate(entry_type = "compound")
    samples_df <- safe_table("sample_registry") |> dplyr::mutate(entry_type = "sample")
    labels_df <- safe_table("endpoint_labels") |> dplyr::mutate(entry_type = "label")
    measurements_df <- safe_table("analytical_measurements") |> dplyr::mutate(entry_type = "measurement")
    
    bind_rows(
      compounds_df |> dplyr::select(entry_type, created_at, dplyr::everything()),
      samples_df |> dplyr::mutate(created_at = collection_date) |> dplyr::select(entry_type, created_at, dplyr::everything()),
      labels_df |> dplyr::select(entry_type, created_at, dplyr::everything()),
      measurements_df |> dplyr::select(entry_type, created_at, dplyr::everything())
    ) |>
      dplyr::arrange(dplyr::desc(created_at))
  })
  
  ml_export <- reactive({
    compounds_df <- safe_table("compound_registry")
    labels_df <- safe_table("endpoint_labels")
    measurements_df <- safe_table("analytical_measurements")
    samples_df <- safe_table("sample_registry")
    
    if (nrow(compounds_df) == 0 || nrow(labels_df) == 0) return(tibble::tibble())
    
    labels_df <- labels_df |>
      dplyr::filter(review_status == "approved")
    
    compounds_df <- compounds_df |>
      dplyr::filter(review_status == "approved")
    
    labels_df |>
      dplyr::inner_join(compounds_df, by = "compound_id") |>
      dplyr::left_join(measurements_df, by = "compound_id") |>
      dplyr::left_join(samples_df, by = "sample_id") |>
      dplyr::select(
        compound_id, compound_name, smiles, cas, pfas_subclass,
        matrix, sample_type, retention_time, precursor_mz, product_mz,
        peak_area, signal_to_noise, concentration, concentration_unit,
        lod, loq, internal_standard,
        endpoint, label_value, label_source, confidence_score,
        review_status, source_type, source_reference
      )
  })
  
  output$tbl_system_readiness <- renderDT(render_dt(system_readiness, 10))
  output$tbl_oecd_home <- renderDT(render_dt(oecd_checklist, 5))
  output$tbl_dataset_registry <- renderDT(render_dt(dataset_registry, 8))
  output$tbl_endpoint_definitions <- renderDT(render_dt(endpoint_definitions, 6))
  output$tbl_proxy_assays <- renderDT(render_dt(proxy_assay_table, 6))
  output$tbl_descriptor_schema <- renderDT(render_dt(descriptor_schema, 10))
  output$tbl_fingerprint_schema <- renderDT(render_dt(fingerprint_schema, 5))
  output$tbl_structural_alerts <- renderDT(render_dt(structural_alert_table, 8))
  output$tbl_compounds <- renderDT(render_dt(compounds, 8))
  output$tbl_model_registry <- renderDT(render_dt(model_registry, 8))
  output$tbl_baseline_comparison <- renderDT(render_dt(baseline_comparison, 8))
  output$tbl_hyperparameters <- renderDT(render_dt(hyperparameter_summary, 10))
  output$tbl_validation_summary <- renderDT(render_dt(validation_summary, 8))
  output$tbl_error_buckets <- renderDT(render_dt(error_buckets, 8))
  output$tbl_performance_metrics <- renderDT(render_dt(performance_metrics, 8))
  output$tbl_predictions <- renderDT(render_dt(predictions, 10))

  # Enterprise 5.0 — cloud screening API (FastAPI /predict; see PFAS_API_URL)
  e5_api_last <- reactiveVal(NULL)
  observeEvent(input$e5_run, {
    req(auth$user)
    api_base <- trimws(Sys.getenv("PFAS_API_URL", PFAS_API_URL))
    api_base <- sub("/+$", "", api_base)
    payload <- list(
      sample_id = input$e5_sample_id,
      dtxsid = input$e5_dtxsid,
      method_id = input$e5_method_id,
      matrix = input$e5_matrix
    )
    res <- tryCatch(
      httr::POST(
        paste0(api_base, "/predict"),
        body = payload,
        encode = "json",
        httr::content_type_json(),
        httr::timeout(45)
      ),
      error = function(e) {
        list(error = TRUE, message = conditionMessage(e))
      }
    )
    if (isTRUE(res$error)) {
      e5_api_last(list(status = 0L, text = "", err = res$message, parsed = NULL))
      showNotification(res$message, type = "error")
      return(invisible(NULL))
    }
    sc <- httr::status_code(res)
    txt <- tryCatch(httr::content(res, "text", encoding = "UTF-8"), error = function(e) "")
    parsed <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)
    e5_api_last(list(status = sc, text = txt, err = NULL, parsed = parsed))
    if (sc < 400) {
      write_audit(
        "cloud_api_predict",
        as.character(input$e5_sample_id %||% "unknown"),
        "screening_request",
        op_id(),
        paste0("Enterprise 5.0 POST /predict (", api_base, ")"),
        details = list(
          dtxsid = input$e5_dtxsid,
          method_id = input$e5_method_id,
          matrix = input$e5_matrix,
          run_id = if (!is.null(parsed)) parsed$run_id else NA_character_
        )
      )
    } else {
      showNotification(paste0("API HTTP ", sc), type = "warning")
    }
  }, ignoreInit = TRUE)

  output$e5_result <- renderPrint({
    r <- e5_api_last()
    req(r)
    if (!is.null(r$err)) {
      cat("Request failed: ", r$err, "\n", sep = "")
      return(invisible(NULL))
    }
    if (r$status >= 400) {
      cat("HTTP ", r$status, "\n", r$text, "\n", sep = "")
      return(invisible(NULL))
    }
    p <- r$parsed
    if (is.null(p)) {
      cat(r$text)
      return(invisible(NULL))
    }
    keep <- c("run_id", "prediction", "confidence", "ad_warning", "intended_use")
    show <- p[intersect(keep, names(p))]
    print(show)
  })

  output$e5_sustainability <- renderPrint({
    r <- e5_api_last()
    req(r)
    p <- r$parsed
    if (is.null(p)) {
      cat("(no parsed response)\n")
      return(invisible(NULL))
    }
    if (!is.null(p$sustainability)) {
      print(p$sustainability)
    } else {
      cat("(no sustainability block)\n")
    }
  })

  output$e5_raw <- renderPrint({
    r <- e5_api_last()
    req(r)
    if (nzchar(r$text %||% "")) {
      cat(r$text)
    } else if (!is.null(r$err)) {
      cat(r$err)
    } else {
      cat("(empty)\n")
    }
  })

  output$tbl_ad_registry <- renderDT(render_dt(ad_registry, 8))
  output$tbl_ad_summary <- renderDT(render_dt(compound_ad_summary, 10))
  output$tbl_analog_support <- renderDT(render_dt(analog_support, 8))
  output$tbl_mechanistic_rationale <- renderDT(render_dt(mechanistic_rationale, 8))
  output$tbl_woe <- renderDT(render_dt(weight_of_evidence, 10))
  output$tbl_oecd_checklist <- renderDT(render_dt(oecd_checklist, 8))
  output$tbl_model_cards <- renderDT(render_dt(model_cards, 8))
  output$pfas_metrics_status <- renderPrint({
    pfas_results_nonce()
    m <- read_results_json("nhanes_model_metrics.json")
    task_counts <- read_training_csv("model_matrix_task_counts.csv")

    matrix_n_train <- NA_integer_
    matrix_n_test <- NA_integer_
    if (!is.null(task_counts) && nrow(task_counts) > 0) {
      matrix_n_train <- as.integer(sum(suppressWarnings(as.numeric(task_counts$rows_train)), na.rm = TRUE))
      matrix_n_test <- as.integer(sum(suppressWarnings(as.numeric(task_counts$rows_test)), na.rm = TRUE))
    }

    metrics_n_train <- if (!is.null(m) && !is.null(m$n_train)) {
      suppressWarnings(as.integer(m$n_train))
    } else {
      NA_integer_
    }
    metrics_n_test <- if (!is.null(m) && !is.null(m$n_test)) {
      suppressWarnings(as.integer(m$n_test))
    } else {
      NA_integer_
    }

    # Prefer counts from nhanes_model_metrics.json — they match accuracy/AUC/confusion_matrix_0_1.
    # Summed model_matrix_task_counts.csv can reflect a broader multi-task matrix than the sklearn hold-out slice.
    show_n_train <- if (!is.na(metrics_n_train)) metrics_n_train else matrix_n_train
    show_n_test <- if (!is.na(metrics_n_test)) metrics_n_test else matrix_n_test

    if (!is.na(show_n_train)) cat("n_train:", show_n_train, "\n")
    if (!is.na(show_n_test)) cat("n_test :", show_n_test, "\n")
    if (
      !is.na(metrics_n_train) && !is.na(matrix_n_train) &&
        (!is.na(matrix_n_test) && !is.na(metrics_n_test)) &&
        (metrics_n_train != matrix_n_train || metrics_n_test != matrix_n_test)
    ) {
      cat(
        "Note: model_matrix_task_counts.csv totals (train:",
        matrix_n_train,
        ", test:",
        matrix_n_test,
        ") differ from the evaluation split above.\n"
      )
    }

    if (is.null(m) && is.na(matrix_n_train) && is.na(matrix_n_test)) {
      cat("No PFAS exceedance model metrics found.\nRun: python scripts/train_pfas_model.py\n")
      return(invisible(NULL))
    }

    if (!is.null(m)) {
      if (is.null(m$group_split_enabled)) {
        cat("WARNING: Legacy metrics artifact detected (no anti-leakage metadata).\n")
        cat("Re-run: 9) Train PFAS Exceedance Model to generate group-split validated metrics.\n\n")
      }
      # Accuracy/AUC are produced by Python metrics; keep showing them when available.
      if (!is.null(m$accuracy)) cat("accuracy:", round(as.numeric(m$accuracy), 4), "\n")
      if (!is.null(m$auc)) cat("auc     :", round(as.numeric(m$auc), 4), "\n")
      if (!is.null(m$group_split_enabled)) cat("group_split_enabled:", as.logical(m$group_split_enabled), "\n")
      if (!is.null(m$group_overlap_count)) cat("group_overlap_count :", as.integer(m$group_overlap_count), "\n")
      if (!is.null(m$min_recall_positive_cli) && is.finite(suppressWarnings(as.numeric(m$min_recall_positive_cli)))) {
        cat("min_recall_positive (CLI):", m$min_recall_positive_cli, "\n")
      }
      cat_iso_holdout_metrics(m$iso_holdout_metrics, n_test_align = m$n_test)
      sint <- trimws(as.character(m$screening_interpretation %||% ""))
      if (nzchar(sint)) {
        cat("\nInterpretation: ", sint, "\n", sep = "")
      }
      print_holdout_probability_debug(m$holdout_probability_debug)
      if (!is.null(m$leakage_warnings) && length(m$leakage_warnings) > 0) {
        cat("leakage_warnings:\n")
        for (w in m$leakage_warnings) cat(" -", as.character(w), "\n")
      }
      if (!is.null(m$auc_note)) cat("note    :", m$auc_note, "\n")
      if (!is.null(m$confusion_matrix_0_1)) {
        cat("\nconfusion_matrix_0_1:\n")
        print(m$confusion_matrix_0_1)
      }
    }

    metrics_path <- file.path(PROJECT_DIR, "results", "nhanes_model_metrics.json")
    matrix_counts_path <- file.path(PROJECT_DIR, "data", "training", "model_matrix_task_counts.csv")
    if (file.exists(matrix_counts_path) && file.exists(metrics_path)) {
      mt_metrics <- file.info(metrics_path)$mtime
      mt_matrix <- file.info(matrix_counts_path)$mtime
      if (is.finite(as.numeric(mt_metrics)) && is.finite(as.numeric(mt_matrix)) && mt_matrix > mt_metrics) {
        cat("\nNote: matrix counts are newer than Python metrics.\n")
      }
    }
  })

  output$pfas_label_integrity_banner <- renderUI({
    pfas_results_nonce()
    rep <- read_label_integrity_report_payload()
    show_big <- isTRUE(rep$show_prominent_operator_warning)
    txt <- trimws(rep$prominent_operator_warning %||% "")
    if (!nzchar(txt)) {
      txt <- paste0(
        "Label integrity warning: This model used incomplete or placeholder PFAS limit data. ",
        "Predictions are suitable only for screening/development, not compliance or ISO 17025 decision-making."
      )
    }
    if (show_big) {
      tags$div(class = "alert alert-warning", style = "font-weight:600;", txt)
    } else if (!is.null(rep) && length(rep$warnings %||% character(0)) > 0L) {
      tags$div(
        class = "alert alert-info",
        "Review ",
        tags$code("results/label_integrity_report.json"),
        " — advisory warnings were emitted during training."
      )
    } else {
      invisible(NULL)
    }
  })

  output$pfas_label_integrity_summary <- renderPrint({
    pfas_results_nonce()
    a <- read_label_derivation_audit_payload()
    st <- reconciliation_dataset_builder_stages()
    dropped <- NA_real_
    if (!is.null(st) && !is.null(st$rows_dropped_no_usable_limit_or_result)) {
      dropped <- suppressWarnings(as.numeric(st$rows_dropped_no_usable_limit_or_result[[1]]))
    }
    if (is.null(a)) {
      cat("No results/label_derivation_audit.json yet.\n")
      cat("Run step 9 (Train PFAS Exceedance Model); requires train script v3.2.4+.\n")
      return(invisible(NULL))
    }
    cat("Train script (audit): ", a$train_script_version %||% "?", "\n", sep = "")
    cat("missing_limit_after_join:", a$missing_limit_after_join %||% NA, "\n")
    if (is.finite(dropped)) {
      cat("rows_dropped_no_usable_limit_or_result:", dropped, "\n")
    } else {
      cat("rows_dropped_no_usable_limit_or_result: (open python_training_row_reconciliation.json)\n")
    }
    pr <- suppressWarnings(as.numeric(a$positive_rate_after_derive))
    cat("positive_rate_after_derive:", if (is.finite(pr)) format(pr, digits = 10) else "NA", "\n")
    ta <- a$top_analytes_missing_limit_among_rows_with_result
    cat("\nTop analytes missing limit (first 15 of audit histogram):\n")
    if (is.null(ta) || length(ta) == 0L) {
      cat(" — none —\n")
    } else {
      nm <- names(ta)
      vv <- unlist(ta, use.names = FALSE)
      n_show <- min(15L, length(vv))
      if (length(nm) != length(vv)) {
        cat(" — (malformed histogram in JSON) —\n")
      } else {
        for (i in seq_len(n_show)) {
          cat(sprintf("  %s : %s\n", nm[[i]], as.character(vv[[i]])))
        }
        if (length(vv) > n_show) {
          cat(sprintf(" ... %d more rows in JSON\n", length(vv) - n_show))
        }
      }
    }
    cat(
      "\nIf missing limits or drops are large relative to ingest, labels may not reflect real regulatory comparisons.\n",
      "Do not treat placeholder limits in data/config/pfas_regulatory_limits.csv as compliance MCLs.\n"
    )
  })

  output$tbl_pfas_label_integrity_missing <- renderDT({
    pfas_results_nonce()
    a <- read_label_derivation_audit_payload()
    ta <- if (!is.null(a)) a$top_analytes_missing_limit_among_rows_with_result else NULL
    if (is.null(ta) || length(ta) == 0L) {
      return(DT::datatable(tibble::tibble(note = "No histogram in label_derivation_audit.json yet."), rownames = FALSE))
    }
    nm <- names(ta)
    vv <- suppressWarnings(as.integer(unlist(ta, use.names = FALSE)))
    df <- tibble::tibble(normalized_analyte = nm, rows_missing_limit = vv)
    df <- df[order(-df$rows_missing_limit), , drop = FALSE]
    DT::datatable(df, rownames = FALSE, options = list(pageLength = 15L, scrollX = TRUE))
  })

  render_task_metrics <- function(task_key) {
    pfas_results_nonce()
    m <- read_results_json("nhanes_model_metrics_by_task.json")
    if (is.null(m) || is.null(m[[task_key]])) {
      cat("No metrics yet.\nRun: 9) Train PFAS Exceedance Model\n")
      return(invisible(NULL))
    }
    t <- m[[task_key]]
    if (!is.null(t$n_train)) cat("n_train:", t$n_train, "\n")
    if (!is.null(t$n_test)) cat("n_test :", t$n_test, "\n")
    if (!is.null(t$accuracy)) cat("accuracy:", round(as.numeric(t$accuracy), 4), "\n")
    if (!is.null(t$auc)) cat("auc     :", round(as.numeric(t$auc), 4), "\n")
    if (!is.null(t$auc_note)) cat("note    :", t$auc_note, "\n")
    cat_iso_holdout_metrics(t$iso_holdout_metrics, n_test_align = t$n_test)
    sint_t <- trimws(as.character(t$screening_interpretation %||% ""))
    if (nzchar(sint_t)) {
      cat("\nInterpretation: ", sint_t, "\n", sep = "")
    }
  }

  output$pfas_task_human_status <- renderPrint({
    render_task_metrics("task_human_health")
  })
  output$pfas_task_environment_status <- renderPrint({
    render_task_metrics("task_environmental_occurrence")
  })
  output$pfas_task_facility_status <- renderPrint({
    render_task_metrics("task_facility_risk_enrichment")
  })
  output$tbl_pfas_task_comparison <- renderDT({
    pfas_results_nonce()
    m <- read_results_json("nhanes_model_metrics_by_task.json")
    if (is.null(m) || length(m) == 0) {
      return(DT::datatable(
        tibble::tibble(note = "No per-task metrics found. Run: 9) Train PFAS Exceedance Model"),
        rownames = FALSE
      ))
    }

    task_keys <- names(m)
    labels <- c(
      task_human_health = "Human Health",
      task_environmental_occurrence = "Environmental Occurrence",
      task_facility_risk_enrichment = "Facility Risk Enrichment"
    )
    rows <- lapply(task_keys, function(k) {
      x <- m[[k]]
      im <- x$iso_holdout_metrics
      rec1 <- NA_real_
      prec1 <- NA_real_
      f10k <- NA_real_
      if (is.list(im) && is.null(im$error)) {
        rv <- suppressWarnings(as.numeric(unlist(im$recall_positive, use.names = FALSE)))
        if (length(rv) >= 1L && is.finite(rv[[1]])) rec1 <- round(rv[[1]], 4)
        pv <- suppressWarnings(as.numeric(unlist(im$precision_positive, use.names = FALSE)))
        if (length(pv) >= 1L && is.finite(pv[[1]])) prec1 <- round(pv[[1]], 4)
        fv <- suppressWarnings(as.numeric(unlist(im$flags_per_10k_holdout, use.names = FALSE)))
        if (length(fv) >= 1L && is.finite(fv[[1]])) {
          f10k <- round(fv[[1]], 2)
        } else {
          tpv <- suppressWarnings(as.numeric(unlist(im$tp, use.names = FALSE)))
          fpv <- suppressWarnings(as.numeric(unlist(im$fp, use.names = FALSE)))
          csv <- suppressWarnings(as.numeric(unlist(im$cm_sum, use.names = FALSE)))
          if (length(tpv) >= 1L && length(fpv) >= 1L && length(csv) >= 1L) {
            pred_pos <- as.integer(round(tpv[[1]]) + round(fpv[[1]]))
            cs <- as.integer(round(csv[[1]]))
            if (!is.na(cs) && cs > 0L && !is.na(pred_pos)) {
              f10k <- round(pred_pos / cs * 10000, 2)
            }
          }
        }
      }
      tibble::tibble(
        task = unname(labels[k] %||% k),
        auc = (if (!is.null(x$auc)) round(as.numeric(x$auc), 4) else NA_real_),
        accuracy = (if (!is.null(x$accuracy)) round(as.numeric(x$accuracy), 4) else NA_real_),
        recall_pos = rec1,
        precision_pos = prec1,
        flags_per_10k_holdout = f10k,
        n_train = (if (!is.null(x$n_train)) as.integer(x$n_train) else NA_integer_),
        n_test = (if (!is.null(x$n_test)) as.integer(x$n_test) else NA_integer_)
      )
    })
    df <- dplyr::bind_rows(rows)
    render_dt(df, 10)
  })
  output$pfas_target_status <- renderPrint({
    pfas_results_nonce()
    p <- read_training_json("pfas_training_target_progress.json")
    if (is.null(p)) {
      cat("No target progress file found.\nRun: 3) Build multi-source training table\n")
      return(invisible(NULL))
    }
    fmt_int <- function(x) {
      xv <- suppressWarnings(as.numeric(x))
      if (!is.finite(xv)) return(as.character(x))
      format(xv, big.mark = ",", scientific = FALSE, trim = TRUE)
    }
    fmt_pct <- function(x) {
      xv <- suppressWarnings(as.numeric(x))
      if (!is.finite(xv)) return(as.character(x))
      digits <- if (xv < 1) 6 else 2
      paste0(formatC(xv, format = "f", digits = digits), "%")
    }
    if (!is.null(p$current_rows) && !is.null(p$target_rows)) {
      cat("Rows:", fmt_int(p$current_rows), "/", fmt_int(p$target_rows), "\n")
    }
    if (!is.null(p$pct_of_target_raw)) {
      cat("Percent:", fmt_pct(p$pct_of_target_raw), "\n")
    } else if (!is.null(p$pct_of_target)) {
      cat("Percent:", fmt_pct(p$pct_of_target), "\n")
    }
    if (!is.null(p$rows_remaining)) cat("Rows remaining:", fmt_int(p$rows_remaining), "\n")
    if (!is.null(p$rows_above_target) && isTRUE(as.numeric(p$rows_above_target) > 0)) {
      cat("Rows above target:", fmt_int(p$rows_above_target), "\n")
    }
    if (!is.null(p$generated_at_utc)) cat("Generated at (UTC):", p$generated_at_utc, "\n")
  })
  output$pfas_last_training_status <- renderPrint({
    pfas_results_nonce()
    res_dir <- file.path(PROJECT_DIR, "results")
    if (!dir.exists(res_dir)) {
      cat("No results directory found.\n")
      return(invisible(NULL))
    }

    primary <- c(
      "nhanes_model_metrics.json",
      "nhanes_model_metrics_by_task.json",
      "nhanes_feature_importance.csv",
      "nhanes_test_predictions.csv"
    )
    primary_paths <- file.path(res_dir, primary)
    existing_primary <- primary_paths[file.exists(primary_paths)]

    task_metric_files <- list.files(
      res_dir,
      pattern = "^nhanes_model_metrics_task_.*\\.json$",
      full.names = TRUE
    )

    all_files <- c(existing_primary, task_metric_files)
    if (length(all_files) == 0) {
      cat("No training artifacts found in results/.\n")
      cat("Run local step 9 (Train PFAS Exceedance Model) and redeploy results artifacts.\n")
      return(invisible(NULL))
    }

    fi <- file.info(all_files)
    mt <- fi$mtime
    idx <- which.max(mt)
    newest <- all_files[[idx]]
    newest_time <- mt[[idx]]
    age_mins <- as.numeric(difftime(Sys.time(), newest_time, units = "mins"))
    freshness <- if (is.finite(age_mins) && age_mins <= 60) {
      "fresh (<= 60 min)"
    } else if (is.finite(age_mins) && age_mins <= 24 * 60) {
      "recent (<= 24 h)"
    } else {
      "stale (> 24 h)"
    }

    cat("Newest artifact:", basename(newest), "\n")
    cat("Modified (local server time):", format(newest_time, "%Y-%m-%d %H:%M:%S"), "\n")
    cat("Age (minutes):", round(age_mins, 1), "\n")
    cat("Freshness:", freshness, "\n")
    cat("Artifacts detected:", length(all_files), "\n")
  })
  output$tbl_task_row_availability <- renderDT({
    pfas_results_nonce()
    p <- file.path(PROJECT_DIR, "data", "training", "model_matrix_task_counts.csv")
    if (!file.exists(p)) {
      return(DT::datatable(
        tibble::tibble(note = "No task count file yet. Run: 7) Build model matrix"),
        rownames = FALSE
      ))
    }
    df <- tryCatch(read.csv(p, stringsAsFactors = FALSE, check.names = FALSE), error = function(e) NULL)
    if (is.null(df) || nrow(df) == 0) {
      return(DT::datatable(
        tibble::tibble(note = "Task count file is empty. Check upstream source data."),
        rownames = FALSE
      ))
    }
    if (!("task_type" %in% names(df))) {
      return(render_dt(df, 10))
    }
    labels <- c(
      task_human_health = "Human Health",
      task_environmental_occurrence = "Environmental Occurrence",
      task_facility_risk_enrichment = "Facility Risk Enrichment"
    )
    df$task <- ifelse(is.na(labels[df$task_type]), df$task_type, unname(labels[df$task_type]))
    keep <- intersect(c("task", "task_type", "rows_input", "rows_train", "rows_test"), names(df))
    render_dt(df[, keep, drop = FALSE], 10)
  })
  output$tbl_pfas_feature_importance <- renderDT({
    pfas_results_nonce()
    df <- read_results_csv("nhanes_feature_importance.csv")
    if (is.null(df) || nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "Run python scripts/train_pfas_model.py to generate feature importance."), rownames = FALSE))
    }
    if ("feature" %in% names(df)) {
      leak_hits <- safe_detect(
        tolower(as.character(df$feature)),
        "result_value|log_result|analyticalresult|resultngl|resultclean"
      )
      if (any(leak_hits, na.rm = TRUE)) {
        return(DT::datatable(
          tibble::tibble(
            note = "Detected stale leakage-style feature artifacts (result_value/log_result_value). Re-run 9) Train PFAS Exceedance Model after app restart."
          ),
          rownames = FALSE
        ))
      }
    }
    render_dt(df, 10)
  })
  output$tbl_pfas_test_predictions <- renderDT({
    pfas_results_nonce()
    df <- read_results_csv("nhanes_test_predictions.csv")
    if (is.null(df) || nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "Run python scripts/train_pfas_model.py to generate test predictions."), rownames = FALSE))
    }
    render_dt(df, 10)
  })

  get_upload_mapping <- reactive({
    keys <- c(
      "source_dataset", "sample_id", "matrix", "date", "analyte", "cas",
      "result_value", "unit", "qualifier", "mdl", "rl", "detect_flag",
      "state", "county", "region", "facility_water_type", "sample_point_type",
      "method_id", "collection_year", "collection_month", "pws_size", "facility_id", "sample_point_id",
      "latitude", "longitude", "health_endpoint", "health_value"
    )
    vals <- lapply(keys, function(k) input[[paste0("map_", k)]] %||% "")
    names(vals) <- keys
    # Guard against sticky bad picks in UI state.
    if (nzchar(vals$result_value %||% "")) {
      rv <- tolower(trimws(as.character(vals$result_value)))
      if (is_identifier_like_result_col(rv) ||
          safe_detect(rv, "modifier|qualifier|flag|vvl|tract|population|geoid|zip|pesticide|chemical|contaminant|name")) {
        vals$result_value <- ""
      }
    }
    if (nzchar(vals$analyte %||% "")) {
      av <- tolower(vals$analyte)
      if (safe_detect(av, "modifier|qualifier|result|value|vvl|tract|population|geoid|zip")) {
        vals$analyte <- ""
      }
    }
    if (nzchar(vals$sample_id %||% "")) {
      sv <- tolower(vals$sample_id)
      if (safe_detect(sv, "pesticide|contaminant|chemical|analyte|result|value|tract|population|geoid|zip")) {
        vals$sample_id <- ""
      }
    }

    # Backend auto-detect fallback (independent of UI state), case-insensitive.
    df <- external_upload_raw()
    if (!is.null(df) && is.data.frame(df) && ncol(df) > 0) {
      cn <- names(df)
      norm <- function(x) tolower(gsub("[^a-z0-9]+", "", trimws(as.character(x))))
      cn_norm <- norm(cn)
      parse_num <- function(x) {
        y <- trimws(as.character(x))
        y[y %in% c("", "NA", "N/A", "na", "n/a", "NULL", "null")] <- NA_character_
        y <- gsub(",", "", y, fixed = TRUE)
        y <- gsub("^<\\s*", "", y)
        y <- gsub("^>\\s*", "", y)
        direct <- suppressWarnings(as.numeric(y))
        need_extract <- is.na(direct) & !is.na(y) & nzchar(y)
        if (any(need_extract, na.rm = TRUE)) {
          tok <- stringr::str_extract(y[need_extract], "[-+]?[0-9]*\\.?[0-9]+(?:[eE][-+]?[0-9]+)?")
          direct[need_extract] <- suppressWarnings(as.numeric(tok))
        }
        direct
      }
      is_bad_result_col <- function(cname) {
        if (!nzchar(cname) || !(cname %in% cn)) return(TRUE)
        nkey <- norm(cname)
        vals <- as.character(df[[cname]])
        vals <- vals[!is.na(vals)]
        if (length(vals) == 0) return(TRUE)
        vals <- utils::head(vals, 250)
        letter_rate <- mean(safe_detect(vals, "[A-Za-z]"), na.rm = TRUE)
        numeric_rate <- mean(!is.na(parse_num(vals)), na.rm = TRUE)
        looks_result_name <- safe_detect(nkey, "result|concentration|value|ngl|clean")
        looks_id_name <- safe_detect(nkey, "pws|well|station|sample|_id$|^id$|id")
        if (looks_id_name && !looks_result_name) return(TRUE)
        if (letter_rate > 0.70 && !looks_result_name) return(TRUE)
        if (numeric_rate < 0.20) return(TRUE)
        FALSE
      }
      col_by_alias <- function(aliases) {
        a <- norm(aliases)
        hit <- which(cn_norm %in% a)
        if (length(hit) > 0) return(cn[[hit[[1]]]])
        for (ax in a) {
          axx <- suppressWarnings(trimws(as.character(ax)))
          if (length(axx) != 1L || is.na(axx) || !nzchar(axx)) next
          hp <- which(safe_detect(cn_norm, axx))
          if (length(hp) > 0) return(cn[[hp[[1]]]])
        }
        ""
      }
      col_by_norm <- function(nm) {
        hit <- which(cn_norm == norm(nm))
        if (length(hit) > 0) cn[[hit[[1]]]] else ""
      }

      if (!nzchar(vals$analyte %||% "")) {
        vals$analyte <- col_by_norm("gm_chemical_name")
        if (!nzchar(vals$analyte)) {
          vals$analyte <- col_by_alias(c("analyte", "analyte_name", "contaminant", "chemical_name", "parameter", "compound", "name"))
        }
      }
      if (!nzchar(vals$result_value %||% "")) {
        vals$result_value <- col_by_norm("gm_result")
        if (!nzchar(vals$result_value)) vals$result_value <- col_by_norm("result_ngl")
        if (!nzchar(vals$result_value)) vals$result_value <- col_by_norm("result_clean")
        if (nzchar(vals$result_value) && isTRUE(is_bad_result_col(vals$result_value))) vals$result_value <- ""
        if (!nzchar(vals$result_value)) {
          pref <- col_by_alias(c("result", "result_value", "concentration", "value", "ngl", "clean"))
          if (nzchar(pref) && !isTRUE(is_bad_result_col(pref))) {
            vals$result_value <- pref
          } else {
            # Final fallback: most numeric-like column (avoid obvious ID/demographic fields).
            candidates <- cn[!safe_detect(cn_norm, "id|pws|well|station|sample|tract|population|geoid|zip|lat|lon")]
            if (length(candidates) == 0) candidates <- cn
            candidates <- candidates[!vapply(candidates, is_bad_result_col, logical(1))]
            rates <- vapply(candidates, function(cname) mean(!is.na(parse_num(df[[cname]]))), numeric(1))
            if (length(rates) > 0 && is.finite(max(rates, na.rm = TRUE)) && max(rates, na.rm = TRUE) > 0.3) {
              vals$result_value <- candidates[[which.max(rates)]]
            }
          }
        }
      }
      if (!nzchar(vals$sample_id %||% "")) {
        vals$sample_id <- col_by_norm("gm_well_id")
        if (!nzchar(vals$sample_id)) vals$sample_id <- col_by_alias(c("sample_id", "sampleid", "well_id", "pwsid", "station_id", "id"))
      }
      if (!nzchar(vals$state %||% "")) {
        vals$state <- col_by_norm("gm_state")
        if (!nzchar(vals$state)) vals$state <- col_by_alias(c("state", "state_abbr", "state_code"))
      }
      if (!nzchar(vals$county %||% "")) {
        vals$county <- col_by_alias(c("county"))
      }
      if (!nzchar(vals$region %||% "")) {
        vals$region <- col_by_alias(c("region"))
      }
      if (!nzchar(vals$facility_water_type %||% "")) {
        vals$facility_water_type <- col_by_alias(c("facilitywatertype", "facility_water_type"))
      }
      if (!nzchar(vals$sample_point_type %||% "")) {
        vals$sample_point_type <- col_by_alias(c("samplepointtype", "sample_point_type"))
      }
      if (!nzchar(vals$method_id %||% "")) {
        vals$method_id <- col_by_alias(c("methodid", "method_id"))
      }
      if (!nzchar(vals$collection_year %||% "")) {
        vals$collection_year <- col_by_alias(c("collectionyear", "collection_year", "year"))
      }
      if (!nzchar(vals$collection_month %||% "")) {
        vals$collection_month <- col_by_alias(c("collectionmonth", "collection_month", "month"))
      }
      if (!nzchar(vals$pws_size %||% "")) {
        vals$pws_size <- col_by_alias(c("pwssize", "pws_size"))
      }
      if (!nzchar(vals$facility_id %||% "")) {
        vals$facility_id <- col_by_alias(c("facilityid", "facility_id"))
      }
      if (!nzchar(vals$sample_point_id %||% "")) {
        vals$sample_point_id <- col_by_alias(c("samplepointid", "sample_point_id"))
      }
      if (!nzchar(vals$unit %||% "")) {
        vals$unit <- col_by_norm("gm_result_unit")
        if (!nzchar(vals$unit)) vals$unit <- col_by_alias(c("unit", "units", "uom"))
      }
      if (!nzchar(vals$qualifier %||% "")) {
        vals$qualifier <- col_by_norm("gm_result_modifier")
        if (!nzchar(vals$qualifier)) vals$qualifier <- col_by_alias(c("qualifier", "modifier", "flag"))
      }
      # Final hard-stop: identifier-like columns must never survive as result_value.
      if (nzchar(vals$result_value %||% "") && isTRUE(is_bad_result_col(vals$result_value))) {
        vals$result_value <- ""
      }
    }
    vals
  })

  observeEvent(input$btn_external_validate, {
    df <- external_upload_raw()
    req(!is.null(df))
    ds_type <- input$external_dataset_type %||% "unknown/custom"
    raw_sha <- ""
    uf <- normalize_shiny_file_upload(input$external_ml_file)
    if (!is.null(uf) && nzchar(uf$datapath)) {
      raw_sha <- external_upload_raw_digest(uf$datapath)
    }
    schema_cfg <- load_external_upload_schema()
    mapping <- get_upload_mapping()
    mapped_result_col <- trimws(as.character(mapping$result_value %||% ""))

    audit_strict <- function(sch_done, notes) {
      write_audit(
        "external_upload",
        sch_done$run_id %||% "none",
        ifelse(isTRUE(sch_done$ok), "strict_schema_pass", "strict_schema_fail"),
        op_id(),
        notes,
        list(
          schema_version = sch_done$schema_version,
          metrics = sch_done$metrics,
          violations = sch_done$violations,
          raw_sha256 = raw_sha,
          dataset_type = ds_type
        )
      )
    }

    if (nzchar(mapped_result_col) && isTRUE(is_identifier_like_result_col(mapped_result_col))) {
      sch_res <- list(
        ok = FALSE,
        schema_version = schema_cfg$schema_version,
        row_count = 0L,
        rows_pass = 0L,
        rows_fail = 0L,
        metrics = list(reason = "IDENTIFIER_RESULT_MAPPING", mapped_column = mapped_result_col),
        violations = list(list(rule = "RESULT_VALUE_IDENTIFIER")),
        run_id = NA_character_
      )
      sch_done <- persist_upload_validation_run(con, "validate_ui", sch_res, op_id(), external_upload_name() %||% "", raw_sha, ds_type)
      external_upload_strict_result(sch_done)
      audit_strict(sch_done, "Blocked: result_value mapped to identifier-like column")
      showNotification(
        paste0(
          "Mapped result_value column looks like an identifier (",
          mapped_result_col,
          "). Please map result_value to a numeric measurement column."
        ),
        type = "error",
        duration = 10
      )
      return(invisible(NULL))
    }

    norm <- normalize_upload_schema_with_wide_fallback(df, mapping, ds_type)

    missing_required <- sum(is.na(norm$analyte) | norm$analyte == "" | is.na(norm$result_value))
    numeric_invalid <- 0L
    if (nzchar(mapped_result_col) && (mapped_result_col %in% names(df))) {
      raw_vals <- trimws(as.character(df[[mapped_result_col]]))
      raw_vals[raw_vals %in% c("", "NA", "N/A", "na", "n/a", "NULL", "null")] <- NA_character_
      parsed_vals <- suppressWarnings(as.numeric(gsub("^\\s*[<>]\\s*|,", "", raw_vals)))
      numeric_invalid <- sum(!is.na(raw_vals) & is.na(parsed_vals), na.rm = TRUE)
    }
    dup_n <- sum(duplicated(paste(norm$sample_id, norm$sample_date, norm$analyte, norm$result_value, sep = "||")))
    allowed_units <- c("ng/l", "ug/l", "mg/l", "ng/ml", "ug/ml", "mg/ml", "ppb", "ppt", "pg/l")
    unit_clean <- tolower(trimws(norm$result_unit %||% ""))
    unsupported_units <- sum(nzchar(unit_clean) & !(unit_clean %in% allowed_units), na.rm = TRUE)
    nd_count <- sum(safe_detect(tolower(trimws(norm$qualifier %||% "")), "^<|nd|non.?detect|bdl|u\\b|uj\\b"), na.rm = TRUE)

    report <- list(
      rows = nrow(norm),
      missing_required_fields = missing_required,
      invalid_numeric_results = numeric_invalid,
      duplicate_rows = dup_n,
      unsupported_units = unsupported_units,
      non_detect_qualifier_rows = nd_count
    )
    external_upload_report(report)
    external_upload_normalized(norm)

    no_required_mapping <- !nzchar(trimws(mapping$analyte %||% "")) || !nzchar(trimws(mapping$result_value %||% ""))
    if (isTRUE(no_required_mapping) || missing_required >= nrow(norm)) {
      sch_res <- list(
        ok = FALSE,
        schema_version = schema_cfg$schema_version,
        row_count = as.integer(nrow(norm)),
        rows_pass = 0L,
        rows_fail = as.integer(max(nrow(norm), 1L)),
        metrics = list(
          block_reason = "MAPPING_OR_HEURISTIC",
          missing_required_fields = missing_required,
          heuristic_rows = report$rows
        ),
        violations = list(list(rule = "MAPPING_REQUIRED_FIELDS")),
        run_id = NA_character_
      )
      sch_done <- persist_upload_validation_run(con, "validate_ui", sch_res, op_id(), external_upload_name() %||% "", raw_sha, ds_type)
      external_upload_strict_result(sch_done)
      audit_strict(sch_done, "Heuristic validation blocked before strict schema")
      showNotification(
        paste0(
          "No valid analyte/result mapping found for this file. ",
          "Current mapping analyte='", mapping$analyte %||% "", "', result_value='", mapping$result_value %||% "", "'. ",
          "If this is a summary/demographic table (e.g., Census Tract), upload the PFAS measurement table instead."
        ),
        type = "error",
        duration = 12
      )
      return(invisible(NULL))
    }

    sch_res <- strict_validate_normalized_external(norm, schema_cfg)
    sch_done <- persist_upload_validation_run(con, "validate_ui", sch_res, op_id(), external_upload_name() %||% "", raw_sha, ds_type)
    external_upload_strict_result(sch_done)
    audit_strict(sch_done, "Strict schema validation (Validate button)")

    if (nrow(norm) == 0 || report$rows == 0) {
      showNotification("Validation failed: no usable rows.", type = "error")
    } else if (!isTRUE(sch_done$ok)) {
      showNotification(
        "Strict schema validation FAILED. Review Strict schema panel; fix rows/units or adjust data/config/external_upload_schema.json.",
        type = "error",
        duration = 14
      )
    } else {
      showNotification("Validation completed (heuristic + strict schema PASS).", type = "message")
    }
  })

  observeEvent(input$btn_external_normalize, {
    df <- external_upload_raw()
    req(!is.null(df))
    mapping <- get_upload_mapping()
    norm <- normalize_upload_schema_with_wide_fallback(df, mapping, input$external_dataset_type %||% "unknown/custom")
    external_upload_normalized(norm)
    external_upload_strict_result(NULL)
    showNotification("Normalization completed. Re-run Validate for strict schema + SQLite record.", type = "message")
  })

  observeEvent(input$btn_external_save, {
    mapping <- get_upload_mapping()
    mapped_result_col <- trimws(as.character(mapping$result_value %||% ""))
    if (nzchar(mapped_result_col) && isTRUE(is_identifier_like_result_col(mapped_result_col))) {
      external_upload_save_note(
        paste0(
          "Save blocked: mapped result_value column '",
          mapped_result_col,
          "' appears to be an identifier (not a numeric measurement)."
        )
      )
      showNotification(
        paste0(
          "Save blocked: result_value column '",
          mapped_result_col,
          "' looks like an identifier. Map result_value to a numeric PFAS result column first."
        ),
        type = "error",
        duration = 12
      )
      return(invisible(NULL))
    }
    norm <- external_upload_normalized()
    req(!is.null(norm), nrow(norm) > 0)

    ds_type <- input$external_dataset_type %||% "unknown/custom"
    raw_sha <- ""
    uf <- normalize_shiny_file_upload(input$external_ml_file)
    if (!is.null(uf) && nzchar(uf$datapath)) {
      raw_sha <- external_upload_raw_digest(uf$datapath)
    }
    schema_cfg <- load_external_upload_schema()
    sch_res <- strict_validate_normalized_external(norm, schema_cfg)
    sch_gate <- persist_upload_validation_run(con, "save_gate", sch_res, op_id(), external_upload_name() %||% "", raw_sha, ds_type)
    external_upload_strict_result(sch_gate)

    if (!isTRUE(sch_res$ok)) {
      external_upload_save_note(
        paste0(
          "Save blocked: strict schema validation FAILED (run_id=", sch_gate$run_id %||% "n/a", "). ",
          "Click Validate after fixes or edit data/config/external_upload_schema.json."
        )
      )
      write_audit(
        "external_upload",
        sch_gate$run_id %||% "none",
        "save_blocked_strict_schema",
        op_id(),
        "Save blocked: normalized table failed strict schema gate",
        list(metrics = sch_res$metrics, violations = sch_res$violations)
      )
      showNotification(
        "Save blocked: strict schema validation failed. Run Validate and fix issues.",
        type = "error",
        duration = 14
      )
      return(invisible(NULL))
    }

    rows_before_dedup <- nrow(norm)
    norm <- norm %>%
      distinct(sample_id, sample_date, analyte, result_value, .keep_all = TRUE)
    dedup_removed <- rows_before_dedup - nrow(norm)
    usable_rows <- sum(
      !is.na(norm$analyte) & nzchar(trimws(as.character(norm$analyte))) & !is.na(norm$result_value),
      na.rm = TRUE
    )
    if (usable_rows == 0) {
      external_upload_save_note(
        "Save blocked: 0 usable rows (analyte + numeric result_value). Use Map/Validate and confirm required fields are populated."
      )
      showNotification(
        "Save blocked: no usable analyte/result rows detected. Map columns, Validate, then Normalize again.",
        type = "error"
      )
      return(invisible(NULL))
    }
    upload_id <- paste0(
      "UPL-",
      format(Sys.time(), "%Y%m%d%H%M%S"),
      "-",
      substr(digest::digest(as.character(runif(1)), serialize = FALSE), 1, 6)
    )
    ts <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    norm$upload_id <- upload_id
    norm$uploaded_at <- ts
    norm$source_dataset <- ifelse(is.na(norm$source_dataset) | norm$source_dataset == "", input$external_dataset_type %||% "unknown/custom", norm$source_dataset)
    external_upload_normalized(norm)

    dir_uploads <- file.path(PROJECT_DIR, "data", "external_uploads")
    dir_processed <- file.path(PROJECT_DIR, "data", "processed")
    dir_external_ingest <- file.path(PROJECT_DIR, "data", "external", "external_uploads")
    dir.create(dir_uploads, recursive = TRUE, showWarnings = FALSE)
    dir.create(dir_processed, recursive = TRUE, showWarnings = FALSE)
    dir.create(dir_external_ingest, recursive = TRUE, showWarnings = FALSE)

    out_norm <- file.path(dir_uploads, paste0(upload_id, "_normalized.csv"))
    out_ingest <- file.path(dir_external_ingest, paste0(upload_id, "_normalized.csv"))
    utils::write.csv(norm, out_norm, row.names = FALSE)
    utils::write.csv(norm, out_ingest, row.names = FALSE)

    master_path <- file.path(dir_processed, "pfas_training_master.csv")
    master <- if (file.exists(master_path)) {
      tryCatch(
        utils::read.csv(master_path, stringsAsFactors = FALSE, check.names = FALSE),
        error = function(e) {
          data.frame(stringsAsFactors = FALSE, check.names = FALSE)
        }
      )
    } else {
      data.frame(stringsAsFactors = FALSE, check.names = FALSE)
    }

    for (cn in upload_schema_cols) {
      if (!cn %in% names(master)) {
        master[[cn]] <- NA_character_
      }

      if (!cn %in% names(norm)) {
        norm[[cn]] <- NA_character_
      }
    }

    master_aligned <- master[, upload_schema_cols, drop = FALSE]
    norm_aligned <- norm[, upload_schema_cols, drop = FALSE]

    for (cn in upload_schema_cols) {
      if (!cn %in% names(master_aligned)) {
        master_aligned[[cn]] <- NA_character_
      }

      if (!cn %in% names(norm_aligned)) {
        norm_aligned[[cn]] <- NA_character_
      }
    }

    master_aligned <- master_aligned[, upload_schema_cols, drop = FALSE]
    norm_aligned <- norm_aligned[, upload_schema_cols, drop = FALSE]

    master_aligned[] <- lapply(master_aligned, function(x) {
      as.character(x)
    })

    norm_aligned[] <- lapply(norm_aligned, function(x) {
      as.character(x)
    })

    combined <- rbind(master_aligned, norm_aligned)
    utils::write.csv(combined, master_path, row.names = FALSE)

    log_path <- file.path(dir_uploads, "upload_log.csv")
    log_row <- tibble::tibble(
      upload_id = upload_id,
      uploaded_at = ts,
      file_name = external_upload_name() %||% NA_character_,
      dataset_type = input$external_dataset_type %||% "unknown/custom",
      rows_saved = nrow(norm),
      dedup_rows_removed = dedup_removed,
      normalized_file = basename(out_norm),
      appended_master = basename(master_path)
    )
    if (file.exists(log_path)) {
      old <- tryCatch(
        utils::read.csv(log_path, stringsAsFactors = FALSE, check.names = FALSE),
        error = function(e) {
          data.frame()
        }
      )
      old <- dplyr::bind_rows(old, log_row)
      utils::write.csv(old, log_path, row.names = FALSE)
    } else {
      utils::write.csv(log_row, log_path, row.names = FALSE)
    }

    write_audit(
      "external_upload",
      upload_id,
      "normalized_save_success",
      op_id(),
      paste0("Saved ", nrow(norm), " normalized rows to master"),
      list(
        upload_id = upload_id,
        strict_gate_run_id = sch_gate$run_id,
        dedup_removed = dedup_removed,
        raw_sha256 = raw_sha,
        dataset_type = ds_type
      )
    )

    external_upload_save_note(
      paste(
        "Saved normalized rows:", nrow(norm), "\n",
        "De-duplicated rows removed:", dedup_removed, "\n",
        "Upload file:", out_norm, "\n",
        "External ingest copy:", out_ingest, "\n",
        "Master updated:", master_path, "\n",
        "Upload log:", log_path
      )
    )
    showNotification(
      paste0("Upload saved. ", nrow(norm), " rows kept; ", dedup_removed, " duplicate rows removed."),
      type = "message"
    )
  })

  observeEvent(input$btn_external_train, {
    if (!enforce_iso_preflight("External train")) return(invisible(NULL))
    # Use in-process execution for R steps to avoid runtime issues resolving subprocess Rscript.
    ok_m <- run_r_script_in_process("prepare_multisource_training.R", "prepare_multisource_training.R")
    ok_b <- if (ok_m) run_r_script_in_process("build_model_matrix.R", "build_model_matrix.R") else FALSE
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    python_available <- nzchar(py_exec)
    ok_t <- if (ok_b && python_available) run_python_step() else FALSE

    if (ok_m && ok_b && (!python_available || ok_t)) {
      if (!python_available) {
        showNotification(
          "Data refresh completed (prepare + matrix). Python executable not found, so model retrain was skipped.",
          type = "warning",
          duration = 10
        )
      } else if (!ok_t) {
        showNotification(
          "Data refresh completed, but Python model retrain failed. Check PFAS pipeline log.",
          type = "warning",
          duration = 10
        )
      } else {
        showNotification("Training completed from uploaded/merged sources.", type = "message")
      }
      # Refresh UI artifacts (target tracker and any updated results files).
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else if (!ok_m) {
      showNotification(
        paste0(
          "Training failed at prepare_multisource_training.R: ",
          pipeline_last_error() %||% "unknown error"
        ),
        type = "error",
        duration = 12
      )
    } else if (!ok_b) {
      showNotification(
        paste0(
          "Training failed at build_model_matrix.R: ",
          pipeline_last_error() %||% "unknown error"
        ),
        type = "error",
        duration = 12
      )
    } else {
      showNotification(
        paste0("Training failed: ", pipeline_last_error() %||% "unknown error"),
        type = "error",
        duration = 12
      )
    }
  })

  observeEvent(input$train_pfas_model, {
    if (!enforce_iso_preflight("PFAS model training")) return(invisible(NULL))
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    if (!nzchar(py_exec)) {
      showNotification(
        "Python executable not found. Set 'Python executable' then retry PFAS model training.",
        type = "error",
        duration = 10
      )
      return(invisible(NULL))
    }
    ok <- run_python_step()
    if (ok) {
      showNotification("PFAS exceedance model training completed.", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification("PFAS model training failed; check PFAS pipeline log.", type = "error")
    }
  })

  observeEvent(input$btn_generate_ml_validation_report, {
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    if (!nzchar(py_exec)) {
      showNotification(
        "Python executable not found. Set 'Python executable' then regenerate the ML validation report.",
        type = "error",
        duration = 10
      )
      return(invisible(NULL))
    }
    ok <- run_ml_validation_report_step()
    if (ok) {
      showNotification(
        "ML validation report generated: results/ISO17025_ML_Validation_Report.html",
        type = "message",
        duration = 12
      )
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification("ML validation report step failed; check PFAS pipeline log.", type = "error")
    }
  })

  observeEvent(input$run_pfas_prediction, {
    if (!enforce_iso_preflight("PFAS prediction")) return(invisible(NULL))
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    if (!nzchar(py_exec)) {
      showNotification(
        "Python executable not found. Set 'Python executable' then retry prediction.",
        type = "error",
        duration = 10
      )
      return(invisible(NULL))
    }
    ok <- run_pfas_prediction_step()
    if (ok) {
      showNotification("PFAS prediction run completed.", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification("PFAS prediction failed; check PFAS pipeline log.", type = "error")
    }
  })

  observeEvent(input$qc_dataset_file, {
    qc_path <- resolve_pipeline_path(input$pfas_qc_path, file.path(PROJECT_DIR, "data", "external", "qc_datasets"))
    qc_stage_dir <- if (file.exists(qc_path) && !dir.exists(qc_path)) dirname(qc_path) else qc_path
    dest <- ensure_uploaded_artifact(input$qc_dataset_file, qc_stage_dir, "qc_dataset.csv")
    if (is.null(dest)) return(invisible(NULL))
    qc_pt_upload_status_note(paste0("QC dataset staged: ", normalizePath(dest, winslash = "/", mustWork = FALSE)))
    append_pipeline_log("QC input staged: ", basename(dest))
    pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$pt_dataset_file, {
    pt_path <- resolve_pipeline_path(input$pfas_pt_path, file.path(PROJECT_DIR, "data", "external", "proficiency_testing"))
    pt_stage_dir <- if (file.exists(pt_path) && !dir.exists(pt_path)) dirname(pt_path) else pt_path
    dest <- ensure_uploaded_artifact(input$pt_dataset_file, pt_stage_dir, "pt_dataset.csv")
    if (is.null(dest)) return(invisible(NULL))
    qc_pt_upload_status_note(paste0("PT dataset staged: ", normalizePath(dest, winslash = "/", mustWork = FALSE)))
    append_pipeline_log("PT input staged: ", basename(dest))
    pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$btn_validate_reference_dataset, {
    ok <- step_validate_reference_dataset()
    write_audit(
      "pfas_pipeline",
      "validate_reference_dataset",
      ifelse(ok, "execute_success", "execute_failure"),
      op_id(),
      ifelse(ok, "Reference dataset loaded/validated", "Reference dataset load/validation failed"),
      list(error = pipeline_last_error() %||% "")
    )
    if (ok) {
      showNotification("Reference dataset loaded/validated.", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification(paste0("Reference step failed: ", pipeline_last_error() %||% "unknown error"), type = "error")
    }
  })

  observeEvent(input$btn_qc_validation_check, {
    ok <- step_qc_validation_check()
    write_audit(
      "pfas_pipeline",
      "qc_validation_check",
      ifelse(ok, "execute_success", "execute_failure"),
      op_id(),
      ifelse(ok, "QC validation check completed", "QC validation check failed"),
      list(error = pipeline_last_error() %||% "")
    )
    if (ok) {
      showNotification("QC validation check completed.", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification(paste0("QC validation check failed: ", pipeline_last_error() %||% "unknown error"), type = "error")
    }
  })

  observeEvent(input$btn_applicability_domain_check, {
    ok <- step_applicability_domain_check()
    write_audit(
      "pfas_pipeline",
      "applicability_domain_check",
      ifelse(ok, "execute_success", "execute_failure"),
      op_id(),
      ifelse(ok, "Applicability-domain check completed", "Applicability-domain check failed"),
      list(error = pipeline_last_error() %||% "")
    )
    if (ok) {
      showNotification("Applicability-domain check completed.", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification(paste0("Applicability-domain check failed: ", pipeline_last_error() %||% "unknown error"), type = "error")
    }
  })

  observeEvent(input$btn_external_pt_validation, {
    ok <- step_external_pt_validation()
    write_audit(
      "pfas_pipeline",
      "external_pt_validation",
      ifelse(ok, "execute_success", "execute_failure"),
      op_id(),
      ifelse(ok, "External PT validation completed", "External PT validation failed"),
      list(error = pipeline_last_error() %||% "")
    )
    if (ok) {
      showNotification("External PT validation completed.", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification(paste0("External PT validation failed: ", pipeline_last_error() %||% "unknown error"), type = "error")
    }
  })

  observeEvent(input$btn_generate_iso_compliance_report, {
    ok <- step_generate_iso_compliance_report()
    write_audit(
      entity_type = "pfas_pipeline",
      entity_id = "generate_iso_compliance_report",
      action_type = ifelse(ok, "execute_success", "execute_failure"),
      changed_by = op_id(),
      message = ifelse(ok, "ISO compliance report generated", "ISO compliance report generation failed"),
      details = list(error = pipeline_last_error() %||% "")
    )
    if (ok) {
      showNotification("ISO compliance report generated.", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification(paste0("ISO compliance report failed: ", pipeline_last_error() %||% "unknown error"), type = "error")
    }
  })

  output$external_quality_status <- renderPrint({
    rep <- external_upload_report()
    mapping <- get_upload_mapping()
    cat("Mapping engine version:", MAPPING_ENGINE_VERSION, "\n")
    cat("Current mapping\n")
    cat("analyte     :", mapping$analyte %||% "", "\n")
    cat("result_value:", mapping$result_value %||% "", "\n")
    cat("sample_id   :", mapping$sample_id %||% "", "\n")
    cat("state       :", mapping$state %||% "", "\n\n")
    mapped_result_col <- trimws(as.character(mapping$result_value %||% ""))
    if (nzchar(mapped_result_col) && isTRUE(is_identifier_like_result_col(mapped_result_col))) {
      cat("WARNING: result_value appears to be an identifier column and is invalid for training.\n\n")
    }
    if (is.null(rep)) {
      cat("No validation report yet.\n")
      return(invisible(NULL))
    }
    cat("Validation summary\n")
    cat("Rows:", rep$rows, "\n")
    cat("Missing required fields (analyte/result_value):", rep$missing_required_fields, "\n")
    cat("Invalid numeric results:", rep$invalid_numeric_results, "\n")
    cat("Duplicate rows:", rep$duplicate_rows, "\n")
    cat("Unsupported units:", rep$unsupported_units, "\n")
    cat("Non-detect qualifier rows:", rep$non_detect_qualifier_rows, "\n")
  })

  output$external_strict_schema_status <- renderPrint({
    sr <- external_upload_strict_result()
    schema_now <- load_external_upload_schema()
    cat("Schema file:", file.path(PROJECT_DIR, "data", "config", "external_upload_schema.json"), "\n")
    cat("Active schema_version:", schema_now$schema_version %||% "unknown", "\n\n")
    if (is.null(sr)) {
      cat("No strict validation recorded yet for this session (click Validate after upload/map).\n")
      return(invisible(NULL))
    }
    cat("Last validation record\n")
    cat(" run_id       :", sr$run_id %||% "", "\n")
    cat(" schema_version:", sr$schema_version %||% "", "\n")
    cat(" strict OK    :", isTRUE(sr$ok), "\n")
    cat(" rows (total) :", sr$row_count %||% NA, "\n")
    cat(" rows PASS    :", sr$rows_pass %||% NA, "\n")
    cat(" rows FAIL    :", sr$rows_fail %||% NA, "\n")
    if (!is.null(sr$metrics) && length(sr$metrics) > 0) {
      cat("\nMetrics:\n")
      print(sr$metrics)
    }
    if (!is.null(sr$violations) && length(sr$violations) > 0) {
      cat("\nViolations:\n")
      print(sr$violations)
    }
    cat("\nSQLite table:", "upload_validation_run", "(controlled validation evidence).\n")
  })

  output$external_save_status <- renderPrint({
    cat(external_upload_save_note(), "\n")
  })

  observeEvent(input$btn_pfas_download, {
    ok <- run_r_script_step("download_echo_nhanes.R", "download_echo_nhanes.R")
    if (ok) pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$btn_pfas_prepare, {
    ok <- run_r_script_step("prepare_nhanes_training.R", "prepare_nhanes_training.R")
    if (ok) pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$btn_epa_ucmr5_download, {
    ok <- run_r_script_step("download_epa_ucmr5.R", "download_epa_ucmr5.R")
    if (ok) pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$btn_epa_echo_download, {
    ok <- run_r_script_step("download_epa_echo_api.R", "download_epa_echo_api.R", extra_env = pipeline_env())
    if (ok) pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$btn_epa_sdwis_download, {
    ok <- run_r_script_step("download_epa_sdwis.R", "download_epa_sdwis.R", extra_env = pipeline_env())
    if (ok) pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$btn_epa_icis_npdes_download, {
    lim <- if (isTRUE(input$epa_icis_include_limits)) "1" else "0"
    ok <- run_r_script_step(
      "download_epa_icis_npdes.R",
      "download_epa_icis_npdes.R",
      extra_env = c(
        PFAS_ICIS_DMR_YEARS = trimws(input$epa_icis_dmr_years %||% "2024,2025"),
        PFAS_ICIS_INCLUDE_LIMITS = lim
      )
    )
    if (ok) {
      showNotification("ICIS-NPDES ECHO downloads completed (see data/raw/epa_icis_npdes).", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification("ICIS-NPDES download failed; see PFAS pipeline log.", type = "error")
    }
  })

  observeEvent(input$btn_epa_icis_filter_dmr, {
    ok <- run_icis_dmr_filter_step()
    if (ok) {
      showNotification("DMR PFAS filter completed (data/processed/npdes_dmr_pfas_fy*.csv).", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification("DMR PFAS filter failed; check Python path and FY ZIP present.", type = "error")
    }
  })

  observeEvent(input$btn_pfas_matrix, {
    ok <- run_r_script_step("build_model_matrix.R", "build_model_matrix.R")
    if (ok) pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$btn_pfas_multisource, {
    ok <- run_r_script_step("prepare_multisource_training.R", "prepare_multisource_training.R")
    if (ok) pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$btn_validate_python_exec, {
    py_exec_raw <- trimws(input$pfas_python_exec %||% "")
    if (!nzchar(py_exec_raw)) {
      showNotification("Python path is empty.", type = "error")
      return(invisible(NULL))
    }
    py_exec <- resolve_python_exec(py_exec_raw)
    exists_exec <- nzchar(py_exec)
    if (!exists_exec) {
      append_pipeline_log("Python validate: ", py_exec_raw, " | exists=FALSE")
      showNotification("Python not found in this runtime.", type = "error")
      return(invisible(NULL))
    }
    ver <- tryCatch(
      system2(py_exec, args = "--version", stdout = TRUE, stderr = TRUE),
      error = function(e) {
        paste("ERROR:", conditionMessage(e))
      }
    )
    append_pipeline_log("Python validate: ", py_exec, " | exists=", exists_exec, " | ", paste(ver, collapse = " "))
    if (exists_exec && !any(grepl("^ERROR:", ver))) {
      showNotification(paste("Python validated:", paste(ver, collapse = " ")), type = "message")
    } else {
      showNotification("Python validation failed. Check path or environment.", type = "error")
    }
  })

  observeEvent(input$btn_check_intake_api_health, {
    h <- check_intake_api_health(LINK_DATASET_FORM, PFAS_INTAKE_STAGING_TOKEN)
    intake_api_health(h)
    level_to_type <- c(ok = "message", pending = "warning", warning = "warning", disabled = "warning", error = "error")
    notify_type <- level_to_type[[h$level]]
    if (is.null(notify_type)) notify_type <- "warning"
    showNotification(paste(h$summary, "|", h$smoke$summary), type = notify_type)
    append_pipeline_log(
      "Intake API health check: ",
      h$summary,
      " | smoke=",
      h$smoke$status %||% "unknown",
      " | http=",
      as.character(h$smoke$http_status %||% NA),
      " | endpoint=",
      h$endpoint
    )
  })

  observeEvent(input$btn_pfas_run_all, {
    if (!enforce_iso_preflight("Run all steps")) return(invisible(NULL))
    write_audit(
      "pfas_pipeline",
      "run_all",
      "execute_start",
      op_id(),
      "PFAS one-click pipeline started",
      list(trigger = "btn_pfas_run_all")
    )
    ok1 <- run_r_script_step("download_echo_nhanes.R", "download_echo_nhanes.R")
    ok2 <- if (ok1) run_r_script_step("download_epa_ucmr5.R", "download_epa_ucmr5.R") else FALSE
    ok3 <- if (ok2) run_r_script_step("download_epa_echo_api.R", "download_epa_echo_api.R", extra_env = pipeline_env()) else FALSE
    ok4 <- if (ok3) run_r_script_step("download_epa_sdwis.R", "download_epa_sdwis.R", extra_env = pipeline_env()) else FALSE
    ok5 <- if (ok4) run_r_script_step("prepare_nhanes_training.R", "prepare_nhanes_training.R") else FALSE
    ok6 <- if (ok5) run_r_script_step("prepare_multisource_training.R", "prepare_multisource_training.R") else FALSE
    ok7 <- if (ok6) run_r_script_step("build_model_matrix.R", "build_model_matrix.R") else FALSE
    ok8 <- if (ok7) run_python_step() else FALSE
    ok9 <- if (ok8) run_pfas_prediction_step() else FALSE
    ok10 <- if (ok9) step_validate_reference_dataset() else FALSE
    ok11 <- if (ok10) step_qc_validation_check() else FALSE
    ok12 <- if (ok11) step_applicability_domain_check() else FALSE
    ok13 <- if (ok12) step_external_pt_validation() else FALSE
    ok14 <- if (ok13) step_generate_iso_compliance_report() else FALSE
    ok15 <- if (ok14) run_ml_validation_report_step() else FALSE
    if (ok1 && ok2 && ok3 && ok4 && ok5 && ok6 && ok7 && ok8 && ok9 && ok10 && ok11 && ok12 && ok13 && ok14 && ok15) {
      append_pipeline_log("Pipeline completed successfully.")
      write_audit(
        "pfas_pipeline",
        "run_all",
        "execute_success",
        op_id(),
        "PFAS one-click pipeline completed successfully",
        list(
          download_nhanes = ok1,
          download_ucmr5 = ok2,
          download_echo = ok3,
          download_sdwis = ok4,
          prepare_nhanes = ok5,
          prepare_multisource = ok6,
          matrix = ok7,
          train = ok8,
          predict = ok9,
          validate_reference_dataset = ok10,
          qc_validation_check = ok11,
          applicability_domain_check = ok12,
          external_pt_validation = ok13,
          generate_iso_compliance_report = ok14,
          generate_ml_validation_report = ok15
        )
      )
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      append_pipeline_log("Pipeline stopped due to step failure.")
      write_audit(
        "pfas_pipeline",
        "run_all",
        "execute_failure",
        op_id(),
        "PFAS one-click pipeline stopped due to failure",
        list(
          download_nhanes = ok1,
          download_ucmr5 = ok2,
          download_echo = ok3,
          download_sdwis = ok4,
          prepare_nhanes = ok5,
          prepare_multisource = ok6,
          matrix = ok7,
          train = ok8,
          predict = ok9,
          validate_reference_dataset = ok10,
          qc_validation_check = ok11,
          applicability_domain_check = ok12,
          external_pt_validation = ok13,
          generate_iso_compliance_report = ok14,
          generate_ml_validation_report = ok15
        )
      )
    }
  })

  output$tbl_recent_entries <- renderDT({
    DT::datatable(recent_entries(), options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })
  
  output$tbl_feature_importance <- renderDT({
    df <- feature_importance |>
      dplyr::filter(endpoint == input$mechanistic_endpoint)
    render_dt(df, 8)
  })
  
  output$plot_missingness <- renderPlot(plot_missingness())
  output$plot_class_balance <- renderPlot(plot_class_balance())
  output$plot_bal_acc <- renderPlot(plot_validation_metrics("Balanced_Accuracy"))
  output$plot_prediction_risk <- renderPlot(plot_prediction_risk())
  output$plot_ad_distribution <- renderPlot(plot_ad_distribution())
  output$plot_feature_importance <- renderPlot(plot_feature_importance(input$mechanistic_endpoint))
  
  output$download_ml_export <- downloadHandler(
    filename = function() {
      paste0("pfas_ml_export_", Sys.Date(), ".csv")
    },
    content = function(file) {
      oid <- op_id()
      write_audit(
        "ml_export",
        basename(file),
        "export",
        oid,
        "ML training CSV export",
        list(rows = nrow(ml_export()))
      )
      write.csv(ml_export(), file, row.names = FALSE)
    }
  )

  output$dl_ml_validation_report <- downloadHandler(
    filename = function() {
      "ISO17025_ML_Validation_Report.html"
    },
    content = function(file) {
      src <- file.path(PROJECT_DIR, "results", "ISO17025_ML_Validation_Report.html")
      oid <- op_id()
      if (!file.exists(src)) {
        write_audit(
          "pfas_pipeline",
          "ml_validation_report_download",
          "export_missing",
          oid,
          "ML validation HTML missing at download time",
          list(expected_path = src)
        )
        writeLines(
          c(
            "ISO17025_ML_Validation_Report.html was not found.",
            paste0("Expected: ", normalizePath(src, winslash = "/", mustWork = FALSE)),
            "Use Reports -> 16) Generate ML validation report (HTML), then retry download."
          ),
          con = file
        )
      } else {
        write_audit(
          "pfas_pipeline",
          "ml_validation_report_download",
          "export",
          oid,
          "ML validation HTML downloaded",
          list(source_path = normalizePath(src, winslash = "/", mustWork = FALSE))
        )
        file.copy(src, file, overwrite = TRUE)
      }
    }
  )

  # --- ISO 17025 / EPA 1633 validation UI ---------------------------------
  observe({
    df <- safe_table("epa1633_test_case")
    if (nrow(df) == 0) {
      updateSelectInput(session, "v_test_case_id", choices = c("Run seed or restore DB" = ""))
    } else {
      updateSelectInput(
        session,
        "v_test_case_id",
        choices = stats::setNames(df$test_case_id, paste(df$test_case_id, df$category))
      )
    }
  })

  output$apr_select_ui <- renderUI({
    df <- safe_table("approval_record")
    pend <- df[df$status == "pending", , drop = FALSE]
    if (nrow(pend) == 0) {
      return(selectInput("apr_pick", "Pending approval", choices = c("(none)" = "")))
    }
    selectInput(
      "apr_pick",
      "Pending approval",
      choices = stats::setNames(
        pend$approval_id,
        paste(pend$approval_step, pend$object_type, pend$object_id)
      )
    )
  })

  observeEvent(input$btn_save_validation_result, {
    oid <- op_id()
    req(nzchar(input$v_test_case_id %||% ""))
    tc <- safe_table("epa1633_test_case")
    row <- tc[tc$test_case_id == input$v_test_case_id, , drop = FALSE]
    exp <- if (nrow(row) == 1) row$acceptance_criteria[[1]] else NA_character_
    rid <- make_id("VTR")
    out <- tibble::tibble(
      result_id = rid,
      test_case_id = input$v_test_case_id,
      protocol_ref = input$v_protocol_ref %||% "",
      run_at = as.character(Sys.time()),
      operator = oid,
      expected_result = as.character(exp %||% ""),
      actual_result = input$v_pass_fail,
      pass_fail = input$v_pass_fail,
      evidence_notes = input$v_evidence_notes %||% ""
    )
    DBI::dbWriteTable(con, "validation_test_result", out, append = TRUE)
    write_audit("validation_test_result", rid, "create", oid, "EPA 1633 validation test recorded", list(test = input$v_test_case_id))
    showNotification("Validation result saved.", type = "message")
  })

  observeEvent(input$btn_save_capa, {
    oid <- op_id()
    req(nzchar(input$capa_title %||% ""))
    cid <- make_id("CAPA")
    row <- tibble::tibble(
      capa_id = cid,
      title = input$capa_title,
      description = input$capa_description %||% "",
      status = "open",
      priority = input$capa_priority %||% "Medium",
      opened_at = as.character(Sys.time()),
      opened_by = oid,
      root_cause = NA_character_,
      corrective_action = NA_character_,
      preventive_action = NA_character_,
      effectiveness_check = NA_character_,
      closed_at = NA_character_,
      closed_by = NA_character_,
      linked_entity_type = input$capa_linked_type %||% "",
      linked_entity_id = input$capa_linked_id %||% ""
    )
    DBI::dbWriteTable(con, "capa", row, append = TRUE)
    write_audit("capa", cid, "create", oid, "CAPA opened", list(title = input$capa_title))
    showNotification("CAPA opened.", type = "message")
  })

  observeEvent(input$btn_request_approval, {
    oid <- op_id()
    req(nzchar(input$apr_object_id %||% ""))
    aid <- make_id("APR")
    row <- tibble::tibble(
      approval_id = aid,
      object_type = input$apr_object_type %||% "record",
      object_id = input$apr_object_id,
      approval_step = input$apr_step %||% "QC review",
      status = "pending",
      requested_at = as.character(Sys.time()),
      requested_by = oid,
      decided_at = NA_character_,
      decided_by = NA_character_,
      rationale = NA_character_,
      esig_meaning = NA_character_
    )
    DBI::dbWriteTable(con, "approval_record", row, append = TRUE)
    write_audit("approval_record", aid, "create", oid, "Approval requested", list(step = input$apr_step))
    showNotification("Approval request recorded.", type = "message")
  })

  observeEvent(input$btn_decide_approval, {
    oid <- op_id()
    pick <- input$apr_pick %||% ""
    req(nzchar(pick))
    dec <- input$apr_decision %||% "approved"
    DBI::dbExecute(
      con,
      "UPDATE approval_record SET status = ?, decided_at = ?, decided_by = ?, rationale = ? WHERE approval_id = ?",
      params = list(dec, as.character(Sys.time()), oid, input$apr_rationale %||% "", pick)
    )
    write_audit("approval_record", pick, "update", oid, paste("Approval", dec), list(decision = dec))
    showNotification("Approval decision recorded.", type = "message")
  })

  observeEvent(input$btn_esig, {
    oid <- op_id()
    req(nzchar(input$esig_record_id %||% ""))
    sid <- make_id("ESIG")
    row <- tibble::tibble(
      signature_id = sid,
      record_type = input$esig_record_type %||% "record",
      record_id = input$esig_record_id,
      meaning = input$esig_meaning %||% "signoff",
      signer_id = oid,
      signed_at = as.character(Sys.time()),
      witness_id = NA_character_,
      method_note = "PFAS Enterprise 4.0 UI attestation (map to 21 CFR Part 11 SOP)"
    )
    DBI::dbWriteTable(con, "electronic_signature", row, append = TRUE)
    write_audit("electronic_signature", sid, "create", oid, "Electronic signature applied", list(record = input$esig_record_id))
    showNotification("Electronic signature recorded.", type = "message")
  })

  observeEvent(input$btn_save_qc, {
    oid <- op_id()
    req(nzchar(input$qc_batch_id %||% ""))
    qid <- make_id("QC")
    row <- tibble::tibble(
      qc_id = qid,
      batch_id = input$qc_batch_id,
      method_ref = "EPA 1633",
      matrix = input$qc_matrix %||% "",
      run_date = as.character(input$qc_run_date),
      analyst = oid,
      blanks_ok = as.integer(isTRUE(input$qc_blanks_ok)),
      checks_ok = as.integer(isTRUE(input$qc_checks_ok)),
      cal_verified = as.integer(isTRUE(input$qc_cal_ok)),
      overall_status = input$qc_overall %||% "Accept",
      notes = input$qc_notes %||% "",
      created_at = as.character(Sys.time())
    )
    DBI::dbWriteTable(con, "qc_batch", row, append = TRUE)
    write_audit("qc_batch", qid, "create", oid, "QC batch logged", list(batch = input$qc_batch_id))
    showNotification("QC batch saved.", type = "message")
  })

  observeEvent(input$btn_save_training, {
    oid <- op_id()
    req(nzchar(input$tr_user %||% ""))
    tid <- make_id("TRN")
    row <- tibble::tibble(
      training_id = tid,
      user_id = input$tr_user,
      topic = input$tr_topic %||% "",
      method_ref = "EPA 1633",
      completed_at = as.character(input$tr_completed),
      trainer = input$tr_trainer %||% "",
      expiry_date = if (inherits(input$tr_expiry, "Date") && !is.na(input$tr_expiry)) {
        as.character(input$tr_expiry)
      } else {
        NA_character_
      },
      evidence_ref = input$tr_evidence %||% "",
      quiz_score = NA_real_
    )
    DBI::dbWriteTable(con, "training_record", row, append = TRUE)
    write_audit("training_record", tid, "create", oid, "Training recorded", list(user = input$tr_user))
    showNotification("Training record saved.", type = "message")
  })

  observeEvent(input$btn_save_cal, {
    oid <- op_id()
    req(nzchar(input$cal_instrument %||% ""))
    cid <- make_id("CAL")
    pass <- identical(input$cal_pass, "pass")
    row <- tibble::tibble(
      cal_id = cid,
      instrument_id = input$cal_instrument,
      parameter = input$cal_parameter %||% "",
      nominal_value = input$cal_nominal,
      measured_value = input$cal_measured,
      tolerance_pct = input$cal_tol_pct,
      result_pass = as.integer(pass),
      performed_at = as.character(Sys.time()),
      performed_by = oid,
      standard_ref = "NIST-traceable / vendor SOP",
      cert_ref = input$cal_cert %||% "",
      next_due = if (inherits(input$cal_next, "Date") && !is.na(input$cal_next)) {
        as.character(input$cal_next)
      } else {
        NA_character_
      }
    )
    DBI::dbWriteTable(con, "calibration_log", row, append = TRUE)
    write_audit("calibration_log", cid, "create", oid, "Calibration entry", list(instrument = input$cal_instrument))
    showNotification("Calibration saved.", type = "message")
  })

  output$tbl_epa1633_cases <- renderDT({
    input$btn_save_validation_result
    df <- safe_table("epa1633_test_case")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "No EPA 1633 test cases in DB."), rownames = FALSE))
    }
    render_dt(df, 12)
  })

  output$tbl_validation_results <- renderDT({
    input$btn_save_validation_result
    df <- safe_table("validation_test_result")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "No validation runs recorded."), rownames = FALSE))
    }
    render_dt(df, 10)
  })

  output$tbl_capa <- renderDT({
    input$btn_save_capa
    df <- safe_table("capa")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "No CAPA records."), rownames = FALSE))
    }
    render_dt(df, 10)
  })

  output$tbl_approvals <- renderDT({
    input$btn_decide_approval
    input$btn_request_approval
    df <- safe_table("approval_record")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "No approvals."), rownames = FALSE))
    }
    render_dt(df, 10)
  })

  output$tbl_esig <- renderDT({
    input$btn_esig
    df <- safe_table("electronic_signature")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "No signatures."), rownames = FALSE))
    }
    render_dt(df, 10)
  })

  output$tbl_qc_batch <- renderDT({
    input$btn_save_qc
    df <- safe_table("qc_batch")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "No QC batches."), rownames = FALSE))
    }
    render_dt(df, 10)
  })

  output$tbl_training <- renderDT({
    input$btn_save_training
    df <- safe_table("training_record")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "No training records."), rownames = FALSE))
    }
    render_dt(df, 10)
  })

  output$tbl_calibration <- renderDT({
    input$btn_save_cal
    df <- safe_table("calibration_log")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "No calibration rows."), rownames = FALSE))
    }
    render_dt(df, 10)
  })

  iq_path <- function(...) file.path(PROJECT_DIR, "validation", ...)

  output$dl_iq_template_md <- downloadHandler(
    filename = function() {
      "Installation_Qualification_Template.md"
    },
    content = function(file) {
      p <- iq_path("IQ", "Installation_Qualification_Template.md")
      if (!file.exists(p)) {
        writeLines("# IQ template missing from repository.", file)
      } else {
        file.copy(p, file, overwrite = TRUE)
      }
      oid <- op_id()
      write_audit("iq_template", "Installation_Qualification_Template.md", "export", oid, "IQ template download", list())
    }
  )

  output$dl_epa1633_protocol_md <- downloadHandler(
    filename = function() {
      "EPA_Method_1633_Validation_Protocol.md"
    },
    content = function(file) {
      p <- iq_path("test_cases", "EPA_Method_1633_Validation_Protocol.md")
      if (!file.exists(p)) {
        writeLines("# Protocol missing from repository.", file)
      } else {
        file.copy(p, file, overwrite = TRUE)
      }
      oid <- op_id()
      write_audit("validation_protocol", "EPA_Method_1633_Validation_Protocol.md", "export", oid, "Validation protocol download", list())
    }
  )

  output$dl_epa1633_tests_csv <- downloadHandler(
    filename = function() {
      "EPA_Method_1633_Test_Cases.csv"
    },
    content = function(file) {
      p <- iq_path("test_cases", "EPA_Method_1633_Test_Cases.csv")
      if (!file.exists(p)) {
        utils::write.csv(safe_table("epa1633_test_case"), file, row.names = FALSE)
      } else {
        file.copy(p, file, overwrite = TRUE)
      }
      oid <- op_id()
      write_audit("epa1633_tests", "EPA_Method_1633_Test_Cases.csv", "export", oid, "EPA 1633 test case CSV export", list())
    }
  )

  output$tbl_glp_audit <- renderDT({
    input$glp_verify_chain_btn
    df <- safe_table("glp_audit_trail")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(message = "No GLP audit rows yet."), rownames = FALSE))
    }
    DT::datatable(df, options = list(pageLength = 15, scrollX = TRUE, order = list(list(0, "desc"))), rownames = FALSE)
  })

  output$tbl_legacy_audit <- renderDT({
    input$glp_verify_chain_btn
    df <- safe_table("audit_log")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(message = "No legacy audit rows."), rownames = FALSE))
    }
    DT::datatable(df, options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE)
  })

  load_partner_intake_admin <- function(limit_n = 50L) {
    limit_n <- suppressWarnings(as.integer(limit_n %||% 50L))
    if (is.na(limit_n) || limit_n < 10L) limit_n <- 50L
    if (limit_n > 500L) limit_n <- 500L

    src <- "none"
    raw_df <- tibble::tibble()

    if (nzchar(PFAS_PARTNER_AUDIT_SQLITE_TABLE)) {
      tbl_df <- tryCatch(
        safe_table(PFAS_PARTNER_AUDIT_SQLITE_TABLE),
        error = function(e) {
          tibble::tibble()
        }
      )
      if (nrow(tbl_df) > 0) {
        raw_df <- tbl_df
        src <- paste0("SQLite table: ", PFAS_PARTNER_AUDIT_SQLITE_TABLE)
      }
    }

    if (nrow(raw_df) == 0 && nzchar(PFAS_PARTNER_AUDIT_MIRROR_CSV) && file.exists(PFAS_PARTNER_AUDIT_MIRROR_CSV)) {
      csv_df <- tryCatch(
        read.csv(PFAS_PARTNER_AUDIT_MIRROR_CSV, stringsAsFactors = FALSE, check.names = FALSE),
        error = function(e) {
          tibble::tibble()
        }
      )
      if (nrow(csv_df) > 0) {
        raw_df <- tibble::as_tibble(csv_df)
        src <- paste0("CSV mirror: ", normalizePath(PFAS_PARTNER_AUDIT_MIRROR_CSV, winslash = "/", mustWork = FALSE))
      }
    }

    if (nrow(raw_df) == 0) {
      legacy <- tryCatch(
        safe_table("audit_log"),
        error = function(e) {
          tibble::tibble()
        }
      )
      if (nrow(legacy) > 0 && all(c("entity_type", "action_type") %in% names(legacy))) {
        legacy <- dplyr::filter(
          legacy,
          (tolower(entity_type %||% "") %in% c("partner_intake", "partner_intake_submit")) |
            (tolower(action_type %||% "") %in% c("partner_intake", "partner_intake_submit"))
        )
        if (nrow(legacy) > 0) {
          raw_df <- legacy
          src <- "legacy audit_log"
        }
      }
    }

    if (nrow(raw_df) == 0) {
      return(list(
        df = tibble::tibble(note = "No partner intake records found in configured mirrors."),
        status = "No records available. Mirror DynamoDB submissions into SQLite or CSV for this view.",
        source = src,
        rows = 0L
      ))
    }

    names(raw_df) <- tolower(names(raw_df))
    details_col <- intersect(c("details", "detail", "payload", "payload_json"), names(raw_df))
    details_col <- if (length(details_col) > 0) details_col[[1]] else NA_character_

    parse_detail <- function(x) {
      if (is.null(x) || length(x) == 0 || all(is.na(x))) return(list())
      if (is.list(x) && !is.data.frame(x)) return(x)
      sx <- as.character(x)[1]
      if (!nzchar(sx)) return(list())
      tryCatch(
        jsonlite::fromJSON(sx, simplifyVector = TRUE),
        error = function(e) {
          list()
        }
      )
    }
    details_list <- if (!is.na(details_col)) {
      lapply(raw_df[[details_col]], parse_detail)
    } else {
      vector("list", nrow(raw_df))
    }

    detail_field <- function(key) {
      vapply(details_list, function(dd) {
        vv <- dd[[key]]
        if (is.null(vv) || length(vv) == 0 || all(is.na(vv))) "" else as.character(vv)[1]
      }, character(1))
    }

    event_time <- if ("changed_at" %in% names(raw_df)) {
      as.character(raw_df$changed_at)
    } else if ("created_at" %in% names(raw_df)) {
      as.character(raw_df$created_at)
    } else if ("timestamp" %in% names(raw_df)) {
      as.character(raw_df$timestamp)
    } else if ("sk" %in% names(raw_df)) {
      sub("^TS#([^#]+).*$", "\\1", as.character(raw_df$sk))
    } else {
      rep("", nrow(raw_df))
    }

    email <- if ("email" %in% names(raw_df)) as.character(raw_df$email) else detail_field("email")
    if ("pk" %in% names(raw_df)) {
      from_pk <- sub("^CONTACT#", "", as.character(raw_df$pk))
      email <- ifelse(nzchar(email), email, from_pk)
    }

    nr <- nrow(raw_df)
    ip_vec <- if ("ip" %in% names(raw_df)) as.character(raw_df$ip) else rep("", nr)
    msg_raw <- if ("message" %in% names(raw_df)) as.character(raw_df$message) else detail_field("message")

    # Precompute vectors: nested if/else-if inside tibble() can confuse the R parser
    # ("possible missing comma" / sourcing failure on some builds).
    status_vec <- if ("status" %in% names(raw_df)) {
      as.character(raw_df$status)
    } else if ("action_type" %in% names(raw_df)) {
      as.character(raw_df$action_type)
    } else {
      rep("", nr)
    }
    action_vec <- if ("action" %in% names(raw_df)) {
      as.character(raw_df$action)
    } else if ("action_type" %in% names(raw_df)) {
      as.character(raw_df$action_type)
    } else {
      rep("", nr)
    }

    name_vec <- if ("name" %in% names(raw_df)) as.character(raw_df$name) else detail_field("name")
    organization_vec <- if ("organization" %in% names(raw_df)) {
      as.character(raw_df$organization)
    } else {
      detail_field("organization")
    }
    submission_id_vec <- if ("submission_id" %in% names(raw_df)) {
      as.character(raw_df$submission_id)
    } else {
      detail_field("submission_id")
    }
    row_source_vec <- if ("source" %in% names(raw_df)) {
      as.character(raw_df$source)
    } else {
      detail_field("source")
    }

    out <- tibble::tibble(
      event_time = event_time,
      status = status_vec,
      email = email,
      name = name_vec,
      organization = organization_vec,
      submission_id = submission_id_vec,
      source = row_source_vec,
      action = action_vec,
      ip = ip_vec,
      message_excerpt = substr(msg_raw, 1L, 180L)
    ) |>
      dplyr::arrange(dplyr::desc(event_time)) |>
      utils::head(limit_n)

    list(
      df = out,
      status = paste0("Source: ", src, " | Rows shown: ", nrow(out), " | Checked: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
      source = src,
      rows = nrow(out)
    )
  }

  partner_audit_snapshot <- reactiveVal(load_partner_intake_admin(50L))
  partner_audit_bootstrapped <- reactiveVal(FALSE)

  observe({
    if (isTRUE(partner_audit_bootstrapped())) return(invisible(NULL))
    partner_audit_bootstrapped(TRUE)
    partner_audit_snapshot(load_partner_intake_admin(isolate(input$partner_audit_limit %||% 50L)))
  })

  observeEvent(input$btn_partner_audit_refresh, {
    if (!isTRUE(auth$admin)) {
      showNotification("Admin privileges are required for partner intake operational review.", type = "error")
      return(invisible(NULL))
    }
    snap <- load_partner_intake_admin(input$partner_audit_limit %||% 50L)
    partner_audit_snapshot(snap)
    showNotification("Partner intake admin view refreshed.", type = "message")
  })

  output$partner_audit_status <- renderPrint({
    req(auth$user)
    if (!isTRUE(auth$admin)) {
      cat("Admin access required for this panel.\n")
      return(invisible(NULL))
    }
    snap <- partner_audit_snapshot()
    cat(snap$status %||% "No status available.", "\n")
    if (!identical(snap$source, "none")) {
      cat("Tip: set PFAS_PARTNER_AUDIT_SQLITE_TABLE or PFAS_PARTNER_AUDIT_MIRROR_CSV to control data source.\n")
    }
  })

  output$tbl_partner_intake_admin <- renderDT({
    req(auth$user)
    if (!isTRUE(auth$admin)) {
      return(DT::datatable(tibble::tibble(note = "Admin access required."), rownames = FALSE))
    }
    snap <- partner_audit_snapshot()
    render_dt(snap$df, 10)
  })

  output$glp_chain_status <- renderPrint({
    if (is.null(input$glp_verify_chain_btn) || input$glp_verify_chain_btn == 0) {
      cat("Click 'Re-verify hash chain' to validate SHA-256 linkage from GENESIS.\n")
      return(invisible(NULL))
    }
    if (!exists("glp_verify_chain", mode = "function")) {
      cat("glp_audit.R not loaded.\n")
      return(invisible(NULL))
    }
    print(glp_verify_chain(con))
  })

  output$dl_glp_audit_csv <- downloadHandler(
    filename = function() {
      paste0("glp_audit_trail_", Sys.Date(), ".csv")
    },
    content = function(file) {
      oid <- op_id()
      write_audit(
        "glp_audit_trail",
        "full_table",
        "export",
        oid,
        "GLP audit trail CSV export",
        list(rows = nrow(safe_table("glp_audit_trail")))
      )
      utils::write.csv(safe_table("glp_audit_trail"), file, row.names = FALSE)
    }
  )
}

shinyApp(ui, server)
