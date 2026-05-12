#!/usr/bin/env Rscript
# smoke_blind_validation.R
#
# Regression test for the sealed external blind-validation harness:
#   scripts/build_blind_validation_pack.py
#   scripts/score_blind_validation.py
#
# Test cycle (deterministic; produces no leftover artifacts in the repo):
#   1. Generate a synthetic drinking_water dataset with truth_label and
#      predicted_score/label columns.
#   2. Seal it via build_blind_validation_pack.py -> capture submission_id.
#   3. Score it -> assert all 9 required metric fields are present and the
#      reveal JSON is well-formed.
#   4. Re-score without --force -> assert single-shot refusal
#      (status = ALREADY_REVEALED).
#   5. Tamper with the sealed dataset (append a row) -> attempt to re-score
#      with --force -> assert hash-mismatch refusal
#      (status = REFUSED, exit_code = 3).
#   6. Clean up the test submission.
#
# This test does NOT pollute manifests/submissions_index.jsonl with the
# test submission: it uses a dedicated --project-root pointing at a scratch
# directory that mirrors the canonical layout (data/config, data/ad_models,
# data/audit, validation/blind_external) via symlinks where possible and
# copies otherwise.

suppressPackageStartupMessages({
  library(jsonlite)
})

repo_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
py <- Sys.which("python")
if (!nzchar(py)) py <- Sys.which("python3")
stopifnot(nzchar(py))

cat("=== Smoke test: blind-validation harness ===\n")
cat("repo_root =", repo_root, "\n")
cat("python    =", py, "\n\n")

# Use a scratch project root so we don't write into the canonical
# validation/blind_external/ tree at all.
scratch <- file.path(tempdir(), paste0("pfas_blindval_smoke_", as.integer(Sys.time())))
dir.create(scratch, recursive = TRUE, showWarnings = FALSE)
cat("scratch   =", scratch, "\n\n")

# Mirror the directories the scripts need to read.
for (sub in c("data/config", "data/ad_models", "scripts",
              "validation/blind_external/sealed",
              "validation/blind_external/revealed",
              "validation/blind_external/manifests",
              "validation/blind_external/submissions")) {
  dir.create(file.path(scratch, sub), recursive = TRUE, showWarnings = FALSE)
}

file.copy(
  file.path(repo_root, "data", "config", "matrix_pipeline_sop.csv"),
  file.path(scratch, "data", "config", "matrix_pipeline_sop.csv"),
  overwrite = TRUE
)
limits <- file.path(repo_root, "data", "config", "ucmr_analyte_limits_ngl.csv")
if (file.exists(limits)) {
  file.copy(limits, file.path(scratch, "data", "config", "ucmr_analyte_limits_ngl.csv"),
            overwrite = TRUE)
}
for (lane in c("drinking_water", "serum", "biosolids_sludge", "afff",
               "methanol_standards", "air_emissions")) {
  src <- file.path(repo_root, "data", "ad_models", lane, "ad_model.json")
  if (file.exists(src)) {
    dir.create(file.path(scratch, "data", "ad_models", lane), recursive = TRUE,
               showWarnings = FALSE)
    file.copy(src, file.path(scratch, "data", "ad_models", lane, "ad_model.json"),
              overwrite = TRUE)
  }
}
file.copy(
  file.path(repo_root, "scripts", "apply_ad_guard.py"),
  file.path(scratch, "scripts", "apply_ad_guard.py"),
  overwrite = TRUE
)
file.copy(
  file.path(repo_root, "scripts", "build_blind_validation_pack.py"),
  file.path(scratch, "scripts", "build_blind_validation_pack.py"),
  overwrite = TRUE
)
file.copy(
  file.path(repo_root, "scripts", "score_blind_validation.py"),
  file.path(scratch, "scripts", "score_blind_validation.py"),
  overwrite = TRUE
)

# Generate the synthetic dataset.
set.seed(123)
n <- 100L
analytes <- c("PFOA", "PFOS", "PFHxS", "PFBS", "PFHpA", "PFBA", "PFHxA", "PFNA", "PFDA")
truth <- as.integer(runif(n) < 0.2)
base  <- ifelse(truth == 1L, 2.5, 1.0)
val   <- pmax(0.01, exp(rnorm(n, 0, 0.6)) * base)
score <- 1 / (1 + exp(-(val - 4.0) / 2.0))
label <- as.integer(score >= 0.5)

df <- data.frame(
  pipeline_lane        = "drinking_water",
  matrix               = "drinking water",
  analyte              = sample(analytes, n, replace = TRUE),
  result_unit          = "ng/L",
  result_value_numeric = sprintf("%.3f", val),
  method_id            = "EPA_UCMR5_method",
  state                = "CA",
  qualifier            = "",
  truth_label          = truth,
  predicted_score      = sprintf("%.4f", score),
  predicted_label      = label,
  stringsAsFactors     = FALSE
)
dataset_csv <- file.path(scratch, "validation", "blind_external", "submissions",
                         "smoke_drinking_water.csv")
write.csv(df, dataset_csv, row.names = FALSE)
cat(sprintf("synthetic dataset: %d rows, %d positives\n\n", nrow(df), sum(truth)))

