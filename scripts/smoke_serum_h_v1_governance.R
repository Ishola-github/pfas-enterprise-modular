# =============================================================================
# Smoke -- serum_h v1.0 governance bundle
# =============================================================================
#
# This is the cycle-H counterpart of scripts/smoke_serum_anchor_invariants.R.
# It verifies the integrity of the validation/serum_h_v1/ governance
# bundle issued for NHANES cycle H (2013-2014, PFAS_H.XPT). The
# checks are machine-checkable invariants of the contract -- if any
# of them fails, the cycle-H lane has drifted from its written
# contract and needs review before any model is trained.
#
# What this smoke does NOT do (kept honest):
#   * Re-derive the anchor CSV. That is handled by
#     scripts/docker_fetch_pfas_h.sh (Docker / Ubuntu) and
#     scripts/convert_pfas_h_xpt_to_csv.R (R-only). This smoke
#     just reads the disk artifact and confirms its SHA-256
#     matches what the contract documents.
#   * Touch the cycle-J anchor. The serum v1.0 anchor at
#     data/training/serum/nhanes_serum_pfas_2017_2018.csv MUST stay
#     byte-for-byte identical to its v1.0 documented hash; this
#     smoke verifies that explicitly as a side-effect check.
#   * Assert that serum_h is wired into the build pipeline. The
#     lane is intentionally governance-only at issuance, so the
#     smoke instead asserts the **opposite**: serum_h must NOT
#     yet appear in matrix_pipeline_sop.csv, must NOT have a
#     training.csv / manifest.json / ad_model.json, and the
#     PHYSIOLOGICAL_LANE_STAMPS narrowness (serum only) is
#     unchanged. When the lane IS wired in later, these checks
#     need to flip; that's a deliberate gatekeeping signal.
#
# Author: pfas-enterprise-modular
# =============================================================================

`%||%` <- function(a, b) if (is.null(a)) b else a

repo_root <- normalizePath(getwd())
gov_dir   <- file.path(repo_root, "validation/serum_h_v1")
sibling_gov_dir <- file.path(repo_root, "validation/serum_v1")

ANCHOR_CSV_PATH         <- "data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv"
ANCHOR_CSV_DOCUMENTED   <- "98d11b27beadad159a9bb596caa2e8839b5bfca279fd32f618e60539c53f644f"
RAW_PFAS_H_XPT          <- "data/external/nhanes_serum_h/PFAS_H.XPT"
RAW_PFAS_H_DOCUMENTED   <- "ab062b2ecf99989b1731cb63588d8305409c2e554a76de7e05946f4877091652"
RAW_SSPFAS_H_XPT        <- "data/external/nhanes_serum_h/SSPFAS_H.XPT"
RAW_SSPFAS_H_DOCUMENTED <- "1e23688dfa6bdfdc14c0447f4d34032983271063a1a343c04338ae4258515c99"

CYCLE_J_ANCHOR_PATH      <- "data/training/serum/nhanes_serum_pfas_2017_2018.csv"
CYCLE_J_ANCHOR_DOCUMENTED <- "dfd4dbb59128043e91870265acc15f91f673ec81ee3d00d91223022755e4490f"

EXPECTED_FILES <- c(
  "README.md",
  "intended_use.txt",
  "applicability_domain.txt",
  "schema_contract.md",
  "schema_contract.json",
  "limitations.md",
  "provenance.md",
  "data_dictionary.md",
  "data_dictionary.csv"
)

EXPECTED_ANALYTE_VALUE_COLS <- c(
  "lbxpfde", "lbxpfhs", "lbxmpah", "lbxpfbs",
  "lbxpfhp", "lbxpfna", "lbxpfua", "lbxpfdo"
)
EXPECTED_ANALYTE_LOD_COLS <- c(
  "lbdpfdel", "lbdpfhsl", "lbdmpahl", "lbdpfbsl",
  "lbdpfhpl", "lbdpfnal", "lbdpfual", "lbdpfdol"
)
EXPECTED_STRUCTURAL_COLS <- c("seqn", "wtsb2yr")
EXPECTED_TOTAL_COLS <- length(EXPECTED_STRUCTURAL_COLS) +
                      length(EXPECTED_ANALYTE_VALUE_COLS) +
                      length(EXPECTED_ANALYTE_LOD_COLS) # 18
EXPECTED_ROWS <- 2339L

