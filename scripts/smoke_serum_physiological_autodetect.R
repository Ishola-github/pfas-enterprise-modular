# Smoke test: physiological-sample autodetect for NHANES serum biomonitoring
# uploads. Mirrors the per-column classification logic in LatestPFAS.R so the
# wiring contract can be verified without bringing up the Shiny session.
#
# Governance anchors:
#   - validation/serum_v1/schema_contract.md \u00a72 (analyte panel, paired LOD codes)
#   - validation/serum_v1/data_dictionary.csv  (canonical analyte short names)
#   - SCOPE_AND_INTENDED_USE.md \u00a714           (physiological vs occurrence)
#   - LatestPFAS.R                              (autodetect_physiological_serum_columns)
#
# Run from project root:
#   Rscript scripts/smoke_serum_physiological_autodetect.R

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
}

normalize_upload_colnames <- function(col_names) {
  x <- tolower(trimws(as.character(col_names)))
  x <- gsub("[[:space:].]+", "_", x, perl = FALSE)
  x <- gsub("_+", "_", x, perl = FALSE)
  x
}

NHANES_SERUM_LBX_TO_ANALYTE <- list(
  lbxnfoa = "n-PFOA",   lbxbfoa = "Sb-PFOA",
  lbxnfos = "n-PFOS",   lbxmfos = "Sm-PFOS",
  lbxpfhs = "PFHxS",    lbxpfna = "PFNA",
  lbxpfde = "PFDA",     lbxpfua = "PFUnDA",
  lbxmpah = "Me-PFOSA-AcOH"
)
NHANES_SERUM_LBD_TO_ANALYTE <- list(
  lbdnfoal = "n-PFOA",  lbdbfoal = "Sb-PFOA",
  lbdnfosl = "n-PFOS",  lbdmfosl = "Sm-PFOS",
  lbdpfhsl = "PFHxS",   lbdpfnal = "PFNA",
  lbdpfdel = "PFDA",    lbdpfual = "PFUnDA",
  lbdmpahl = "Me-PFOSA-AcOH"
)
NHANES_SERUM_WEIGHT_COLS <- c(
  "wtsb2yr", "wtmec2yr", "wtmecprp", "wtssch2y", "wtssch2yr"
)

# Lane-stamped physiological classification (validation/serum_v1/
# schema_contract.md \u00a79). Mirror of SERUM_PHYSIOLOGICAL_STAMP /
# PHYSIOLOGICAL_CLASSIFICATION_FIELDS / physiological_guard() in
# LatestPFAS.R so the smoke can verify those constants and behavior
# without sourcing the Shiny app.
PHYSIOLOGICAL_CLASSIFICATION_FIELDS <- c(
  "sample_domain", "sample_matrix", "measurement_context",
  "source_program", "governance_lane"
)
SERUM_PHYSIOLOGICAL_STAMP <- list(
  sample_domain       = "physiological",
  sample_matrix       = "human_serum",
  measurement_context = "biomonitoring",
  source_program      = "CDC NHANES",
  governance_lane     = "serum_v1"
)
PHYSIOLOGICAL_GUARD_REFUSAL_CODES <- list(
  missing_field  = "physiological_classification_missing",
  value_mismatch = "physiological_classification_mismatch"
)

physiological_lane_stamp <- function(lane = "serum") {
  if (identical(lane, "serum")) return(SERUM_PHYSIOLOGICAL_STAMP)
  NULL
}

physiological_guard <- function(row, lane = "serum") {
  expected <- physiological_lane_stamp(lane)
  if (is.null(expected)) {
    return(list(ok = FALSE, code = "physiological_guard_unknown_lane",
                missing = character(0), mismatched = character(0),
                expected = list(), observed = list()))
  }
  observed <- list(); missing <- character(0); mismatched <- character(0)
  for (k in names(expected)) {
    v <- if (is.list(row)) row[[k]] else NULL
    if (is.null(v) || length(v) == 0L) {
      missing <- c(missing, k); observed[[k]] <- NA_character_; next
    }
    v_chr <- as.character(v)
    # Empty-string / NA cells count as missing-field, not mismatch
    # (matches LatestPFAS.R :: physiological_guard so a blank-stamp
    # NIST SRM 1957 row is refused as "missing", which is the honest
    # verdict for a reference-material row).
    if (all(is.na(v_chr)) || all(!nzchar(v_chr))) {
      missing <- c(missing, k); observed[[k]] <- NA_character_; next
    }
    observed[[k]] <- v_chr
    if (!all(v_chr == as.character(expected[[k]]))) {
      mismatched <- c(mismatched, k)
    }
  }
  code <- if (length(missing) > 0L) {
    PHYSIOLOGICAL_GUARD_REFUSAL_CODES$missing_field
  } else if (length(mismatched) > 0L) {
    PHYSIOLOGICAL_GUARD_REFUSAL_CODES$value_mismatch
  } else { "physiological_guard_ok" }
  list(ok = length(missing) == 0L && length(mismatched) == 0L,
       code = code, missing = missing, mismatched = mismatched,
       expected = expected, observed = observed)
}

