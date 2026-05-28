# Smoke test: NHANES serum biomonitoring upload signature
# (same detection + hard-block logic as LatestPFAS.R).
#
# Governance anchor: validation/serum_v1/
#   - schema_contract.md   (matrix isolation, refusal conditions)
#   - applicability_domain.txt (R5: mixed-matrix refusal)
#   - limitations.md       (\u00a76: not cross-matrix)
#
# Run from project root:
#   Rscript scripts/smoke_serum_upload_banner.R
# Or in RStudio (Console), after setwd() to the repo pfas-toxicology folder:
#   source("scripts/smoke_serum_upload_banner.R", echo = FALSE)

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
}

normalize_upload_colnames <- function(col_names) {
  x <- tolower(trimws(as.character(col_names)))
  x <- gsub("[[:space:].]+", "_", x, perl = FALSE)
  x <- gsub("_+", "_", x, perl = FALSE)
  x
}

NHANES_SERUM_LBX_COLS <- c(
  "lbxnfoa", "lbxbfoa", "lbxnfos", "lbxmfos",
  "lbxpfhs", "lbxpfna", "lbxpfde", "lbxpfua", "lbxmpah"
)
NHANES_SERUM_LBD_COLS <- c(
  "lbdnfoal", "lbdbfoal", "lbdnfosl", "lbdmfosl",
  "lbdpfhsl", "lbdpfnal", "lbdpfdel", "lbdpfual", "lbdmpahl"
)

detect_nhanes_serum_biomonitoring <- function(col_names, file_name = "") {
  if (is.null(col_names) || length(col_names) < 1L) {
    return(FALSE)
  }
  cn <- normalize_upload_colnames(col_names)
  cn <- unique(cn[nzchar(cn)])

  if ("seqn" %in% cn && "wtsb2yr" %in% cn) {
    return(TRUE)
  }

  lbx_hits <- sum(NHANES_SERUM_LBX_COLS %in% cn)
  lbd_hits <- sum(NHANES_SERUM_LBD_COLS %in% cn)
  if ("seqn" %in% cn && (lbx_hits + lbd_hits) >= 1L) {
    return(TRUE)
  }

  if ((lbx_hits + lbd_hits) >= 2L) {
    return(TRUE)
  }

  fn <- tolower(trimws(as.character(file_name %||% "")))
  if (nzchar(fn)) {
    if (grepl("pfas_j", fn, fixed = TRUE)) return(TRUE)
    if (grepl("pfas_i", fn, fixed = TRUE)) return(TRUE)
    if (grepl("p_pfas", fn, fixed = TRUE)) return(TRUE)
    if (grepl("nhanes", fn, fixed = TRUE) && grepl("pfas", fn, fixed = TRUE)) {
      return(TRUE)
    }
    if (grepl("serum", fn, fixed = TRUE) && grepl("pfas", fn, fixed = TRUE)) {
      return(TRUE)
    }
  }

  FALSE
}

root <- Sys.getenv("PFAS_SMOKE_PROJECT_ROOT", "")
if (!nzchar(root)) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) >= 1L && nzchar(args[[1]])) {
    root <- args[[1]]
  } else {
    root <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  }
}
latest <- file.path(root, "LatestPFAS.R")
if (!file.exists(latest)) {
  stop("LatestPFAS.R not found at: ", latest,
       " \u2014 run from pfas-toxicology/ or set PFAS_SMOKE_PROJECT_ROOT")
}

expr <- parse(latest, keep.source = FALSE)
if (length(expr) < 1L) {
  stop("LatestPFAS.R parse produced no expressions")
}

src <- paste(readLines(latest, warn = FALSE), collapse = "\n")

# Standalone mirror of the constants we test against the metadata-lane
# blanking invariant.
PFAS_OCCURRENCE_MAP_FIELDS <- c(
  "result_value", "unit", "qualifier", "analyte", "cas", "date",
  "mdl", "rl", "detect_flag", "matrix", "sample_id", "state", "county",
  "method_id", "facility_water_type", "sample_point_type",
  "collection_year", "facility_id", "sample_point_id",
  "latitude", "longitude"
)

# Pure-function mirror of the off-lane mapping invariant in LatestPFAS.R.
# When the upload is detected as serum, every PFAS-occurrence field must be
# blanked, so prior auto-detect picks (SEQN -> result_value, etc.) cannot
# survive into validate/save.
mapping_after_serum_hardblock <- function(col_names, file_name = "",
                                          sticky = list()) {
  is_serum <- detect_nhanes_serum_biomonitoring(col_names, file_name)
  vals <- as.list(sticky)
  if (isTRUE(is_serum)) {
    for (k in PFAS_OCCURRENCE_MAP_FIELDS) vals[[k]] <- ""
  }
  vals
}