EXPECTED_STAMP_FIELDS <- c(
  "sample_domain", "sample_matrix", "measurement_context",
  "source_program", "governance_lane"
)
EXPECTED_STAMP_VALUES <- list(
  sample_domain        = "physiological",
  sample_matrix        = "human_serum",
  measurement_context  = "biomonitoring",
  source_program       = "CDC NHANES",
  governance_lane      = "serum_h_v1"
)

EXPECTED_OUT_OF_SCOPE_CYCLES <- c(
  "PFAS_J", "P_PFAS", "PFAS_I", "L06AGE_C"
)

if (!requireNamespace("digest",   quietly = TRUE)) install.packages("digest")
if (!requireNamespace("jsonlite", quietly = TRUE)) install.packages("jsonlite")
suppressPackageStartupMessages({
  library(digest)
  library(jsonlite)
})

sha256 <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  digest::digest(file = path, algo = "sha256")
}

read_text <- function(path) {
  if (!file.exists(path)) return("")
  readLines(path, warn = FALSE, encoding = "UTF-8") |> paste(collapse = "\n")
}

checks <- list()
add <- function(name, ok) checks[[length(checks) + 1L]] <<- list(name = name, ok = isTRUE(ok))

# ===========================================================================
# (1) Governance directory exists with all 9 expected files
# ===========================================================================
for (f in EXPECTED_FILES) {
  add(
    name = sprintf("gov_file_present__%s", f),
    ok   = file.exists(file.path(gov_dir, f))
  )
}

# ===========================================================================
# (2) Anchor CSV exists, hash matches, has expected dimensions
# ===========================================================================
anchor_path <- file.path(repo_root, ANCHOR_CSV_PATH)
add(
  name = "anchor_csv_exists",
  ok   = file.exists(anchor_path)
)
add(
  name = "anchor_csv_sha256_matches_documented",
  ok   = identical(tolower(sha256(anchor_path)), tolower(ANCHOR_CSV_DOCUMENTED))
)
add(
  name = "anchor_csv_has_expected_row_count",
  ok   = {
    if (!file.exists(anchor_path)) FALSE else {
      con <- file(anchor_path, "r")
      on.exit(close(con), add = TRUE)
      n <- 0L
      repeat {
        chunk <- readLines(con, n = 65536L, warn = FALSE)
        if (length(chunk) == 0L) break
        n <- n + length(chunk)
      }
      (n - 1L) == EXPECTED_ROWS  # subtract header
    }
  }
)
add(
  name = "anchor_csv_header_carries_expected_columns",
  ok   = {
    if (!file.exists(anchor_path)) FALSE else {
      hdr <- readLines(anchor_path, n = 1L, warn = FALSE)
      cols <- strsplit(hdr, ",", fixed = TRUE)[[1]]
      length(cols) == EXPECTED_TOTAL_COLS &&
        setequal(cols,
                 c(EXPECTED_STRUCTURAL_COLS,
                   EXPECTED_ANALYTE_VALUE_COLS,
                   EXPECTED_ANALYTE_LOD_COLS))
    }
  }
)

# ===========================================================================
# (3) Raw XPT artifacts: documented hashes, exist on disk
# ===========================================================================
add(
  name = "raw_pfas_h_xpt_exists",
  ok   = file.exists(file.path(repo_root, RAW_PFAS_H_XPT))
)
add(
  name = "raw_pfas_h_xpt_sha256_matches_documented",
  ok   = identical(
    tolower(sha256(file.path(repo_root, RAW_PFAS_H_XPT))),
    tolower(RAW_PFAS_H_DOCUMENTED)
  )
)
add(
  name = "raw_sspfas_h_xpt_exists",
  ok   = file.exists(file.path(repo_root, RAW_SSPFAS_H_XPT))
)
add(
  name = "raw_sspfas_h_xpt_sha256_matches_documented",
  ok   = identical(
    tolower(sha256(file.path(repo_root, RAW_SSPFAS_H_XPT))),
    tolower(RAW_SSPFAS_H_DOCUMENTED)
  )
)