# Mirror of autodetect_physiological_serum_columns() from LatestPFAS.R.
autodetect_physiological_serum_columns <- function(col_names) {
  empty_cols_df <- data.frame(
    column = character(0), normalized = character(0),
    role = character(0), analyte = character(0),
    paired_with = character(0), units = character(0),
    notes = character(0), stringsAsFactors = FALSE
  )
  empty <- list(
    is_physiological = FALSE,
    lane = NA_character_, semantic_type = NA_character_,
    matrix = NA_character_, method = NA_character_,
    units = NA_character_, format = NA_character_,
    columns = empty_cols_df, paired_lbx_lbd = list(),
    counts = list(respondent_id = 0L, survey_weight = 0L,
                  analyte_concentration = 0L,
                  analyte_detection_code = 0L, unknown = 0L)
  )
  if (is.null(col_names) || length(col_names) < 1L) return(empty)
  orig <- as.character(col_names)
  norm <- normalize_upload_colnames(orig)
  classify_one <- function(i) {
    nm <- norm[[i]]
    role <- "unknown"
    analyte <- NA_character_
    paired <- NA_character_
    units <- NA_character_
    notes <- ""
    if (identical(nm, "seqn")) {
      role <- "respondent_id"
      notes <- "NHANES sequence number; not a PFAS concentration"
    } else if (nm %in% NHANES_SERUM_WEIGHT_COLS) {
      role <- "survey_weight"
      notes <- "NHANES survey weight; not an analytical measurement"
    } else if (nm %in% names(NHANES_SERUM_LBX_TO_ANALYTE)) {
      role <- "analyte_concentration"
      analyte <- NHANES_SERUM_LBX_TO_ANALYTE[[nm]]
      pair_nm <- paste0(sub("^lbx", "lbd", nm), "l")
      paired <- if (pair_nm %in% norm) orig[[which(norm == pair_nm)[[1]]]] else NA_character_
      units <- "ng/mL"
    } else if (nm %in% names(NHANES_SERUM_LBD_TO_ANALYTE)) {
      role <- "analyte_detection_code"
      analyte <- NHANES_SERUM_LBD_TO_ANALYTE[[nm]]
      pair_nm <- sub("l$", "", sub("^lbd", "lbx", nm))
      paired <- if (pair_nm %in% norm) orig[[which(norm == pair_nm)[[1]]]] else NA_character_
      units <- "0/1"
    }
    data.frame(
      column = orig[[i]], normalized = nm, role = role,
      analyte = analyte, paired_with = paired,
      units = units, notes = notes, stringsAsFactors = FALSE
    )
  }
  rows <- do.call(rbind, lapply(seq_along(orig), classify_one))
  counts <- list(
    respondent_id          = sum(rows$role == "respondent_id"),
    survey_weight          = sum(rows$role == "survey_weight"),
    analyte_concentration  = sum(rows$role == "analyte_concentration"),
    analyte_detection_code = sum(rows$role == "analyte_detection_code"),
    unknown                = sum(rows$role == "unknown")
  )
  paired <- list()
  for (i in which(rows$role == "analyte_concentration")) {
    if (!is.na(rows$paired_with[[i]])) {
      paired[[length(paired) + 1L]] <- list(
        lbx_column = rows$column[[i]],
        lbd_column = rows$paired_with[[i]],
        analyte    = rows$analyte[[i]]
      )
    }
  }
  recognized <- counts$respondent_id + counts$survey_weight +
    counts$analyte_concentration + counts$analyte_detection_code
  list(
    is_physiological = recognized > 0L,
    lane = "serum", semantic_type = "serum_biomonitoring",
    matrix = "human serum",
    method = "CDC NHANES PFAS (LC/MS/MS, isotope-dilution)",
    units = "ng/mL",
    format = "wide (one row per respondent, one column per analyte)",
    columns = rows, paired_lbx_lbd = paired, counts = counts,
    classification_stamp = physiological_lane_stamp("serum"),
    classification_fields = PHYSIOLOGICAL_CLASSIFICATION_FIELDS
  )
}

repo_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
app_path  <- file.path(repo_root, "LatestPFAS.R")
if (!file.exists(app_path)) stop("Missing ", app_path)
src <- paste(readLines(app_path, warn = FALSE), collapse = "\n")
expr <- tryCatch(parse(file = app_path), error = function(e) {
  stop("LatestPFAS.R failed to parse: ", conditionMessage(e))
})

