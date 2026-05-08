# Install LatestPFAS / app.R dependencies into a user-writable library (Windows-safe).
.ver <- paste(R.version$major, strsplit(R.version$minor, ".", fixed = TRUE)[[1L]][1L], sep = ".")
ulib <- file.path(Sys.getenv("USERPROFILE"), "Documents", "R", "win-library", .ver)
dir.create(ulib, recursive = TRUE, showWarnings = FALSE)
message("User library: ", ulib)
.libPaths(c(ulib, .libPaths()))
pkgs <- c(
  "shiny", "shinydashboard", "shinymanager", "DT", "ggplot2", "dplyr", "tidyr",
  "tibble", "purrr", "stringr", "scales", "jsonlite", "httr", "digest", "DBI", "RSQLite"
)
missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1L), quietly = TRUE)]
if (length(missing)) {
  install.packages(missing, lib = ulib, repos = "https://cloud.r-project.org", type = "win.binary")
}
ok <- vapply(pkgs, requireNamespace, logical(1L), quietly = TRUE)
if (!all(ok)) stop("Some packages still missing: ", paste(pkgs[!ok], collapse = ", "))
message("All packages available.")
