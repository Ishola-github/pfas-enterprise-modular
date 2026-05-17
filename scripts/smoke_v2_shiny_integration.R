# Smoke test: V2 R wrapper (same path Shiny uses).
root <- Sys.getenv("PFAS_SMOKE_PROJECT_ROOT", unset = "")
if (!nzchar(root)) {
  root <- normalizePath(getwd(), winslash = "/")
}
source(file.path(root, "scripts", "run_v2_contextualization.R"), local = TRUE)

fixture <- file.path(root, "data", "v1", "fixtures", "nhanes_j_governed_v1_input.csv")
out <- file.path(root, "data", "v2", "outputs", "smoke_shiny")
dir.create(out, recursive = TRUE, showWarnings = FALSE)

res <- run_v2_serum_contextualization(
  input_csv = fixture,
  output_dir = out,
  project_root = root
)
cat(res$log, "\n")
if (!isTRUE(res$ok)) {
  stop("V2 smoke failed: ", res$message)
}
cat("PASS run_id=", res$summary$run_id, "\n")
