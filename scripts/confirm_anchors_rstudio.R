# =============================================================================
# Three-environment confirmation -- RStudio / Rscript side.
# =============================================================================
#
# Computes SHA-256 of the four serum-lane integrity anchors using
# the `digest` package (the same hash algorithm the governance
# smokes already use) and writes the result deterministically to
# validation/serum_h_v1/.confirm_rstudio.txt.
#
# Output format mirrors `sha256sum` so the three environments can
# be diffed line-for-line.
#
# Intended invocation (from the repo root):
#
#   Rscript scripts/confirm_anchors_rstudio.R
#
# Or from an RStudio session:
#
#   source("scripts/confirm_anchors_rstudio.R")
#
# =============================================================================

suppressPackageStartupMessages({
  if (!requireNamespace("digest", quietly = TRUE)) install.packages("digest", repos = c(CRAN = "https://cloud.r-project.org"))
  library(digest)
})

files <- c(
  "data/training/serum/nhanes_serum_pfas_2017_2018.csv",
  "data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv",
  "data/external/nhanes_serum_h/PFAS_H.XPT",
  "data/external/nhanes_serum_h/SSPFAS_H.XPT"
)

out_lines <- c(
  "# Three-environment confirmation -- R / Rscript",
  sprintf("# R version:       %s", R.version.string),
  sprintf("# Platform:        %s", R.version$platform),
  sprintf("# Run timestamp:   %s",
          format(Sys.time(), tz = "UTC", "%Y-%m-%dT%H:%M:%SZ")),
  ""
)

for (rel in files) {
  if (file.exists(rel)) {
    h  <- digest::digest(file = rel, algo = "sha256")
    sz <- file.info(rel)$size
    out_lines <- c(out_lines,
                   sprintf("%s  %s  (%d bytes)", h, rel, sz))
  } else {
    out_lines <- c(out_lines,
                   sprintf("MISSING  ----------------------------------------------------------------  %s",
                           rel))
  }
}

dir.create("validation/serum_h_v1", recursive = TRUE, showWarnings = FALSE)
writeLines(out_lines, "validation/serum_h_v1/.confirm_rstudio.txt")

cat("[confirm_rstudio] wrote validation/serum_h_v1/.confirm_rstudio.txt\n")
cat(paste(out_lines, collapse = "\n"), "\n", sep = "")