# ===========================================================================
# (4) Schema contract JSON: structure + stamp + paired artifacts
# ===========================================================================
schema_json_path <- file.path(gov_dir, "schema_contract.json")
schema_json <- tryCatch(
  jsonlite::fromJSON(schema_json_path, simplifyVector = FALSE),
  error = function(e) NULL
)
add(
  name = "schema_json_parses_ok",
  ok   = !is.null(schema_json)
)
add(
  name = "schema_json_declares_lane_serum_h",
  ok   = !is.null(schema_json) && identical(schema_json$lane, "serum_h")
)
add(
  name = "schema_json_declares_version_1_0",
  ok   = !is.null(schema_json) && identical(schema_json$version, "1.0")
)
add(
  name = "schema_json_anchor_csv_sha256_matches_documented",
  ok   = !is.null(schema_json) &&
         identical(tolower(schema_json$anchor_csv_sha256),
                   tolower(ANCHOR_CSV_DOCUMENTED))
)
add(
  name = "schema_json_anchor_dataset_records_pfas_h_raw_sha256",
  ok   = !is.null(schema_json) &&
         identical(tolower(schema_json$anchor_dataset$raw_file_sha256),
                   tolower(RAW_PFAS_H_DOCUMENTED))
)
add(
  name = "schema_json_records_sspfas_h_raw_sha256",
  ok   = !is.null(schema_json) &&
         identical(tolower(schema_json$paired_artifacts$SSPFAS_H_2013_2014$raw_file_sha256),
                   tolower(RAW_SSPFAS_H_DOCUMENTED))
)
add(
  name = "schema_json_analyte_panel_has_exactly_8_analytes",
  ok   = !is.null(schema_json) && length(schema_json$analyte_columns) == 8L
)
add(
  name = "schema_json_analyte_value_columns_match_expected",
  ok   = !is.null(schema_json) && {
    got <- vapply(schema_json$analyte_columns, function(a) a$value, character(1))
    setequal(got, EXPECTED_ANALYTE_VALUE_COLS)
  }
)
add(
  name = "schema_json_lists_cycle_h_specific_analytes_correctly",
  ok   = !is.null(schema_json) && {
    setequal(unlist(schema_json$analytes_added_vs_serum_v1_0),
             c("LBXPFBS", "LBXPFHP", "LBXPFDO")) &&
    setequal(unlist(schema_json$analytes_missing_vs_serum_v1_0),
             c("LBXNFOA", "LBXBFOA", "LBXNFOS", "LBXMFOS"))
  }
)

# Stamp values
add(
  name = "schema_json_stamp_has_5_fields_with_expected_names",
  ok   = !is.null(schema_json) &&
         setequal(names(schema_json$physiological_classification$fields),
                  EXPECTED_STAMP_FIELDS)
)
for (fld in EXPECTED_STAMP_FIELDS) {
  add(
    name = sprintf("schema_json_stamp_value__%s", fld),
    ok   = !is.null(schema_json) &&
           identical(schema_json$physiological_classification$fields[[fld]],
                     EXPECTED_STAMP_VALUES[[fld]])
  )
}

# Label-unit reconciliation block exists
add(
  name = "schema_json_label_unit_reconciliation_block_present",
  ok   = !is.null(schema_json) &&
         !is.null(schema_json$label_unit_reconciliation) &&
         identical(schema_json$label_unit_reconciliation$sas_label_says, "(ug/L)") &&
         identical(schema_json$label_unit_reconciliation$codebook_llod_table_says, "ng/mL")
)

# ===========================================================================
# (5) Schema contract markdown: required sections present
# ===========================================================================
schema_md <- read_text(file.path(gov_dir, "schema_contract.md"))
required_md_anchors <- c(
  "## 1. Anchor dataset",
  "## 3. Analyte panel",
  "### 3.2 Label-unit reconciliation",
  "## 5. Matrix isolation",
  "## 6. Refusal conditions",
  "## 7. Paired and out-of-scope artifacts",
  "## 8. Promotion gate",
  "## 9. Physiological-sample classification stamp"
)
for (sec in required_md_anchors) {
  add(
    name = sprintf("schema_md_contains_section__%s",
                   gsub("[^A-Za-z0-9]+", "_", sec)),
    ok   = grepl(sec, schema_md, fixed = TRUE)
  )
}
add(
  name = "schema_md_records_anchor_csv_sha256",
  ok   = grepl(ANCHOR_CSV_DOCUMENTED, schema_md, fixed = TRUE)
)
add(
  name = "schema_md_records_peer_cycle_j_frozen_anchor_sha256",
  ok   = grepl(CYCLE_J_ANCHOR_DOCUMENTED, schema_md, fixed = TRUE)
)

