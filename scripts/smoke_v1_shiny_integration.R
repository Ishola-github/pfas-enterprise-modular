# Smoke: V1 R wrapper + governed template (same path Shiny uses).
#
#   Rscript scripts/smoke_v1_shiny_integration.R

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
}

root <- Sys.getenv("PFAS_SMOKE_PROJECT_ROOT", "")
if (!nzchar(root)) {
  root <- normalizePath(getwd(), winslash = "/")
}

source(file.path(root, "scripts", "run_v1_contextualization.R"), local = TRUE)

template <- file.path(root, "data", "v1", "templates", "governed_serum_pfos_pfoa_input_template.csv")
out_dir <- file.path(root, "data", "v1", "outputs", "smoke_shiny")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

stopifnot(file.exists(template))

res <- run_v1_serum_contextualization(
  input_csv = template,
  output_dir = out_dir,
  project_root = root,
  default_cycle = "J"
)

if (!isTRUE(res$ok)) {
  cat("FAIL:", res$message, "\n", res$log, "\n", sep = "")
  quit(status = 1)
}

sm <- res$summary
pdf_ok <- is.null(sm$pdf_path) || identical(sm$pdf_skipped, TRUE) || file.exists(sm$pdf_path)
checks <- c(
  file.exists(sm$csv_path),
  pdf_ok,
  file.exists(sm$manifest_path),
  is.numeric(sm$n_in_domain) && sm$n_in_domain >= 1L,
  is.numeric(sm$n_refused) && sm$n_refused >= 0L,
  nzchar(sm$run_id),
  nzchar(sm$output_csv_sha256)
)
names(checks) <- c("csv", "pdf", "manifest", "n_in_domain", "n_refused", "run_id", "output_hash")

if (!all(checks)) {
  cat("FAIL checks:\n")
  print(checks)
  quit(status = 1)
}

cat("PASS smoke_v1_shiny_integration run_id=", sm$run_id, "\n", sep = "")
