# Smoke test: ICIS-AIR bulk upload column signature (same logic as LatestPFAS.R).
# Run from project root:
#   Rscript scripts/smoke_icis_air_upload_banner.R
# Or in RStudio (Console), after setwd() to the repo pfas-toxicology folder:
#   source("scripts/smoke_icis_air_upload_banner.R", echo = FALSE)

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
}

normalize_upload_colnames <- function(col_names) {
  x <- tolower(trimws(as.character(col_names)))
  x <- gsub("[[:space:].]+", "_", x, perl = FALSE)
  x <- gsub("_+", "_", x, perl = FALSE)
  x
}

detect_icis_air_bulk_program_table <- function(col_names, file_name = "") {
  if (is.null(col_names) || length(col_names) < 1L) {
    return(FALSE)
  }
  cn <- normalize_upload_colnames(col_names)
  cn <- unique(cn[nzchar(cn)])
  if (!("pgm_sys_id" %in% cn && "pollutant_code" %in% cn)) {
    return(FALSE)
  }
  air_meta <- any(
    c(
      "pollutant_desc",
      "srs_id",
      "chemical_abstract_service_nmbr",
      "chemical_abstract_service_number",
      "air_pollutant_class_code",
      "air_pollutant_class_desc"
    ) %in% cn
  )
  if (isTRUE(air_meta)) {
    return(TRUE)
  }
  fn <- tolower(trimws(as.character(file_name %||% "")))
  if (nzchar(fn) && grepl("icis", fn, fixed = TRUE) && grepl("air", fn, fixed = TRUE)) {
    return(TRUE)
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
  stop("LatestPFAS.R not found at: ", latest, " — run from pfas-toxicology/ or set PFAS_SMOKE_PROJECT_ROOT")
}

expr <- parse(latest, keep.source = FALSE)
# First expression is the big shiny app; only need parse success + line sync note.
if (length(expr) < 1L) {
  stop("LatestPFAS.R parse produced no expressions")
}

# Read the app source so we can assert the hard-block code paths actually exist.
# (Strings are easier than evaling Shiny reactives outside an http session.)
src <- paste(readLines(latest, warn = FALSE), collapse = "\n")

# Standalone mirror of the constants/helpers so we can test hard-block logic.
PFAS_OCCURRENCE_MAP_FIELDS <- c(
  "result_value", "unit", "qualifier", "analyte", "cas", "date",
  "mdl", "rl", "detect_flag", "matrix", "sample_id", "state", "county",
  "method_id", "facility_water_type", "sample_point_type",
  "collection_year", "facility_id", "sample_point_id",
  "latitude", "longitude"
)

# Pure-function mirror of the metadata-lane logic in LatestPFAS.R, used to
# verify that the same input -> blank-mapping invariant holds.
mapping_after_hardblock <- function(col_names, file_name = "",
                                    sticky = list()) {
  is_air <- detect_icis_air_bulk_program_table(col_names, file_name)
  vals <- as.list(sticky)
  if (isTRUE(is_air)) {
    for (k in PFAS_OCCURRENCE_MAP_FIELDS) vals[[k]] <- ""
  }
  vals
}

# Canonical ICIS-AIR_POLLUTANTS headers (EPA bulk)
icis_cols <- c(
  "PGM_SYS_ID", "POLLUTANT_CODE", "POLLUTANT_DESC", "SRS_ID",
  "CHEMICAL_ABSTRACT_SERVICE_NMBR", "AIR_POLLUTANT_CLASS_CODE", "AIR_POLLUTANT_CLASS_DESC"
)

checks <- list(
  list(
    name = "icis_air_canonical_headers",
    ok = isTRUE(detect_icis_air_bulk_program_table(icis_cols, "ICIS-AIR_POLLUTANTS.csv"))
  ),
  list(
    name = "icis_air_lowercase_spaced_headers",
    ok = isTRUE(detect_icis_air_bulk_program_table(
      c("pgm sys id", "pollutant code", "pollutant desc"),
      "something.csv"
    ))
  ),
  list(
    name = "icis_air_filename_fallback",
    ok = isTRUE(detect_icis_air_bulk_program_table(
      c("PGM_SYS_ID", "POLLUTANT_CODE"),
      "echo_icis_air_export.csv"
    ))
  ),
  list(
    name = "ucmr_like_not_icis_air",
    ok = !isTRUE(detect_icis_air_bulk_program_table(
      c("PWSID", "SampleID", "Contaminant", "Result", "Unit"),
      "UCMR5_sample.csv"
    ))
  ),
  list(
    name = "empty_cols_false",
    ok = !isTRUE(detect_icis_air_bulk_program_table(character(0), ""))
  ),
  # ---------------- hard-block mapping invariants ----------------
  list(
    name = "hardblock_pollutant_code_not_result_value",
    ok = identical(
      mapping_after_hardblock(
        icis_cols, "ICIS-AIR_POLLUTANTS.csv",
        sticky = list(result_value = "pollutant_code")
      )$result_value,
      ""
    )
  ),
  list(
    name = "hardblock_cas_not_state",
    ok = identical(
      mapping_after_hardblock(
        icis_cols, "ICIS-AIR_POLLUTANTS.csv",
        sticky = list(state = "chemical_abstract_service_nmbr")
      )$state,
      ""
    )
  ),
  list(
    name = "hardblock_all_occurrence_fields_blank",
    ok = {
      m <- mapping_after_hardblock(
        icis_cols, "ICIS-AIR_POLLUTANTS.csv",
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
    name = "non_icis_air_passes_through_unchanged",
    ok = identical(
      mapping_after_hardblock(
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
    name = "wiring_get_upload_mapping_hardblock_present",
    ok = grepl("upload_is_metadata_lane()", src, fixed = TRUE) &&
      grepl("PFAS_OCCURRENCE_MAP_FIELDS", src, fixed = TRUE)
  ),
  list(
    name = "wiring_validate_refusal_hook_present",
    ok = grepl('refuse_pfas_op_on_metadata_lane("Validate")', src, fixed = TRUE)
  ),
  list(
    name = "wiring_normalize_refusal_hook_present",
    ok = grepl('refuse_pfas_op_on_metadata_lane("Normalize")', src, fixed = TRUE)
  ),
  list(
    name = "wiring_save_refusal_hook_present",
    ok = grepl('refuse_pfas_op_on_metadata_lane("Save")', src, fixed = TRUE)
  ),
  list(
    name = "wiring_train_refusal_hook_present",
    ok = grepl('refuse_pfas_op_on_metadata_lane("Train (Evidence-Governed)")', src, fixed = TRUE) &&
      grepl('refuse_pfas_op_on_metadata_lane("Screening', src, fixed = TRUE)
  )
)

failed <- character(0)
for (c in checks) {
  if (!isTRUE(c$ok)) {
    failed <- c(failed, c$name)
  }
}

cat("LatestPFAS.R parse: OK (", length(expr), " top-level expr)\n", sep = "")
cat("ICIS-AIR signature smoke:\n")
for (c in checks) {
  cat(sprintf("  %s: %s\n", c$name, if (isTRUE(c$ok)) "PASS" else "FAIL"))
}

if (length(failed) > 0L) {
  stop("FAILED: ", paste(failed, collapse = ", "))
}
cat("Overall: PASS\n")