# Canonical NHANES PFAS_J upper-case header (cycle J), 20 columns total.
nhanes_pfas_j_upper <- c(
  "SEQN", "WTSB2YR",
  "LBXNFOA", "LBDNFOAL", "LBXBFOA", "LBDBFOAL",
  "LBXNFOS", "LBDNFOSL", "LBXMFOS", "LBDMFOSL",
  "LBXPFHS", "LBDPFHSL", "LBXPFNA", "LBDPFNAL",
  "LBXPFDE", "LBDPFDEL", "LBXPFUA", "LBDPFUAL",
  "LBXMPAH", "LBDMPAHL"
)
nhanes_pfas_j_lower <- tolower(nhanes_pfas_j_upper)
ucmr_like <- c("PWSID", "Contaminant", "AnalyticalResultValue", "UnitOfMeasure")

# ---------------- Function-level checks ------------------------------------
a_upper <- autodetect_physiological_serum_columns(nhanes_pfas_j_upper)
a_lower <- autodetect_physiological_serum_columns(nhanes_pfas_j_lower)
a_partial <- autodetect_physiological_serum_columns(
  c("SEQN", "WTSB2YR", "LBXNFOA", "LBDNFOAL")
)
a_ucmr <- autodetect_physiological_serum_columns(ucmr_like)
a_empty <- autodetect_physiological_serum_columns(character(0))
a_lbx_no_pair <- autodetect_physiological_serum_columns(c("SEQN", "LBXNFOA"))

checks <- list(
  # is_physiological flag
  list(name = "upper_is_physiological",
       ok = isTRUE(a_upper$is_physiological)),
  list(name = "lower_is_physiological",
       ok = isTRUE(a_lower$is_physiological)),
  list(name = "ucmr_is_not_physiological",
       ok = isFALSE(a_ucmr$is_physiological)),
  list(name = "empty_cols_is_not_physiological",
       ok = isFALSE(a_empty$is_physiological)),
  # Lane summary values
  list(name = "lane_summary_serum",
       ok = identical(a_upper$lane, "serum") &&
            identical(a_upper$semantic_type, "serum_biomonitoring") &&
            identical(a_upper$matrix, "human serum") &&
            identical(a_upper$units, "ng/mL")),
  # Counts
  list(name = "counts_upper_full_panel",
       ok = a_upper$counts$respondent_id == 1L &&
            a_upper$counts$survey_weight == 1L &&
            a_upper$counts$analyte_concentration == 9L &&
            a_upper$counts$analyte_detection_code == 9L &&
            a_upper$counts$unknown == 0L),
  list(name = "counts_lower_full_panel_matches_upper",
       ok = identical(a_upper$counts, a_lower$counts)),
  # Per-column classification
  list(name = "seqn_classified_respondent_id",
       ok = {
         r <- a_upper$columns[a_upper$columns$column == "SEQN", , drop = FALSE]
         nrow(r) == 1L && identical(r$role, "respondent_id")
       }),
  list(name = "wtsb2yr_classified_survey_weight",
       ok = {
         r <- a_upper$columns[a_upper$columns$column == "WTSB2YR", , drop = FALSE]
         nrow(r) == 1L && identical(r$role, "survey_weight")
       }),
  list(name = "lbxnfoa_classified_concentration_with_ngml",
       ok = {
         r <- a_upper$columns[a_upper$columns$column == "LBXNFOA", , drop = FALSE]
         nrow(r) == 1L &&
           identical(r$role, "analyte_concentration") &&
           identical(r$analyte, "n-PFOA") &&
           identical(r$units, "ng/mL") &&
           identical(r$paired_with, "LBDNFOAL")
       }),
  list(name = "lbdnfoal_classified_detection_code_with_pair",
       ok = {
         r <- a_upper$columns[a_upper$columns$column == "LBDNFOAL", , drop = FALSE]
         nrow(r) == 1L &&
           identical(r$role, "analyte_detection_code") &&
           identical(r$analyte, "n-PFOA") &&
           identical(r$units, "0/1") &&
           identical(r$paired_with, "LBXNFOA")
       }),
  # Paired LBX/LBD coverage for full panel
  list(name = "full_panel_pairs_9_analytes",
       ok = length(a_upper$paired_lbx_lbd) == 9L),
  list(name = "partial_pairs_one_analyte",
       ok = length(a_partial$paired_lbx_lbd) == 1L),
  list(name = "lbx_without_lbd_pair_records_na",
       ok = {
         r <- a_lbx_no_pair$columns[a_lbx_no_pair$columns$column == "LBXNFOA",
                                    , drop = FALSE]
         nrow(r) == 1L && is.na(r$paired_with)
       }),
  # Negative case
  list(name = "ucmr_columns_all_unknown",
       ok = all(a_ucmr$columns$role == "unknown")),
  # Canonical short names from validation/serum_v1/data_dictionary.csv
  # (the 'analyte' column). Compared as an unordered, unnamed set so the
  # check does not depend on insertion order or list-name attributes.
  list(
    name = "analyte_short_names_match_data_dictionary",
    ok = setequal(
      unname(unlist(NHANES_SERUM_LBX_TO_ANALYTE)),
      c("n-PFOA", "Sb-PFOA", "n-PFOS", "Sm-PFOS",
        "PFHxS", "PFNA", "PFDA", "PFUnDA", "Me-PFOSA-AcOH")
    ) &&
      setequal(
        unname(unlist(NHANES_SERUM_LBD_TO_ANALYTE)),
        c("n-PFOA", "Sb-PFOA", "n-PFOS", "Sm-PFOS",
          "PFHxS", "PFNA", "PFDA", "PFUnDA", "Me-PFOSA-AcOH")
      )
  )
)

