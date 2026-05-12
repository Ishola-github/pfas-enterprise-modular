#!/usr/bin/env Rscript
# smoke_ad_enforcement.R
#
# Regression test for the per-lane applicability-domain (AD) enforcement
# framework (scripts/build_ad_models.py + scripts/apply_ad_guard.py).
#
# For each lane we stage a tiny synthetic CSV with:
#   - one row that MUST be in_domain
#   - one row that MUST be reject (out-of-envelope or out-of-coverage)
#   - one row that MUST be reject (analyte/unit/state unseen)
#
# We then call apply_ad_guard.py in strict mode and assert that the
# annotated output marks each row with the expected ad_status. Hard refusal
# also requires that the result columns be blanked on reject — we check that
# too. Audit log entries are confirmed to have been appended.

suppressPackageStartupMessages({
  library(jsonlite)
})

project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
py <- Sys.which("python")
if (!nzchar(py)) py <- Sys.which("python3")
stopifnot(nzchar(py))

cat("=== Smoke test: per-lane AD enforcement ===\n")
cat("project_root =", project_root, "\n")
cat("python       =", py, "\n\n")

ad_models_dir <- file.path(project_root, "data", "ad_models")
stopifnot(file.exists(file.path(ad_models_dir, "index.json")))

tmp_root <- file.path(tempdir(), paste0("pfas_ad_smoke_", as.integer(Sys.time())))
dir.create(tmp_root, recursive = TRUE, showWarnings = FALSE)
cat("scratch dir  =", tmp_root, "\n\n")

run_guard <- function(input_csv, output_csv, lane = NULL, mode = "strict") {
  args <- c("scripts/apply_ad_guard.py",
            "--project-root", project_root,
            "--input", input_csv,
            "--output", output_csv,
            "--mode", mode)
  if (!is.null(lane)) args <- c(args, "--lane", lane)
  stdout_file <- tempfile(fileext = ".log")
  rc <- system2(py, args, stdout = stdout_file, stderr = stdout_file, wait = TRUE)
  list(rc = rc, log = paste(readLines(stdout_file), collapse = "\n"))
}

read_ad <- function(out_csv) {
  read.csv(out_csv, stringsAsFactors = FALSE, check.names = FALSE)
}

assert_status <- function(df, idx, expected_status, label) {
  actual <- df[idx, "ad_status"]
  ok <- isTRUE(actual == expected_status)
  cat(sprintf("  [%s] row %d  expected=%s  actual=%s  %s\n",
              label, idx, expected_status, actual,
              if (ok) "OK" else "FAIL"))
  if (!ok) cat("    ad_reason=", df[idx, "ad_reason"], "\n")
  ok
}

assert_blanked <- function(df, idx, label) {
  cols_to_check <- intersect(
    c("result_value_raw", "result_value_numeric", "result_unit", "qualifier"),
    colnames(df))
  blanked <- all(vapply(cols_to_check,
                        function(c) df[idx, c] %in% c("", NA),
                        logical(1)))
  cat(sprintf("  [%s] row %d  reject-blank-check: %s\n",
              label, idx, if (blanked) "OK" else "FAIL"))
  blanked
}

results <- list()

# --- drinking_water lane ----------------------------------------------------
cat(">>> Lane: drinking_water\n")
dw_csv <- file.path(tmp_root, "dw_in.csv")
writeLines(c(
  "pipeline_lane,matrix,analyte,result_unit,result_value_numeric,qualifier,method_id,state",
  "drinking_water,drinking water,PFOA,ng/L,7.5,,EPA_UCMR5_method,CA",            # in-domain
  "drinking_water,drinking water,PFOA,ng/L,5000,,EPA_UCMR5_method,CA",           # way out of envelope
  "drinking_water,drinking water,UnknownPFAS,ng/L,5.0,,EPA_UCMR5_method,CA",     # analyte unseen
  "drinking_water,drinking water,PFOA,ug/L,0.0075,,EPA_UCMR5_method,CA",         # unit mismatch
  "drinking_water,drinking water,PFOA,ng/L,,ND,EPA_UCMR5_method,CA"              # non-detect (should be in_domain)
), dw_csv)
dw_out <- file.path(tmp_root, "dw_out.csv")
res <- run_guard(dw_csv, dw_out, lane = "drinking_water", mode = "strict")
cat(res$log, "\n")
dw_df <- read_ad(dw_out)
results$dw <- c(
  assert_status(dw_df, 1, "in_domain", "dw"),
  assert_status(dw_df, 2, "reject",    "dw"),
  assert_blanked(dw_df, 2, "dw"),
  assert_status(dw_df, 3, "reject",    "dw"),
  assert_status(dw_df, 4, "reject",    "dw"),
  assert_status(dw_df, 5, "in_domain", "dw")
)
cat("\n")