# ===========================================================================
# (6) Provenance: records both raw XPT hashes + derived CSV hash + recipe
# ===========================================================================
prov_md <- read_text(file.path(gov_dir, "provenance.md"))
add(
  name = "provenance_md_records_raw_pfas_h_sha256",
  ok   = grepl(RAW_PFAS_H_DOCUMENTED, prov_md, fixed = TRUE)
)
add(
  name = "provenance_md_records_raw_sspfas_h_sha256",
  ok   = grepl(RAW_SSPFAS_H_DOCUMENTED, prov_md, fixed = TRUE)
)
add(
  name = "provenance_md_records_anchor_csv_sha256",
  ok   = grepl(ANCHOR_CSV_DOCUMENTED, prov_md, fixed = TRUE)
)
add(
  name = "provenance_md_documents_docker_recipe",
  ok   = grepl("rocker/r-ver:4.4", prov_md, fixed = TRUE) &&
         grepl("scripts/docker_fetch_pfas_h.sh", prov_md, fixed = TRUE)
)
add(
  name = "provenance_md_records_peer_cycle_j_frozen_anchor_sha256",
  ok   = grepl(CYCLE_J_ANCHOR_DOCUMENTED, prov_md, fixed = TRUE)
)

# ===========================================================================
# (7) Data dictionary CSV: column-name rows match the anchor header
# ===========================================================================
dd_csv_path <- file.path(gov_dir, "data_dictionary.csv")
add(
  name = "data_dictionary_csv_lists_all_18_anchor_columns",
  ok   = {
    if (!file.exists(dd_csv_path)) FALSE else {
      lines <- readLines(dd_csv_path, warn = FALSE, encoding = "UTF-8")
      # data column rows (excluding the lane-stamped derived columns
      # that appear at the bottom and are flagged LANE_STAMP)
      anchor_cols <- c(EXPECTED_STRUCTURAL_COLS,
                       EXPECTED_ANALYTE_VALUE_COLS,
                       EXPECTED_ANALYTE_LOD_COLS)
      all(vapply(anchor_cols,
                 function(c) any(grepl(paste0("^", c, ","), lines)),
                 logical(1)))
    }
  }
)
add(
  name = "data_dictionary_csv_lists_5_stamp_rows",
  ok   = {
    if (!file.exists(dd_csv_path)) FALSE else {
      lines <- readLines(dd_csv_path, warn = FALSE, encoding = "UTF-8")
      all(vapply(EXPECTED_STAMP_FIELDS,
                 function(c) any(grepl(paste0("^", c, ",.*LANE_STAMP"), lines)),
                 logical(1)))
    }
  }
)

# ===========================================================================
# (8) Cycle-J anchor is still frozen (governance side-effect check)
# ===========================================================================
add(
  name = "cycle_j_anchor_csv_still_byte_for_byte_unchanged",
  ok   = identical(
    tolower(sha256(file.path(repo_root, CYCLE_J_ANCHOR_PATH))),
    tolower(CYCLE_J_ANCHOR_DOCUMENTED)
  )
)

# ===========================================================================
# (9) Cross-link from sibling v1.0 docs to serum_h_v1
# ===========================================================================
sibling_readme <- read_text(file.path(sibling_gov_dir, "README.md"))
add(
  name = "sibling_v1_readme_links_to_serum_h_v1",
  ok   = grepl("validation/serum_h_v1/", sibling_readme, fixed = TRUE) &&
         grepl(ANCHOR_CSV_DOCUMENTED, sibling_readme, fixed = TRUE)
)
sibling_schema_md <- read_text(file.path(sibling_gov_dir, "schema_contract.md"))
add(
  name = "sibling_v1_schema_md_records_peer_anchor_sha",
  ok   = grepl(ANCHOR_CSV_DOCUMENTED, sibling_schema_md, fixed = TRUE)
)
sibling_schema_json_path <- file.path(sibling_gov_dir, "schema_contract.json")
sibling_schema_json <- tryCatch(
  jsonlite::fromJSON(sibling_schema_json_path, simplifyVector = FALSE),
  error = function(e) NULL
)
add(
  name = "sibling_v1_schema_json_records_peer_lane_pointer",
  ok   = !is.null(sibling_schema_json) &&
         identical(
           sibling_schema_json$out_of_scope_versions$PFAS_H_2013_2014$peer_lane_governance_directory,
           "validation/serum_h_v1"
         ) &&
         identical(
           tolower(sibling_schema_json$out_of_scope_versions$PFAS_H_2013_2014$peer_lane_anchor_csv_sha256),
           tolower(ANCHOR_CSV_DOCUMENTED)
         )
)