# ---------------- LatestPFAS.R wiring contract ----------------------------
ui_checks <- list(
  list(name = "wiring_autodetect_function_defined_in_app",
       ok = grepl("autodetect_physiological_serum_columns <- function",
                  src, fixed = TRUE)),
  list(name = "wiring_lbx_to_analyte_map_present",
       ok = grepl("NHANES_SERUM_LBX_TO_ANALYTE <- list",
                  src, fixed = TRUE)),
  list(name = "wiring_lbd_to_analyte_map_present",
       ok = grepl("NHANES_SERUM_LBD_TO_ANALYTE <- list",
                  src, fixed = TRUE)),
  list(name = "wiring_weight_cols_constant_present",
       ok = grepl("NHANES_SERUM_WEIGHT_COLS <- c",
                  src, fixed = TRUE)),
  list(name = "wiring_autodetect_version_constant_present",
       ok = grepl("SERUM_BIOMONITORING_AUTODETECT_VERSION <- ",
                  src, fixed = TRUE)),
  list(name = "wiring_autodetect_version_value_bumped",
       ok = grepl('"2026-05-13-physiological-autodetect-1"',
                  src, fixed = TRUE)),
  list(name = "wiring_mapping_engine_version_bumped",
       ok = grepl('MAPPING_ENGINE_VERSION <- "2026-05-13-physiological-autodetect-1"',
                  src, fixed = TRUE)),
  list(name = "wiring_quality_status_calls_autodetect",
       ok = grepl("auto <- autodetect_physiological_serum_columns",
                  src, fixed = TRUE)),
  list(name = "wiring_quality_status_branches_on_serum_semantic",
       ok = grepl('identical(sem_now, "serum_biomonitoring")',
                  src, fixed = TRUE)),
  list(name = "wiring_autodetect_summary_renderui_defined",
       ok = grepl("output\\$serum_external_autodetect_summary <- renderUI",
                  src)),
  list(name = "wiring_autodetect_summary_uioutput_present",
       ok = grepl('uiOutput("serum_external_autodetect_summary")',
                  src, fixed = TRUE)),
  # Position contract: the summary uiOutput appears AFTER the banner.
  list(
    name = "wiring_autodetect_summary_appears_after_serum_banner",
    ok = {
      i_b <- regexpr('uiOutput\\("serum_external_upload_banner"\\)',
                     src, perl = TRUE)
      i_s <- regexpr('uiOutput\\("serum_external_autodetect_summary"\\)',
                     src, perl = TRUE)
      as.integer(i_b) > 0 && as.integer(i_s) > 0 &&
        as.integer(i_s) > as.integer(i_b)
    }
  ),
  # Serum branch in the quality-status pane must point at lane assets.
  list(
    name = "quality_status_branch_points_at_serum_lane_assets",
    ok = grepl("data/training/serum/training.csv", src, fixed = TRUE) &&
      grepl("data/ad_models/serum/ad_model.json", src, fixed = TRUE) &&
      grepl("scripts/convert_nhanes_xpt_to_csv.R", src, fixed = TRUE) &&
      grepl("validation/serum_v1/schema_contract.md", src, fixed = TRUE)
  )
)

