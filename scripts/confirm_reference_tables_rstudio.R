# =============================================================================
# Three-environment confirmation -- R / Rscript (reference tables side).
# =============================================================================
#
# Hashes the two precomputed reference tables and all 8 raw XPTs
# under data/raw/nhanes/ using digest::digest(file=, algo='sha256')
# and writes the result to:
#
#   data/reference_tables/.confirm_rstudio.txt
#
# Invocation (from the repo root):
#
#   Rscript scripts/confirm_reference_tables_rstudio.R
# =============================================================================

suppressPackageStartupMessages({
  if (!requireNamespace("digest", quietly = TRUE)) install.packages("digest", repos = c(CRAN = "https://cloud.r-project.org"))
  library(digest)
})

files <- c(
  "data/reference_tables/nhanes_pfas_reference_tables_v1.csv",
  "data/reference_tables/nhanes_pfas_weighted_reference_tables_v1.csv",
  "data/raw/nhanes/2013_2014/PFAS_H.XPT",
  "data/raw/nhanes/2013_2014/DEMO_H.XPT",
  "data/raw/nhanes/2015_2016/PFAS_I.XPT",
  "data/raw/nhanes/2015_2016/DEMO_I.XPT",
  "data/raw/nhanes/2017_2018/PFAS_J.XPT",
  "data/raw/nhanes/2017_2018/DEMO_J.XPT",
  "data/raw/nhanes/2017_2020/P_PFAS.XPT",
  "data/raw/nhanes/2017_2020/P_DEMO.XPT"
)

out_lines <- c(
  "# Three-environment confirmation -- R / Rscript (reference tables + raw XPTs)",
  sprintf("# R version:     %s", R.version.string),
  sprintf("# Platform:      %s", R.version$platform),
  sprintf("# Run timestamp: %s",
          format(Sys.time(), tz = "UTC", "%Y-%m-%dT%H:%M:%SZ")),
  ""
)

for (rel in files) {
  if (file.exists(rel)) {
    h <- digest::digest(file = rel, algo = "sha256")
    sz <- file.info(rel)$size
    out_lines <- c(out_lines,
                   sprintf("%s  %s  (%d bytes)", h, rel, sz))
  } else {
    out_lines <- c(out_lines,
                   sprintf("MISSING  ----------------------------------------------------------------  %s",
                           rel))
  }
}

dir.create("data/reference_tables", recursive = TRUE, showWarnings = FALSE)
writeLines(out_lines, "data/reference_tables/.confirm_rstudio.txt")

cat("[confirm_reference_tables_rstudio] wrote data/reference_tables/.confirm_rstudio.txt\n")
cat(paste(out_lines, collapse = "\n"), "\n", sep = "")
