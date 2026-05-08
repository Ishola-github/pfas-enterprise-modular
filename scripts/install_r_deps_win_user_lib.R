# Install LatestPFAS / app.R dependencies into a user-writable library (Windows-safe).
# Respects R_LIBS_USER; otherwise uses %LOCALAPPDATA%\R\win-library\<x.y> or Documents\...

argv <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", argv, value = TRUE)
script_dir <- if (length(file_arg)) {
  dirname(normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/"))
} else {
  getwd()
}
source(file.path(script_dir, "_win_user_lib.R"))

ulib <- win_user_lib_dir()
dir.create(ulib, recursive = TRUE, showWarnings = FALSE)
message("User library: ", ulib)
.libPaths(c(ulib, .libPaths()))
pkgs <- c(
  "shiny", "shinydashboard", "shinymanager", "DT", "ggplot2", "dplyr", "tidyr",
  "tibble", "purrr", "stringr", "scales", "jsonlite", "httr", "digest", "DBI", "RSQLite",
  "markdown"
)
missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1L), quietly = TRUE)]
if (length(missing)) {
  install.packages(missing, lib = ulib, repos = "https://cloud.r-project.org", type = "win.binary")
}
ok <- vapply(pkgs, requireNamespace, logical(1L), quietly = TRUE)
if (!all(ok)) stop("Some packages still missing: ", paste(pkgs[!ok], collapse = ", "))
message("All packages available.")