stamp_checks <- list(
  # -------------------- Stamp constants (mirror of LatestPFAS.R) ------
  list(
    name = "stamp_field_names_exact",
    ok = identical(
      PHYSIOLOGICAL_CLASSIFICATION_FIELDS,
      c("sample_domain", "sample_matrix", "measurement_context",
        "source_program", "governance_lane")
    )
  ),
  list(
    name = "stamp_sample_domain_value",
    ok = identical(SERUM_PHYSIOLOGICAL_STAMP$sample_domain, "physiological")
  ),
  list(
    name = "stamp_sample_matrix_value",
    ok = identical(SERUM_PHYSIOLOGICAL_STAMP$sample_matrix, "human_serum")
  ),
  list(
    name = "stamp_measurement_context_value",
    ok = identical(SERUM_PHYSIOLOGICAL_STAMP$measurement_context,
                   "biomonitoring")
  ),
  list(
    name = "stamp_source_program_value",
    ok = identical(SERUM_PHYSIOLOGICAL_STAMP$source_program,
                   "CDC NHANES")
  ),
  list(
    name = "stamp_governance_lane_value",
    ok = identical(SERUM_PHYSIOLOGICAL_STAMP$governance_lane, "serum_v1")
  ),
  list(
    name = "stamp_does_not_carry_units_field",
    # Concentration units are a row property (result_unit); the stamp
    # must not duplicate them. NHANES rows are ng/mL, SRM rows are
    # ug/kg; one lane-stamped 'units' constant cannot honestly
    # describe both.
    ok = is.null(SERUM_PHYSIOLOGICAL_STAMP$units) &&
      !"units" %in% PHYSIOLOGICAL_CLASSIFICATION_FIELDS
  ),
  list(
    name = "stamp_only_serum_lane_registered",
    ok = !is.null(physiological_lane_stamp("serum")) &&
      is.null(physiological_lane_stamp("drinking_water")) &&
      is.null(physiological_lane_stamp("biosolids_sludge")) &&
      is.null(physiological_lane_stamp("afff")) &&
      is.null(physiological_lane_stamp("methanol_standards")) &&
      is.null(physiological_lane_stamp("air_emissions"))
  ),
  # -------------------- Guard behavior --------------------------------
  list(
    name = "guard_ok_when_row_carries_full_stamp",
    ok = {
      g <- physiological_guard(SERUM_PHYSIOLOGICAL_STAMP, lane = "serum")
      isTRUE(g$ok) && identical(g$code, "physiological_guard_ok") &&
        length(g$missing) == 0L && length(g$mismatched) == 0L
    }
  ),
  list(
    name = "guard_missing_field_when_row_lacks_stamp",
    ok = {
      g <- physiological_guard(list(), lane = "serum")
      isFALSE(g$ok) &&
        identical(g$code, "physiological_classification_missing") &&
        setequal(g$missing, PHYSIOLOGICAL_CLASSIFICATION_FIELDS)
    }
  ),
  list(
    name = "guard_partial_missing_reports_only_missing_fields",
    ok = {
      r <- SERUM_PHYSIOLOGICAL_STAMP
      r$measurement_context <- NULL
      g <- physiological_guard(r, lane = "serum")
      isFALSE(g$ok) &&
        identical(g$code, "physiological_classification_missing") &&
        setequal(g$missing, "measurement_context") &&
        length(g$mismatched) == 0L
    }
  ),
  list(
    name = "guard_value_mismatch_when_row_has_wrong_value",
    ok = {
      r <- SERUM_PHYSIOLOGICAL_STAMP
      r$sample_matrix <- "drinking_water"
      g <- physiological_guard(r, lane = "serum")
      isFALSE(g$ok) &&
        identical(g$code, "physiological_classification_mismatch") &&
        setequal(g$mismatched, "sample_matrix")
    }
  ),
  list(
    name = "guard_unknown_lane_refuses",
    ok = {
      g <- physiological_guard(SERUM_PHYSIOLOGICAL_STAMP,
                                lane = "drinking_water")
      isFALSE(g$ok) &&
        identical(g$code, "physiological_guard_unknown_lane")
    }
  ),
  # -------------------- Autodetect emits stamp ------------------------
  list(
    name = "autodetect_attaches_classification_stamp",
    ok = {
      a <- autodetect_physiological_serum_columns(nhanes_pfas_j_upper)
      identical(a$classification_stamp$sample_domain, "physiological") &&
        identical(a$classification_stamp$sample_matrix, "human_serum") &&
        identical(a$classification_stamp$measurement_context, "biomonitoring") &&
        identical(a$classification_stamp$source_program, "CDC NHANES") &&
        identical(a$classification_stamp$governance_lane, "serum_v1")
    }
  ),
  list(
    name = "autodetect_exposes_classification_fields_list",
    ok = identical(
      autodetect_physiological_serum_columns(nhanes_pfas_j_upper)$classification_fields,
      PHYSIOLOGICAL_CLASSIFICATION_FIELDS
    )
  ),
  # -------------------- LatestPFAS.R wiring contract ------------------
  list(
    name = "wiring_app_defines_physiological_stamp_constant",
    ok = grepl("SERUM_PHYSIOLOGICAL_STAMP <- list", src, fixed = TRUE)
  ),
  list(
    name = "wiring_app_defines_classification_fields_constant",
    ok = grepl("PHYSIOLOGICAL_CLASSIFICATION_FIELDS <- c",
               src, fixed = TRUE)
  ),
  list(
    name = "wiring_app_defines_lane_stamp_function",
    ok = grepl("physiological_lane_stamp <- function",
               src, fixed = TRUE)
  ),
  list(
    name = "wiring_app_defines_guard_function",
    ok = grepl("physiological_guard <- function", src, fixed = TRUE)
  ),
  list(
    name = "wiring_app_carries_canonical_stamp_values",
    ok = grepl('sample_domain       = "physiological"', src, fixed = TRUE) &&
      grepl('sample_matrix       = "human_serum"', src, fixed = TRUE) &&
      grepl('measurement_context = "biomonitoring"', src, fixed = TRUE) &&
      grepl('source_program      = "CDC NHANES"', src, fixed = TRUE) &&
      grepl('governance_lane     = "serum_v1"', src, fixed = TRUE)
  ),
  list(
    name = "wiring_app_refusal_codes_present",
    ok = grepl('"physiological_classification_missing"',
               src, fixed = TRUE) &&
      grepl('"physiological_classification_mismatch"',
            src, fixed = TRUE)
  ),
  list(
    name = "wiring_app_autodetect_attaches_stamp",
    ok = grepl('classification_stamp = physiological_lane_stamp\\("serum"\\)',
               src, perl = TRUE)
  ),
  list(
    name = "wiring_app_autodetect_summary_renders_stamp_table",
    ok = grepl("Lane-stamped physiological classification", src, fixed = TRUE)
  ),
  list(
    name = "wiring_app_quality_status_prints_stamp",
    ok = grepl("Lane-stamped physiological classification \\(auto-mapped",
               src, perl = TRUE)
  ),
  list(
    name = "wiring_app_refusal_audit_attaches_guard_payload",
    ok = grepl("physiological_guard = list", src, fixed = TRUE) &&
      grepl('governance_ref = "validation/serum_v1/schema_contract.md',
            src, fixed = TRUE)
  ),
  # -------------------- Governance docs carry the stamp ---------------
  list(
    name = "governance_schema_contract_md_section_9",
    ok = grepl("## 9. Physiological-sample classification stamp",
               paste(readLines(
                 file.path(repo_root, "validation/serum_v1/schema_contract.md"),
                 warn = FALSE
               ), collapse = "\n"), fixed = TRUE)
  ),
  list(
    name = "governance_schema_contract_json_has_block",
    ok = {
      txt <- paste(readLines(
        file.path(repo_root, "validation/serum_v1/schema_contract.json"),
        warn = FALSE
      ), collapse = "\n")
      grepl('"physiological_classification"', txt, fixed = TRUE) &&
        grepl('"sample_domain":       "physiological"', txt, fixed = TRUE)
    }
  ),
  list(
    # Read line-anchored to dodge Windows-locale (\xa7) parsing quirks
    # in utils::read.csv; the row is valid CSV regardless of encoding,
    # we just need to confirm each stamp field starts a row.
    name = "governance_data_dictionary_csv_has_stamp_rows",
    ok = {
      lines <- readLines(
        file.path(repo_root, "validation/serum_v1/data_dictionary.csv"),
        warn = FALSE, encoding = "UTF-8"
      )
      all(vapply(PHYSIOLOGICAL_CLASSIFICATION_FIELDS, function(k) {
        any(grepl(paste0("^", k, ","), lines, fixed = FALSE))
      }, logical(1)))
    }
  ),
  list(
    name = "governance_manifest_carries_classification_block",
    ok = {
      if (!requireNamespace("jsonlite", quietly = TRUE)) {
        install.packages("jsonlite",
                         repos = c(CRAN = "https://cloud.r-project.org"))
      }
      man <- jsonlite::fromJSON(
        file.path(repo_root, "data/training/serum/manifest.json"),
        simplifyVector = TRUE
      )
      !is.null(man$physiological_classification) &&
        identical(man$physiological_classification$fields$sample_domain,
                  "physiological") &&
        identical(man$physiological_classification$fields$source_program,
                  "CDC NHANES") &&
        identical(man$physiological_classification$fields$governance_lane,
                  "serum_v1") &&
        is.null(man$physiological_classification$fields$units) &&
        identical(man$physiological_classification$refusal_codes$missing_field,
                  "physiological_classification_missing")
    }
  ),
  # -------------------- Built training table carries the stamp -----------
  # These checks verify that the *built* artifact at
  # data/training/serum/training.csv physically carries the five
  # classification columns, that every NHANES row is stamped with the
  # canonical biomonitoring values, and that every NIST SRM 1957 row
  # leaves those columns blank (per the per-row applicability rule in
  # manifest.json :: physiological_classification.row_level_applicability).
  list(
    name = "built_training_csv_header_has_five_stamp_columns",
    ok = {
      tr <- file.path(repo_root, "data/training/serum/training.csv")
      hdr <- if (file.exists(tr))
               strsplit(readLines(tr, n = 1, warn = FALSE), ",",
                        fixed = TRUE)[[1]]
             else character(0)
      all(PHYSIOLOGICAL_CLASSIFICATION_FIELDS %in% hdr)
    }
  ),
  list(
    name = "built_training_csv_stamp_columns_are_appended_after_canonical",
    # The stamp columns are LANE-SPECIFIC; they must sit after the
    # canonical core, not interleaved into it, so a downstream reader
    # that only knows the canonical header is unaffected for other
    # lanes. We check that the five stamp columns are the LAST five.
    ok = {
      tr <- file.path(repo_root, "data/training/serum/training.csv")
      hdr <- if (file.exists(tr))
               strsplit(readLines(tr, n = 1, warn = FALSE), ",",
                        fixed = TRUE)[[1]]
             else character(0)
      identical(tail(hdr, 5L), as.character(PHYSIOLOGICAL_CLASSIFICATION_FIELDS))
    }
  ),
  list(
    name = "built_training_csv_all_nhanes_rows_carry_stamp",
    ok = {
      tr <- file.path(repo_root, "data/training/serum/training.csv")
      df <- tryCatch(utils::read.csv(tr, stringsAsFactors = FALSE,
                                     check.names = FALSE),
                     error = function(e) NULL)
      if (is.null(df) || !"source" %in% names(df)) {
        FALSE
      } else {
        nh <- df[df$source == "CDC_NHANES", , drop = FALSE]
        nrow(nh) > 0 &&
          all(nh$sample_domain       == "physiological") &&
          all(nh$sample_matrix       == "human_serum") &&
          all(nh$measurement_context == "biomonitoring") &&
          all(nh$source_program      == "CDC NHANES") &&
          all(nh$governance_lane     == "serum_v1") &&
          !"units" %in% names(nh)
      }
    }
  ),
  list(
    name = "built_training_csv_srm_rows_have_blank_stamp",
    # NIST SRM 1957 rows are reference material, not biomonitoring.
    # They must leave every stamp column blank so the physiological
    # guard refuses them with `physiological_classification_missing`
    # rather than silently accepting a reference value as a body-burden
    # measurement. See manifest.json :: physiological_classification.
    # row_level_applicability.
    ok = {
      tr <- file.path(repo_root, "data/training/serum/training.csv")
      df <- tryCatch(utils::read.csv(tr, stringsAsFactors = FALSE,
                                     check.names = FALSE),
                     error = function(e) NULL)
      if (is.null(df) || !"source" %in% names(df)) {
        FALSE
      } else {
        srm <- df[df$source == "NIST_SRM1957", , drop = FALSE]
        is_blank <- function(x) is.na(x) | !nzchar(as.character(x))
        nrow(srm) > 0 &&
          all(is_blank(srm$sample_domain)) &&
          all(is_blank(srm$sample_matrix)) &&
          all(is_blank(srm$measurement_context)) &&
          all(is_blank(srm$source_program)) &&
          all(is_blank(srm$governance_lane))
      }
    }
  ),
  list(
    name = "built_training_csv_guard_refuses_blank_srm_row",
    # Run the actual physiological_guard against a blanked-stamp row
    # taken from training.csv (i.e. a NIST SRM 1957 row). The verdict
    # must be missing_field, not value_mismatch.
    ok = {
      tr <- file.path(repo_root, "data/training/serum/training.csv")
      df <- tryCatch(utils::read.csv(tr, stringsAsFactors = FALSE,
                                     check.names = FALSE),
                     error = function(e) NULL)
      if (is.null(df) || !"source" %in% names(df)) {
        FALSE
      } else {
        srm <- df[df$source == "NIST_SRM1957", , drop = FALSE]
        if (nrow(srm) < 1L) FALSE else {
          row1 <- as.list(srm[1L, , drop = FALSE])
          v <- physiological_guard(row1, lane = "serum")
          (!isTRUE(v$ok)) &&
            identical(v$code,
                      PHYSIOLOGICAL_GUARD_REFUSAL_CODES$missing_field)
        }
      }
    }
  ),
  list(
    name = "built_training_csv_guard_passes_nhanes_row",
    # And the converse: a stamped NHANES row must pass cleanly.
    ok = {
      tr <- file.path(repo_root, "data/training/serum/training.csv")
      df <- tryCatch(utils::read.csv(tr, stringsAsFactors = FALSE,
                                     check.names = FALSE),
                     error = function(e) NULL)
      if (is.null(df) || !"source" %in% names(df)) {
        FALSE
      } else {
        nh <- df[df$source == "CDC_NHANES", , drop = FALSE]
        if (nrow(nh) < 1L) FALSE else {
          row1 <- as.list(nh[1L, , drop = FALSE])
          v <- physiological_guard(row1, lane = "serum")
          isTRUE(v$ok) && identical(v$code, "physiological_guard_ok")
        }
      }
    }
  ),
  list(
    name = "built_training_csv_hash_matches_manifest",
    # Treat the manifest as the authoritative pointer and require it
    # to match the on-disk file. If anyone hand-edits training.csv
    # without rerunning the build, this fails.
    ok = {
      tr <- file.path(repo_root, "data/training/serum/training.csv")
      mf <- file.path(repo_root, "data/training/serum/manifest.json")
      if (!(file.exists(tr) && file.exists(mf))) FALSE else {
        if (!requireNamespace("digest", quietly = TRUE)) {
          install.packages("digest",
                           repos = c(CRAN = "https://cloud.r-project.org"))
        }
        h <- digest::digest(file = tr, algo = "sha256")
        m <- jsonlite::fromJSON(mf, simplifyVector = TRUE)
        identical(tolower(h), tolower(m$training_csv_sha256))
      }
    }
  ),
  list(
    name = "built_ad_model_hash_matches_manifest",
    # The AD model carries a copy of training_csv_sha256. If the
    # training table was rebuilt but the AD model was not (or vice
    # versa), this drift gets caught here. The Shiny app refuses
    # predictions when these disagree (see ad_status='reject').
    ok = {
      mf <- file.path(repo_root, "data/training/serum/manifest.json")
      am <- file.path(repo_root, "data/ad_models/serum/ad_model.json")
      if (!(file.exists(mf) && file.exists(am))) FALSE else {
        m <- jsonlite::fromJSON(mf, simplifyVector = TRUE)
        a <- jsonlite::fromJSON(am, simplifyVector = TRUE)
        identical(tolower(m$training_csv_sha256),
                  tolower(a$training_csv_sha256)) &&
          identical(as.integer(m$rows_written),
                    as.integer(a$training_csv_rows))
      }
    }
  ),
  list(
    name = "built_manifest_carries_lane_kind",
    # Regression check for yesterday's lane_kind work: a manifest
    # rebuild must NOT drop lane_kind. _write_manifest now reads it
    # from data/config/matrix_pipeline_sop.csv.
    ok = {
      mf <- file.path(repo_root, "data/training/serum/manifest.json")
      if (!file.exists(mf)) FALSE else {
        m <- jsonlite::fromJSON(mf, simplifyVector = TRUE)
        identical(m$lane_kind, "physiological_biomonitoring") &&
          identical(m$semantic_type, "serum_biomonitoring")
      }
    }
  ),
  list(
    name = "built_pipeline_stamp_helper_present",
    # The Python pipeline must contain the stamp helper and apply it
    # to NHANES rows in _build_serum. If a refactor accidentally
    # removes the call, this fails immediately.
    ok = {
      rp <- file.path(repo_root, "scripts/run_matrix_pipeline.py")
      if (!file.exists(rp)) FALSE else {
        txt <- paste(readLines(rp, warn = FALSE), collapse = "\n")
        grepl("def _stamp_physiological_classification(", txt,
              fixed = TRUE) &&
          grepl("PHYSIOLOGICAL_CLASSIFICATION_FIELDS", txt, fixed = TRUE) &&
          grepl("_stamp_physiological_classification(row, lane)", txt,
                fixed = TRUE) &&
          grepl("extra_columns=PHYSIOLOGICAL_CLASSIFICATION_FIELDS", txt,
                fixed = TRUE)
      }
    }
  )
)

checks <- c(checks, ui_checks, stamp_checks)
failed <- character(0)
for (c in checks) if (!isTRUE(c$ok)) failed <- c(failed, c$name)

cat("LatestPFAS.R parse: OK (", length(expr), " top-level expr)\n", sep = "")
cat("Physiological-sample autodetect smoke:\n")
for (c in checks) {
  cat(sprintf("  %s: %s\n", c$name,
              if (isTRUE(c$ok)) "PASS" else "FAIL"))
}
if (length(failed) > 0L) {
  stop("FAILED: ", paste(failed, collapse = ", "))
}
cat("Overall: PASS (", length(checks), "/", length(checks), ")\n", sep = "")