# Canonical NHANES PFAS_J header (uppercase SAS variable names, as the file
# arrives from CDC before janitor::clean_names normalization).
nhanes_pfas_j_upper <- c(
  "SEQN", "WTSB2YR",
  "LBXPFDE", "LBDPFDEL", "LBXPFHS", "LBDPFHSL",
  "LBXMPAH", "LBDMPAHL", "LBXPFNA", "LBDPFNAL",
  "LBXPFUA", "LBDPFUAL", "LBXNFOA", "LBDNFOAL",
  "LBXBFOA", "LBDBFOAL", "LBXNFOS", "LBDNFOSL",
  "LBXMFOS", "LBDMFOSL"
)

# Same file after the documented snake_case normalization (the form that
# appears in data/training/serum/nhanes_serum_pfas_2017_2018.csv).
nhanes_pfas_j_lower <- c(
  "seqn", "wtsb2yr",
  "lbxpfde", "lbdpfdel", "lbxpfhs", "lbdpfhsl",
  "lbxmpah", "lbdmpahl", "lbxpfna", "lbdpfnal",
  "lbxpfua", "lbdpfual", "lbxnfoa", "lbdnfoal",
  "lbxbfoa", "lbdbfoal", "lbxnfos", "lbdnfosl",
  "lbxmfos", "lbdmfosl"
)

