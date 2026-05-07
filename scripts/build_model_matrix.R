# Emit data/training/model_matrix_task_counts.csv for Shiny pre-train diagnostics.
# Serum step 9 (train_pfas_model.py -> train_nhanes_serum_pfas.py) reads NHANES XPT, not this matrix.

root <- getwd()
train_dir <- file.path(root, "data", "training")
dir.create(train_dir, recursive = TRUE, showWarnings = FALSE)

count_csv_body_rows <- function(path, chunk = 65536L) {
  if (!file.exists(path)) {
    return(0L)
  }
  con <- file(path, "r")
  on.exit(close(con), add = TRUE)
  n <- 0L
  repeat {
    lines <- readLines(con, n = chunk, warn = FALSE)
    if (length(lines) == 0L) {
      break
    }
    n <- n + as.integer(length(lines))
    if (length(lines) < chunk) {
      break
    }
  }
  max(0L, n - 1L)
}

ms <- file.path(train_dir, "pfas_multisource_training.csv")
n_ms <- count_csv_body_rows(ms)

nh_csv <- file.path(train_dir, "nhanes_prepared.csv")
n_h <- if (file.exists(nh_csv)) nrow(utils::read.csv(nh_csv, stringsAsFactors = FALSE, check.names = FALSE)) else 0L

n_fac <- 0L
if (n_ms > 0L && file.exists(ms)) {
  samp <- utils::read.csv(ms, nrows = min(50000L, max(1L, n_ms)), stringsAsFactors = FALSE, check.names = FALSE)
  if (nrow(samp) > 0L && all(c("source", "facility_id") %in% names(samp))) {
    src <- tolower(as.character(samp$source))
    fid <- trimws(as.character(samp$facility_id))
    hit <- grepl("epa_icis|npdes", src) & nzchar(fid) & !is.na(fid)
    p <- sum(hit, na.rm = TRUE) / nrow(samp)
    n_fac <- as.integer(round(p * n_ms))
  }
}

frac_train <- 0.85
rows_train_env <- floor(n_ms * frac_train)
rows_test_env <- n_ms - rows_train_env
rows_train_fac <- floor(n_fac * frac_train)
rows_test_fac <- n_fac - rows_train_fac
rows_train_hum <- floor(n_h * frac_train)
rows_test_hum <- n_h - rows_train_hum

counts <- data.frame(
  task_type = c(
    "task_human_health",
    "task_environmental_occurrence",
    "task_facility_risk_enrichment"
  ),
  rows_input = c(n_h, n_ms, n_fac),
  rows_train = c(rows_train_hum, rows_train_env, rows_train_fac),
  rows_test = c(rows_test_hum, rows_test_env, rows_test_fac),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

out_fp <- file.path(train_dir, "model_matrix_task_counts.csv")
utils::write.csv(counts, out_fp, row.names = FALSE)

message(
  "Wrote task counts (diagnostic): ",
  normalizePath(out_fp, winslash = "/", mustWork = FALSE)
)
