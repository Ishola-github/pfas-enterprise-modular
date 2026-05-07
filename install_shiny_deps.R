# Run once in R: source("install_shiny_deps.R") or Rscript install_shiny_deps.R
repos <- Sys.getenv("CRAN_MIRROR", "https://cloud.r-project.org")
pkgs <- c(
  "shiny", "shinydashboard", "shinymanager", "DT", "ggplot2", "dplyr",
  "tidyr", "tibble", "purrr", "stringr", "scales", "jsonlite", "digest",
  "DBI", "RSQLite", "readr", "readxl", "haven"
)
need <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(need)) {
  install.packages(need, repos = repos)
}
message("PFAS Enterprise Shiny dependency check complete.")