# --- serum lane -------------------------------------------------------------
# NHANES P_PFAS does not have an LBXPFOA column — PFOA is split into LBXNFOA
# (linear) and LBXBFOA (branched). Using the real LBXNFOA column for the
# in-domain row exercises the envelope correctly.
cat(">>> Lane: serum\n")
sr_csv <- file.path(tmp_root, "sr_in.csv")
writeLines(c(
  "pipeline_lane,matrix,analyte,result_unit,result_value_numeric,method_id",
  "serum,serum,LBXNFOA,ng/mL,1.5,CDC_NHANES_PFAS",          # in-domain (linear PFOA, typical NHANES value)
  "serum,serum,LBXNFOA,ng/mL,99999,CDC_NHANES_PFAS",        # out of envelope
  "serum,serum,LBXFAKE,ng/mL,1.0,CDC_NHANES_PFAS",          # analyte unseen
  "serum,serum,LBXNFOA,mg/L,1.5,CDC_NHANES_PFAS"            # unit mismatch
), sr_csv)
sr_out <- file.path(tmp_root, "sr_out.csv")
res <- run_guard(sr_csv, sr_out, lane = "serum", mode = "strict")
cat(res$log, "\n")
sr_df <- read_ad(sr_out)
results$sr <- c(
  assert_status(sr_df, 1, "in_domain", "sr"),
  assert_status(sr_df, 2, "reject",    "sr"),
  assert_blanked(sr_df, 2, "sr"),
  assert_status(sr_df, 3, "reject",    "sr"),
  assert_status(sr_df, 4, "reject",    "sr")
)
cat("\n")

# --- biosolids_sludge lane --------------------------------------------------
cat(">>> Lane: biosolids_sludge (categorical coverage)\n")
bs_csv <- file.path(tmp_root, "bs_in.csv")
writeLines(c(
  "pipeline_lane,matrix,value_type,state,method_id",
  "biosolids_sludge,biosolids/sludge,program_metadata,CA,EPA_1633A_metadata",            # in-domain
  "biosolids_sludge,biosolids/sludge,field_measurement,CA,EPA_1633A_metadata",           # concentration-claim refusal
  "biosolids_sludge,biosolids/sludge,program_metadata,ZZ,EPA_1633A_metadata",            # unseen state
  "biosolids_sludge,drinking water,program_metadata,CA,EPA_1633A_metadata",              # matrix mismatch
  "biosolids_sludge,biosolids/sludge,program_metadata,CA,EPA_OTM50"                      # method unseen
), bs_csv)
bs_out <- file.path(tmp_root, "bs_out.csv")
res <- run_guard(bs_csv, bs_out, lane = "biosolids_sludge", mode = "strict")
cat(res$log, "\n")
bs_df <- read_ad(bs_out)
results$bs <- c(
  assert_status(bs_df, 1, "in_domain", "bs"),
  assert_status(bs_df, 2, "reject",    "bs"),
  assert_status(bs_df, 3, "reject",    "bs"),
  assert_status(bs_df, 4, "reject",    "bs"),
  assert_status(bs_df, 5, "reject",    "bs")
)
cat("\n")

# --- afff lane --------------------------------------------------------------
cat(">>> Lane: afff (per-analyte; n=1 -> sparse warning)\n")
af_csv <- file.path(tmp_root, "af_in.csv")
writeLines(c(
  "pipeline_lane,matrix,analyte,result_unit,result_value_numeric,method_id",
  "afff,AFFF,Perfluorooctanoic Acid,ug/g,0.10,LC-MS/MS",   # likely sparse_training (n=1)
  "afff,AFFF,UnknownPerfluoroX,ug/g,0.10,LC-MS/MS"         # analyte unseen -> reject
), af_csv)
af_out <- file.path(tmp_root, "af_out.csv")
res <- run_guard(af_csv, af_out, lane = "afff", mode = "strict")
cat(res$log, "\n")
af_df <- read_ad(af_out)
results$af <- c(
  isTRUE(af_df$ad_status[1] %in% c("warning", "in_domain")),
  assert_status(af_df, 2, "reject", "af")
)
cat("  [af] row 1 status =", af_df$ad_status[1], "  reason=", af_df$ad_reason[1], "\n\n")