# ===========================================================================
# (10) Negative checks: serum_h is intentionally NOT wired into the
# build pipeline yet. If any of these flips, the lane has moved past
# "governance-only" and the wider invariants smoke
# (smoke_serum_anchor_invariants.R) needs its lane-registry
# narrowness assertions updated.
# ===========================================================================
sop_csv <- file.path(repo_root, "data/config/matrix_pipeline_sop.csv")
add(
  name = "negative__serum_h_not_yet_in_matrix_pipeline_sop",
  ok   = {
    if (!file.exists(sop_csv)) TRUE else {
      txt <- read_text(sop_csv)
      !grepl("^serum_h,", txt) && !grepl(",serum_h,", txt) &&
        !grepl("\nserum_h,", txt)
    }
  }
)
add(
  name = "negative__serum_h_training_csv_not_yet_built",
  ok   = !file.exists(file.path(repo_root, "data/training/serum_h/training.csv"))
)
add(
  name = "negative__serum_h_manifest_not_yet_emitted",
  ok   = !file.exists(file.path(repo_root, "data/training/serum_h/manifest.json"))
)
add(
  name = "negative__serum_h_ad_model_not_yet_built",
  ok   = !file.exists(file.path(repo_root, "data/ad_models/serum_h/ad_model.json"))
)

# Python lane-registry narrowness: PHYSIOLOGICAL_LANE_STAMPS should
# still contain ONLY "serum" until serum_h is intentionally wired in.
py_pipeline <- file.path(repo_root, "scripts/run_matrix_pipeline.py")
add(
  name = "negative__python_PHYSIOLOGICAL_LANE_STAMPS_does_not_yet_contain_serum_h",
  ok   = {
    if (!file.exists(py_pipeline)) TRUE else {
      txt <- read_text(py_pipeline)
      # The registry currently maps {"serum": SERUM_PHYSIOLOGICAL_STAMP}.
      # If "serum_h" appears as a stamp key, it has been wired in.
      !grepl('"serum_h"\\s*:\\s*SERUM_H', txt) &&
        !grepl("'serum_h'\\s*:\\s*SERUM_H", txt) &&
        !grepl('"serum_h":\\s*\\{', txt) &&
        !grepl("'serum_h':\\s*\\{", txt)
    }
  }
)

# R lane-registry narrowness: PHYSIOLOGICAL_LANE_STAMPS in
# LatestPFAS.R should still contain ONLY "serum".
r_app <- file.path(repo_root, "LatestPFAS.R")
add(
  name = "negative__R_PHYSIOLOGICAL_LANE_STAMPS_does_not_yet_contain_serum_h",
  ok   = {
    if (!file.exists(r_app)) TRUE else {
      txt <- read_text(r_app)
      # Look for the registry block and check it has no serum_h entry.
      # The named-list shape is `serum_h = list(`.
      !grepl("serum_h\\s*=\\s*list\\(", txt)
    }
  }
)

# ===========================================================================
# (11) Out-of-scope cycles documented consistently in serum_h_v1
# ===========================================================================
for (cyc in EXPECTED_OUT_OF_SCOPE_CYCLES) {
  add(
    name = sprintf("schema_md_lists_out_of_scope_cycle__%s", cyc),
    ok   = grepl(cyc, schema_md, fixed = TRUE)
  )
}
prov_txt <- read_text(file.path(gov_dir, "provenance.md"))
for (cyc in EXPECTED_OUT_OF_SCOPE_CYCLES) {
  add(
    name = sprintf("provenance_md_lists_out_of_scope_cycle__%s", cyc),
    ok   = grepl(cyc, prov_txt, fixed = TRUE)
  )
}

# ===========================================================================
# Report
# ===========================================================================
failed <- character(0)
for (c in checks) if (!isTRUE(c$ok)) failed <- c(failed, c$name)

cat("Serum_h v1.0 governance smoke:\n")
for (c in checks) {
  cat(sprintf("  %s %s\n",
              if (isTRUE(c$ok)) "[OK]   " else "[FAIL] ",
              c$name))
}
cat(sprintf("\n  %d checks, %d failures\n", length(checks), length(failed)))

if (length(failed) > 0L) {
  stop(sprintf("serum_h_v1 governance smoke FAILED: %s",
               paste(failed, collapse = ", ")))
} else {
  cat("\n  PASS\n")
}
