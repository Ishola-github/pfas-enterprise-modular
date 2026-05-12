#!/usr/bin/env Rscript
# run_ad_guard.R
#
# R-side helper for the per-lane Applicability-Domain (AD) guard. This is the
# canonical entry point used by the Shiny app and any R-driven pipeline.
#
# It wraps scripts/apply_ad_guard.py and:
#   1. Locates the project Python interpreter (PATH or env override).
#   2. Resolves --lane (or routes per-row by pipeline_lane).
#   3. Calls the guard in strict mode by default.
#   4. Captures the JSON summary printed by the guard so callers can render
#      counts / refusal reasons / audit-log path in the UI.
#   5. Returns a list with: $rc, $summary (parsed JSON), $output_csv, $log_text.
#
# Usage:
#   source("scripts/run_ad_guard.R")
#   res <- run_ad_guard(
#     input_csv  = "data/uploads/my_water.csv",
#     output_csv = "data/uploads/my_water.ad_annotated.csv",
#     lane       = "drinking_water",
#     mode       = "strict"
#   )
#   res$summary$counts    # named list of in_domain / warning / reject

suppressPackageStartupMessages({
  library(jsonlite)
})

# Locate the Python interpreter once at source time. Allow override via env.
.ad_python <- function() {
  env_py <- Sys.getenv("PFAS_PYTHON", unset = "")
  if (nzchar(env_py)) return(env_py)
  cand <- Sys.which("python")
  if (!nzchar(cand)) cand <- Sys.which("python3")
  if (!nzchar(cand)) stop("run_ad_guard.R: cannot find a python interpreter on PATH; set PFAS_PYTHON.")
  cand
}

run_ad_guard <- function(
  input_csv,
  output_csv = NULL,
  lane = NULL,
  mode = c("strict", "annotate"),
  project_root = getwd(),
  audit = TRUE
) {
  mode <- match.arg(mode)
  if (!file.exists(input_csv)) {
    stop("run_ad_guard.R: input not found: ", input_csv)
  }
  project_root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)

  if (is.null(output_csv)) {
    output_csv <- sub("\\.csv$", ".ad_annotated.csv", input_csv, ignore.case = TRUE)
    if (identical(output_csv, input_csv)) {
      output_csv <- paste0(input_csv, ".ad_annotated.csv")
    }
  }

  args <- c(
    file.path(project_root, "scripts", "apply_ad_guard.py"),
    "--project-root", project_root,
    "--input", input_csv,
    "--output", output_csv,
    "--mode", mode
  )
  if (!is.null(lane) && nzchar(lane)) {
    args <- c(args, "--lane", lane)
  }
  if (!audit) {
    args <- c(args, "--no-audit")
  }

  log_file <- tempfile(fileext = ".log")
  on.exit(try(unlink(log_file), silent = TRUE), add = TRUE)
  rc <- system2(.ad_python(), args, stdout = log_file, stderr = log_file, wait = TRUE)
  log_text <- paste(readLines(log_file, warn = FALSE), collapse = "\n")

  summary_obj <- list()
  jstart <- regexpr("\\{", log_text)
  if (jstart > 0) {
    candidate <- substring(log_text, jstart)
    summary_obj <- tryCatch(
      jsonlite::fromJSON(candidate, simplifyVector = FALSE),
      error = function(e) list(parse_error = conditionMessage(e), raw = candidate)
    )
  }

  list(
    rc = rc,
    summary = summary_obj,
    output_csv = output_csv,
    log_text = log_text,
    mode = mode,
    lane = lane
  )
}

# Convenience: build all per-lane AD models from the canonical training CSVs.
# Wrapper around scripts/build_ad_models.py.
rebuild_ad_models <- function(project_root = getwd(), lane = "all") {
  project_root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)
  args <- c(
    file.path(project_root, "scripts", "build_ad_models.py"),
    "--project-root", project_root,
    "--lane", lane
  )
  log_file <- tempfile(fileext = ".log")
  on.exit(try(unlink(log_file), silent = TRUE), add = TRUE)
  rc <- system2(.ad_python(), args, stdout = log_file, stderr = log_file, wait = TRUE)
  list(
    rc = rc,
    log_text = paste(readLines(log_file, warn = FALSE), collapse = "\n"),
    index = tryCatch(
      jsonlite::fromJSON(file.path(project_root, "data", "ad_models", "index.json"),
                         simplifyVector = FALSE),
      error = function(e) list(parse_error = conditionMessage(e))
    )
  )
}

# Read the AD audit log (jsonl) as a data.frame for display.
read_ad_audit <- function(
  project_root = getwd(),
  tail_n = 200L
) {
  audit_path <- file.path(project_root, "data", "audit", "ad_decisions.jsonl")
  if (!file.exists(audit_path)) {
    return(data.frame(
      timestamp_utc = character(),
      reference_lane = character(),
      ad_status = character(),
      ad_reason = character(),
      ad_distance = character(),
      training_range_version = character(),
      ad_model_version = character(),
      mode = character(),
      stringsAsFactors = FALSE
    ))
  }
  lines <- readLines(audit_path, warn = FALSE)
  if (length(lines) == 0L) {
    return(data.frame())
  }
  if (length(lines) > tail_n) {
    lines <- tail(lines, tail_n)
  }
  recs <- lapply(lines, function(x) tryCatch(jsonlite::fromJSON(x), error = function(e) NULL))
  recs <- Filter(Negate(is.null), recs)
  if (!length(recs)) return(data.frame())

  cols <- c("timestamp_utc", "reference_lane", "ad_status", "ad_reason",
            "ad_distance", "training_range_version", "ad_model_version", "mode")
  df <- do.call(rbind, lapply(recs, function(r) {
    as.data.frame(lapply(cols, function(c) as.character(r[[c]] %||% "")),
                  col.names = cols, stringsAsFactors = FALSE)
  }))
  df
}

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && is.na(a))) b else a
