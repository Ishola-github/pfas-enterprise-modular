# =============================================================================
# Convert NHANES PFAS_H (cycle H, 2013-2014) SAS Transport (.xpt) to CSV
# =============================================================================
#
# Purpose
# -------
# This is the R-only peer of `scripts/docker_fetch_pfas_h.sh` and the
# cycle-H counterpart of `scripts/convert_nhanes_xpt_to_csv.R` (which
# converts cycle J / pre-pandemic / cycle C; the cycle-H lane is
# intentionally separated so its output never mixes with the cycle-J
# anchor directory `data/training/serum/`).
#
# It reads `PFAS_H.XPT` with `haven::read_xpt()`, normalizes column
# names with `janitor::clean_names()`, and writes the cycle-H lane
# anchor CSV at:
#
#   data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv
#
# Conversion contract (must match `scripts/docker_fetch_pfas_h.sh`):
#   * read_xpt        --  reads SAS Transport v5/v8 directly, preserves
#                         the SAS variable labels as `label` attributes
#                         on each column (visible via
#                         labelled::var_label(); not written to CSV).
#   * clean_names     --  normalizes the SAS uppercase variable names
#                         (`SEQN`, `WTSB2YR`, `LBXPFDE`, ...) to
#                         lowercase snake_case (`seqn`, `wtsb2yr`,
#                         `lbxpfde`, ...). This matches the same
#                         pipeline used by cycle J's converter and is
#                         the governance contract recorded in
#                         `validation/serum_h_v1/schema_contract.md`
#                         under "Column naming convention".
#   * write_csv       --  writes UTF-8, LF, comma-delimited, no row
#                         names. Default `readr` behavior.
#
# Expected output:
#   rows = 2,339
#   cols = 18
#   SHA-256 of CSV = 98d11b27beadad159a9bb596caa2e8839b5bfca279fd32f618e60539c53f644f
#
# Required input:
#   data/external/nhanes_serum_h/PFAS_H.XPT
#   (downloaded from
#   https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/PFAS_H.xpt
#   by scripts/docker_fetch_pfas_h.sh, or manually placed there.)
#
# What this script does NOT do (kept honest):
#   * Convert SSPFAS_H.XPT (the surplus-serum isomer companion). The
#     cycle-H isomer file is recorded by SHA-256 in
#     validation/serum_h_v1/provenance.md but NOT admitted under the
#     serum_h_v1 anchor (see schema_contract.md sec 7.1). Admitting
#     it requires a follow-up artifact and a peer R converter at that
#     time.
#   * Touch any artifact under data/training/serum/ (the frozen
#     cycle-J anchor lane). The cycle-J lane is governed by
#     validation/serum_v1/ and its anchor at
#     data/training/serum/nhanes_serum_pfas_2017_2018.csv must
#     remain byte-for-byte unchanged
#     (SHA-256 dfd4dbb59128043e91870265acc15f91f673ec81ee3d00d91223022755e4490f).
#
# Usage from RStudio (with the repo root as the working directory):
#
#   source("scripts/convert_pfas_h_xpt_to_csv.R")
#
# =============================================================================

suppressPackageStartupMessages({
  if (!requireNamespace("haven",   quietly = TRUE)) install.packages("haven")
  if (!requireNamespace("readr",   quietly = TRUE)) install.packages("readr")
  if (!requireNamespace("janitor", quietly = TRUE)) install.packages("janitor")
  library(haven)
  library(readr)
  library(janitor)
})

input_file  <- "data/external/nhanes_serum_h/PFAS_H.XPT"
output_file <- "data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv"

if (!file.exists(input_file)) {
  stop(sprintf(
    "Input XPT not found at %s.\nRun scripts/docker_fetch_pfas_h.sh first (Docker/Ubuntu), or place the file manually.",
    input_file
  ))
}

dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)

df <- haven::read_xpt(input_file)

# Normalize SAS uppercase variable names to lowercase snake_case so
# the produced CSV matches the governance contract in
# validation/serum_h_v1/schema_contract.md (and matches cycle J's
# convention, so an operator can compare the two anchors with a
# single column-naming mental model).
df <- janitor::clean_names(df)

readr::write_csv(df, output_file)

cat(sprintf(
  "[OK] PFAS_H.XPT -> %s\n     rows = %d, cols = %d\n     columns: %s\n",
  output_file,
  nrow(df),
  ncol(df),
  paste(names(df), collapse = ", ")
))

invisible(list(
  input   = input_file,
  output  = output_file,
  n_rows  = nrow(df),
  n_cols  = ncol(df),
  columns = names(df)
))