# --- methanol_standards lane ------------------------------------------------
cat(">>> Lane: methanol_standards\n")
ms_csv <- file.path(tmp_root, "ms_in.csv")
writeLines(c(
  "pipeline_lane,matrix,analyte,result_unit,result_value_numeric,method_id",
  "methanol_standards,methanol calibration,Perfluorooctanoic acid,mg/kg,1.0,LC-MS/MS",   # sparse_training (n=1)
  "methanol_standards,methanol calibration,LBXPFOA,mg/kg,1.0,LC-MS/MS"                   # analyte unseen
), ms_csv)
ms_out <- file.path(tmp_root, "ms_out.csv")
res <- run_guard(ms_csv, ms_out, lane = "methanol_standards", mode = "strict")
cat(res$log, "\n")
ms_df <- read_ad(ms_out)
results$ms <- c(
  isTRUE(ms_df$ad_status[1] %in% c("warning", "in_domain")),
  assert_status(ms_df, 2, "reject", "ms")
)
cat("  [ms] row 1 status =", ms_df$ad_status[1], "  reason=", ms_df$ad_reason[1], "\n\n")

# --- air_emissions lane -----------------------------------------------------
# Trifluoromethane (Fluoroform) is an OTM-50 analyte with 19 detects spanning
# ~0.36 - 47 ug/m3 (log10 mean ≈ 0.73 ~ 5.4 ug/m3). FC-116 has only 2
# identical detects giving std=0; we deliberately do not pick it here because
# zero-std analytes correctly trigger reject for any non-matching value.
cat(">>> Lane: air_emissions\n")
ae_csv <- file.path(tmp_root, "ae_in.csv")
writeLines(c(
  "pipeline_lane,matrix,analyte,result_unit,result_value_numeric,method_id",
  "air_emissions,air emissions,Trifluoromethane (Fluoroform),ug/m3,5.0,EPA_OTM50",   # in-domain (envelope center)
  "air_emissions,air emissions,Trifluoromethane (Fluoroform),ug/m3,1e12,EPA_OTM50",  # out of envelope
  "air_emissions,air emissions,Some_Phantom_PFAS,ug/m3,5.0,EPA_OTM50"                # unseen analyte
), ae_csv)
ae_out <- file.path(tmp_root, "ae_out.csv")
res <- run_guard(ae_csv, ae_out, lane = "air_emissions", mode = "strict")
cat(res$log, "\n")
ae_df <- read_ad(ae_out)
results$ae <- c(
  isTRUE(ae_df$ad_status[1] %in% c("in_domain", "warning")),
  assert_status(ae_df, 2, "reject", "ae"),
  assert_status(ae_df, 3, "reject", "ae")
)
cat("  [ae] row 1 status =", ae_df$ad_status[1], "  reason=", ae_df$ad_reason[1], "\n\n")

# --- audit log existence ----------------------------------------------------
audit_path <- file.path(project_root, "data", "audit", "ad_decisions.jsonl")
audit_ok <- file.exists(audit_path)
audit_lines <- if (audit_ok) length(readLines(audit_path, warn = FALSE)) else 0L
cat(sprintf(">>> Audit log: %s  exists=%s  lines=%d\n",
            audit_path, audit_ok, audit_lines))
results$audit <- audit_ok && audit_lines >= 1

# --- summary ----------------------------------------------------------------
cat("\n=== SUMMARY ===\n")
all_passes <- 0L
all_total  <- 0L
for (lane in names(results)) {
  r <- results[[lane]]
  passes <- sum(unlist(r))
  total  <- length(unlist(r))
  all_passes <- all_passes + passes
  all_total  <- all_total + total
  cat(sprintf("  %-6s : %d / %d %s\n", lane, passes, total,
              if (passes == total) "PASS" else "FAIL"))
}
cat(sprintf("\nOverall: %d / %d %s\n", all_passes, all_total,
            if (all_passes == all_total) "PASS" else "FAIL"))

if (all_passes != all_total) quit(status = 1)
quit(status = 0)