run <- function(script, args, expect_rc = 0L) {
  out_file <- tempfile(fileext = ".log")
  on.exit(try(unlink(out_file), silent = TRUE), add = TRUE)
  rc <- system2(py,
                c(file.path(scratch, "scripts", script),
                  "--project-root", scratch, args),
                stdout = out_file, stderr = out_file, wait = TRUE)
  log_text <- paste(readLines(out_file, warn = FALSE), collapse = "\n")
  list(rc = rc, log = log_text)
}

parse_json_tail <- function(log_text) {
  j <- regexpr("\\{", log_text)
  if (j > 0) {
    cand <- substring(log_text, j)
    return(tryCatch(jsonlite::fromJSON(cand, simplifyVector = FALSE),
                    error = function(e) list(parse_error = conditionMessage(e))))
  }
  list(parse_error = "no JSON in stdout")
}

results <- list()

cat("--- 1. Seal submission ---\n")
seal <- run("build_blind_validation_pack.py",
            c("--input", dataset_csv,
              "--lane", "drinking_water",
              "--truth-column", "truth_label",
              "--predicted-score-column", "predicted_score",
              "--predicted-label-column", "predicted_label",
              "--submitted-by", "smoke_test",
              "--model-version", "smoke_v1+commit_test"))
cat("rc=", seal$rc, "\n")
seal_obj <- parse_json_tail(seal$log)
print(seal_obj)
sub_id <- seal_obj$submission_id
ok_seal <- !is.null(sub_id) && nzchar(sub_id) && identical(seal_obj$status, "sealed")
results$seal <- ok_seal
cat("seal ok =", ok_seal, "\n\n")

cat("--- 2. Score submission ---\n")
sc <- run("score_blind_validation.py", c("--submission-id", sub_id))
cat("rc=", sc$rc, "\n")
score_obj <- parse_json_tail(sc$log)
print(score_obj)
metrics <- score_obj$metrics %||% list()
required_keys <- c("roc_auc", "precision", "recall", "f1", "flags_per_10k",
                   "FP_per_TP", "ad_reject_count", "ad_warning_count",
                   "ad_in_domain_count")
have_all <- all(required_keys %in% names(metrics))
ok_score <- identical(score_obj$status, "REVEALED") && have_all
results$score_revealed <- ok_score
results$score_has_all_metrics <- have_all
cat("score REVEALED =", ok_score, "  all required fields present =", have_all, "\n\n")

cat("--- 3. Re-score without --force (single-shot refusal) ---\n")
sc2 <- run("score_blind_validation.py", c("--submission-id", sub_id))
sc2_obj <- parse_json_tail(sc2$log)
print(sc2_obj)
ok_singleshot <- identical(sc2_obj$status, "ALREADY_REVEALED")
results$single_shot <- ok_singleshot
cat("single-shot enforcement =", ok_singleshot, "\n\n")

cat("--- 4. Tamper with sealed dataset + force-score (hash refusal) ---\n")
sealed_csv <- file.path(scratch, "validation", "blind_external", "sealed", sub_id, "dataset.csv")
if (file.exists(sealed_csv)) {
  Sys.chmod(sealed_csv, mode = "0666")
  cat("  pre-tamper sealed size:", file.info(sealed_csv)$size, "bytes\n")
  con <- file(sealed_csv, open = "ab")
  writeLines("drinking_water,drinking water,FAKE,ng/L,99,EPA_UCMR5_method,CA,,0,0.5,1", con)
  close(con)
  cat("  post-tamper sealed size:", file.info(sealed_csv)$size, "bytes\n")
}
sc3 <- run("score_blind_validation.py", c("--submission-id", sub_id, "--force"))
sc3_obj <- parse_json_tail(sc3$log)
print(sc3_obj)
ok_tamper <- identical(sc3_obj$status, "REFUSED") &&
             identical(sc3_obj$reason, "dataset_sha256_mismatch") &&
             identical(as.integer(sc3$rc), 3L)
results$tamper_refused <- ok_tamper
cat("tamper refusal =", ok_tamper, "  exit_code =", sc3$rc, "\n\n")

cat("--- 5. Manifest index sanity ---\n")
idx <- file.path(scratch, "validation", "blind_external", "manifests",
                 "submissions_index.jsonl")
ok_idx <- file.exists(idx) && length(readLines(idx, warn = FALSE)) >= 1L
cat("submissions_index.jsonl exists with >=1 line:", ok_idx, "\n")
results$index_written <- ok_idx
rev_idx <- file.path(scratch, "validation", "blind_external", "manifests",
                     "reveals_index.jsonl")
ok_rev_idx <- file.exists(rev_idx) && length(readLines(rev_idx, warn = FALSE)) >= 1L
cat("reveals_index.jsonl exists with >=1 line   :", ok_rev_idx, "\n")
results$rev_index_written <- ok_rev_idx

cat("\n=== SUMMARY ===\n")
all_pass <- TRUE
for (nm in names(results)) {
  cat(sprintf("  %-25s : %s\n", nm,
              if (isTRUE(results[[nm]])) "PASS" else "FAIL"))
  if (!isTRUE(results[[nm]])) all_pass <- FALSE
}
cat(sprintf("\nOverall: %s\n", if (all_pass) "PASS" else "FAIL"))

if (!all_pass) quit(status = 1)
quit(status = 0)

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && is.na(a))) b else a
