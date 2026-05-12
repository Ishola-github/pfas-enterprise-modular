# Reference-data sanity check (no extra packages).
# PowerShell / CI:  Rscript scripts/reference_registry_r_check.R
# RStudio:         Set working directory to project root, then Source this file.

args <- commandArgs(trailingOnly = FALSE)
idx <- grep("^--file=", args, value = FALSE)
file_arg <- if (length(idx)) sub("^--file=", "", args[idx[[1]]]) else ""
root <- if (nzchar(file_arg)) {
  normalizePath(file.path(dirname(file_arg), ".."))
} else {
  normalizePath(getwd())
}

reg <- file.path(root, "data", "reference", "registry", "reference_registry.csv")
nist_serum <- file.path(root, "data", "reference", "nist", "srm1957", "serum_pfas.csv")
nist_rm8446 <- file.path(root, "data", "reference", "nist", "rm8446", "methanol_pfas.csv")
nist_rm8690 <- file.path(root, "data", "reference", "nist", "rm8690", "afff_pfas.csv")

ok <- function(path) isTRUE(file.exists(path))

cat("=== R reference sanity (project root:", root, ") ===\n", sep = "")
stopifnot(
  ok(reg),
  ok(nist_serum),
  ok(nist_rm8446),
  ok(nist_rm8690)
)
lines <- readLines(reg, warn = FALSE)
stopifnot(length(lines) >= 2L)
cat("registry lines:", length(lines), "\n")
cat("R checks: OK\n")
