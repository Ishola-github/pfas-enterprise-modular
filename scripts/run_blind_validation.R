#!/usr/bin/env Rscript
# run_blind_validation.R
#
# R-side helper for the sealed external blind-validation harness.
# Wraps scripts/build_blind_validation_pack.py and
# scripts/score_blind_validation.py for Shiny and R callers.

suppressPackageStartupMessages({
  library(jsonlite)
})

.bv_python <- function() {
  env_py <- Sys.getenv("PFAS_PYTHON", unset = "")
  if (nzchar(env_py)) return(env_py)
  cand <- Sys.which("python")
  if (!nzchar(cand)) cand <- Sys.which("python3")
  if (!nzchar(cand)) stop("run_blind_validation.R: cannot find python on PATH; set PFAS_PYTHON.")
  cand
}

.run_py <- function(script_rel, args, project_root) {
  log_file <- tempfile(fileext = ".log")
  on.exit(try(unlink(log_file), silent = TRUE), add = TRUE)
  rc <- system2(.bv_python(),
                c(file.path(project_root, script_rel),
                  "--project-root", project_root,
                  args),
                stdout = log_file, stderr = log_file, wait = TRUE)
  txt <- paste(readLines(log_file, warn = FALSE), collapse = "\n")
  j <- regexpr("\\{", txt)
  parsed <- if (j > 0) {
    tryCatch(jsonlite::fromJSON(substring(txt, j), simplifyVector = FALSE),
             error = function(e) list(parse_error = conditionMessage(e), raw = txt))
  } else list(raw = txt)
  list(rc = rc, log = txt, parsed = parsed)
}

#' Seal a blind-validation submission.
#' Returns list($rc, $log, $parsed) where parsed$submission_id identifies the seal.
bv_build_pack <- function(input_csv,
                          lane,
                          truth_column,
                          submitted_by,
                          model_version,
                          predicted_score_column = NULL,
                          predicted_label_column = NULL,
                          threshold_version_override = NULL,
                          note = "",
                          project_root = getwd()) {
  if (!file.exists(input_csv)) stop("input_csv not found: ", input_csv)
  project_root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)
  args <- c(
    "--input", input_csv,
    "--lane", lane,
    "--truth-column", truth_column,
    "--submitted-by", submitted_by,
    "--model-version", model_version
  )
  if (!is.null(predicted_score_column) && nzchar(predicted_score_column))
    args <- c(args, "--predicted-score-column", predicted_score_column)
  if (!is.null(predicted_label_column) && nzchar(predicted_label_column))
    args <- c(args, "--predicted-label-column", predicted_label_column)
  if (!is.null(threshold_version_override) && nzchar(threshold_version_override))
    args <- c(args, "--threshold-version-override", threshold_version_override)
  if (nzchar(note %||% ""))
    args <- c(args, "--note", note)
  .run_py("scripts/build_blind_validation_pack.py", args, project_root)
}

#' Score a sealed submission by id.
bv_score <- function(submission_id, force = FALSE, project_root = getwd()) {
  project_root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)
  args <- c("--submission-id", submission_id)
  if (isTRUE(force)) args <- c(args, "--force")
  .run_py("scripts/score_blind_validation.py", args, project_root)
}

#' List sealed submissions (parsed from the scorer's --list output).
bv_list <- function(project_root = getwd()) {
  project_root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)
  r <- .run_py("scripts/score_blind_validation.py", c("--list"), project_root)
  ids <- character(0)
  if (is.list(r$parsed) && !is.null(r$parsed$sealed_submissions)) {
    ids <- unlist(r$parsed$sealed_submissions, use.names = FALSE)
  }
  list(submissions = ids, log = r$log)
}

#' Read submissions / reveals indexes for UI rendering.
bv_read_submissions_index <- function(project_root = getwd(), tail_n = 100L) {
  p <- file.path(project_root, "validation", "blind_external", "manifests",
                 "submissions_index.jsonl")
  if (!file.exists(p)) return(data.frame())
  lines <- readLines(p, warn = FALSE)
  if (!length(lines)) return(data.frame())
  if (length(lines) > tail_n) lines <- tail(lines, tail_n)
  recs <- lapply(lines, function(x)
    tryCatch(jsonlite::fromJSON(x, simplifyVector = TRUE), error = function(e) NULL))
  recs <- Filter(Negate(is.null), recs)
  if (!length(recs)) return(data.frame())
  cols <- c("submission_id", "submitted_at", "submitted_by", "matrix_lane",
            "dataset_sha256", "manifest_sha256", "ad_policy_version",
            "model_version", "threshold_version", "n_rows")
  do.call(rbind, lapply(recs, function(r)
    as.data.frame(lapply(cols, function(c) as.character(r[[c]] %||% "")),
                  col.names = cols, stringsAsFactors = FALSE)))
}

bv_read_reveals_index <- function(project_root = getwd(), tail_n = 100L) {
  p <- file.path(project_root, "validation", "blind_external", "manifests",
                 "reveals_index.jsonl")
  if (!file.exists(p)) return(data.frame())
  lines <- readLines(p, warn = FALSE)
  if (!length(lines)) return(data.frame())
  if (length(lines) > tail_n) lines <- tail(lines, tail_n)
  recs <- lapply(lines, function(x)
    tryCatch(jsonlite::fromJSON(x, simplifyVector = TRUE), error = function(e) NULL))
  recs <- Filter(Negate(is.null), recs)
  if (!length(recs)) return(data.frame())
  rows <- lapply(recs, function(r) {
    m <- r$metrics %||% list()
    data.frame(
      submission_id   = as.character(r$submission_id  %||% ""),
      revealed_at_utc = as.character(r$revealed_at_utc %||% ""),
      matrix_lane     = as.character(r$matrix_lane    %||% ""),
      roc_auc         = as.character(m$roc_auc        %||% ""),
      precision       = as.character(m$precision      %||% ""),
      recall          = as.character(m$recall         %||% ""),
      f1              = as.character(m$f1             %||% ""),
      flags_per_10k   = as.character(m$flags_per_10k  %||% ""),
      FP_per_TP       = as.character(m$FP_per_TP      %||% ""),
      ad_in_domain    = as.character(m$ad_in_domain_count %||% ""),
      ad_warning      = as.character(m$ad_warning_count %||% ""),
      ad_reject       = as.character(m$ad_reject_count %||% ""),
      ad_policy_drift = as.character(r$ad_policy_drift %||% "FALSE"),
      threshold_drift = as.character(r$threshold_drift %||% "FALSE"),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && is.na(a))) b else a