checks <- list(
  # ---------------- detection: positive cases ----------------
  list(
    name = "nhanes_pfas_j_uppercase_header",
    ok = isTRUE(detect_nhanes_serum_biomonitoring(
      nhanes_pfas_j_upper, "PFAS_J.XPT"
    ))
  ),
  list(
    name = "nhanes_pfas_j_lowercase_header",
    ok = isTRUE(detect_nhanes_serum_biomonitoring(
      nhanes_pfas_j_lower, "nhanes_serum_pfas_2017_2018.csv"
    ))
  ),
  list(
    name = "seqn_plus_wtsb2yr_only",
    ok = isTRUE(detect_nhanes_serum_biomonitoring(
      c("SEQN", "WTSB2YR"), "something.csv"
    ))
  ),
  list(
    name = "seqn_plus_one_analyte_column",
    ok = isTRUE(detect_nhanes_serum_biomonitoring(
      c("seqn", "lbxnfoa"), "subset.csv"
    ))
  ),
  list(
    name = "two_analyte_columns_without_seqn",
    ok = isTRUE(detect_nhanes_serum_biomonitoring(
      c("lbxnfoa", "lbdnfoal"), "subset.csv"
    ))
  ),
  list(
    name = "filename_fallback_pfas_j",
    ok = isTRUE(detect_nhanes_serum_biomonitoring(
      c("col_a", "col_b"), "PFAS_J.XPT"
    ))
  ),
  list(
    name = "filename_fallback_nhanes_pfas",
    ok = isTRUE(detect_nhanes_serum_biomonitoring(
      c("col_a", "col_b"), "nhanes_pfas_serum.csv"
    ))
  ),
  list(
    name = "filename_fallback_p_pfas",
    ok = isTRUE(detect_nhanes_serum_biomonitoring(
      c("col_a", "col_b"), "P_PFAS.XPT"
    ))
  ),
  list(
    name = "filename_fallback_serum_pfas",
    ok = isTRUE(detect_nhanes_serum_biomonitoring(
      c("col_a", "col_b"), "any_serum_pfas_export.csv"
    ))
  ),
  # ---------------- detection: negative cases ----------------
  list(
    name = "ucmr_like_not_serum",
    ok = !isTRUE(detect_nhanes_serum_biomonitoring(
      c("PWSID", "SampleID", "Contaminant", "Result", "Unit"),
      "UCMR5_533.txt"
    ))
  ),
  list(
    name = "icis_air_like_not_serum",
    ok = !isTRUE(detect_nhanes_serum_biomonitoring(
      c("PGM_SYS_ID", "POLLUTANT_CODE", "POLLUTANT_DESC"),
      "ICIS-AIR_POLLUTANTS.csv"
    ))
  ),
  list(
    name = "empty_cols_false",
    ok = !isTRUE(detect_nhanes_serum_biomonitoring(character(0), ""))
  ),
  list(
    name = "single_unrelated_column_false",
    ok = !isTRUE(detect_nhanes_serum_biomonitoring(
      c("lbxnfoa"), "subset.csv"
    ))
  ),
  list(
    name = "seqn_alone_without_analyte_is_not_serum",
    ok = !isTRUE(detect_nhanes_serum_biomonitoring(
      c("SEQN", "AGE", "GENDER"), "demographics.csv"
    ))
  ),
  # ---------------- hard-block mapping invariants ----------------
  list(
    name = "hardblock_seqn_not_result_value",
    ok = identical(
      mapping_after_serum_hardblock(
        nhanes_pfas_j_upper, "PFAS_J.XPT",
        sticky = list(result_value = "SEQN")
      )$result_value,
      ""
    )
  ),
  list(
    name = "hardblock_wtsb2yr_not_result_value",
    ok = identical(
      mapping_after_serum_hardblock(
        nhanes_pfas_j_upper, "PFAS_J.XPT",
        sticky = list(result_value = "WTSB2YR")
      )$result_value,
      ""
    )
  ),
  list(
    name = "hardblock_lbxnfoa_not_analyte",
    ok = identical(
      mapping_after_serum_hardblock(
        nhanes_pfas_j_lower, "nhanes_serum_pfas_2017_2018.csv",
        sticky = list(analyte = "lbxnfoa")
      )$analyte,
      ""
    )
  ),
  list(
    name = "hardblock_all_occurrence_fields_blank",
    ok = {
      m <- mapping_after_serum_hardblock(
        nhanes_pfas_j_upper, "PFAS_J.XPT",
        sticky = setNames(
          as.list(rep("something", length(PFAS_OCCURRENCE_MAP_FIELDS))),
          PFAS_OCCURRENCE_MAP_FIELDS
        )
      )
      all(vapply(PFAS_OCCURRENCE_MAP_FIELDS,
                 function(k) identical(m[[k]], ""), logical(1)))
    }
  ),
  list(
    name = "non_serum_passes_through_unchanged",
    ok = identical(
      mapping_after_serum_hardblock(
        c("PWSID", "Contaminant", "AnalyticalResultValue", "UnitOfMeasure"),
        "UCMR5_533.txt",
        sticky = list(result_value = "AnalyticalResultValue",
                      analyte = "Contaminant")
      )$result_value,
      "AnalyticalResultValue"
    )
  ),
  # ---------------- LatestPFAS.R wiring contract -------------------
  list(
    name = "wiring_serum_biomonitoring_in_semantic_types",
    ok = grepl('"serum_biomonitoring"', src, fixed = TRUE)
  ),
  list(
    name = "wiring_serum_detector_function_defined",
    ok = grepl("detect_nhanes_serum_biomonitoring <- function",
               src, fixed = TRUE)
  ),
  list(
    name = "wiring_semantic_type_routes_to_serum",
    ok = grepl('return("serum_biomonitoring")', src, fixed = TRUE)
  ),
  list(
    name = "wiring_metadata_lane_includes_serum",
    ok = grepl('identical(sem, "serum_biomonitoring")',
               src, fixed = TRUE)
  ),
  list(
    name = "wiring_serum_refusal_message_branch",
    ok = grepl('serum_biomonitoring_refusal', src, fixed = TRUE)
  ),
  list(
    name = "wiring_serum_banner_uioutput_present",
    ok = grepl('uiOutput("serum_external_upload_banner")',
               src, fixed = TRUE)
  ),
  list(
    name = "wiring_serum_banner_renderui_present",
    ok = grepl("output\\$serum_external_upload_banner <- renderUI",
               src)
  ),
  list(
    name = "wiring_validate_refusal_still_hooked",
    ok = grepl('refuse_pfas_op_on_metadata_lane("Validate")',
               src, fixed = TRUE)
  ),
  list(
    name = "wiring_normalize_refusal_still_hooked",
    ok = grepl('refuse_pfas_op_on_metadata_lane("Normalize")',
               src, fixed = TRUE)
  ),
  list(
    name = "wiring_save_refusal_still_hooked",
    ok = grepl('refuse_pfas_op_on_metadata_lane("Save")',
               src, fixed = TRUE)
  ),
  list(
    name = "wiring_train_evidence_refusal_still_hooked",
    ok = grepl('refuse_pfas_op_on_metadata_lane("Train (Evidence-Governed)")',
               src, fixed = TRUE)
  ),
  list(
    name = "wiring_train_screening_refusal_still_hooked",
    ok = grepl('refuse_pfas_op_on_metadata_lane("Screening',
               src, fixed = TRUE)
  ),
  list(
    name = "wiring_serum_banner_points_at_validation_serum_v1",
    ok = grepl("validation/serum_v1/", src, fixed = TRUE)
  ),
  list(
    name = "wiring_serum_banner_points_at_convert_script",
    ok = grepl("scripts/convert_nhanes_xpt_to_csv.R",
               src, fixed = TRUE)
  )
)

failed <- character(0)
for (c in checks) {
  if (!isTRUE(c$ok)) {
    failed <- c(failed, c$name)
  }
}

cat("LatestPFAS.R parse: OK (", length(expr), " top-level expr)\n", sep = "")
cat("NHANES serum biomonitoring signature smoke:\n")
for (c in checks) {
  cat(sprintf("  %s: %s\n", c$name,
              if (isTRUE(c$ok)) "PASS" else "FAIL"))
}

if (length(failed) > 0L) {
  stop("FAILED: ", paste(failed, collapse = ", "))
}
cat("Overall: PASS (", length(checks), "/", length(checks), ")\n", sep = "")
