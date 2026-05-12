# Smoke test: SOP matrix-separation merge guard in prepare_multisource_training.R
#
# Stages two fixture _normalized.csv files (UCMR drinking water + AFFF foam) under a
# temp project root, runs the real prepare_multisource_training.R against it, and
# checks the expected behavior:
#   - Two distinct PFAS pipeline lanes -> stop()/non-zero exit (default).
#   - Same two parts, PFAS_ALLOW_MULTISOURCE_MERGE=1 -> warn + zero exit (escape hatch).
# Run from repo root:
#   Rscript scripts/smoke_sop_matrix_separation.R

repo_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
script_src <- file.path(repo_root, "scripts", "prepare_multisource_training.R")
if (!file.exists(script_src)) {
  stop("Run from repo root containing scripts/prepare_multisource_training.R")
}

sop_src <- file.path(repo_root, "data", "config", "matrix_pipeline_sop.csv")
if (!file.exists(sop_src)) {
  stop("Missing data/config/matrix_pipeline_sop.csv")
}

tmp_root <- tempfile("pfas_sop_smoke_")
dir.create(tmp_root, showWarnings = FALSE, recursive = TRUE)
on.exit(unlink(tmp_root, recursive = TRUE, force = TRUE), add = TRUE)

dir.create(file.path(tmp_root, "scripts"), showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(tmp_root, "data", "config"), showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(tmp_root, "data", "external_uploads"), showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(tmp_root, "data", "processed"), showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(tmp_root, "data", "training"), showWarnings = FALSE, recursive = TRUE)

file.copy(script_src, file.path(tmp_root, "scripts", "prepare_multisource_training.R"), overwrite = TRUE)
file.copy(sop_src, file.path(tmp_root, "data", "config", "matrix_pipeline_sop.csv"), overwrite = TRUE)

schema_cols <- c(
  "source", "source_dataset", "sample_id", "matrix", "sample_date",
  "analyte", "cas", "result_value", "result_unit", "qualifier",
  "mdl", "rl", "detect_flag", "state", "county", "latitude", "longitude",
  "region", "facility_water_type", "sample_point_type", "method_id",
  "collection_year", "collection_month", "pws_size", "facility_id", "sample_point_id",
  "health_endpoint", "health_value", "dataset_type", "upload_id", "uploaded_at",
  "pipeline_lane"
)

mk_row <- function(matrix_val, src_dataset, analyte) {
  base <- as.list(setNames(rep(NA, length(schema_cols)), schema_cols))
  base$source <- "external_upload"
  base$source_dataset <- src_dataset
  base$sample_id <- paste0("SAMPLE_", analyte)
  base$matrix <- matrix_val
  base$sample_date <- "2025-01-01"
  base$analyte <- analyte
  base$cas <- "335-67-1"
  base$result_value <- 5.5
  base$result_unit <- "ng/L"
  base$detect_flag <- 1L
  base$method_id <- "EPA_533"
  base$dataset_type <- "environmental occurrence"
  as.data.frame(base, stringsAsFactors = FALSE, check.names = FALSE)
}

ucmr_rows <- do.call(rbind, list(
  mk_row("finished drinking water", "UCMR5", "PFOA"),
  mk_row("finished drinking water", "UCMR5", "PFOS")
))
afff_rows <- do.call(rbind, list(
  mk_row("AFFF foam", "NIST_RM8690", "PFOS"),
  mk_row("AFFF foam", "NIST_RM8690", "PFHxS")
))

utils::write.csv(ucmr_rows,
  file.path(tmp_root, "data", "external_uploads", "UPL-UCMR-001_normalized.csv"),
  row.names = FALSE
)
utils::write.csv(afff_rows,
  file.path(tmp_root, "data", "external_uploads", "UPL-AFFF-001_normalized.csv"),
  row.names = FALSE
)

run_in <- function(cwd, env_extra = character(0)) {
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  log_path <- tempfile("sop_smoke_log_", fileext = ".txt")
  old_env <- list()
  for (kv in env_extra) {
    parts <- strsplit(kv, "=", fixed = TRUE)[[1]]
    old_env[[parts[[1]]]] <- Sys.getenv(parts[[1]], unset = NA_character_)
    do.call(Sys.setenv, setNames(list(parts[[2]]), parts[[1]]))
  }
  old_wd <- getwd()
  setwd(cwd)
  status <- tryCatch(
    system2(
      rscript,
      args = c("--vanilla", "scripts/prepare_multisource_training.R"),
      stdout = log_path,
      stderr = log_path,
      wait = TRUE
    ),
    error = function(e) 99L
  )
  setwd(old_wd)
  for (k in names(old_env)) {
    v <- old_env[[k]]
    if (is.na(v)) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(v), k))
  }
  out <- if (file.exists(log_path)) paste(readLines(log_path, warn = FALSE), collapse = "\n") else ""
  list(status = as.integer(status), output = out)
}

cat("=== TEST 1: two lanes, default (should BLOCK) ===\n")
Sys.unsetenv("PFAS_ALLOW_MULTISOURCE_MERGE")
r1 <- run_in(tmp_root)
cat(r1$output, "\n")
cat("exit_code: ", r1$status, "\n\n", sep = "")

cat("=== TEST 2: two lanes, PFAS_ALLOW_MULTISOURCE_MERGE=1 (should WARN + write) ===\n")
r2 <- run_in(tmp_root, env_extra = c("PFAS_ALLOW_MULTISOURCE_MERGE=1"))
cat(r2$output, "\n")
cat("exit_code: ", r2$status, "\n\n", sep = "")
Sys.unsetenv("PFAS_ALLOW_MULTISOURCE_MERGE")

cat("=== TEST 3: drop AFFF -> single lane (should PASS) ===\n")
file.remove(file.path(tmp_root, "data", "external_uploads", "UPL-AFFF-001_normalized.csv"))
r3 <- run_in(tmp_root)
cat(r3$output, "\n")
cat("exit_code: ", r3$status, "\n\n", sep = "")

ok1 <- r1$status != 0L && grepl("SOP matrix separation", r1$output, fixed = FALSE)
ok2 <- r2$status == 0L && grepl("WARNING: multiple pipeline lanes merged", r2$output)
ok3 <- r3$status == 0L && grepl("Wrote .* rows", r3$output)

cat("=== SUMMARY ===\n")
cat("TEST 1 (block on two lanes):  ", if (ok1) "PASS" else "FAIL", "\n")
cat("TEST 2 (warn + merge with override): ", if (ok2) "PASS" else "FAIL", "\n")
cat("TEST 3 (single lane writes csv):     ", if (ok3) "PASS" else "FAIL", "\n")

if (!(ok1 && ok2 && ok3)) {
  quit(status = 1L)
}
