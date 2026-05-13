# =============================================================================
# Convert NHANES PFAS SAS Transport (.xpt) files to CSV
# =============================================================================
#
# Purpose
# -------
# NHANES distributes its PFAS serum datasets as SAS Transport (.xpt) files.
# This script reads them with `haven::read_xpt()` and writes equivalent CSV
# files into `data/training/serum/`, ready for the `serum` matrix lane.
#
# It is intentionally narrow:
#   * one input .xpt -> one output .csv (one-to-one, no harmonization)
#   * no column renaming, no analyte mapping, no LOD logic
#   * preserves SAS variable labels in the read object (visible via str()
#     or labelled::var_label()) but CSV itself drops them by convention
#
# Three NHANES cycles are wired up:
#   * PFAS_J.xpt     -> nhanes_serum_pfas_2017_2018.csv   (cycle J)
#   * P_PFAS.xpt     -> nhanes_serum_pfas_prepandemic.csv (pre-pandemic Pre-P)
#   * L06AGE_C.xpt   -> nhanes_serum_pfas_2003_2004.csv   (cycle C, legacy panel)
#
# Usage from RStudio (with project root as working directory):
#
#   source("scripts/convert_nhanes_xpt_to_csv.R")
#
# Any input that is not on disk yet is reported as [MISSING] but does not
# stop the script. Cycles that exist are converted; the rest can be added
# later once their .xpt files are placed at the expected path.
#
# Author: pfas-enterprise-modular
# =============================================================================

suppressPackageStartupMessages({
  if (!requireNamespace("haven", quietly = TRUE)) install.packages("haven")
  if (!requireNamespace("readr", quietly = TRUE)) install.packages("readr")
  library(haven)
  library(readr)
})

`%||%` <- function(a, b) if (is.null(a)) b else a

convert_xpt <- function(input_file, output_file, label = NA_character_) {
  stopifnot(file.exists(input_file))
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)

  df <- haven::read_xpt(input_file)

  readr::write_csv(df, output_file)

  cat(sprintf(
    "[OK]      %s\n          %s -> %s\n          rows = %d, cols = %d\n",
    if (is.na(label)) basename(input_file) else label,
    input_file, output_file, nrow(df), ncol(df)
  ))

  invisible(list(
    label   = label,
    input   = input_file,
    output  = output_file,
    n_rows  = nrow(df),
    n_cols  = ncol(df),
    columns = names(df),
    labels  = vapply(
      df,
      function(x) attr(x, "label") %||% NA_character_,
      character(1)
    )
  ))
}

# -----------------------------------------------------------------------------
# Cycle table (intentionally explicit, one row per NHANES cycle)
# -----------------------------------------------------------------------------
xpt_pairs <- list(
  list(
    label  = "2017-2018 (PFAS_J, modern PFAS panel)",
    input  = "data/external/nhanes_serum/PFAS_J.xpt",
    output = "data/training/serum/nhanes_serum_pfas_2017_2018.csv"
  ),
  list(
    label  = "Pre-pandemic 2021-2023 (P_PFAS)",
    input  = "data/external/nhanes_serum/P_PFAS.xpt",
    output = "data/training/serum/nhanes_serum_pfas_prepandemic.csv"
  ),
  list(
    label  = "2003-2004 (L06AGE_C, legacy panel)",
    input  = "data/external/nhanes_serum/L06AGE_C.xpt",
    output = "data/training/serum/nhanes_serum_pfas_2003_2004.csv"
  )
)

# -----------------------------------------------------------------------------
# Run
# -----------------------------------------------------------------------------
cat("Converting NHANES PFAS .xpt files to CSV\n")
cat("Working directory:", getwd(), "\n\n")

results <- lapply(xpt_pairs, function(p) {
  if (!file.exists(p$input)) {
    cat(sprintf(
      "[MISSING] %s\n          expected at: %s (skipped)\n\n",
      p$label, p$input
    ))
    return(NULL)
  }
  res <- convert_xpt(p$input, p$output, label = p$label)
  cat("\n")
  res
})

# -----------------------------------------------------------------------------
# Schema overlap summary across cycles that did convert
# -----------------------------------------------------------------------------
ok <- Filter(Negate(is.null), results)

if (length(ok) >= 2) {
  cat("\n== Cross-cycle column overlap ==\n")
  col_sets <- lapply(ok, function(r) r$columns)
  names(col_sets) <- vapply(ok, function(r) r$label, character(1))
  all_cols <- unique(unlist(col_sets))
  presence <- vapply(
    col_sets,
    function(cs) as.integer(all_cols %in% cs),
    integer(length(all_cols))
  )
  overlap_df <- data.frame(
    column = all_cols,
    presence,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  print(utils::head(overlap_df, 50), row.names = FALSE)
  if (nrow(overlap_df) > 50) {
    cat(sprintf("... (%d more columns)\n", nrow(overlap_df) - 50))
  }
} else {
  cat("\nFewer than two cycles converted; skipping overlap summary.\n")
}

invisible(results)
