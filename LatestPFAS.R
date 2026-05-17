# PFAS Enterprise 5.0 — Standards-compliant predictive toxicology Shiny application
# SQLite-backed data collection, curation, audit logging, ML export scaffold, and Cloud API screening.

suppressPackageStartupMessages({
  library(shiny)
  library(shinydashboard)
  library(shinymanager)
  library(DT)
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(purrr)
  library(stringr)
  library(scales)
  library(jsonlite)
  library(httr)
  library(digest)
  library(DBI)
  library(RSQLite)
})

options(shiny.sanitize.errors = FALSE)
max_upload_mb <- suppressWarnings(as.numeric(Sys.getenv("PFAS_MAX_UPLOAD_MB", "512")))
if (is.na(max_upload_mb) || max_upload_mb <= 0) max_upload_mb <- 512
options(shiny.maxRequestSize = max_upload_mb * 1024^2)

APP_TITLE <- "PFAS Enterprise 5.0 — Standards-Compliant Toxicology & Regulatory Screening"
APP_VERSION <- "5.0.0"
# Portable project root: shiny::runApp() uses the application directory as working directory
PROJECT_DIR <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
DISCLAIMER_MD_PATH <- file.path(PROJECT_DIR, "DISCLAIMER.md")
DISCLAIMER_GITHUB_URL <- "https://github.com/Ishola-github/pfas-enterprise-modular/blob/main/DISCLAIMER.md"
MAPPING_ENGINE_VERSION <- "2026-05-13-physiological-autodetect-1"
# ISO / PFAS screening MVP: user-facing Map + mapping status only (22 keys).
# Normalized tables still carry legacy columns (region, collection_month, pws_size, health_*) as all-NA for master/SQLite column alignment.
CORE_EXTERNAL_MAP_KEYS <- c(
  "source_dataset", "sample_id", "matrix", "date", "analyte", "cas",
  "result_value", "unit", "qualifier", "mdl", "rl", "detect_flag",
  "state", "county", "facility_water_type", "sample_point_type",
  "method_id", "collection_year", "facility_id", "sample_point_id",
  "latitude", "longitude"
)
REFERENCE_EXTRA_MAP_KEYS <- c("uncertainty", "reference_id")
# Must match selectInput choice in External ML upload panel exactly.
REFERENCE_MATERIAL_DATASET_TYPE <- "reference material (NIST / RM / bench)"
# Shown in External ML upload panel. Grep LatestPFAS.R for UPLOAD_READER_VERSION or substring
# delimited-base-only (no readr); substring e.g. utf16-unquoted indicates encoding/quote-escape hardening.
UPLOAD_READER_VERSION <- "2026-06-06-upload-nrows-nulsanitize-fix"
ICIS_NPDES_UI_VERSION <- "2026-05-07-icis-npdes-echo-bulk"
# Shown in External ML upload banner when ICIS-AIR bulk column signature matches.
ICIS_AIR_UPLOAD_BANNER_VERSION <- "2026-05-12-icis-air-hardblock-1"
# Shown in External ML upload banner when NHANES serum biomonitoring signature
# matches. The serum lane is governed separately (validation/serum_v1/) and
# must not flow through the environmental PFAS-occurrence mapper.
SERUM_UPLOAD_BANNER_VERSION <- "2026-05-13-serum-hardblock-1"
# V1 governed serum PFOS/PFOA contextualization (src/v1/, weighted reference table).
V1_CONTEXTUALIZATION_VERSION <- "1.0.1-serum-pfos-pfoa"
V1_INPUT_TEMPLATE_REL <- file.path("data", "v1", "templates", "governed_serum_pfos_pfoa_input_template.csv")
V2_CONTEXTUALIZATION_VERSION <- "2.0.0-cross-cycle-temporal"
V2_FIXTURE_REL <- file.path("data", "v1", "fixtures", "nhanes_j_governed_v1_input.csv")
# Canonical semantic types for the upload mapper. Each one routes through a
# different policy (mapping eligibility, validation rules, training eligibility).
# Mapping is enforced in get_upload_mapping() + the btn_external_* handlers.
UPLOAD_SEMANTIC_TYPES <- c(
  "pfas_occurrence_or_other",
  "air_program_metadata",
  "biosolids_program_metadata",
  "serum_biomonitoring",
  "reference_material",
  "method_validation",
  "facility_enrichment"
)
# Fields that are PFAS-occurrence specific. Blanked + hard-refused for
# program-metadata semantic types (air / biosolids).
PFAS_OCCURRENCE_MAP_FIELDS <- c(
  "result_value", "unit", "qualifier", "analyte", "cas", "date",
  "mdl", "rl", "detect_flag", "matrix", "sample_id", "state", "county",
  "method_id", "facility_water_type", "sample_point_type",
  "collection_year", "facility_id", "sample_point_id",
  "latitude", "longitude"
)
DB_PATH <- file.path(PROJECT_DIR, "pfas_collection.sqlite")
LOCAL_PYTHON_DEFAULT <- file.path("C:", "pfasenv", "Scripts", "python.exe")
LINK_SHINY_DEMO <- Sys.getenv("PFAS_LINK_SHINY_DEMO", "https://demo.yourcompany.com/request-access")
LINK_GITHUB_REPO <- Sys.getenv("PFAS_LINK_GITHUB_REPO", "https://github.com/your-org/private-pfas-repo")
PFAS_INTAKE_API_URL <- trimws(Sys.getenv("PFAS_INTAKE_API_URL", ""))
# Cloud screening API (FastAPI /predict, e.g. Render). Same env as thin app.R / README.
PFAS_API_URL <- trimws(Sys.getenv("PFAS_API_URL", "https://pfas-enterprise-5.onrender.com"))
PFAS_INTAKE_API_ENDPOINT <- if (nzchar(PFAS_INTAKE_API_URL)) {
  paste0(sub("/+$", "", PFAS_INTAKE_API_URL), "/upload")
} else {
  "null"
}
LINK_DATASET_FORM <- Sys.getenv("PFAS_LINK_DATASET_FORM", PFAS_INTAKE_API_ENDPOINT)
LINK_COLLAB <- Sys.getenv("PFAS_LINK_COLLAB", "mailto:techjoyadisco@yahoo.com")
PFAS_INTAKE_STAGING_TOKEN <- trimws(Sys.getenv("PFAS_INTAKE_STAGING_TOKEN", ""))
PFAS_PARTNER_AUDIT_SQLITE_TABLE <- trimws(Sys.getenv("PFAS_PARTNER_AUDIT_SQLITE_TABLE", "partner_intake_audit_mirror"))
PFAS_PARTNER_AUDIT_MIRROR_CSV <- trimws(Sys.getenv("PFAS_PARTNER_AUDIT_MIRROR_CSV", file.path(PROJECT_DIR, "data", "external", "partner_intake_audit_mirror.csv")))
DATASET_FORM_CONFIRMATION_MESSAGE <- Sys.getenv(
  "PFAS_DATASET_FORM_CONFIRMATION_MESSAGE",
  "Thank you for submitting your PFAS dataset inquiry. Your submission has been received for confidential commercial review."
)

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
}

# Normalize header names for signature checks (case/spacing/punctuation tolerant).
normalize_upload_colnames <- function(col_names) {
  x <- tolower(trimws(as.character(col_names)))
  x <- gsub("[[:space:].]+", "_", x, perl = FALSE)
  x <- gsub("_+", "_", x, perl = FALSE)
  x
}

# True when the uploaded table looks like EPA ECHO ICIS-AIR_POLLUTANTS bulk export
# (facility/program pollutant listings — not stack or ambient PFAS concentrations).
# Used only for a governance banner; strict schema validation remains authoritative.
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

# NHANES serum biomonitoring analyte and LOD-code columns, per
# validation/serum_v1/schema_contract.md (snake_case after janitor::clean_names).
# Used by detect_nhanes_serum_biomonitoring() to identify a serum upload that
# would otherwise be silently routed through the environmental PFAS-occurrence
# mapper.
NHANES_SERUM_LBX_COLS <- c(
  "lbxnfoa", "lbxbfoa", "lbxnfos", "lbxmfos",
  "lbxpfhs", "lbxpfna", "lbxpfde", "lbxpfua", "lbxmpah"
)
NHANES_SERUM_LBD_COLS <- c(
  "lbdnfoal", "lbdbfoal", "lbdnfosl", "lbdmfosl",
  "lbdpfhsl", "lbdpfnal", "lbdpfdel", "lbdpfual", "lbdmpahl"
)

# Per-analyte short names (validation/serum_v1/data_dictionary.csv,
# 'analyte' column). Keys are the normalized lowercase LBX*/LBD* tokens.
# These names are normative; any change must be coordinated with the
# governance dictionary.
NHANES_SERUM_LBX_TO_ANALYTE <- list(
  lbxnfoa = "n-PFOA",
  lbxbfoa = "Sb-PFOA",
  lbxnfos = "n-PFOS",
  lbxmfos = "Sm-PFOS",
  lbxpfhs = "PFHxS",
  lbxpfna = "PFNA",
  lbxpfde = "PFDA",
  lbxpfua = "PFUnDA",
  lbxmpah = "Me-PFOSA-AcOH"
)
NHANES_SERUM_LBD_TO_ANALYTE <- list(
  lbdnfoal = "n-PFOA",
  lbdbfoal = "Sb-PFOA",
  lbdnfosl = "n-PFOS",
  lbdmfosl = "Sm-PFOS",
  lbdpfhsl = "PFHxS",
  lbdpfnal = "PFNA",
  lbdpfdel = "PFDA",
  lbdpfual = "PFUnDA",
  lbdmpahl = "Me-PFOSA-AcOH"
)
# NHANES survey-weight columns observed across PFAS-special-subsample cycles.
NHANES_SERUM_WEIGHT_COLS <- c(
  "wtsb2yr", "wtmec2yr", "wtmecprp", "wtssch2y", "wtssch2yr"
)

# Version of the physiological auto-detect (recorded in the "Current
# mapping" pane and in the autodetect summary UI).
SERUM_BIOMONITORING_AUTODETECT_VERSION <- "2026-05-13-physiological-autodetect-1"

# Lane-stamped physiological classification fields (validation/serum_v1/
# schema_contract.md \u00a79). These five fields are constants for the serum
# lane, not column mappings from the upload, so an operator cannot
# misroute them. They make the physiological-vs-environmental
# distinction explicit at the row level instead of leaving it implicit
# in the matrix name. The scope is lane-specific (\u00a79.3) -- other lanes
# MUST NOT borrow this stamp; doing so would collapse matrix isolation.
#
# `governance_lane` is the (pipeline_id, governance_version) coordinate
# (`serum_v1` -> validation/serum_v1/). It makes the row's governance
# bundle machine-checkable, so a downstream consumer can join any row
# back to the contract under which it was admitted. `units` is NOT in
# this stamp; the row-level `result_unit` already carries that
# information, and duplicating it as a lane-stamped column made the
# SRM-vs-NHANES per-row unit difference confusing.
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

# Per-lane registry of physiological classification stamps.
# INTENTIONALLY NARROW: only lanes whose
# data/config/matrix_pipeline_sop.csv :: lane_kind ==
# "physiological_biomonitoring" appear here. Environmental-occurrence
# lanes (drinking_water, biosolids_sludge, air_emissions) and
# reference-material lanes (afff, methanol_standards) MUST NOT be
# added; adding them would collapse matrix isolation. The smoke
# scripts/smoke_serum_anchor_invariants.R fails if the keys of this
# registry ever change.
PHYSIOLOGICAL_LANE_STAMPS <- list(
  serum = SERUM_PHYSIOLOGICAL_STAMP
)

# Return the lane-stamped physiological classification for a known
# physiological lane. Reads from PHYSIOLOGICAL_LANE_STAMPS so a new
# lane can only be admitted by editing the registry (and then editing
# the smoke), not by editing this function.
physiological_lane_stamp <- function(lane = "serum") {
  PHYSIOLOGICAL_LANE_STAMPS[[lane]]
}

# Verify that a row / mapping carries the lane-stamped classification
# fields with EXACTLY the values listed in the lane contract. Returns
# list(ok, code, missing, mismatched, expected, observed). The caller
# (validate / normalize / save / train handlers) MUST treat ok=FALSE as
# a refusal, not a warning.
physiological_guard <- function(row, lane = "serum") {
  expected <- physiological_lane_stamp(lane)
  if (is.null(expected)) {
    return(list(
      ok = FALSE, code = "physiological_guard_unknown_lane",
      missing = character(0), mismatched = character(0),
      expected = list(), observed = list()
    ))
  }
  observed <- list()
  missing <- character(0)
  mismatched <- character(0)
  for (k in names(expected)) {
    v <- NULL
    if (is.list(row)) {
      v <- row[[k]]
    } else if (is.data.frame(row) && k %in% names(row)) {
      v <- row[[k]]
    } else if (is.environment(row)) {
      v <- tryCatch(get(k, envir = row, inherits = FALSE),
                    error = function(e) NULL)
    }
    if (is.null(v) || length(v) == 0L) {
      missing <- c(missing, k)
      observed[[k]] <- NA_character_
      next
    }
    v_chr <- as.character(v)
    # Empty-string / NA cells count as missing-field, not mismatch.
    # This matters for the serum training table where NIST SRM 1957 rows
    # carry blank stamp columns: they should be refused as "missing"
    # (reference-material row, not a biomonitoring row), not flagged as
    # if a value-mismatch was deliberately introduced.
    if (all(is.na(v_chr)) || all(!nzchar(v_chr))) {
      missing <- c(missing, k)
      observed[[k]] <- NA_character_
      next
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
  } else {
    "physiological_guard_ok"
  }
  list(
    ok        = length(missing) == 0L && length(mismatched) == 0L,
    code      = code,
    missing   = missing,
    mismatched = mismatched,
    expected  = expected,
    observed  = observed
  )
}

# Affirmative auto-detect for NHANES serum biomonitoring uploads. Where
# the environmental PFAS-occurrence auto-detect can only blank the
# mapping fields on a serum file (because the schema does not match),
# this function classifies every recognized column by role, pairs each
# LBX* concentration column with its LBD* LOD-code companion, and
# returns a structured summary the UI can render. The lane summary
# (matrix, method, units, format) is normative and matches
# validation/serum_v1/schema_contract.md.
autodetect_physiological_serum_columns <- function(col_names) {
  empty_cols_df <- data.frame(
    column = character(0), normalized = character(0),
    role = character(0), analyte = character(0),
    paired_with = character(0), units = character(0),
    notes = character(0), stringsAsFactors = FALSE
  )
  empty <- list(
    is_physiological = FALSE,
    lane = NA_character_,
    semantic_type = NA_character_,
    matrix = NA_character_,
    method = NA_character_,
    units = NA_character_,
    format = NA_character_,
    columns = empty_cols_df,
    paired_lbx_lbd = list(),
    counts = list(
      respondent_id = 0L, survey_weight = 0L,
      analyte_concentration = 0L, analyte_detection_code = 0L,
      unknown = 0L
    ),
    classification_stamp = NULL,
    classification_fields = PHYSIOLOGICAL_CLASSIFICATION_FIELDS,
    autodetect_version = SERUM_BIOMONITORING_AUTODETECT_VERSION
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
      role  <- "respondent_id"
      notes <- "NHANES sequence number; not a PFAS concentration"
    } else if (nm %in% NHANES_SERUM_WEIGHT_COLS) {
      role  <- "survey_weight"
      notes <- "NHANES survey weight; not an analytical measurement"
    } else if (nm %in% names(NHANES_SERUM_LBX_TO_ANALYTE)) {
      role    <- "analyte_concentration"
      analyte <- NHANES_SERUM_LBX_TO_ANALYTE[[nm]]
      pair_nm <- paste0(sub("^lbx", "lbd", nm), "l")
      paired  <- if (pair_nm %in% norm) orig[[which(norm == pair_nm)[[1]]]] else NA_character_
      units   <- "ng/mL"
      notes   <- "Serum concentration; below-LOD imputed at LOD/sqrt(2) by NHANES"
    } else if (nm %in% names(NHANES_SERUM_LBD_TO_ANALYTE)) {
      role    <- "analyte_detection_code"
      analyte <- NHANES_SERUM_LBD_TO_ANALYTE[[nm]]
      pair_nm <- sub("l$", "", sub("^lbd", "lbx", nm))
      paired  <- if (pair_nm %in% norm) orig[[which(norm == pair_nm)[[1]]]] else NA_character_
      units   <- "0/1"
      notes   <- "Detection code: 0=at/above LOD, 1=below LOD"
    }
    data.frame(
      column      = orig[[i]],
      normalized  = nm,
      role        = role,
      analyte     = analyte,
      paired_with = paired,
      units       = units,
      notes       = notes,
      stringsAsFactors = FALSE
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
  conc_idx <- which(rows$role == "analyte_concentration")
  for (i in conc_idx) {
    if (!is.na(rows$paired_with[[i]])) {
      paired[[length(paired) + 1L]] <- list(
        lbx_column = rows$column[[i]],
        lbd_column = rows$paired_with[[i]],
        analyte    = rows$analyte[[i]]
      )
    }
  }
  recognized <- counts$respondent_id +
                counts$survey_weight +
                counts$analyte_concentration +
                counts$analyte_detection_code
  list(
    is_physiological = recognized > 0L,
    lane             = "serum",
    semantic_type    = "serum_biomonitoring",
    matrix           = "human serum",
    method           = "CDC NHANES PFAS (LC/MS/MS, isotope-dilution)",
    units            = "ng/mL",
    format           = "wide (one row per respondent, one column per analyte)",
    columns          = rows,
    paired_lbx_lbd   = paired,
    counts           = counts,
    classification_stamp = physiological_lane_stamp("serum"),
    classification_fields = PHYSIOLOGICAL_CLASSIFICATION_FIELDS,
    autodetect_version = SERUM_BIOMONITORING_AUTODETECT_VERSION
  )
}

# True when the uploaded table looks like a NHANES PFAS serum biomonitoring
# file (PFAS_J / PFAS_I / P_PFAS or their case-folded CSV equivalents). The
# serum lane lives in validation/serum_v1/ and is governed by
# scripts/convert_nhanes_xpt_to_csv.R; it MUST NOT be mapped through the
# environmental PFAS-occurrence schema (long-format ng/L drinking-water
# data). Used only for a governance banner + hard-block; strict schema
# validation remains authoritative.
detect_nhanes_serum_biomonitoring <- function(col_names, file_name = "") {
  if (is.null(col_names) || length(col_names) < 1L) {
    return(FALSE)
  }
  cn <- normalize_upload_colnames(col_names)
  cn <- unique(cn[nzchar(cn)])

  # Strong signature: NHANES respondent id + the two-year subsample weight.
  # This pair appears together only in NHANES public-use serum biomonitoring
  # files (PFAS_J carries WTSB2YR; the joint occurrence in an environmental
  # file is implausible).
  if ("seqn" %in% cn && "wtsb2yr" %in% cn) {
    return(TRUE)
  }

  # Strong signature: NHANES respondent id + at least one PFAS serum analyte
  # or LOD-code column. The lbx*/lbd* prefix is NHANES-specific and not
  # used by any environmental-matrix lane.
  lbx_hits <- sum(NHANES_SERUM_LBX_COLS %in% cn)
  lbd_hits <- sum(NHANES_SERUM_LBD_COLS %in% cn)
  if ("seqn" %in% cn && (lbx_hits + lbd_hits) >= 1L) {
    return(TRUE)
  }

  # Weaker signature: 2+ PFAS serum analyte or LOD-code columns even without
  # SEQN (e.g. an analyst exported a subset). Two independent NHANES-prefixed
  # columns is still strong evidence the file is serum biomonitoring.
  if ((lbx_hits + lbd_hits) >= 2L) {
    return(TRUE)
  }

  # Filename fallback: explicit NHANES / PFAS_J / serum-PFAS naming.
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

# First existing path wins: env UCMR5_533_TXT, option pfas.ucmr5_533_path, then project data/.
resolve_ucmr5_533_txt <- function(project_dir = PROJECT_DIR) {
  envp <- Sys.getenv("UCMR5_533_TXT", "")
  optp <- getOption("pfas.ucmr5_533_path", default = "")
  if (!is.character(optp) || !nzchar(optp)) {
    optp <- ""
  }
  cand <- c(
    if (nzchar(envp)) envp else NA_character_,
    if (nzchar(optp)) optp else NA_character_,
    file.path(project_dir, "data/external/epa_ucmr5/UCMR5_533.txt"),
    file.path(project_dir, "data/raw/UCMR5_533.txt")
  )
  cand <- cand[!is.na(cand) & nzchar(cand)]
  hit <- cand[vapply(cand, file.exists, logical(1L))]
  if (length(hit) < 1) {
    return(NA_character_)
  }
  hit[[1]]
}

ucmr_pipeline_priority_csv <- function(project_dir, output_root, run_id) {
  rid <- trimws(run_id %||% "")
  root <- trimws(output_root %||% "runs")
  if (!nzchar(rid)) {
    return(NA_character_)
  }
  p <- file.path(project_dir, root, rid, "priority_report.csv")
  normalizePath(p, winslash = "/", mustWork = FALSE)
}

safe_pattern <- function(p) {
  if (is.null(p) || length(p) == 0) {
    return(NA_character_)
  }
  pc <- trimws(as.character(p)[[1]])
  if (length(pc) < 1 || is.na(pc) || !nzchar(pc)) {
    return(NA_character_)
  }
  pc
}

safe_detect <- function(string, pattern, negate = FALSE, ...) {
  p <- safe_pattern(pattern)
  if (is.na(p)) {
    out <- rep(FALSE, length(string))
    return(if (isTRUE(negate)) !out else out)
  }
  stringr::str_detect(string, p, negate = negate, ...)
}

safe_matches <- function(pattern, ...) {
  p <- safe_pattern(pattern)
  if (is.na(p)) {
    return(dplyr::matches("$^"))
  }
  dplyr::matches(p, ...)
}

is_placeholder_link <- function(url) {
  if (is.null(url) || length(url) == 0) {
    return(TRUE)
  }
  candidate <- trimws(as.character(url)[1])
  if (!nzchar(candidate)) {
    return(FALSE)
  }
  if (is_disabled_link(candidate)) {
    return(FALSE)
  }
  bad_tokens <- c(
    "REPLACE_WITH_YOUR_FORM",
    "yourcompany.com",
    "your-org",
    "example.com"
  )
  any(vapply(bad_tokens, function(tok) {
    tok <- trimws(as.character(tok))
    nzchar(tok) && grepl(tok, candidate, fixed = TRUE)
  }, logical(1)))
}

is_disabled_link <- function(url) {
  if (is.null(url) || length(url) == 0) {
    return(TRUE)
  }
  candidate <- trimws(as.character(url)[1])
  if (!nzchar(candidate)) {
    return(TRUE)
  }
  tolower(candidate) %in% c("null", "na", "none", "disabled")
}

is_configured_link <- function(url) {
  !is_placeholder_link(url) && !is_disabled_link(url)
}

featured_stack_button <- function(url, btn_class, label) {
  enabled <- is_configured_link(url)
  disabled <- is_disabled_link(url)
  tags$a(
    href = if (enabled) url else "#",
    target = if (enabled) "_blank" else NULL,
    class = paste("btn", btn_class, if (!enabled) "disabled"),
    `aria-disabled` = if (!enabled) "true" else NULL,
    style = if (!enabled) "pointer-events:none; opacity:0.65;" else NULL,
    title = if (!enabled) {
      if (disabled) "Disabled pending verification" else "Link pending configuration"
    } else NULL,
    label
  )
}

featured_link_status <- function(url) {
  enabled <- is_configured_link(url)
  disabled <- is_disabled_link(url)
  tags$span(
    class = paste("label", if (enabled) "label-success" else if (disabled) "label-warning" else "label-default"),
    style = "margin-left:8px;",
    if (enabled) "Configured" else if (disabled) "Disabled" else "Pending configuration"
  )
}

run_intake_api_smoke_test <- function(url, bearer_token) {
  candidate <- trimws(as.character(url %||% "")[1])
  token <- trimws(as.character(bearer_token %||% "")[1])
  if (!nzchar(token)) {
    return(list(
      status = "skipped",
      summary = "Smoke test skipped: PFAS_INTAKE_STAGING_TOKEN is not set.",
      http_status = NA_integer_,
      detail = "Set PFAS_INTAKE_STAGING_TOKEN to run authenticated POST /upload checks."
    ))
  }
  if (!requireNamespace("httr", quietly = TRUE)) {
    return(list(
      status = "error",
      summary = "Smoke test failed: required package 'httr' is not available.",
      http_status = NA_integer_,
      detail = "Install with install.packages('httr') in this runtime."
    ))
  }

  body <- list(
    filename = paste0("smoke-", format(Sys.time(), "%Y%m%d%H%M%S"), ".csv"),
    content_type = "text/csv"
  )
  resp <- tryCatch(
    httr::POST(
      url = candidate,
      httr::add_headers(
        Authorization = paste("Bearer", token),
        `Content-Type` = "application/json"
      ),
      body = jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"),
      encode = "raw",
      httr::timeout(12)
    ),
    error = function(e) e
  )

  if (inherits(resp, "error")) {
    return(list(
      status = "fail",
      summary = "Smoke test failed: request error.",
      http_status = NA_integer_,
      detail = conditionMessage(resp)
    ))
  }

  status_code <- httr::status_code(resp)
  body_text <- tryCatch(httr::content(resp, as = "text", encoding = "UTF-8"), error = function(e) "")
  looks_ok <- status_code >= 200 && status_code < 300 && grepl("upload_url|object_key|expires_in_seconds", body_text)
  if (looks_ok) {
    return(list(
      status = "pass",
      summary = "Smoke test passed: authenticated POST /upload returned expected payload.",
      http_status = status_code,
      detail = "Token auth and upload-init response are working."
    ))
  }

  snippet <- if (nzchar(body_text)) substr(gsub("[\r\n\t]+", " ", body_text), 1, 220) else "<empty>"
  list(
    status = "fail",
    summary = "Smoke test failed: endpoint response did not match expected upload-init payload.",
    http_status = status_code,
    detail = paste("HTTP", status_code, "|", snippet)
  )
}

check_intake_api_health <- function(url, bearer_token = "") {
  checked_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  candidate <- trimws(as.character(url %||% "")[1])

  if (is_disabled_link(candidate)) {
    return(list(
      level = "disabled",
      summary = "Disabled. No public endpoint resolves.",
      detail = "Will remain disabled until Cognito SSO + Macie PII scan + audit logging pass 7.11.2 OQ.",
      endpoint = "<disabled>",
      checked_at = checked_at,
      smoke = list(
        status = "skipped",
        summary = "Smoke test skipped.",
        http_status = 503L,
        detail = "{\"status\":\"disabled_pending_7.11.3\"}"
      )
    ))
  }

  if (is_placeholder_link(candidate)) {
    return(list(
      level = "pending",
      summary = "Intake endpoint is pending configuration.",
      detail = "Placeholder URL detected; keep submission disabled until access controls are verified.",
      endpoint = candidate,
      checked_at = checked_at,
      smoke = list(status = "skipped", summary = "Smoke test skipped.", http_status = NA_integer_, detail = "Endpoint is placeholder.")
    ))
  }

  if (!grepl("^https?://", candidate, ignore.case = TRUE)) {
    return(list(
      level = "error",
      summary = "Endpoint URL format is invalid.",
      detail = "URL must begin with http:// or https://.",
      endpoint = candidate,
      checked_at = checked_at,
      smoke = list(status = "skipped", summary = "Smoke test skipped.", http_status = NA_integer_, detail = "Endpoint format invalid.")
    ))
  }

  host <- sub("^https?://([^/:?#]+).*$", "\\1", candidate, perl = TRUE)
  port <- if (grepl("^https://", candidate, ignore.case = TRUE)) 443L else 80L
  reachable <- tryCatch(
    {
      con <- socketConnection(host = host, port = port, open = "r+", blocking = TRUE, timeout = 3)
      on.exit(close(con), add = TRUE)
      TRUE
    },
    error = function(e) FALSE
  )

  if (!reachable) {
    return(list(
      level = "warning",
      summary = "Endpoint is configured but host is not reachable from this runtime.",
      detail = "Verify DNS/network path, API gateway deployment, and security group/ACL rules.",
      endpoint = candidate,
      checked_at = checked_at,
      smoke = list(status = "skipped", summary = "Smoke test skipped.", http_status = NA_integer_, detail = "Host unreachable.")
    ))
  }

  smoke <- run_intake_api_smoke_test(candidate, bearer_token)
  overall_level <- if (identical(smoke$status, "pass")) "ok" else if (identical(smoke$status, "skipped")) "warning" else "error"
  overall_summary <- if (identical(smoke$status, "pass")) {
    "Endpoint is reachable and authenticated POST /upload smoke test passed."
  } else if (identical(smoke$status, "skipped")) {
    "Endpoint is reachable; authenticated smoke test is skipped until staging token is set."
  } else {
    "Endpoint is reachable but authenticated POST /upload smoke test failed."
  }

  list(
    level = overall_level,
    summary = overall_summary,
    detail = "Network reachability check passed (port-level).",
    endpoint = candidate,
    checked_at = checked_at,
    smoke = smoke
  )
}

# -------------------------------------------------------------------
# SQLite setup
# -------------------------------------------------------------------

dir.create(PROJECT_DIR, showWarnings = FALSE, recursive = TRUE)
con <- DBI::dbConnect(RSQLite::SQLite(), DB_PATH)

# Re-open SQLite if the handle was invalidated (browser refresh after bad disconnect,
# OneDrive sync, etc.). Assigned with <<- so the same binding server() closes over updates.
ensure_valid_db_connection <- function() {
  ok <- tryCatch(
    inherits(con, "DBIConnection") && DBI::dbIsValid(con),
    error = function(e) FALSE
  )
  if (!ok) {
    con <<- DBI::dbConnect(RSQLite::SQLite(), DB_PATH)
  }
  invisible(con)
}

glp_audit_file <- file.path(PROJECT_DIR, "utils", "glp_audit.R")
if (file.exists(glp_audit_file)) {
  source(glp_audit_file, local = FALSE)
}
if (exists("glp_ensure_audit_table")) {
  glp_ensure_audit_table(con)
}

iso17025_file <- file.path(PROJECT_DIR, "utils", "iso17025_schema.R")
if (file.exists(iso17025_file)) {
  source(iso17025_file, local = FALSE)
}
if (exists("iso17025_ensure_tables")) {
  iso17025_ensure_tables(con)
  if (exists("iso17025_seed_epa1633_tests")) {
    iso17025_seed_epa1633_tests(con)
  }
}

ensure_table <- function(con, table_name, create_sql) {
  if (!DBI::dbExistsTable(con, table_name)) {
    DBI::dbExecute(con, create_sql)
  }
}

ensure_table(con, "compound_registry", "
CREATE TABLE compound_registry (
  compound_id TEXT PRIMARY KEY,
  compound_name TEXT NOT NULL,
  smiles TEXT NOT NULL,
  cas TEXT,
  pfas_subclass TEXT,
  source_type TEXT,
  source_reference TEXT,
  created_at TEXT NOT NULL,
  created_by TEXT NOT NULL,
  review_status TEXT NOT NULL DEFAULT 'draft'
);
")

ensure_table(con, "sample_registry", "
CREATE TABLE sample_registry (
  sample_id TEXT PRIMARY KEY,
  project_id TEXT,
  client_id TEXT,
  matrix TEXT NOT NULL,
  sample_type TEXT,
  collection_date TEXT,
  batch_id TEXT,
  instrument_id TEXT,
  method_id TEXT,
  operator TEXT,
  notes TEXT
);
")

ensure_table(con, "analytical_measurements", "
CREATE TABLE analytical_measurements (
  measurement_id TEXT PRIMARY KEY,
  compound_id TEXT NOT NULL,
  sample_id TEXT NOT NULL,
  retention_time REAL,
  precursor_mz REAL,
  product_mz REAL,
  peak_area REAL,
  signal_to_noise REAL,
  concentration REAL,
  concentration_unit TEXT,
  lod REAL,
  loq REAL,
  internal_standard TEXT,
  result_flag TEXT,
  qc_flag TEXT,
  created_at TEXT NOT NULL,
  created_by TEXT NOT NULL
);
")

ensure_table(con, "endpoint_labels", "
CREATE TABLE endpoint_labels (
  label_id TEXT PRIMARY KEY,
  compound_id TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  label_value INTEGER NOT NULL,
  label_source TEXT NOT NULL,
  assay_id TEXT,
  source_reference TEXT,
  confidence_score REAL,
  curator TEXT NOT NULL,
  review_status TEXT NOT NULL DEFAULT 'draft',
  notes TEXT,
  created_at TEXT NOT NULL
);
")

ensure_table(con, "audit_log", "
CREATE TABLE audit_log (
  audit_id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  action_type TEXT NOT NULL,
  changed_by TEXT NOT NULL,
  changed_at TEXT NOT NULL,
  change_notes TEXT
);
")

ensure_table(con, "app_login_users", "
CREATE TABLE app_login_users (
  user TEXT PRIMARY KEY,
  password TEXT NOT NULL,
  admin INTEGER NOT NULL DEFAULT 0,
  full_name TEXT,
  active INTEGER NOT NULL DEFAULT 1
);
")

ensure_table(con, "upload_validation_run", "
CREATE TABLE upload_validation_run (
  run_id TEXT PRIMARY KEY,
  phase TEXT NOT NULL,
  schema_version TEXT NOT NULL,
  status TEXT NOT NULL,
  validated_at TEXT NOT NULL,
  validated_by TEXT NOT NULL,
  file_name TEXT,
  raw_sha256 TEXT,
  dataset_type TEXT,
  row_count INTEGER,
  rows_pass INTEGER,
  rows_fail INTEGER,
  metrics_json TEXT NOT NULL,
  mapping_engine_version TEXT
);
")

nu_login <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM app_login_users")$n[[1]]
if (is.na(nu_login) || nu_login == 0) {
  DBI::dbExecute(
    con,
    "INSERT INTO app_login_users (user, password, admin, full_name, active) VALUES (?, ?, ?, ?, ?)",
    params = list("admin", "admin123", 1L, "QA Administrator", 1L)
  )
  DBI::dbExecute(
    con,
    "INSERT INTO app_login_users (user, password, admin, full_name, active) VALUES (?, ?, ?, ?, ?)",
    params = list("analyst", "analyst123", 0L, "Laboratory Analyst", 1L)
  )
}

worm_src <- file.path(PROJECT_DIR, "utils", "glp_audit_archive.R")
if (file.exists(worm_src)) {
  source(worm_src, local = FALSE)
}

login_credentials_df <- DBI::dbGetQuery(
  con,
  "SELECT user, password, admin, full_name FROM app_login_users WHERE active = 1"
)
login_credentials_df$admin <- as.logical(as.integer(login_credentials_df$admin))
login_credentials_df$full_name <- ifelse(
  is.na(login_credentials_df$full_name) | login_credentials_df$full_name == "",
  login_credentials_df$user,
  login_credentials_df$full_name
)

make_id <- function(prefix) {
  ts <- gsub("[^0-9]", "", format(Sys.time(), "%Y%m%d%H%M%OS3"))
  nonce <- substr(
    digest::digest(
      paste(prefix, ts, Sys.getpid(), runif(1), sep = "|"),
      algo = "xxhash64",
      serialize = FALSE
    ),
    1,
    8
  )
  paste0(prefix, "-", ts, "-", nonce)
}

default_external_upload_schema <- function() {
  list(
    schema_version = "external_normalized_v1",
    max_rows = 5000000,
    allowed_result_units = c(
      "", "ng/l", "ug/l", "mg/l", "ng/ml", "ug/ml", "mg/ml",
      "ppb", "ppt", "pg/l"
    ),
    analyte_max_chars = 512L,
    sample_id_max_chars = 256L,
    enforce_lat_lon_range = TRUE
  )
}

# Shared across narrow normalize, wide fallback, and strict_validate_normalized_external.
parse_external_upload_numeric <- function(x) {
  y <- trimws(as.character(x))
  y[y %in% c("", "NA", "N/A", "na", "n/a", "NULL", "null")] <- NA_character_
  y <- gsub(",", "", y, fixed = TRUE)
  y <- gsub("^<\\s*", "", y)
  y <- gsub("^>\\s*", "", y)
  direct <- suppressWarnings(as.numeric(y))
  need_extract <- is.na(direct) & !is.na(y) & nzchar(y)
  if (any(need_extract, na.rm = TRUE)) {
    tok <- stringr::str_extract(y[need_extract], "[-+]?[0-9]*\\.?[0-9]+(?:[eE][-+]?[0-9]+)?")
    direct[need_extract] <- suppressWarnings(as.numeric(tok))
  }
  direct
}

# Unicode micro signs + wordy UOM strings -> tokens in allowed_result_units.
normalize_external_result_unit_for_schema <- function(u) {
  x <- trimws(as.character(u))
  x[is.na(x)] <- ""
  x <- gsub("\u00b5|\u03bc", "u", x, perl = TRUE)
  x <- tolower(trimws(x))
  x <- gsub("\t|\r|\n", " ", x, perl = TRUE)
  x <- gsub("\\s+", " ", x, perl = TRUE)
  x <- gsub("^micrograms?\\s*/\\s*l(it(er)?s?)?$", "ug/l", x, perl = TRUE)
  x <- gsub("^nanograms?\\s*/\\s*l(it(er)?s?)?$", "ng/l", x, perl = TRUE)
  x <- gsub("^milligrams?\\s*/\\s*l(it(er)?s?)?$", "mg/l", x, perl = TRUE)
  x <- gsub("^micrograms?\\s*/\\s*ml$", "ug/ml", x, perl = TRUE)
  x <- gsub("^nanograms?\\s*/\\s*ml$", "ng/ml", x, perl = TRUE)
  x <- gsub("\\s*\\.\\s*$", "", x, perl = TRUE)
  trimws(x)
}

load_external_upload_schema <- function(project_dir = PROJECT_DIR) {
  path <- file.path(project_dir, "data", "config", "external_upload_schema.json")
  base <- default_external_upload_schema()
  if (!file.exists(path)) {
    return(base)
  }
  js <- tryCatch(jsonlite::fromJSON(path, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(js) || !is.list(js)) {
    return(base)
  }
  for (nm in names(js)) {
    base[[nm]] <- js[[nm]]
  }
  base
}

external_upload_raw_digest <- function(datapath) {
  if (is.null(datapath)) {
    return("")
  }
  dp <- trimws(as.character(datapath)[1])
  if (!nzchar(dp) || !file.exists(dp)) {
    return("")
  }
  digest::digest(file = dp, algo = "sha256", serialize = FALSE)
}

strict_validate_normalized_external <- function(norm_df, schema = NULL, dataset_type = NULL) {
  sch <- schema %||% default_external_upload_schema()
  sv <- as.character(sch$schema_version %||% "external_normalized_v1")
  violations <- list()
  metrics <- list(schema_version = sv, n_rows = 0L)

  if (is.null(norm_df) || !is.data.frame(norm_df)) {
    return(list(
      ok = FALSE,
      schema_version = sv,
      row_count = 0L,
      rows_pass = 0L,
      rows_fail = 0L,
      metrics = metrics,
      violations = c(violations, list(list(rule = "NO_DATAFRAME"))),
      run_id = NA_character_
    ))
  }

  nr <- nrow(norm_df)
  metrics$n_rows <- nr
  max_r <- suppressWarnings(as.numeric(sch$max_rows %||% 5e6))
  if (!is.finite(max_r) || max_r <= 0) {
    max_r <- 5e6
  }

  if (nr == 0L) {
    violations <- c(violations, list(list(rule = "ZERO_ROWS", detail = "Normalized table has zero rows")))
    return(list(
      ok = FALSE,
      schema_version = sv,
      row_count = 0L,
      rows_pass = 0L,
      rows_fail = 0L,
      metrics = metrics,
      violations = violations,
      run_id = NA_character_
    ))
  }

  if (nr > max_r) {
    violations <- c(violations, list(list(
      rule = "SCHEMA_MAX_ROWS",
      detail = sprintf("rows=%s max=%s", nr, max_r)
    )))
    return(list(
      ok = FALSE,
      schema_version = sv,
      row_count = nr,
      rows_pass = 0L,
      rows_fail = nr,
      metrics = metrics,
      violations = violations,
      run_id = NA_character_
    ))
  }

  reqc <- c("analyte", "result_value")
  miss_col <- setdiff(reqc, names(norm_df))
  if (length(miss_col)) {
    violations <- c(violations, list(list(
      rule = "MISSING_REQUIRED_COLUMNS",
      detail = paste(miss_col, collapse = ",")
    )))
    return(list(
      ok = FALSE,
      schema_version = sv,
      row_count = nr,
      rows_pass = 0L,
      rows_fail = nr,
      metrics = metrics,
      violations = violations,
      run_id = NA_character_
    ))
  }

  mx <- suppressWarnings(as.integer(sch$analyte_max_chars %||% 512L))
  if (is.na(mx) || mx < 1L) {
    mx <- 512L
  }
  smx <- suppressWarnings(as.integer(sch$sample_id_max_chars %||% 256L))
  if (is.na(smx) || smx < 1L) {
    smx <- 256L
  }

  analyte <- trimws(as.character(norm_df$analyte))
  analyte[is.na(analyte)] <- ""

  result_num <- parse_external_upload_numeric(norm_df$result_value)

  allowed_u <- sch$allowed_result_units %||% default_external_upload_schema()$allowed_result_units
  allowed_u <- unique(normalize_external_result_unit_for_schema(as.character(allowed_u)))
  if (identical(trimws(as.character(dataset_type %||% "")), REFERENCE_MATERIAL_DATASET_TYPE)) {
    extra_ref <- c(
      "ug/kg", "mg/kg", "ng/kg", "g/kg",
      "ug/g", "mg/g", "ng/g", "g/g",
      "ppm", "ppt", "ppb", "ppq",
      "ng/l", "ug/l", "mg/l", "mg/ml", "ug/ml", "ng/ml"
    )
    allowed_u <- unique(c(allowed_u, normalize_external_result_unit_for_schema(extra_ref)))
  }

  ru <- if ("result_unit" %in% names(norm_df)) norm_df$result_unit else rep(NA_character_, nr)
  ru <- normalize_external_result_unit_for_schema(ru)
  ru[is.na(ru)] <- ""

  qv <- if ("qualifier" %in% names(norm_df)) tolower(trimws(as.character(norm_df$qualifier))) else rep("", nr)
  qv[is.na(qv)] <- ""
  nd_from_qual <- safe_detect(qv, "^<|\\bnd\\b|non[- ]?detect|\\bbdl\\b|not\\s+detected|\\babsent\\b|^u\\b|^uj\\b")
  nd_from_detect <- rep(FALSE, nr)
  if ("detect_flag" %in% names(norm_df)) {
    dfv <- suppressWarnings(as.integer(norm_df$detect_flag))
    nd_from_detect <- !is.na(dfv) & dfv == 0L
  }
  nd_row <- nd_from_qual | nd_from_detect

  result_numeric_fail <- (is.na(result_num) | !is.finite(result_num)) & !nd_row

  row_bad <- (analyte == "") | result_numeric_fail |
    (nzchar(ru) & !(ru %in% allowed_u))

  an_len <- nchar(analyte, type = "chars", allowNA = TRUE)
  an_len[is.na(an_len)] <- 0L
  row_bad <- row_bad | (an_len > mx)

  if ("sample_id" %in% names(norm_df)) {
    sid <- trimws(as.character(norm_df$sample_id))
    sid[is.na(sid)] <- ""
    sid_len <- nchar(sid, type = "chars", allowNA = TRUE)
    sid_len[is.na(sid_len)] <- 0L
    row_bad <- row_bad | (sid_len > smx)
  }

  if (isTRUE(sch$enforce_lat_lon_range %||% TRUE)) {
    if ("latitude" %in% names(norm_df)) {
      latv <- suppressWarnings(as.numeric(norm_df$latitude))
      row_bad <- row_bad | (!is.na(latv) & (latv < -90 | latv > 90))
    }
    if ("longitude" %in% names(norm_df)) {
      lonv <- suppressWarnings(as.numeric(norm_df$longitude))
      row_bad <- row_bad | (!is.na(lonv) & (lonv < -180 | lonv > 180))
    }
  }

  rows_fail <- sum(row_bad, na.rm = TRUE)
  rows_pass <- nr - rows_fail

  metrics$n_analyte_blank <- sum(analyte == "", na.rm = TRUE)
  metrics$n_analyte_too_long <- sum(an_len > mx, na.rm = TRUE)
  metrics$n_result_nonfinite <- sum(result_numeric_fail, na.rm = TRUE)
  metrics$n_non_detect_rows <- sum(nd_row, na.rm = TRUE)
  metrics$n_unit_invalid <- sum(nzchar(ru) & !(ru %in% allowed_u), na.rm = TRUE)
  if ("sample_id" %in% names(norm_df)) {
    sid <- trimws(as.character(norm_df$sample_id))
    sid[is.na(sid)] <- ""
    metrics$n_sample_id_too_long <- sum(nchar(sid, type = "chars", allowNA = TRUE) > smx, na.rm = TRUE)
  }
  metrics$n_rows_fail <- rows_fail
  metrics$n_rows_pass <- rows_pass

  ok <- rows_fail == 0L && length(violations) == 0L

  list(
    ok = ok,
    schema_version = sv,
    row_count = nr,
    rows_pass = rows_pass,
    rows_fail = rows_fail,
    metrics = metrics,
    violations = violations,
    run_id = NA_character_
  )
}

df_has_reference_column_signature <- function(cnames) {
  if (length(cnames) < 1L) {
    return(FALSE)
  }
  n <- tolower(gsub("[^a-z0-9]+", "", trimws(as.character(cnames))))
  sig1 <- any(
    n %in% c(
      "valuestatus", "coveragefactor", "referencematerial", "referencesource",
      "nisttablecitation", "nisttable", "weightedmeanbasis"
    )
  )
  sig2 <- any(n == "uncertainty") && any(n %in% c("referencesource", "referencematerial", "shortname"))
  isTRUE(sig1) || isTRUE(sig2)
}

reference_upload_filename_hint <- function(fname) {
  f <- tolower(trimws(fname %||% ""))
  if (!nzchar(f)) {
    return(FALSE)
  }
  safe_detect(f, "^nist_|nist_|/nist/|srm[ _]?1957|rm[ _]?8446|rm[ _]?8690")
}

run_reference_material_preflight <- function(norm, mapping, raw_df, declared_type, upload_fname) {
  out <- list(
    status = "PASS",
    label = "Reference material preflight",
    codes = character(0),
    messages = character(0)
  )
  decl <- trimws(declared_type %||% "")
  ref_sig <- isTRUE(df_has_reference_column_signature(names(raw_df))) ||
    isTRUE(reference_upload_filename_hint(upload_fname))

  if (decl %in% c("environmental occurrence", "facility enrichment") && isTRUE(ref_sig)) {
    out$status <- "BLOCK"
    out$codes <- c(out$codes, "REFERENCE_AS_OCCURRENCE")
    out$messages <- c(
      out$messages,
      paste0(
        "Reference-material / bench table detected (column names or filename suggest NIST/RM extracts), ",
        "but Dataset type is '", decl, "'. Choose '", REFERENCE_MATERIAL_DATASET_TYPE,
        "' — do not treat bench CSVs as UCMR-style occurrence data."
      )
    )
    return(out)
  }

  if (decl != REFERENCE_MATERIAL_DATASET_TYPE) {
    return(out)
  }

  req_maps <- c("matrix", "analyte", "result_value", "unit", "uncertainty")
  miss <- !vapply(req_maps, function(k) nzchar(trimws(mapping[[k]] %||% "")), logical(1))
  if (any(miss)) {
    out$status <- "BLOCK"
    out$codes <- c(out$codes, "MISSING_REQUIRED_MAP")
    out$messages <- c(
      out$messages,
      paste0(
        "Reference material requires mapped columns: matrix, analyte, result_value (value), unit, uncertainty. ",
        "Missing: ", paste(req_maps[miss], collapse = ", ")
      )
    )
    return(out)
  }

  prov_ok <- nzchar(trimws(mapping$reference_id %||% "")) ||
    nzchar(trimws(mapping$source_dataset %||% ""))
  review_msgs <- character(0)
  if (!prov_ok) {
    review_msgs <- c(
      review_msgs,
      paste0(
        "Map reference_id (preferred) or source_dataset to document / catalog id (e.g. SRM 1957, RM 8446) ",
        "for full provenance."
      )
    )
  }

  nr <- nrow(raw_df)
  pickv <- function(map_key) {
    col <- trimws(mapping[[map_key]] %||% "")
    if (!nzchar(col) || !(col %in% names(raw_df))) {
      return(rep(NA_character_, nr))
    }
    as.character(raw_df[[col]])
  }
  unc_raw <- pickv("uncertainty")
  unc_chr <- trimws(as.character(unc_raw))
  unc_chr[is.na(unc_chr)] <- ""
  unc_chr <- gsub("^±\\s*", "", unc_chr, perl = TRUE)
  unc_chr <- gsub("^\\+/-\\s*", "", unc_chr, perl = TRUE)
  unc_num <- parse_external_upload_numeric(unc_chr)
  finite_unc <- sum(!is.na(unc_num) & is.finite(unc_num), na.rm = TRUE)
  if (nr > 0L && finite_unc == 0L) {
    out$status <- "BLOCK"
    out$codes <- c(out$codes, "UNCERTAINTY_NONNUMERIC")
    out$messages <- c(
      out$messages,
      "Mapped uncertainty column has no finite numeric values after parse (reference material requires numeric uncertainty, typically expanded U)."
    )
    return(out)
  }

  mat <- if (!is.null(norm) && "matrix" %in% names(norm)) trimws(as.character(norm$matrix)) else character(0)
  mat[is.na(mat)] <- ""
  if (length(mat) > 0L) {
    frac_serum <- mean(safe_detect(tolower(mat), "serum|plasma|blood"), na.rm = TRUE)
    if (is.finite(frac_serum) && frac_serum > 0.5) {
      review_msgs <- c(
        review_msgs,
        "Majority physiological matrix (serum/plasma/blood): not drinking-water occurrence or MCL-style exceedance context."
      )
    }
    frac_meth <- mean(safe_detect(tolower(mat), "methanol|calibration"), na.rm = TRUE)
    if (is.finite(frac_meth) && frac_meth > 0.35) {
      review_msgs <- c(
        review_msgs,
        "Methanol / calibration-line matrix: not an environmental field sample or distribution sample."
      )
    }
    frac_afff <- mean(safe_detect(tolower(mat), "afff|foam"), na.rm = TRUE)
    if (is.finite(frac_afff) && frac_afff > 0.35) {
      review_msgs <- c(
        review_msgs,
        "AFFF / foam matrix: not drinking-water UCMR occurrence data; keep forensic / foam workflows separate."
      )
    }
  }

  ru <- if (!is.null(norm) && "result_unit" %in% names(norm)) {
    normalize_external_result_unit_for_schema(norm$result_unit)
  } else {
    character(0)
  }
  ru <- ru[!is.na(ru)]
  if (length(mat) > 0L && length(ru) > 0L) {
    frac_meth_mat <- mean(safe_detect(tolower(mat), "methanol"), na.rm = TRUE)
    frac_dw_u <- mean(ru %in% c("ng/l", "ug/l", "mg/l"), na.rm = TRUE)
    if (is.finite(frac_meth_mat) && frac_meth_mat > 0.35 && is.finite(frac_dw_u) && frac_dw_u > 0.5) {
      review_msgs <- c(
        review_msgs,
        "REVIEW: methanol-like matrix with mostly mass/volume water units — confirm units match the certificate (e.g. mg/kg vs ng/L)."
      )
    }
  }

  miss_mat_rows <- if (length(mat) > 0L) sum(mat == "", na.rm = TRUE) else 0L
  if (length(mat) > 0L && miss_mat_rows > 0.2 * length(mat)) {
    out$status <- "BLOCK"
    out$codes <- c(out$codes, "MATRIX_SPARSE")
    out$messages <- c(out$messages, "More than 20% of rows have blank matrix after mapping — reference material requires explicit matrix on each row.")
    return(out)
  }

  if (length(review_msgs) > 0L) {
    out$status <- "REVIEW"
    out$codes <- c(out$codes, "REFERENCE_REVIEW_NOTES")
    out$messages <- c(out$messages, review_msgs)
  }

  out
}

persist_upload_validation_run <- function(con, phase, sch_res, validated_by, file_name, raw_sha256, dataset_type) {
  ensure_valid_db_connection()
  rid <- make_id("UVR")
  sch_res$run_id <- rid
  payload <- jsonlite::toJSON(
    list(
      metrics = sch_res$metrics,
      violations = sch_res$violations,
      phase = phase,
      strict_ok = isTRUE(sch_res$ok)
    ),
    auto_unbox = TRUE,
    null = "null"
  )
  tryCatch(
    DBI::dbExecute(
      con,
      paste0(
        "INSERT INTO upload_validation_run ",
        "(run_id, phase, schema_version, status, validated_at, validated_by, file_name, raw_sha256, dataset_type, ",
        "row_count, rows_pass, rows_fail, metrics_json, mapping_engine_version) ",
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
      ),
      params = list(
        rid,
        as.character(phase %||% "unknown"),
        as.character(sch_res$schema_version %||% ""),
        if (isTRUE(sch_res$ok)) "PASS" else "FAIL",
        as.character(Sys.time()),
        as.character(validated_by %||% "unknown"),
        as.character(file_name %||% ""),
        as.character(raw_sha256 %||% ""),
        as.character(dataset_type %||% ""),
        as.integer(sch_res$row_count %||% 0L),
        as.integer(sch_res$rows_pass %||% 0L),
        as.integer(sch_res$rows_fail %||% 0L),
        as.character(payload),
        as.character(MAPPING_ENGINE_VERSION)
      )
    ),
    error = function(e) {
      warning("upload_validation_run insert failed: ", conditionMessage(e))
      sch_res$run_id <- NA_character_
    }
  )
  sch_res
}

# write_audit() is defined inside server() so GLP hash-chained trail receives Shiny session context.

safe_table <- function(table_name) {
  ensure_valid_db_connection()
  if (DBI::dbExistsTable(con, table_name)) {
    DBI::dbReadTable(con, table_name) |> tibble::as_tibble()
  } else {
    tibble::tibble()
  }
}

# -------------------------------------------------------------------
# Placeholder data builders
# Replace these with real endpoint datasets, descriptors, fingerprints,
# external/prospective validation assets, and audited model metadata.
# -------------------------------------------------------------------

build_compound_registry <- function() {
  tibble::tribble(
    ~compound_id, ~compound_name, ~CAS, ~SMILES, ~pfas_subclass,
    "CMP-001", "PFOA", "335-67-1", "C(C(C(C(C(C(C(F)(F)F)(F)F)(F)F)(F)F)(F)F)(F)F)(=O)O", "PFCA",
    "CMP-002", "PFOS", "1763-23-1", "OS(=O)(=O)C(C(C(C(C(C(C(C(F)(F)F)(F)F)(F)F)(F)F)(F)F)(F)F)(F)F", "PFSA",
    "CMP-003", "PFNA", "375-95-1", "C(C(C(C(C(C(C(C(F)(F)F)(F)F)(F)F)(F)F)(F)F)(F)F)(F)F)(=O)O", "PFCA",
    "CMP-004", "PFHxS", "355-46-4", "OS(=O)(=O)C(C(C(C(C(C(F)(F)F)(F)F)(F)F)(F)F)(F)F", "PFSA",
    "CMP-005", "HFPO-DA", "13252-13-6", "OC(=O)C(OCC(F)(F)C(F)(F)F)(F)F", "Ether-acid",
    "CMP-006", "GenX", "13252-13-6", "OC(=O)C(OCC(F)(F)C(F)(F)F)(F)F", "Ether-acid"
  ) |>
    dplyr::mutate(
      molecular_weight = c(414.07, 500.13, 464.08, 400.12, 330.05, 330.05),
      log_Kow = c(4.5, 5.3, 5.4, 4.0, 3.0, 3.0),
      tpsa = c(37.3, 42.5, 37.3, 42.5, 44.8, 44.8),
      hba = c(2L, 3L, 2L, 3L, 4L, 4L),
      hbd = c(1L, 0L, 1L, 0L, 1L, 1L),
      rotatable_bonds = c(7L, 8L, 8L, 6L, 4L, 4L),
      aromatic_ring_count = 0L,
      formal_charge = 0L,
      fluorine_count = c(15L, 17L, 17L, 13L, 9L, 9L),
      carbon_chain = c(8L, 8L, 9L, 6L, 6L, 6L),
      acid_class = c("PFCA-family", "PFSA-family", "PFCA-family", "PFSA-family", "Ether-acid", "Ether-acid"),
      acid_class_code = c(1, 2, 1, 2, 3, 3),
      ether_flag = c(0L, 0L, 0L, 0L, 1L, 1L),
      sulfonate_flag = c(0L, 1L, 0L, 1L, 0L, 0L),
      carboxylate_flag = c(1L, 0L, 1L, 0L, 1L, 1L),
      precursor_flag = 0L,
      structural_alerts = c("Perfluoroalkyl acid", "Perfluoroalkyl sulfonate", "Long-chain PFCA", "PFSA alert", "Ether PFAS", "Ether PFAS")
    )
}

build_dataset_registry <- function() {
  tibble::tribble(
    ~dataset_id, ~dataset_name, ~source, ~endpoint, ~endpoint_type, ~human_relevance, ~assay_domain, ~n_total, ~n_positive, ~n_negative, ~missing_rate_pct, ~duplicate_rate_pct, ~version, ~provenance,
    "DS-HEP-001", "HepG2 Viability Benchmark", "Public curated benchmark", "hepatotoxicity_proxy", "Binary", "Proxy for human hepatotoxicity", "in vitro", 5000, 1800, 3200, 1.8, 0.6, "2025.1", "Placeholder metadata: replace with actual dataset card",
    "DS-CARD-001", "hERG Cardiotoxicity Benchmark", "Public curated benchmark", "cardiotoxicity_proxy", "Binary", "Proxy for QT/cardiac risk", "in vitro", 7200, 2100, 5100, 2.1, 0.9, "2025.1", "Placeholder metadata: replace with actual dataset card",
    "DS-GENO-001", "Ames / Genotox Benchmark", "Public curated benchmark", "genotoxicity_proxy", "Binary", "Proxy for mutagenicity/genotoxicity", "in vitro", 8400, 2900, 5500, 1.2, 0.4, "2025.1", "Placeholder metadata: replace with actual dataset card",
    "DS-ENDO-001", "Endocrine Screening Benchmark", "Public curated benchmark", "endocrine_disruption_proxy", "Binary", "Proxy for endocrine activity", "in vitro", 4300, 1100, 3200, 3.5, 1.0, "2025.1", "Placeholder metadata: replace with actual dataset card"
  )
}

build_endpoint_definitions <- function() {
  tibble::tribble(
    ~endpoint_id, ~endpoint_name, ~clinical_meaning, ~label_definition, ~proxy_assay, ~intended_decision_context, ~limitations,
    "EP-HEP", "hepatotoxicity_proxy", "Potential liver toxicity risk", "Positive if assay-defined toxic class", "HepG2 viability / CYP-related proxy", "Early deprioritization / follow-up assay selection", "Proxy endpoint; not equivalent to confirmed human DILI",
    "EP-CARD", "cardiotoxicity_proxy", "Potential cardiac liability", "Positive if cardiotoxicity proxy class", "hERG / cardiac electrophysiology proxy", "Early cardiac liability triage", "Proxy endpoint; not full human cardiotoxicity severity",
    "EP-GENO", "genotoxicity_proxy", "Potential genotoxicity / mutagenicity", "Positive if benchmark label positive", "Ames / micronucleus proxy", "Mutagenicity screening / escalation", "Requires confirmatory evidence for regulatory use",
    "EP-ENDO", "endocrine_disruption_proxy", "Potential endocrine activity", "Positive if endocrine-active class", "Reporter / endocrine assay proxy", "Prioritization / assay follow-up", "Proxy endpoint with uncertain translation across contexts"
  )
}

build_proxy_assay_table <- function() {
  tibble::tribble(
    ~toxicity_domain, ~proxy_assay, ~mechanistic_relevance, ~human_translation_note, ~recommended_next_step,
    "Hepatotoxicity", "HepG2 viability / CYP inhibition", "Moderate", "Useful early proxy but incomplete for human liver injury", "Confirm with higher-content hepatic assay / human-relevant system",
    "Cardiotoxicity", "hERG / cardiomyocyte proxy", "High for selected mechanisms", "Captures some cardiac liabilities but not whole-clinical severity", "Confirm with broader cardiac panel / exposure context",
    "Genotoxicity", "Ames / micronucleus", "High", "Well-established screening proxies for mutagenicity/genotoxicity", "Escalate to confirmatory genotox review",
    "Endocrine disruption", "Reporter gene / endocrine assay", "Moderate", "Assay positive does not guarantee in vivo endocrine outcome", "Review receptor specificity and orthogonal evidence"
  )
}

build_descriptor_schema <- function() {
  tibble::tribble(
    ~feature_name, ~type, ~category, ~source, ~used_in_models,
    "molecular_weight", "numeric", "Descriptor", "RDKit placeholder", TRUE,
    "log_Kow", "numeric", "Descriptor", "RDKit placeholder", TRUE,
    "tpsa", "numeric", "Descriptor", "RDKit placeholder", TRUE,
    "hba", "integer", "Descriptor", "RDKit placeholder", TRUE,
    "hbd", "integer", "Descriptor", "RDKit placeholder", TRUE,
    "rotatable_bonds", "integer", "Descriptor", "RDKit placeholder", TRUE,
    "aromatic_ring_count", "integer", "Descriptor", "RDKit placeholder", TRUE,
    "formal_charge", "integer", "Descriptor", "RDKit placeholder", TRUE,
    "fluorine_count", "integer", "PFAS descriptor", "Rule-based placeholder", TRUE,
    "carbon_chain", "integer", "PFAS descriptor", "Rule-based placeholder", TRUE,
    "pfas_subclass", "categorical", "PFAS descriptor", "Rule-based placeholder", TRUE,
    "structural_alerts", "text", "Structural alerts", "Rule-based placeholder", FALSE
  )
}

build_fingerprint_schema <- function() {
  tibble::tribble(
    ~fingerprint_type, ~radius_or_length, ~mode, ~tool, ~included_for_endpoints,
    "MACCS", "166 bits", "binary", "RDKit placeholder", "All",
    "Morgan/ECFP", "radius 2 / 2048 bits", "binary", "RDKit placeholder", "All"
  )
}

build_structural_alert_table <- function() {
  tibble::tribble(
    ~alert_id, ~alert_name, ~mechanistic_relevance, ~endpoint_relevance, ~rule_source,
    "AL-001", "Perfluoroalkyl acid motif", "General persistence / PFAS identity", "All PFAS endpoints", "Placeholder SMARTS",
    "AL-002", "Long-chain PFCA alert", "Bioaccumulation concern", "Bioaccumulation / chronic concern", "Placeholder SMARTS",
    "AL-003", "PFSA alert", "PFSA subclass mechanistic grouping", "Cardio / bioaccumulation context", "Placeholder SMARTS",
    "AL-004", "Ether PFAS alert", "Emerging PFAS subclass", "New chemistry monitoring", "Placeholder SMARTS"
  )
}

build_model_registry <- function() {
  tibble::tribble(
    ~model_id, ~endpoint, ~algorithm, ~representation, ~training_n, ~class_handling, ~calibration, ~version, ~deployment_status,
    "MDL-HEP-RF", "hepatotoxicity_proxy", "Random Forest", "Descriptors + MACCS + Morgan", 5000, "Class weights", "Platt/Isotonic placeholder", "1.0", "Prototype",
    "MDL-CARD-SVM", "cardiotoxicity_proxy", "SVM", "Descriptors + MACCS + Morgan", 7200, "Class weights", "Platt/Isotonic placeholder", "1.0", "Prototype",
    "MDL-GENO-XGB", "genotoxicity_proxy", "XGBoost", "Descriptors + MACCS + Morgan", 8400, "Class weights", "Platt/Isotonic placeholder", "1.0", "Prototype",
    "MDL-ENDO-RF", "endocrine_disruption_proxy", "Random Forest", "Descriptors + MACCS + Morgan", 4300, "Class weights", "Platt/Isotonic placeholder", "1.0", "Prototype"
  )
}

build_hyperparameter_summary <- function() {
  tibble::tribble(
    ~model_id, ~parameter, ~value, ~tuning_method,
    "MDL-HEP-RF", "mtry", "auto placeholder", "Nested CV placeholder",
    "MDL-HEP-RF", "ntree", "500", "Nested CV placeholder",
    "MDL-CARD-SVM", "cost", "auto placeholder", "Nested CV placeholder",
    "MDL-CARD-SVM", "gamma", "auto placeholder", "Nested CV placeholder",
    "MDL-GENO-XGB", "max_depth", "6", "Nested CV placeholder",
    "MDL-GENO-XGB", "eta", "0.05", "Nested CV placeholder",
    "MDL-ENDO-RF", "mtry", "auto placeholder", "Nested CV placeholder"
  )
}

build_baseline_comparison <- function() {
  tibble::tribble(
    ~endpoint, ~baseline_model, ~production_candidate, ~delta_auc, ~delta_balanced_accuracy, ~delta_sensitivity, ~delta_specificity,
    "hepatotoxicity_proxy", "Logistic Regression", "Random Forest", 0.07, 0.06, 0.04, 0.05,
    "cardiotoxicity_proxy", "Logistic Regression", "SVM", 0.05, 0.05, 0.03, 0.04,
    "genotoxicity_proxy", "Logistic Regression", "XGBoost", 0.08, 0.07, 0.05, 0.06,
    "endocrine_disruption_proxy", "Logistic Regression", "Random Forest", 0.04, 0.03, 0.02, 0.03
  )
}

build_validation_summary <- function() {
  tibble::tribble(
    ~model_id, ~endpoint, ~split_strategy, ~train_n, ~validation_n, ~test_n, ~external_set_n, ~prospective_set_n, ~leakage_check, ~status,
    "MDL-HEP-RF", "hepatotoxicity_proxy", "5-fold CV + hold-out", 4000, 500, 500, 700, 0, "Pass", "Needs prospective validation",
    "MDL-CARD-SVM", "cardiotoxicity_proxy", "5-fold CV + hold-out", 5760, 720, 720, 500, 0, "Pass", "Needs prospective validation",
    "MDL-GENO-XGB", "genotoxicity_proxy", "5-fold CV + hold-out", 6720, 840, 840, 600, 0, "Pass", "Needs prospective validation",
    "MDL-ENDO-RF", "endocrine_disruption_proxy", "5-fold CV + hold-out", 3440, 430, 430, 350, 0, "Pass", "Needs prospective validation"
  )
}

build_performance_metrics <- function() {
  tibble::tribble(
    ~model_id, ~AUC, ~Accuracy, ~Balanced_Accuracy, ~Sensitivity, ~Specificity, ~Precision, ~Recall, ~F1, ~MCC, ~Brier,
    "MDL-HEP-RF", 0.84, 0.79, 0.78, 0.75, 0.81, 0.72, 0.75, 0.74, 0.55, 0.16,
    "MDL-CARD-SVM", 0.82, 0.77, 0.76, 0.73, 0.79, 0.70, 0.73, 0.71, 0.51, 0.18,
    "MDL-GENO-XGB", 0.86, 0.80, 0.79, 0.77, 0.81, 0.75, 0.77, 0.76, 0.58, 0.15,
    "MDL-ENDO-RF", 0.78, 0.74, 0.72, 0.68, 0.77, 0.63, 0.68, 0.65, 0.44, 0.20
  )
}

build_error_buckets <- function() {
  tibble::tribble(
    ~endpoint, ~false_positives, ~false_negatives, ~likely_causes, ~high_risk_failure_mode,
    "hepatotoxicity_proxy", 55, 70, "Sparse chemotypes, proxy mismatch", "False negative hepatic liability",
    "cardiotoxicity_proxy", 63, 78, "Exposure context not modeled", "False negative cardiac risk",
    "genotoxicity_proxy", 49, 61, "Assay label inconsistency", "False negative mutagenicity",
    "endocrine_disruption_proxy", 52, 67, "Weak receptor transferability", "False negative endocrine activity"
  )
}

build_ad_registry <- function() {
  tibble::tribble(
    ~endpoint, ~ad_method, ~training_space_basis, ~distance_metric, ~threshold, ~status,
    "hepatotoxicity_proxy", "Distance to training chemical space", "Descriptors + fingerprints", "z-score / NN hybrid placeholder", "1.5 / 2.5", "Prototype",
    "cardiotoxicity_proxy", "Distance to training chemical space", "Descriptors + fingerprints", "z-score / NN hybrid placeholder", "1.5 / 2.5", "Prototype",
    "genotoxicity_proxy", "Distance to training chemical space", "Descriptors + fingerprints", "z-score / NN hybrid placeholder", "1.5 / 2.5", "Prototype",
    "endocrine_disruption_proxy", "Distance to training chemical space", "Descriptors + fingerprints", "z-score / NN hybrid placeholder", "1.5 / 2.5", "Prototype"
  )
}

build_prediction_table <- function(compounds) {
  endpoints <- c("hepatotoxicity_proxy", "cardiotoxicity_proxy", "genotoxicity_proxy", "endocrine_disruption_proxy")
  expand.grid(compound_id = compounds$compound_id, endpoint = endpoints, stringsAsFactors = FALSE) |>
    tibble::as_tibble() |>
    dplyr::left_join(compounds, by = "compound_id") |>
    dplyr::mutate(
      predicted_probability = c(0.61, 0.72, 0.44, 0.31, 0.28, 0.28, 0.67, 0.80, 0.36, 0.22, 0.24, 0.24,
                                0.58, 0.64, 0.51, 0.34, 0.26, 0.26, 0.62, 0.74, 0.40, 0.30, 0.27, 0.27),
      predicted_class = ifelse(predicted_probability >= 0.50, "Positive", "Negative"),
      ad_distance = c(1.1, 1.3, 1.7, 1.4, 2.8, 2.8, 1.2, 1.6, 1.5, 1.4, 2.6, 2.6,
                      1.3, 1.2, 1.8, 1.5, 2.4, 2.4, 1.0, 1.1, 1.9, 1.7, 2.3, 2.3),
      ad_status = dplyr::case_when(
        ad_distance <= 1.5 ~ "Inside",
        ad_distance <= 2.5 ~ "Borderline",
        TRUE ~ "Outside"
      ),
      confidence = dplyr::case_when(
        ad_status == "Outside" ~ "Low",
        predicted_probability >= 0.80 ~ "High",
        predicted_probability >= 0.60 ~ "Medium",
        TRUE ~ "Low"
      ),
      similar_compound_support = c("Moderate", "High", "Moderate", "Low", "Low", "Low", "Moderate", "High", "Moderate", "Low", "Low", "Low",
                                   "Moderate", "Moderate", "Moderate", "Low", "Low", "Low", "High", "High", "Moderate", "Low", "Low", "Low"),
      recommended_action = dplyr::case_when(
        ad_status == "Outside" ~ "Out-of-domain: do not rely",
        predicted_class == "Positive" & confidence %in% c("High", "Medium") ~ "Confirm with assay",
        predicted_class == "Positive" ~ "Needs human review",
        TRUE ~ "Advance with caution"
      )
    )
}

build_feature_importance <- function() {
  tibble::tribble(
    ~endpoint, ~feature, ~importance, ~interpretation,
    "hepatotoxicity_proxy", "log_Kow", 0.23, "Exposure/partitioning-related contribution",
    "hepatotoxicity_proxy", "fluorine_count", 0.19, "PFAS burden proxy",
    "hepatotoxicity_proxy", "molecular_weight", 0.14, "Global size signal",
    "cardiotoxicity_proxy", "sulfonate_flag", 0.21, "Subclass-associated alert contribution",
    "cardiotoxicity_proxy", "log_Kow", 0.17, "Lipophilicity-related signal",
    "genotoxicity_proxy", "structural_alerts", 0.18, "Structural-risk proxy placeholder",
    "genotoxicity_proxy", "molecular_weight", 0.11, "Weak size contribution",
    "endocrine_disruption_proxy", "ether_flag", 0.20, "Subclass-associated pattern",
    "endocrine_disruption_proxy", "carbon_chain", 0.14, "Chain-length contribution"
  )
}

build_analog_support <- function(compounds) {
  tibble::tribble(
    ~query_compound, ~nearest_analog, ~similarity, ~known_label, ~source_dataset, ~relevance,
    "PFOA", "PFNA", 0.89, "Positive in hepatotoxicity proxy", "DS-HEP-001", "High",
    "PFOS", "PFHxS", 0.87, "Positive in cardiotoxicity proxy", "DS-CARD-001", "High",
    "HFPO-DA", "GenX", 0.95, "Negative/Borderline mixed", "DS-ENDO-001", "Moderate"
  )
}

build_mechanistic_rationale <- function() {
  tibble::tribble(
    ~endpoint, ~evidence_type, ~description, ~strength, ~source,
    "hepatotoxicity_proxy", "Proxy assay rationale", "Hepatic proxy endpoint used for early screening", "Moderate", "Internal model card placeholder",
    "cardiotoxicity_proxy", "Mechanistic proxy", "Cardiac proxy informed by electrophysiology-related assay logic", "Moderate", "Internal model card placeholder",
    "genotoxicity_proxy", "Assay benchmark", "Mutagenicity proxy from benchmark screening context", "High", "Internal model card placeholder",
    "endocrine_disruption_proxy", "Assay benchmark", "Endocrine-active proxy from reporter-style endpoint logic", "Moderate", "Internal model card placeholder"
  )
}

build_model_cards <- function() {
  tibble::tribble(
    ~model_id, ~endpoint, ~dataset_source, ~representation, ~algorithm, ~training_date, ~validation_strategy, ~external_validation, ~prospective_validation, ~ad_method, ~intended_use, ~limitations, ~owner_version,
    "MDL-HEP-RF", "hepatotoxicity_proxy", "DS-HEP-001", "Descriptors + MACCS + Morgan", "Random Forest", "2026-04-07", "5-fold CV + hold-out + external set", "Available", "Not yet", "Distance + nearest neighbors", "Screening / prioritization", "Proxy endpoint, no prospective validation yet", "Owner A / v1.0",
    "MDL-CARD-SVM", "cardiotoxicity_proxy", "DS-CARD-001", "Descriptors + MACCS + Morgan", "SVM", "2026-04-07", "5-fold CV + hold-out + external set", "Available", "Not yet", "Distance + nearest neighbors", "Screening / prioritization", "Proxy endpoint, exposure context incomplete", "Owner A / v1.0",
    "MDL-GENO-XGB", "genotoxicity_proxy", "DS-GENO-001", "Descriptors + MACCS + Morgan", "XGBoost", "2026-04-07", "5-fold CV + hold-out + external set", "Available", "Not yet", "Distance + nearest neighbors", "Screening / prioritization", "No prospective validation yet", "Owner A / v1.0",
    "MDL-ENDO-RF", "endocrine_disruption_proxy", "DS-ENDO-001", "Descriptors + MACCS + Morgan", "Random Forest", "2026-04-07", "5-fold CV + hold-out + external set", "Available", "Not yet", "Distance + nearest neighbors", "Screening / prioritization", "Proxy endpoint, mechanism depends on assay context", "Owner A / v1.0"
  )
}

build_oecd_checklist <- function() {
  tibble::tribble(
    ~principle, ~requirement, ~evidence_in_app, ~status, ~notes,
    "Defined endpoint", "Endpoint must be clearly defined", "Endpoint Definitions table", "Partial", "Needs real production endpoint cards",
    "Unambiguous algorithm", "Algorithm and configuration explicit", "Model registry + hyperparameters", "Partial", "Needs production-training provenance",
    "Applicability domain", "AD clearly defined", "AD registry + compound AD summary", "Partial", "Prototype AD only",
    "Goodness-of-fit / robustness / predictivity", "Performance and validation reported", "Validation summary + metrics", "Partial", "Needs real external/prospective runs",
    "Mechanistic interpretation", "Interpretability where possible", "Feature importance + alerts + analog support", "Partial", "Needs endpoint-specific mechanistic evidence"
  )
}

build_system_readiness <- function() {
  tibble::tribble(
    ~component, ~status, ~notes,
    "Endpoint definitions", "Present", "Placeholder endpoint cards loaded",
    "Descriptor generation", "Present", "Placeholder descriptor schema",
    "Fingerprints generation", "Present", "Schema only; connect real generator",
    "Validation metrics", "Present", "Placeholder tables",
    "External validation", "Present", "Placeholder metadata only",
    "Prospective validation", "Missing", "Add prospective test assets",
    "Applicability domain", "Present", "Prototype AD tables",
    "Mechanistic interpretation", "Present", "Placeholder evidence tables",
    "Weight-of-evidence engine", "Present", "Rule-based skeleton",
    "Model cards", "Present", "Placeholder cards"
  )
}

# -------------------------------------------------------------------
# Materialize app data
# -------------------------------------------------------------------

compounds <- build_compound_registry()
dataset_registry <- build_dataset_registry()
endpoint_definitions <- build_endpoint_definitions()
proxy_assay_table <- build_proxy_assay_table()
descriptor_schema <- build_descriptor_schema()
fingerprint_schema <- build_fingerprint_schema()
structural_alert_table <- build_structural_alert_table()
model_registry <- build_model_registry()
hyperparameter_summary <- build_hyperparameter_summary()
baseline_comparison <- build_baseline_comparison()
validation_summary <- build_validation_summary()
performance_metrics <- build_performance_metrics()
error_buckets <- build_error_buckets()
ad_registry <- build_ad_registry()
predictions <- build_prediction_table(compounds)
feature_importance <- build_feature_importance()
analog_support <- build_analog_support(compounds)
mechanistic_rationale <- build_mechanistic_rationale()
model_cards <- build_model_cards()
oecd_checklist <- build_oecd_checklist()
system_readiness <- build_system_readiness()

compound_ad_summary <- predictions |>
  dplyr::select(compound_id, compound_name, endpoint, ad_distance, ad_status, confidence) |>
  dplyr::arrange(endpoint, compound_name)

weight_of_evidence <- predictions |>
  dplyr::mutate(
    structural_alert_count = dplyr::if_else(structural_alerts == "", 0L, 1L),
    evidence_grade = dplyr::case_when(
      ad_status == "Outside" ~ "Weak",
      predicted_class == "Positive" & confidence == "High" ~ "Strong",
      predicted_class == "Positive" ~ "Moderate",
      TRUE ~ "Moderate"
    ),
    woe_score = dplyr::case_when(
      evidence_grade == "Strong" ~ 3,
      evidence_grade == "Moderate" ~ 2,
      TRUE ~ 1
    ),
    suggested_action = recommended_action,
    escalation_priority = dplyr::case_when(
      predicted_class == "Positive" & ad_status != "Outside" ~ "High",
      ad_status == "Outside" ~ "High",
      TRUE ~ "Medium"
    )
  ) |>
  dplyr::select(
    compound_id, compound_name, endpoint, predicted_class, predicted_probability,
    confidence, ad_status, structural_alert_count, similar_compound_support,
    evidence_grade, woe_score, suggested_action, escalation_priority
  )

# -------------------------------------------------------------------
# Reusable plotting helpers
# -------------------------------------------------------------------

plot_class_balance <- function() {
  df <- dataset_registry |>
    dplyr::select(endpoint, n_positive, n_negative) |>
    tidyr::pivot_longer(cols = c(n_positive, n_negative), names_to = "class", values_to = "n")
  
  ggplot(df, aes(x = endpoint, y = n, fill = class)) +
    geom_col(position = "stack") +
    coord_flip() +
    labs(x = NULL, y = "Count", title = "Class balance by endpoint") +
    theme_minimal(base_size = 12)
}

plot_missingness <- function() {
  df <- dataset_registry |>
    dplyr::select(dataset_name, missing_rate_pct)
  
  ggplot(df, aes(x = reorder(dataset_name, missing_rate_pct), y = missing_rate_pct)) +
    geom_col() +
    coord_flip() +
    labs(x = NULL, y = "Missing rate (%)", title = "Dataset missingness") +
    theme_minimal(base_size = 12)
}

plot_validation_metrics <- function(metric_name) {
  df <- performance_metrics |>
    dplyr::select(model_id, all_of(metric_name))
  
  ggplot(df, aes(x = reorder(model_id, .data[[metric_name]]), y = .data[[metric_name]])) +
    geom_col() +
    coord_flip() +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
    labs(x = NULL, y = metric_name, title = paste(metric_name, "by model")) +
    theme_minimal(base_size = 12)
}

plot_ad_distribution <- function() {
  ggplot(compound_ad_summary, aes(x = ad_status)) +
    geom_bar() +
    labs(x = NULL, y = "Count", title = "Applicability-domain status") +
    theme_minimal(base_size = 12)
}

plot_prediction_risk <- function() {
  df <- weight_of_evidence |>
    dplyr::count(endpoint, predicted_class)
  
  ggplot(df, aes(x = endpoint, y = n, fill = predicted_class)) +
    geom_col(position = "stack") +
    coord_flip() +
    labs(x = NULL, y = "Count", title = "Predicted class distribution by endpoint") +
    theme_minimal(base_size = 12)
}

plot_feature_importance <- function(endpoint_pick) {
  df <- feature_importance |>
    dplyr::filter(endpoint == endpoint_pick)
  
  ggplot(df, aes(x = reorder(feature, importance), y = importance)) +
    geom_col() +
    coord_flip() +
    labs(x = NULL, y = "Importance", title = paste("Top features:", endpoint_pick)) +
    theme_minimal(base_size = 12)
}

# -------------------------------------------------------------------
# UI
# -------------------------------------------------------------------

ui_dashboard <- dashboardPage(
  dashboardHeader(title = APP_TITLE),
  dashboardSidebar(
    sidebarMenu(
      menuItem("Home / Overview", tabName = "home", icon = icon("home")),
      menuItem("Data & Endpoints", tabName = "data", icon = icon("database")),
      menuItem(
        "Governance & lineage",
        tabName = "governance_lineage",
        icon = icon("diagram-project")
      ),
      menuItem("Data Collection", tabName = "collection", icon = icon("edit")),
      menuItem("Representations", tabName = "representations", icon = icon("project-diagram")),
      menuItem("Modeling", tabName = "modeling", icon = icon("cogs")),
      menuItem("Validation", tabName = "validation", icon = icon("check-circle")),
      menuItem("Predictions", tabName = "predictions", icon = icon("table")),
      menuItem("Enterprise 5.0 (Cloud API)", tabName = "enterprise5", icon = icon("cloud")),
      menuItem("Applicability Domain", tabName = "ad", icon = icon("bullseye")),
      menuItem("Mechanistic Interpretation", tabName = "mechanistic", icon = icon("microscope")),
      menuItem("Decision Support", tabName = "decision", icon = icon("balance-scale")),
      menuItem("Compliance / Model Cards", tabName = "compliance", icon = icon("clipboard-check")),
      menuItem("Reports / Export", tabName = "reports", icon = icon("file-export")),
      menuItem("ISO 17025 / GLP", tabName = "glp", icon = icon("certificate")),
      menuItem("ISO Blind Spots", tabName = "iso_blind_spots", icon = icon("triangle-exclamation")),
      menuItem("Scope & limitations", tabName = "scope", icon = icon("exclamation-circle"))
    )
  ),
  dashboardBody(
    tags$head(tags$style(HTML(".small-box h3 {font-size: 26px;} .content {padding: 15px;} .box .dataTables_wrapper {overflow-x:auto;}"))),
    tabItems(
      tabItem(
        tabName = "home",
        fluidRow(
          valueBoxOutput("vb_compounds", width = 2),
          valueBoxOutput("vb_datasets", width = 2),
          valueBoxOutput("vb_models", width = 2),
          valueBoxOutput("vb_inside_ad", width = 2),
          valueBoxOutput("vb_outside_ad", width = 2),
          valueBoxOutput("vb_high_concern", width = 2)
        ),
        fluidRow(
          box(width = 6, title = "Intended Use", status = "primary", solidHeader = TRUE,
              p("Use this system for screening, prioritization, transparency review, and weight-of-evidence support. Do not treat this scaffold as a standalone regulatory submission engine until it is backed by validated production endpoint models and audited datasets."),
              p(
                tags$strong("Full scope statement: "),
                "open the ",
                tags$strong("Scope & limitations"),
                " tab in the sidebar (same content as ",
                tags$code("DISCLAIMER.md"),
                " in the repository)."
              )),
          box(width = 6, title = "Current Limitations", status = "warning", solidHeader = TRUE,
              p("This version is a standards-oriented skeleton. Replace placeholder datasets, placeholder validation statistics, and placeholder model cards with real endpoint assets, external validation results, and prospective testing evidence."))
        ),
        fluidRow(
          box(width = 6, title = "System Readiness", status = "info", solidHeader = TRUE, DTOutput("tbl_system_readiness")),
          box(width = 6, title = "OECD / QSAR Principles Checklist", status = "info", solidHeader = TRUE, DTOutput("tbl_oecd_home"))
        ),
        fluidRow(
          box(
            width = 12,
            title = "Final Professional Featured Stack",
            status = "success",
            solidHeader = TRUE,
            tags$p(tags$em("For qualified partners under NDA. All systems must be validated for ISO/IEC 17025:2017 controls before production release.")),
            tags$div(
              style = "display:flex; flex-wrap:wrap; gap:10px;",
              featured_stack_button(LINK_SHINY_DEMO, "btn-primary", "1) Technical Review & Demo"),
              featured_stack_button(LINK_GITHUB_REPO, "btn-info", "2) Code & Validation Package"),
              featured_stack_button(LINK_DATASET_FORM, "btn-warning", "3) Data Submission"),
              featured_stack_button(LINK_COLLAB, "btn-success", "4) Collaboration & Partnership")
            ),
            tags$hr(),
            tags$p(
              tags$strong("1) Technical Review & Demo: "),
              featured_link_status(LINK_SHINY_DEMO),
              tags$br(),
              "Private staging environment. Request access through controlled onboarding. ",
              tags$em("SSO required; sessions logged per ISO 17025 clause 7.11.3.")
            ),
            tags$p(
              tags$strong("2) Code & Validation Package: "),
              featured_link_status(LINK_GITHUB_REPO),
              tags$br(),
              "Private repository access granted after required agreements are executed. ",
              tags$em("Supports software validation evidence and change-control traceability per 7.11.2 and 7.11.4.")
            ),
            tags$p(
              tags$strong("3) Data Submission: "),
              featured_link_status(LINK_DATASET_FORM),
              tags$br(),
              "Secured intake with PII/PHI scan + chemist review planned. ",
              tags$em("Aligns to 8.4.2 + 7.11.6. No public endpoint active.")
            ),
            tags$p(
              tags$strong("Current intake endpoint: "),
              tags$code(if (is_disabled_link(LINK_DATASET_FORM)) "No public endpoint active." else LINK_DATASET_FORM)
            ),
            tags$p(
              tags$strong("Confirmation message after form receipt: "),
              DATASET_FORM_CONFIRMATION_MESSAGE
            ),
            tags$p(
              tags$strong("4) Collaboration & Partnership: "),
              featured_link_status(LINK_COLLAB),
              tags$br(),
              "Partnership intake with QA and legal review prior to project activation. ",
              tags$em("Includes impartiality and confidentiality governance aligned to 4.1.5 and 8.4.2.")
            ),
            tags$hr(),
            tags$div(
              class = "well well-sm",
              style = "margin-bottom:12px;",
              tags$strong("Intake API health"),
              tags$span(" ", style = "display:inline-block; width:6px;"),
              actionButton("btn_check_intake_api_health", "Check now", class = "btn btn-default btn-xs"),
              tags$div(style = "margin-top:8px;", verbatimTextOutput("intake_api_health_status", placeholder = TRUE))
            ),
            tags$hr(),
            tags$small(
              "Optional env overrides: PFAS_LINK_SHINY_DEMO, PFAS_LINK_GITHUB_REPO, PFAS_INTAKE_API_URL, PFAS_LINK_DATASET_FORM, PFAS_LINK_COLLAB, PFAS_DATASET_FORM_CONFIRMATION_MESSAGE, PFAS_INTAKE_STAGING_TOKEN, PFAS_PARTNER_AUDIT_SQLITE_TABLE, PFAS_PARTNER_AUDIT_MIRROR_CSV. PFAS_LINK_DATASET_FORM defaults to PFAS_INTAKE_API_URL + /upload when not explicitly set. In production, set PFAS_INTAKE_API_URL, PFAS_LINK_DATASET_FORM, and PFAS_INTAKE_STAGING_TOKEN to null until 7.11.3 verification is complete."
            )
          )
        )
      ),
      tabItem(
        tabName = "data",
        fluidRow(
          box(width = 12, title = "Datasets", status = "primary", solidHeader = TRUE, DTOutput("tbl_dataset_registry"))
        ),
        fluidRow(
          box(width = 6, title = "Endpoint Definitions", status = "warning", solidHeader = TRUE, DTOutput("tbl_endpoint_definitions")),
          box(width = 6, title = "Proxy Endpoints", status = "warning", solidHeader = TRUE, DTOutput("tbl_proxy_assays"))
        ),
        fluidRow(
          box(width = 6, title = "Dataset Missingness", status = "info", solidHeader = TRUE, plotOutput("plot_missingness", height = 300)),
          box(width = 6, title = "Class Balance", status = "info", solidHeader = TRUE, plotOutput("plot_class_balance", height = 300))
        ),
        fluidRow(
          box(
            width = 12,
            title = "UCMR5 Method 533 occurrence (optional preview)",
            status = "info",
            solidHeader = TRUE,
            helpText(
              "Exploration only (not regulatory analytics). Same encoding as scripts/smoke_read_ucmr533.R (latin1). ",
              "Only the first N rows are loaded to keep memory safe (~1.6M rows in full file). ",
              "UCMR is drinking-water monitoring, not biosolids or serum occurrence—keep matrices separate; see ",
              code("data/reference/registry/reference_registry_README.md"), "."
            ),
            fluidRow(
              column(
                6,
                textInput(
                  "ucmr533_path_override",
                  "Optional path to UCMR5_533.txt (blank = env UCMR5_533_TXT, option pfas.ucmr5_533_path, or data/external/epa_ucmr5/)",
                  value = ""
                )
              ),
              column(
                3,
                numericInput(
                  "ucmr533_preview_rows",
                  "Max rows to load",
                  value = 5000L,
                  min = 100L,
                  max = 50000L,
                  step = 500L
                )
              ),
              column(3, br(), actionButton("ucmr533_load_btn", "Load preview", class = "btn-info"))
            ),
            verbatimTextOutput("ucmr533_resolve_status", placeholder = TRUE),
            DTOutput("ucmr533_preview_tbl")
          )
        ),
        fluidRow(
          box(
            width = 12,
            title = "Python pipeline output (priority triage)",
            status = "success",
            solidHeader = TRUE,
            helpText(
              "Loads ",
              tags$code("priority_report.csv"),
              " from ",
              tags$code("pipeline/process_ucmr5.py"),
              " output: ",
              tags$code("runs/<run_id>/"),
              ". Only the first N rows are read into memory (full file can be 10M+ rows)."
            ),
            fluidRow(
              column(
                3,
                textInput(
                  "ucmr_pipeline_output_root",
                  "Output root (folder under project)",
                  value = "runs"
                )
              ),
              column(
                4,
                textInput(
                  "ucmr_pipeline_run_id",
                  "Run ID (e.g. test_ucmr5_533)",
                  value = "",
                  placeholder = "test_ucmr5_533"
                )
              ),
              column(
                3,
                numericInput(
                  "ucmr_pipeline_preview_rows",
                  "Max rows to load",
                  value = 5000L,
                  min = 100L,
                  max = 50000L,
                  step = 500L
                )
              ),
              column(2, br(), actionButton("ucmr_pipeline_load_btn", "Load priority report", class = "btn-success"))
            ),
            verbatimTextOutput("ucmr_pipeline_status", placeholder = TRUE),
            DTOutput("ucmr_pipeline_priority_tbl")
          )
        )
      ),
      tabItem(
        tabName = "governance_lineage",
        fluidRow(
          box(
            width = 12,
            title = "Cross-matrix governance control center",
            status = "primary",
            solidHeader = TRUE,
            tags$p(
              style = "margin-bottom:8px;",
              tags$strong("Operational visibility — not executive BI."),
              " Read-only roll-up of matrix lanes, provenance files, manifests, AD refusal history, ",
              "threshold reproducibility, SQLite QA trails, and blind-validation index tails. ",
              "Purpose: governed workflow review and audit readiness; ",
              tags$em("not"),
              " generic analytics dashboards."
            ),
            tags$p(
              style = "margin-bottom:8px;font-size:0.95em;color:#424242;",
              "Sources: ",
              code("data/config/matrix_pipeline_sop.csv"), ", ",
              code("data/ad_models/index.json"), ", per-lane ",
              code("data/training/<lane>/manifest.json"), ", ",
              code("data/reference/registry/reference_registry.csv"), ", ",
              code("data/audit/ad_decisions.jsonl"), ", ",
              code("pfas_collection.sqlite"), " (audit / upload validation), ",
              code("validation/blind_external/manifests/*.jsonl"), ", ",
              code("validation/scope_freeze/*/freeze_manifest.json"), ". ",
              "CLI mirror (CI / operators): ",
              code("python scripts/governance_operational_snapshot.py --project-root . --pretty"), "."
            ),
            fluidRow(
              column(3, actionButton("btn_governance_refresh", "Refresh all panels", class = "btn-info")),
              column(
                9,
                helpText(
                  "Click refresh after lane builds, AD runs, registry edits, or external blind-validation actions. ",
                  "Matrix isolation enforcement remains in R training prep + Python API; this tab surfaces evidence only."
                )
              )
            )
          )
        ),
        fluidRow(
          box(
            width = 6,
            title = "Matrix inventory (SOP + AD index)",
            status = "info",
            solidHeader = TRUE,
            DT::dataTableOutput("tbl_governance_matrix_inventory")
          ),
          box(
            width = 6,
            title = "Per-lane manifest / training build status",
            status = "info",
            solidHeader = TRUE,
            DT::dataTableOutput("tbl_governance_manifest_status")
          )
        ),
        fluidRow(
          box(
            width = 7,
            title = "Reference registry lineage (registered artifacts)",
            status = "warning",
            solidHeader = TRUE,
            DT::dataTableOutput("tbl_governance_registry")
          ),
          box(
            width = 5,
            title = "Threshold & scope-freeze reproducibility",
            status = "warning",
            solidHeader = TRUE,
            verbatimTextOutput("txt_governance_threshold_scope", placeholder = TRUE)
          )
        ),
        fluidRow(
          box(
            width = 6,
            title = "AD refusal trends (recent audit tail)",
            status = "danger",
            solidHeader = TRUE,
            helpText(
              "Aggregates the last ",
              tags$strong("5,000"),
              " lines of ",
              code("data/audit/ad_decisions.jsonl"), " by ",
              code("reference_lane"), " and ",
              code("ad_status"), "."
            ),
            DT::dataTableOutput("tbl_governance_ad_trends")
          ),
          box(
            width = 6,
            title = "Blind-validation submissions (index tail)",
            status = "danger",
            solidHeader = TRUE,
            verbatimTextOutput("txt_governance_blind_tail", placeholder = TRUE)
          )
        ),
        fluidRow(
          box(
            width = 6,
            title = "SQLite reviewer / QA activity (audit_log tail)",
            status = "success",
            solidHeader = TRUE,
            DT::dataTableOutput("tbl_governance_sqlite_audit")
          ),
          box(
            width = 6,
            title = "Upload validation & ingestion QA (SQLite)",
            status = "success",
            solidHeader = TRUE,
            DT::dataTableOutput("tbl_governance_upload_validation"),
            tags$hr(),
            tags$strong("Runs with failures or non-OK status (ingestion risk):"),
            DT::dataTableOutput("tbl_governance_ingestion_failures")
          )
        ),
        fluidRow(
          box(
            width = 6,
            title = "Export / results artifact recency (results/)",
            status = "primary",
            solidHeader = TRUE,
            helpText("Newest JSON/CSV under ", code("results/"), " (max 20 files). Not a full provenance chain — quick operational trace."),
            DT::dataTableOutput("tbl_governance_results_recent")
          ),
          box(
            width = 6,
            title = "Matrix isolation checks (evidence)",
            status = "primary",
            solidHeader = TRUE,
            verbatimTextOutput("txt_governance_matrix_isolation", placeholder = TRUE)
          )
        )
      ),
      tabItem(
        tabName = "collection",
        fluidRow(
          box(
            width = 12, title = "Data Collection Hub", status = "primary", solidHeader = TRUE,
            tabsetPanel(
              tabPanel(
                "Compound Intake",
                fluidRow(
                  box(width = 6,
                      textInput("compound_name", "Compound Name"),
                      textInput("smiles", "SMILES"),
                      textInput("cas", "CAS"),
                      selectInput("pfas_subclass", "PFAS Subclass",
                                  choices = c("PFCA", "PFSA", "Ether-acid", "Precursor", "Other")),
                      selectInput("source_type", "Source Type",
                                  choices = c("client", "literature", "standard", "curated", "inferred")),
                      textInput("source_reference", "Source Reference"),
                      selectInput("compound_review_status", "Review Status",
                                  choices = c("draft", "review", "approved", "rejected")),
                      textInput("compound_created_by", "Created By"),
                      actionButton("save_compound", "Save Compound", class = "btn-primary")
                  )
                )
              ),
              tabPanel(
                "Sample / Batch Intake",
                fluidRow(
                  box(width = 6,
                      textInput("sample_id", "Sample ID"),
                      textInput("project_id", "Project ID"),
                      textInput("client_id", "Client ID"),
                      selectInput("matrix", "Matrix",
                                  choices = c("water", "soil", "serum", "sludge", "biosolids", "tissue", "other")),
                      selectInput("sample_type", "Sample Type",
                                  choices = c("raw", "extract", "standard", "blank", "spike")),
                      dateInput("collection_date", "Collection Date"),
                      textInput("batch_id", "Batch ID"),
                      textInput("instrument_id", "Instrument ID"),
                      textInput("method_id", "Method ID"),
                      textInput("operator", "Operator"),
                      textAreaInput("sample_notes", "Notes"),
                      actionButton("save_sample", "Save Sample", class = "btn-primary")
                  )
                )
              ),
              tabPanel(
                "Measurement Entry",
                fluidRow(
                  box(width = 6,
                      uiOutput("compound_select_ui"),
                      uiOutput("sample_select_ui"),
                      numericInput("retention_time", "Retention Time", value = NA),
                      numericInput("precursor_mz", "Precursor m/z", value = NA),
                      numericInput("product_mz", "Product m/z", value = NA),
                      numericInput("peak_area", "Peak Area", value = NA),
                      numericInput("signal_to_noise", "Signal-to-Noise", value = NA),
                      numericInput("concentration", "Concentration", value = NA),
                      selectInput("concentration_unit", "Concentration Unit",
                                  choices = c("ng/L", "ug/L", "mg/L", "ng/g", "ug/kg")),
                      numericInput("lod", "LOD", value = NA),
                      numericInput("loq", "LOQ", value = NA),
                      textInput("internal_standard", "Internal Standard"),
                      selectInput("result_flag", "Result Flag",
                                  choices = c("detected", "nondetect", "estimated", "rejected")),
                      selectInput("qc_flag", "QC Flag",
                                  choices = c("pass", "fail", "review")),
                      textInput("measurement_created_by", "Created By"),
                      actionButton("save_measurement", "Save Measurement", class = "btn-primary")
                  )
                )
              ),
              tabPanel(
                "Label Curation",
                fluidRow(
                  box(width = 6,
                      uiOutput("label_compound_select_ui"),
                      selectInput("endpoint", "Endpoint",
                                  choices = c("hepatotoxicity_proxy", "cardiotoxicity_proxy",
                                              "genotoxicity_proxy", "endocrine_disruption_proxy",
                                              "SR-ARE", "NR-PPAR-gamma")),
                      selectInput("label_value", "Label Value", choices = c("0", "1")),
                      selectInput("label_source", "Label Source",
                                  choices = c("Tox21", "ToxCast", "literature", "curated", "client")),
                      textInput("assay_id", "Assay ID"),
                      textInput("label_reference", "Source Reference"),
                      sliderInput("confidence_score", "Confidence Score", min = 0, max = 1, value = 0.8, step = 0.05),
                      textInput("curator", "Curator"),
                      selectInput("label_review_status", "Review Status",
                                  choices = c("draft", "review", "approved", "rejected")),
                      textAreaInput("label_notes", "Notes"),
                      actionButton("save_label", "Save Label", class = "btn-primary")
                  )
                )
              )
            )
          )
        ),
        fluidRow(
          box(width = 12, title = "Recent Entries", status = "info", solidHeader = TRUE,
              DTOutput("tbl_recent_entries"))
        ),
        fluidRow(
          box(width = 12, title = "Export Training Data", status = "warning", solidHeader = TRUE,
              downloadButton("download_ml_export", "Download ML Training CSV"))
        )
      ),
      tabItem(
        tabName = "representations",
        fluidRow(
          box(width = 6, title = "Descriptor Schema", status = "primary", solidHeader = TRUE, DTOutput("tbl_descriptor_schema")),
          box(width = 6, title = "Fingerprint Schema", status = "primary", solidHeader = TRUE, DTOutput("tbl_fingerprint_schema"))
        ),
        fluidRow(
          box(width = 12, title = "Structural Alerts", status = "warning", solidHeader = TRUE, DTOutput("tbl_structural_alerts"))
        ),
        fluidRow(
          box(width = 12, title = "Compound Registry", status = "info", solidHeader = TRUE, DTOutput("tbl_compounds"))
        )
      ),
      tabItem(
        tabName = "modeling",
        fluidRow(
          box(width = 8, title = "Model Registry", status = "primary", solidHeader = TRUE, DTOutput("tbl_model_registry")),
          box(width = 4, title = "Baseline Comparison", status = "info", solidHeader = TRUE, DTOutput("tbl_baseline_comparison"))
        ),
        fluidRow(
          box(width = 12, title = "Hyperparameter Summary", status = "warning", solidHeader = TRUE, DTOutput("tbl_hyperparameters"))
        )
      ),
      tabItem(
        tabName = "validation",
        fluidRow(
          box(width = 8, title = "Validation Summary", status = "primary", solidHeader = TRUE, DTOutput("tbl_validation_summary")),
          box(width = 4, title = "Error Buckets", status = "warning", solidHeader = TRUE, DTOutput("tbl_error_buckets"))
        ),
        fluidRow(
          box(width = 6, title = "Performance Metrics", status = "info", solidHeader = TRUE, DTOutput("tbl_performance_metrics")),
          box(width = 6, title = "Balanced Accuracy by Model", status = "info", solidHeader = TRUE, plotOutput("plot_bal_acc", height = 300))
        )
      ),
      tabItem(
        tabName = "predictions",
        fluidRow(
          box(width = 12, title = "Compound-Level Predictions", status = "primary", solidHeader = TRUE, DTOutput("tbl_predictions"))
        ),
        fluidRow(
          box(width = 12, title = "Prediction Distribution", status = "info", solidHeader = TRUE, plotOutput("plot_prediction_risk", height = 300))
        )
      ),
      tabItem(
        tabName = "ad",
        fluidRow(
          box(width = 6, title = "Applicability Domain Registry", status = "primary", solidHeader = TRUE, DTOutput("tbl_ad_registry")),
          box(width = 6, title = "AD Status Distribution", status = "info", solidHeader = TRUE, plotOutput("plot_ad_distribution", height = 300))
        ),
        fluidRow(
          box(width = 12, title = "Compound AD Summary", status = "warning", solidHeader = TRUE, DTOutput("tbl_ad_summary"))
        )
      ),
      tabItem(
        tabName = "mechanistic",
        fluidRow(
          box(width = 4, title = "Endpoint", status = "primary", solidHeader = TRUE,
              selectInput("mechanistic_endpoint", "Choose endpoint", choices = unique(feature_importance$endpoint), selected = unique(feature_importance$endpoint)[1])),
          box(width = 8, title = "Top Feature Contributions", status = "info", solidHeader = TRUE, plotOutput("plot_feature_importance", height = 300))
        ),
        fluidRow(
          box(width = 6, title = "Feature Importance Table", status = "primary", solidHeader = TRUE, DTOutput("tbl_feature_importance")),
          box(width = 6, title = "Analog / Read-Across Support", status = "warning", solidHeader = TRUE, DTOutput("tbl_analog_support"))
        ),
        fluidRow(
          box(width = 12, title = "Mechanistic Rationale", status = "info", solidHeader = TRUE, DTOutput("tbl_mechanistic_rationale"))
        )
      ),
      tabItem(
        tabName = "decision",
        fluidRow(
          box(width = 12, title = "Weight-of-Evidence / Decision Summary", status = "primary", solidHeader = TRUE, DTOutput("tbl_woe"))
        )
      ),
      tabItem(
        tabName = "compliance",
        fluidRow(
          box(width = 5, title = "OECD / QSAR Checklist", status = "warning", solidHeader = TRUE, DTOutput("tbl_oecd_checklist")),
          box(width = 7, title = "Model Cards", status = "primary", solidHeader = TRUE, DTOutput("tbl_model_cards"))
        )
      ),
      tabItem(
        tabName = "reports",
        fluidRow(
          box(width = 12, title = "Export / Reporting Specification", status = "info", solidHeader = TRUE,
              tags$ul(
                tags$li(tags$strong("ISO preflight: "), "run ", tags$code("8) ISO Preflight (strict gate)"), " in the pipeline row (same checks as the red ISO Preflight control); evidence-governed train and ", tags$code("Run all steps"), " enforce this gate unless ", tags$code("PFAS_SKIP_ISO_PREFLIGHT"), " is set."),
                tags$li(tags$strong("ML validation (live): "), "after training, run step ", tags$code("16) Generate ML validation report (HTML)"), " below; artifact ", tags$code("results/ISO17025_ML_Validation_Report.html"), " plus ", tags$code("results/ml_validation_report_summary.txt"), "."),
                tags$li(tags$strong("Download: "), tags$code("Download ML validation report (HTML)"), " (same tab, pipeline runner row)."),
                tags$li("Prediction CSV — ", tags$code("results/nhanes_test_predictions.csv"), " when prediction step completes."),
                tags$li("ISO compliance narrative — ", tags$code("results/iso_compliance_report.json"), " / ", tags$code(".txt"), " from step 15."),
                tags$li("EPA ICIS-NPDES PFAS DMR slice — ", tags$code("data/processed/npdes_dmr_pfas_fy*.csv"), " from ", tags$code("scripts/filter_npdes_dmr_pfas.py"), " (effluent monitoring; not biosolids analytical chemistry)."),
                tags$li("Model cards / WoE exports — tables under Modeling / Compliance tabs (CSV exports where wired).")
              ),
              p(tags$em("Regulator / investor pack: archive HTML report, summary text, model_metadata.json, metrics JSON, leakage CSV, and split audit alongside your QMS validation record."))
          )
        ),
        fluidRow(
          box(
            width = 12,
            title = "PFAS External Data + Training Pipeline Runner",
            status = "warning",
            solidHeader = TRUE,
            textInput("pfas_python_exec", "Python executable", value = Sys.getenv("PFAS_PYTHON", if (file.exists(LOCAL_PYTHON_DEFAULT)) LOCAL_PYTHON_DEFAULT else "python"), placeholder = "python or your venv python path"),
            actionButton("btn_validate_python_exec", "Validate Python path", class = "btn-default"),
            checkboxInput("pfas_train_strict", "Training passes --strict (fail on leakage / unrealistic hold-out / TP=0 when positives exist / below min recall)", value = TRUE),
            checkboxInput("pfas_train_verbose", "Training verbose logging (-v)", value = FALSE),
            textInput(
              "pfas_train_min_recall_positive",
              "Optional minimum hold-out recall for class 1 (blank = omit; passes --min-recall-positive)",
              value = "",
              placeholder = "e.g. 0.05"
            ),
            numericInput(
              "pfas_holdout_threshold",
              "Hold-out decision threshold P≥ (confusion matrix / recall; screening default 0.25)",
              value = 0.25,
              min = 0.01,
              max = 0.99,
              step = 0.05
            ),
            helpText(
              "0.5 often yields TP=0 when probabilities sit below 0.5 (misleading accuracy on rare positives). ",
              "Lower tau improves recall but cuts precision (more negatives flagged per true positive — see flags per 10k in Reports). ",
              "Use ~0.25 as a recall-first screening default; open the training log probability summary and tune tau to match review capacity."
            ),
            verbatimTextOutput("pfas_python_status", placeholder = TRUE),
            textInput("epa_echo_urls", "EPA ECHO URL(s)", value = Sys.getenv("PFAS_ECHO_URLS", Sys.getenv("PFAS_ECHO_URL", "")), placeholder = "semicolon-separated direct URL(s)"),
            textInput("sdwis_urls", "SDWIS URL(s)", value = Sys.getenv("PFAS_SDWIS_URLS", Sys.getenv("PFAS_SDWIS_URL", "")), placeholder = "semicolon-separated direct URL(s)"),
            checkboxInput(
              "pfas_show_lab_artifact_schema_badges",
              "Show wet-lab / QMS schema badges (green/red) beside reference, method, QC, and PT paths",
              value = FALSE
            ),
            helpText(
              "Default OFF for screening / field / consultant workflows (no wet lab): paths stay informational — not an ISO 17025 readiness claim. ",
              "Turn ON only if you intentionally want template CSV schema checks next to each folder."
            ),
            textInput("pfas_ref_path", "PFAS Reference Data Path", value = file.path(PROJECT_DIR, "data", "external", "method_validation"), placeholder = "File or folder path for PFAS reference / validation datasets"),
            uiOutput("pfas_ref_path_badge"),
            textInput("pfas_method_path", "PFAS Method Data Path", value = file.path(PROJECT_DIR, "data", "external", "method_data"), placeholder = "File or folder path for EPA 533 / 537.1 / 1633 method data"),
            uiOutput("pfas_method_path_badge"),
            textInput("pfas_qc_path", "PFAS QC Data Path", value = file.path(PROJECT_DIR, "data", "external", "qc_datasets"), placeholder = "File or folder path for QC datasets"),
            uiOutput("pfas_qc_path_badge"),
            textInput("pfas_pt_path", "PFAS Proficiency Test Path", value = file.path(PROJECT_DIR, "data", "external", "proficiency_testing"), placeholder = "File or folder path for PT datasets"),
            uiOutput("pfas_pt_path_badge"),
            helpText(
              tags$strong("Matrix / role hints (informational): "),
              "Gray chips under each path summarize intended scientific role (not accreditation). ",
              "The reference-path row scans CSV/TSV/TXT names under your reference folder for serum vs UCMR vs AFFF vs calibration cues. ",
              "Bundled curated tables live under ", code("data/reference/nist/srm1957/"), ", ", code("nist/rm8446/"), ", ", code("nist/rm8690/"), " (see ", code("nist/manifest.json"), ") and ", code("data/reference/registry/"), ". ",
              tags$em("Note: "), "the default folder name ", code("method_validation"), " is historical — prefer reference/benchmark extracts here; wet-lab method validation reports belong only if you intentionally stage them for desk review. ",
              "Official pointers by matrix (ECHO/ICIS biosolids, NHANES PFAS, OTM-50 air, NIST vs UCMR scope): ",
              code("data/reference/registry/reference_registry_README.md"), "."
            ),
            tags$div(
              class = "alert",
              style = "background:#fff3e0;border:1px solid #ffb74d;color:#bf360c;padding:10px 14px;border-radius:4px;margin:8px 0 10px 0;",
              tags$p(style = "margin:0 0 8px 0;", tags$strong("SOP \u00a7 6 — Separate matrix pipelines")),
              tags$p(
                style = "margin:0 0 8px 0;",
                "Do ", tags$strong("not"), " merge drinking water, serum, biosolids/sludge, AFFF, methanol standards, and air emissions into one generalized PFAS prediction pool."
              ),
              tags$p(
                style = "margin:0;",
                "Canonical mapping: ", code("data/config/matrix_pipeline_sop.csv"), ". ",
                "Step 6) Build multi-source training table refuses multiple ", code("pipeline_lane"), " sources in one run (escape hatch for exploratory screening only: ",
                code("PFAS_ALLOW_MULTISOURCE_MERGE=1"), ")."
              )
            ),
            DT::dataTableOutput("tbl_matrix_pipeline_sop"),
            br(),
            tags$strong("Per-lane training tables (data/training/<pipeline_id>/training.csv):"),
            tags$div(
              style = "margin:6px 0 4px 0;color:#37474f;",
              tags$em(
                "Lanes are partitioned by ", code("lane_kind"),
                " in ", code("data/config/matrix_pipeline_sop.csv"), ". ",
                "Physiological body-burden lanes (human serum, ng/mL, wide format) are kept on a ",
                tags$strong("separate row"),
                " from environmental-occurrence lanes (ng/L or mg/kg, long format) and from reference-material lanes. ",
                "Cross-lane concatenation is refused at build time (SOP \u00a7 6)."
              )
            ),
            tags$div(
              style = "margin:4px 0 2px 0;color:#1b5e20;font-weight:600;",
              "Environmental-occurrence lanes (", tags$span(style = "font-family:monospace;font-weight:400;", "lane_kind=environmental_occurrence"), ")"
            ),
            fluidRow(
              column(12,
                actionButton("btn_lane_drinking_water", "Build lane: drinking_water (UCMR5)", class = "btn-info"),
                actionButton("btn_lane_biosolids_sludge", "Build lane: biosolids/sludge (1633 + EPA biosolids)", class = "btn-info"),
                actionButton("btn_lane_air_emissions", "Build lane: air emissions (OTM-50)", class = "btn-info")
              )
            ),
            tags$div(
              style = "margin:10px 0 2px 0;color:#4a148c;font-weight:600;",
              "Physiological body-burden lanes (", tags$span(style = "font-family:monospace;font-weight:400;", "lane_kind=physiological_biomonitoring"), ", ",
              tags$span(style = "font-family:monospace;font-weight:400;", "semantic_type=serum_biomonitoring"), ")"
            ),
            fluidRow(
              column(12,
                actionButton("btn_lane_serum", "Build lane: serum (NHANES + SRM 1957)", class = "btn-info", style = "background:#ede7f6;border-color:#9575cd;color:#311b92;"),
                tags$span(
                  style = "margin-left:10px;font-size:12px;color:#4a148c;",
                  "Governance boundary: ", code("validation/serum_v1/"),
                  " \u00b7 anchor CSV: ", code("data/training/serum/nhanes_serum_pfas_2017_2018.csv"),
                  " (SHA-256 ", code("dfd4dbb5\u20264490f"), ")",
                  " \u00b7 documented ingestion: ", code("scripts/convert_nhanes_xpt_to_csv.R")
                )
              )
            ),
            tags$div(
              class = "alert",
              style = "background:#ede7f6;border:1px solid #9575cd;color:#311b92;padding:10px 14px;border-radius:4px;margin:12px 0 10px 0;",
              tags$p(style = "margin:0 0 8px 0;",
                tags$strong("V1 serum PFOS/PFOA contextualization (governed, RUO)")),
              tags$p(style = "margin:0 0 8px 0;",
                "Population-reference percentiles against the precomputed weighted NHANES table ",
                code("data/reference_tables/nhanes_pfas_weighted_reference_tables_v1.csv"),
                ". ", tags$strong("Not"), " diagnostic, clinical, or regulatory. ",
                "Uses ", code("src/v1/"), " + ontology ", code("pfos_pfoa_v1.json"), "."),
              tags$p(style = "margin:0 0 6px 0;",
                "Template columns: ", code("sample_matrix"), ", ", code("result_unit"), ", ",
                code("source_program"), ", ", code("analyte"), ", ", code("result_value"),
                " (required); optional ", code("sex"), " (1=male, 2=female), ", code("age_years"), ", ",
                code("reference_cycle"), ", ", code("lod_code"), ". ",
                "Analytes: ", code("n_pfoa"), ", ", code("sb_pfoa"), ", ", code("n_pfos"), ", ",
                code("sm_pfos"), "."),
              tags$p(style = "margin:0;font-size:12px;color:#555;",
                "If ", code("sex"), "/", code("age_years"), " are blank, percentiles use ",
                code("sex_stratum=all"), " and ", code("age_group_stratum=all_ages"), ". ",
                "Merge demographics with ", code("scripts/enrich_v1_input_demographics.py"), ".")
            ),
            fluidRow(
              column(4,
                downloadButton(
                  "btn_download_v1_template",
                  "Download governed input template (CSV)",
                  class = "btn-default",
                  style = "margin-bottom:8px;width:100%;"
                ),
                fileInput(
                  "v1_input_csv",
                  "V1 input CSV (governed schema)",
                  accept = c(".csv", "text/csv")
                ),
                selectInput(
                  "v1_default_cycle",
                  "Default NHANES reference cycle",
                  choices = c("J (2017-2018)" = "J", "I (2015-2016)" = "I", "P (2017-2020 pre-pandemic)" = "P"),
                  selected = "J"
                ),
                actionButton(
                  "btn_v1_run",
                  "Run V1 contextualization",
                  class = "btn-primary",
                  style = "background:#5e35b1;border-color:#4527a0;width:100%;"
                )
              ),
              column(8,
                verbatimTextOutput("v1_context_status", placeholder = TRUE),
                tags$div(style = "margin:8px 0;",
                  downloadButton("btn_download_v1_report_csv", "Download report CSV", class = "btn-info"),
                  downloadButton("btn_download_v1_report_pdf", "Download report PDF (RUO stub)", class = "btn-info"),
                  downloadButton("btn_download_v1_manifest", "Download provenance manifest (JSON)", class = "btn-default")
                ),
                tags$strong("V1 report preview (percentile + strata shown):"),
                DT::dataTableOutput("tbl_v1_report")
              )
            ),
            tags$div(
              class = "alert",
              style = "background:#e0f2f1;border:1px solid #00897b;color:#004d40;padding:10px 14px;border-radius:4px;margin:18px 0 10px 0;",
              tags$p(style = "margin:0 0 8px 0;",
                tags$strong("V2 cross-cycle temporal contextualization (governed, RUO)")),
              tags$p(style = "margin:0 0 8px 0;",
                "Compares weighted NHANES population percentiles across cycles ",
                code("I"), ", ", code("J"), ", and ", code("P"),
                " for the same demographic stratum. ",
                tags$strong("Not"), " individual longitudinal follow-up. ",
                "Uses ", code("src/v2/"), " + ontology ", code("pfos_pfoa_v2.json"), "."),
              tags$p(style = "margin:0 0 6px 0;",
                "Requires ", code("reference_cycle"), " (anchor I/J/P) on every row; optional ",
                code("sex"), ", ", code("age_years"), ", ", code("race_ethnicity"), ", ",
                code("lod_code"), ".")
            ),
            fluidRow(
              column(4,
                fileInput(
                  "v2_input_csv",
                  "V2 input CSV (V1.1 schema + reference_cycle)",
                  accept = c(".csv", "text/csv")
                ),
                actionButton(
                  "btn_v2_run",
                  "Run V2 cross-cycle contextualization",
                  class = "btn-primary",
                  style = "background:#00695c;border-color:#004d40;width:100%;"
                )
              ),
              column(8,
                verbatimTextOutput("v2_context_status", placeholder = TRUE),
                tags$div(style = "margin:8px 0;",
                  downloadButton("btn_download_v2_report_csv", "Download V2 report CSV", class = "btn-info"),
                  downloadButton("btn_download_v2_report_pdf", "Download V2 report PDF (RUO stub)", class = "btn-info"),
                  downloadButton("btn_download_v2_manifest", "Download V2 manifest (JSON)", class = "btn-default")
                ),
                tags$strong("V2 report preview (cross-cycle percentiles):"),
                DT::dataTableOutput("tbl_v2_report")
              )
            ),
            tags$div(
              style = "margin:10px 0 2px 0;color:#bf360c;font-weight:600;",
              "Reference-material lanes (", tags$span(style = "font-family:monospace;font-weight:400;", "lane_kind=reference_material"), ")"
            ),
            fluidRow(
              column(12,
                actionButton("btn_lane_afff", "Build lane: AFFF (RM 8690)", class = "btn-info"),
                actionButton("btn_lane_methanol_standards", "Build lane: methanol standards (RM 8446)", class = "btn-info")
              )
            ),
            br(),
            fluidRow(
              column(12,
                actionButton("btn_lane_all", "Build all 6 lanes separately (across all 3 lane_kinds)", class = "btn-warning")
              )
            ),
            verbatimTextOutput("matrix_pipeline_status", placeholder = TRUE),
            DT::dataTableOutput("tbl_matrix_pipeline_outputs"),
            br(),
            tags$div(
              class = "alert",
              style = "background:#fdecea;border:1px solid #f5c6cb;color:#721c24;padding:10px 14px;border-radius:4px;margin:8px 0 10px 0;",
              tags$p(style = "margin:0 0 8px 0;",
                tags$strong("Applicability-domain enforcement (hard refusal)")),
              tags$p(style = "margin:0 0 8px 0;",
                "Predictions and uploads outside the validated per-lane training envelope are ",
                tags$strong("refused"), ", not silently warned. Each row is annotated with ",
                code("ad_status"), " / ", code("ad_distance"), " / ", code("ad_reason"), " / ",
                code("reference_lane"), " / ", code("training_range_version"), " / ",
                code("ad_model_version"), " / ", code("ad_threshold"), " / ",
                code("nearest_training_source"), " / ", code("ad_method"),
                ". Refused rows have their analytical result columns blanked."),
              tags$p(style = "margin:0;",
                "AD models live in ", code("data/ad_models/<lane>/ad_model.json"),
                " and every decision is appended to ", code("data/audit/ad_decisions.jsonl"), ".")
            ),
            fluidRow(
              column(12,
                actionButton("btn_ad_rebuild_all", "Rebuild AD models (all 6 lanes)", class = "btn-warning"),
                actionButton("btn_ad_refresh_audit", "Refresh audit log view", class = "btn-default")
              )
            ),
            br(),
            fluidRow(
              column(4,
                fileInput("ad_input_csv", "Candidate CSV to gate (per-lane AD)",
                          accept = c(".csv", "text/csv"))),
              column(4,
                selectInput("ad_lane_select", "Reference lane",
                            choices = list(
                              "(auto: use pipeline_lane column)" = "",
                              "Environmental-occurrence lanes" = list(
                                "drinking_water"   = "drinking_water",
                                "biosolids_sludge" = "biosolids_sludge",
                                "air_emissions"    = "air_emissions"
                              ),
                              "Physiological body-burden lanes (serum_biomonitoring)" = list(
                                "serum" = "serum"
                              ),
                              "Reference-material lanes" = list(
                                "afff"               = "afff",
                                "methanol_standards" = "methanol_standards"
                              )
                            ),
                            selected = "")),
              column(4,
                radioButtons("ad_mode", "Refusal mode",
                             choices = c("strict (blank rejected rows)" = "strict",
                                         "annotate only" = "annotate"),
                             selected = "strict", inline = FALSE))
            ),
            actionButton("btn_ad_run_guard", "Run AD guard on candidate CSV", class = "btn-danger"),
            verbatimTextOutput("ad_guard_status", placeholder = TRUE),
            uiOutput("ad_guard_counts"),
            tags$strong("AD-annotated output (head):"),
            DT::dataTableOutput("tbl_ad_guard_output"),
            br(),
            tags$strong("AD decisions audit log (data/audit/ad_decisions.jsonl, tail 100):"),
            DT::dataTableOutput("tbl_ad_audit"),
            br(),
            tags$div(
              class = "alert",
              style = "background:#e8eaf6;border:1px solid #9fa8da;color:#1a237e;padding:10px 14px;border-radius:4px;margin:8px 0 10px 0;",
              tags$p(style = "margin:0 0 8px 0;",
                tags$strong("Sealed external blind validation (preregistration-grade)")),
              tags$p(style = "margin:0 0 8px 0;",
                "Submissions are hash-sealed before any scoring. Once sealed, the four ground rules apply: ",
                tags$strong("no retuning, no threshold change, no model change, no dataset editing after hash submission."),
                " Reveals are ", tags$strong("single-shot"), "; the scorer refuses to re-run unless ",
                code("--force"), " is passed, and any sealed-byte tampering causes ",
                code("dataset_sha256_mismatch"), " refusal."),
              tags$p(style = "margin:0;",
                "Sealed packs live in ", code("validation/blind_external/sealed/<id>/"),
                "; reveals in ", code("validation/blind_external/revealed/<id>/score.json"),
                "; submission and reveal indexes in ",
                code("validation/blind_external/manifests/"), ".")
            ),
            fluidRow(
              column(4, fileInput("bv_input_csv",
                                  "Candidate validation CSV (must include truth + predicted columns)",
                                  accept = c(".csv", "text/csv"))),
              column(4, selectInput("bv_lane", "Matrix lane",
                                    choices = list(
                                      "Environmental-occurrence lanes" = list(
                                        "drinking_water"   = "drinking_water",
                                        "biosolids_sludge" = "biosolids_sludge",
                                        "air_emissions"    = "air_emissions"
                                      ),
                                      "Physiological body-burden lanes (serum_biomonitoring)" = list(
                                        "serum" = "serum"
                                      ),
                                      "Reference-material lanes" = list(
                                        "afff"               = "afff",
                                        "methanol_standards" = "methanol_standards"
                                      )
                                    ),
                                    selected = "drinking_water")),
              column(4, textInput("bv_submitted_by", "Submitted by",
                                  placeholder = "lab / institution / submitter id"))
            ),
            fluidRow(
              column(3, textInput("bv_truth_col", "Truth column (binary 0/1)",
                                  value = "truth_label")),
              column(3, textInput("bv_score_col", "Predicted score column (optional, continuous)",
                                  value = "predicted_score")),
              column(3, textInput("bv_label_col", "Predicted label column (optional, 0/1)",
                                  value = "predicted_label")),
              column(3, textInput("bv_model_version", "Model version",
                                  placeholder = "e.g. mymodel_v1.2+commit_abc1234"))
            ),
            textAreaInput("bv_note", "Note (optional)", value = "",
                          rows = 2, width = "100%"),
            actionButton("btn_bv_seal", "Seal submission (hash + lock)",
                         class = "btn-primary"),
            actionButton("btn_bv_score", "Score a sealed submission",
                         class = "btn-success"),
            actionButton("btn_bv_force_score", "Force re-score (records prior reveal archive)",
                         class = "btn-warning"),
            actionButton("btn_bv_refresh", "Refresh indexes",
                         class = "btn-default"),
            br(), br(),
            selectInput("bv_submission_id", "Sealed submission to score",
                        choices = character(0), selectize = TRUE),
            verbatimTextOutput("bv_status", placeholder = TRUE),
            uiOutput("bv_score_pills"),
            tags$strong("Submissions index (validation/blind_external/manifests/submissions_index.jsonl):"),
            DT::dataTableOutput("tbl_bv_submissions"),
            br(),
            tags$strong("Reveals index (validation/blind_external/manifests/reveals_index.jsonl):"),
            DT::dataTableOutput("tbl_bv_reveals"),
            helpText("These fields are optional. If set, they are passed to downloader scripts as PFAS_ECHO_URLS and PFAS_SDWIS_URLS."),
            helpText(
              tags$strong("EPA ICIS-NPDES (ECHO bulk downloads): "),
              "Facility/compliance + DMR fiscal-year ZIPs + outfalls + ",
              tags$code("REF_Parameter.csv"),
              ". ",
              tags$a(href = "https://echo.epa.gov/tools/data-downloads", "ECHO Data Downloads", target = "_blank", rel = "noopener"),
              ". ",
              tags$em("Biosolids ZIP is program metadata, not national PFAS sludge concentrations; DMR is effluent monitoring — do not merge with NHANES serum rows."),
              " UI tag: ", tags$code(ICIS_NPDES_UI_VERSION), "."
            ),
            fluidRow(
              column(4, textInput("epa_icis_dmr_years", "ICIS DMR fiscal years (comma-separated)", value = "2024,2025")),
              column(
                4,
                checkboxInput("epa_icis_include_limits", "Also download national permit limits ZIP (~459 MB)", value = FALSE)
              ),
              column(4, textInput("epa_icis_filter_fy", "Python DMR filter FY", value = "2024", placeholder = "e.g. 2024"))
            ),
            actionButton("btn_bootstrap_source_folders", "Bootstrap source folders", class = "btn-default"),
            actionButton("btn_iso_preflight", "ISO Preflight (strict gate)", class = "btn-danger"),
            tags$div(
              class = "alert",
              style = "background:#e3f2fd;border:1px solid #90caf9;color:#0d47a1;padding:10px 14px;border-radius:4px;margin:8px 0 10px 0;",
              uiOutput("ml_workflow_mode_badge"),
              tags$p(
                style = "margin:8px 0 0 0;",
                tags$strong("Evidence-governed path: "),
                "Step 9 and External ",
                tags$strong("Train (Evidence-Governed)"),
                " run only after ISO preflight passes (reference, method, QC, PT evidence)."
              ),
              tags$p(
                style = "margin:6px 0 0 0;",
                tags$strong("Exploratory screening path: "),
                tags$em("ISO / QC / PT evidence gates are not enforced. "),
                "Use for research, prioritization, and workflow evaluation only — not for regulated compliance claims, not as laboratory validation, and not a substitute for analyst review."
              )
            ),
            verbatimTextOutput("source_bootstrap_status", placeholder = TRUE),
            verbatimTextOutput("iso_data_paths_status", placeholder = TRUE),
            verbatimTextOutput("iso_preflight_status", placeholder = TRUE),
            fluidRow(
              column(12,
                actionButton("btn_pfas_download", "1) Download baseline NHANES + ECHO note", class = "btn-primary"),
                actionButton("btn_epa_ucmr5_download", "2) Download EPA UCMR5", class = "btn-info"),
                actionButton("btn_epa_icis_npdes_download", "2b) ICIS-NPDES (ECHO bulk)", class = "btn-info"),
                actionButton("btn_epa_icis_filter_dmr", "2c) DMR→PFAS CSV", class = "btn-info"),
                actionButton("btn_epa_echo_download", "3) Download EPA ECHO source", class = "btn-info"),
                actionButton("btn_epa_sdwis_download", "4) Download SDWIS source", class = "btn-info"),
                actionButton("btn_pfas_prepare", "5) Prepare baseline training table", class = "btn-info"),
                actionButton("btn_pfas_multisource", "6) Build multi-source training table", class = "btn-info"),
                actionButton("btn_pfas_matrix", "7) Build model matrix", class = "btn-info"),
                actionButton("btn_pfas_pipeline_iso_preflight", "8) ISO Preflight (strict gate)", class = "btn-danger"),
                actionButton("train_pfas_model", "9) Train PFAS Exceedance Model (Evidence-Governed)", class = "btn-success"),
                actionButton("train_pfas_model_screening", "Screening — Train PFAS Exceedance (Exploratory)", class = "btn-info"),
                actionButton("run_pfas_prediction", "10) Run PFAS Prediction", class = "btn-success"),
                actionButton("btn_nist_reference_validation", "10b) NIST SRM reference validation", class = "btn-info"),
                actionButton("btn_validate_reference_dataset", "11) Load reference dataset", class = "btn-info"),
                actionButton("btn_qc_validation_check", "12) QC validation check", class = "btn-info"),
                actionButton("btn_applicability_domain_check", "13) Applicability domain check", class = "btn-info"),
                actionButton("btn_external_pt_validation", "14) External validation (PT)", class = "btn-info"),
                actionButton("btn_generate_iso_compliance_report", "15) Generate ISO compliance report", class = "btn-warning"),
                actionButton("btn_generate_ml_validation_report", "16) Generate ML validation report (HTML)", class = "btn-warning"),
                downloadButton("dl_ml_validation_report", "Download ML validation report (HTML)", class = "btn-default"),
                actionButton("btn_pfas_run_all", "Run all steps", class = "btn-warning")
              )
            ),
            br(),
            fluidRow(
              column(
                6,
                fileInput(
                  "qc_dataset_file",
                  "QC dataset input (lab QC results)",
                  accept = c(".csv", ".tsv", ".txt", ".xlsx", ".xls", ".json")
                )
              ),
              column(
                6,
                fileInput(
                  "pt_dataset_file",
                  "PT dataset input (proficiency testing)",
                  accept = c(".csv", ".tsv", ".txt", ".xlsx", ".xls", ".json")
                )
              )
            ),
            br(),
            verbatimTextOutput("qc_pt_upload_status", placeholder = TRUE),
            br(),
            verbatimTextOutput("pfas_pipeline_log", placeholder = TRUE),
            tags$div(
              class = "alert",
              style = "background:#e8f5e9;border:1px solid #a5d6a7;color:#1b5e20;padding:10px 14px;border-radius:4px;margin:12px 0 8px 0;",
              tags$p(
                style = "margin:0 0 8px 0;",
                tags$strong("NIST SRM serum reference metadata"),
                " (from last validation run). ",
                tags$em("Physiological / body-burden workflows only"),
                " — not for drinking-water MCL, ISO 17025 lab validation, or environmental recovery claims."
              ),
              tableOutput("nist_reference_audit_table")
            ),
            hr(),
            tags$strong("Schema & folder readiness (not lab validation)"),
            tags$div(
              class = "alert",
              style = "background:#fff8e1;border:1px solid #ffcc80;color:#4e342e;padding:10px 14px;border-radius:4px;margin:10px 0 12px 0;",
              tags$p(
                style = "margin:0 0 8px 0;",
                tags$strong("What a check means: "),
                "file exists and a non-template dataset matches the expected column header pattern (and you are not looking at data quality, provenance, traceability, or ISO/IEC 17025 laboratory validation)."
              ),
              tags$p(
                style = "margin:0;",
                tags$strong("What it does not mean: "),
                "certified reference materials, real QC/PT performance, method fitness-for-purpose, regulator-ready evidence, or “ISO compliant” analytics."
              ),
              tags$p(
                style = "margin:8px 0 0 0;font-style:italic;",
                "Public framing: the platform supports ISO-",
                tags$em("aligned"), " structures and workflow hooks; it is ",
                tags$strong("not"), " a replacement for accredited laboratory validation."
              )
            ),
            helpText(
              "Preflight template CSVs are ignored for these rows. Screening-only / desk workflows may leave QC, PT, or reference rows unchecked unless you add real exports."
            ),
            DTOutput("tbl_pipeline_component_status")
          )
        ),
        fluidRow(
          box(
            width = 12,
            title = "External ML Data Upload (Upload -> Preview -> Map -> Validate -> Normalize -> Save -> Train)",
            status = "primary",
            solidHeader = TRUE,
            fileInput(
              # Server must use input$external_ml_file (same id everywhere; not external_upload).
              "external_ml_file",
              "Upload data file",
              accept = c(".csv", ".tsv", ".txt", ".xlsx", ".xls", ".json", ".parquet", ".rds", ".xpt")
            ),
            uiOutput("icis_air_external_upload_banner"),
            uiOutput("serum_external_upload_banner"),
            uiOutput("serum_external_autodetect_summary"),
            helpText(
              tags$strong("UCMR5 / EPA text: "),
              "This panel expects a ",
              tags$em("single, uniform delimited table"),
              " (comma, tab, pipe, or semicolon). For PFAS drinking-water occurrence rows, prefer method result files such as ",
              code("UCMR5_533.txt"), ", ", code("UCMR5_537_1.txt"), ", or ", code("UCMR5_200_7.txt"),
              " from the EPA zip—not supplemental/reference extracts (e.g. ",
              code("UCMR5_AddtlDataElem.txt"), ", ", code("UCMR5_ZIPCodes.txt"), "), which are not ML measurement tables. ",
              "Some aggregated EPA ", code(".txt"), " exports are ragged or wide; if upload fails, inspect with ",
              code("readLines(..., n = 20)"), " and pre-convert to CSV (e.g. ", code("read.delim"), " + ", code("write.csv"), "). ",
              "Smoke test: ", code("data/test_upload/test_upload.csv"), ". ",
              "If R ", code("read.delim"), " errors on ", code("µg/L"), ", use ", code("fileEncoding = \"latin1\""),
              " then ", code("write.csv(..., fileEncoding = \"UTF-8\")"), " (matches this app’s read order: Latin-1 before UTF-8 after BOM). ",
              "Delimited uploads are read with all columns as text (no ", code("type.convert"), ") so messy EPA rows still preview. ",
              "Huge CSVs (>~200MB) need enough RAM for a single ", code("read.table"), " pass; use a 1–5k-row sample for Snappy UI preview."
            ),
            helpText(
              tags$strong("Suggested inputs by role: "),
              code("PFASSTRUCT.csv"), " (CompTox ", tags$em("PFASSTRUCT"), " export) for registry / QSAR-style chemical tables; ",
              code("UCMR5_533_sample.csv"), " (or equivalent small CSV) for environmental-occurrence upload tests; ",
              "NHANES PFAS lab + linked demographics when ", tags$strong("Dataset type"), " is ",
              tags$em("human biomonitoring"), ". ",
              tags$strong("Reference / bench: "), "NIST SRM/RM extracts (e.g. under ", code("data/reference/nist/"), ") are ",
              tags$em("not"), " UCMR occurrence tables—set ", tags$strong("Dataset type"), " to ",
              tags$em("reference material (NIST / RM / bench)"), " and map ", code("matrix"), ", ", code("analyte"), ", ",
              code("value"), " / ", code("uncertainty"), " columns; for governed serum benchmarking prefer the in-app ",
              tags$strong("10b) NIST SRM reference validation"), " step instead of mixing matrices into training. ",
              "EPA/CDC/NIST source list by matrix: ", code("data/reference/registry/reference_registry_README.md"), "."
            ),
            selectInput(
              "external_dataset_type",
              "Dataset type",
              choices = c(
                "human biomonitoring",
                "environmental occurrence",
                "facility enrichment",
                "method validation",
                "reference material (NIST / RM / bench)",
                "unknown/custom"
              ),
              selected = "environmental occurrence"
            ),
            verbatimTextOutput("external_file_meta", placeholder = TRUE),
            verbatimTextOutput("external_reference_preflight_status", placeholder = TRUE),
            DTOutput("tbl_external_preview"),
            hr(),
            uiOutput("external_map_ui"),
            br(),
            actionButton("btn_external_validate", "Validate"),
            actionButton("btn_external_normalize", "Normalize"),
            actionButton("btn_external_save", "Save"),
            actionButton("btn_external_train", "Train (Evidence-Governed)", class = "btn-success"),
            actionButton("btn_external_train_screening", "Screening — Train (Exploratory)", class = "btn-info"),
            br(), br(),
            verbatimTextOutput("external_quality_status", placeholder = TRUE),
            tags$strong("Strict schema validation (ISO ingest gate)"),
            verbatimTextOutput("external_strict_schema_status", placeholder = TRUE),
            verbatimTextOutput("external_save_status", placeholder = TRUE)
          )
        ),
        fluidRow(
          box(
            width = 12,
            title = "Label integrity dashboard",
            status = "warning",
            solidHeader = TRUE,
            p(
              tags$strong("Purpose: "), "Judge whether ",
              code("PFAS_Risk_Flag"), " labels are trustworthy before trusting model metrics."
            ),
            p(
              "Primary source: ",
              code("results/label_derivation_audit.json"),
              ". Row-drop total is aligned with ",
              code("dataset_builder_stages"),
              " in ",
              code("results/python_training_row_reconciliation.json"),
              "."
            ),
            uiOutput("pfas_label_integrity_banner"),
            verbatimTextOutput("pfas_label_integrity_summary", placeholder = TRUE),
            h4(style = "margin-top:16px;", "Top analytes with numeric result but no joined limit"),
            DTOutput("tbl_pfas_label_integrity_missing")
          )
        ),
        fluidRow(
          box(
            width = 12,
            title = "PFAS Exceedance ML Results (scripts outputs)",
            status = "primary",
            solidHeader = TRUE,
            p(
              "Reads artifacts from ", code("results/"), " (evidence-governed trains) or ", code("results/screening/"),
              " (exploratory screening trains), generated by ", code("python scripts/train_pfas_model.py"), " (PFAS exceedance pipeline)."
            ),
            p(
              tags$em(
                "Screening-level decision support only. Do not replace ISO/IEC 17025 laboratory analytical reporting, analyst review, or validated method release."
              )
            ),
            verbatimTextOutput("pfas_metrics_status", placeholder = TRUE),
            hr(),
            p("Multi-source training target tracker (100,000,000 rows):"),
            verbatimTextOutput("pfas_target_status", placeholder = TRUE)
          )
        ),
        fluidRow(
          box(
            width = 12,
            title = "Training Freshness Status",
            status = "info",
            solidHeader = TRUE,
            verbatimTextOutput("pfas_last_training_status", placeholder = TRUE)
          )
        ),
        fluidRow(
          box(
            width = 12,
            title = "Task Rows Currently Available (pre-train check)",
            status = "primary",
            solidHeader = TRUE,
            DTOutput("tbl_task_row_availability")
          )
        ),
        fluidRow(
          box(width = 4, title = "Human Health Task", status = "success", solidHeader = TRUE, verbatimTextOutput("pfas_task_human_status", placeholder = TRUE)),
          box(width = 4, title = "Environmental Task", status = "info", solidHeader = TRUE, verbatimTextOutput("pfas_task_environment_status", placeholder = TRUE)),
          box(width = 4, title = "Facility Enrichment Task", status = "warning", solidHeader = TRUE, verbatimTextOutput("pfas_task_facility_status", placeholder = TRUE))
        ),
        fluidRow(
          box(
            width = 12,
            title = "Task Comparison (AUC / Accuracy / Train / Test)",
            status = "primary",
            solidHeader = TRUE,
            DTOutput("tbl_pfas_task_comparison")
          )
        ),
        fluidRow(
          box(width = 6, title = "Feature Importance", status = "info", solidHeader = TRUE, DTOutput("tbl_pfas_feature_importance")),
          box(width = 6, title = "Test Predictions", status = "warning", solidHeader = TRUE, DTOutput("tbl_pfas_test_predictions"))
        )
      ),
      tabItem(
        tabName = "glp",
        fluidRow(
          box(
            width = 12,
            title = "PFAS Enterprise 5.0 — ISO 17025 / on-prem GLP mode",
            status = "primary",
            solidHeader = TRUE,
            p(
              "The public demo at ", tags$a(href = "https://ishola-github.shinyapps.io/pfas-epa-method/", "shinyapps.io"),
              " is for prototyping only. For regulated studies, deploy ",
              strong("on qualified infrastructure"), " (access control, backups, NTP, monitored storage) and execute IQ/OQ/PQ per your QMS."
            ),
            p(
              "Artifacts: ",
              code("validation/IQ/Installation_Qualification_Template.md"), ", ",
              code("validation/test_cases/EPA_Method_1633_Test_Cases.csv"), ", ",
              code("validation/test_cases/EPA_Method_1633_Validation_Protocol.md"), "."
            ),
            checkboxInput("iso17025_strict_ui", "ISO 17025 mode: emphasize required QC fields in forms", value = TRUE)
          )
        ),
        fluidRow(
          box(
            width = 4, title = "Operator identity (audit)", status = "warning", solidHeader = TRUE,
            p("Sign in with ", strong("shinymanager"), ". Default accounts: ", code("admin"), " / ", code("admin123"), ", ", code("analyst"), " / ", code("analyst123"), "."),
            checkboxInput("use_login_as_operator", "Use authenticated user for audit, QC, CAPA, and exports (recommended)", value = TRUE),
            textInput("glp_operator_id", "Override operator ID (break-glass / testing only)", value = "", placeholder = "leave blank if using login"),
            helpText("In production, keep the checkbox on and manage users via the ", code("app_login_users"), " table or shinymanager admin."),
            verbatimTextOutput("auth_user_display", placeholder = TRUE)
          ),
          box(
            width = 8, title = "Audit trail integrity (SHA-256 chain)", status = "info", solidHeader = TRUE,
            verbatimTextOutput("glp_chain_status", placeholder = TRUE),
            actionButton("glp_verify_chain_btn", "Re-verify hash chain", class = "btn-info"),
            helpText("Append-only hash chain is stored in table ", code("glp_audit_trail"), ".")
          )
        ),
        fluidRow(
          box(
            width = 12, title = "Quality system modules", status = "primary", solidHeader = TRUE,
            tabsetPanel(
              id = "iso_tabset",
              tabPanel(
                title = "IQ & validation pack",
                icon = icon("file-alt"),
                fluidRow(
                  box(
                    width = 12, status = "info", solidHeader = TRUE,
                    title = "Installation Qualification (IQ)",
                    p("Complete the IQ checklist in the template, then archive signed PDFs per your document control procedure."),
                    downloadButton("dl_iq_template_md", "Download IQ template (.md)"),
                    downloadButton("dl_epa1633_protocol_md", "Download EPA 1633 validation protocol (.md)"),
                    downloadButton("dl_epa1633_tests_csv", "Download EPA 1633 test case list (.csv)")
                  )
                )
              ),
              tabPanel(
                title = "Audit trails",
                icon = icon("history"),
                fluidRow(
                  box(width = 12, title = "GLP hash-chained audit", DTOutput("tbl_glp_audit")),
                  box(width = 12, title = "Legacy audit_log", DTOutput("tbl_legacy_audit")),
                  box(
                    width = 12, title = "Partner intake admin view (operational review)",
                    helpText("Reads recent partner_intake_submit records from a local SQLite mirror table or CSV mirror file."),
                    fluidRow(
                      column(3, numericInput("partner_audit_limit", "Rows", value = 50, min = 10, max = 500, step = 10)),
                      column(3, br(), actionButton("btn_partner_audit_refresh", "Refresh partner intake", class = "btn-default")),
                      column(6, br(), verbatimTextOutput("partner_audit_status", placeholder = TRUE))
                    ),
                    DTOutput("tbl_partner_intake_admin")
                  ),
                  box(
                    width = 12, title = "Exports & WORM archive",
                    downloadButton("dl_glp_audit_csv", "Download GLP audit CSV (controlled copy)"),
                    hr(),
                    verbatimTextOutput("worm_dir_status", placeholder = TRUE),
                    actionButton("btn_worm_archive", "Write timestamped snapshot to WORM directory (PFAS_GLP_WORM_DIR)", class = "btn-warning"),
                    helpText("Creates CSV + .sha256 + .meta.json. Point ", code("PFAS_GLP_WORM_DIR"), " at secured, monitored storage; enforce immutability with IT controls.")
                  )
                )
              ),
              tabPanel(
                title = "EPA 1633 tests",
                icon = icon("flask"),
                fluidRow(
                  box(width = 12, title = "Test case library (database)", DTOutput("tbl_epa1633_cases")),
                  box(
                    width = 6, title = "Record test run",
                    selectInput("v_test_case_id", "Test case ID", choices = NULL),
                    textInput("v_protocol_ref", "Protocol / SOP reference", value = "EPA 1633 / LAB-SOP-1633"),
                    selectInput("v_pass_fail", "Result", choices = c("Pass", "Fail", "N/A")),
                    textAreaInput("v_evidence_notes", "Evidence / deviation notes"),
                    actionButton("btn_save_validation_result", "Save validation result", class = "btn-primary")
                  ),
                  box(width = 6, title = "Recorded runs", DTOutput("tbl_validation_results"))
                )
              ),
              tabPanel(
                title = "CAPA",
                icon = icon("wrench"),
                fluidRow(
                  box(
                    width = 5, title = "Open CAPA",
                    textInput("capa_title", "Title"),
                    textAreaInput("capa_description", "Description"),
                    selectInput("capa_priority", "Priority", choices = c("Low", "Medium", "High", "Critical")),
                    textInput("capa_linked_type", "Linked entity type (optional)", placeholder = "measurement / batch / instrument"),
                    textInput("capa_linked_id", "Linked entity ID (optional)"),
                    actionButton("btn_save_capa", "Open CAPA", class = "btn-warning")
                  ),
                  box(width = 7, title = "CAPA register", DTOutput("tbl_capa"))
                )
              ),
              tabPanel(
                title = "Approvals & e-sign",
                icon = icon("pen-fancy"),
                fluidRow(
                  box(
                    width = 5, title = "Approval request",
                    textInput("apr_object_type", "Object type", value = "analytical_batch"),
                    textInput("apr_object_id", "Object ID"),
                    selectInput("apr_step", "Step", choices = c("QC review", "Technical review", "QA release")),
                    actionButton("btn_request_approval", "Submit for approval", class = "btn-primary")
                  ),
                  box(
                    width = 4, title = "Decide approval",
                    uiOutput("apr_select_ui"),
                    selectInput("apr_decision", "Decision", choices = c("approved", "rejected")),
                    textAreaInput("apr_rationale", "Rationale"),
                    actionButton("btn_decide_approval", "Record decision", class = "btn-success")
                  ),
                  box(
                    width = 3, title = "Electronic signature",
                    textInput("esig_record_type", "Record type"),
                    textInput("esig_record_id", "Record ID"),
                    textInput("esig_meaning", "Signature meaning", value = "I approve this record."),
                    actionButton("btn_esig", "Apply e-signature (intent + user ID)", class = "btn-danger")
                  ),
                  box(width = 12, title = "Approval queue", DTOutput("tbl_approvals")),
                  box(width = 12, title = "Signatures", DTOutput("tbl_esig"))
                )
              ),
              tabPanel(
                title = "QC batches",
                icon = icon("vials"),
                fluidRow(
                  box(
                    width = 4, title = "QC batch log",
                    textInput("qc_batch_id", "Batch / run ID"),
                    textInput("qc_matrix", "Matrix"),
                    dateInput("qc_run_date", "Run date", value = Sys.Date()),
                    checkboxInput("qc_blanks_ok", "Method blanks acceptable", value = TRUE),
                    checkboxInput("qc_checks_ok", "LCS/MS checks acceptable", value = TRUE),
                    checkboxInput("qc_cal_ok", "Calibration / ICV / CCV acceptable", value = TRUE),
                    selectInput("qc_overall", "Overall status", choices = c("Accept", "Hold", "Reject")),
                    textAreaInput("qc_notes", "Notes"),
                    actionButton("btn_save_qc", "Save QC batch", class = "btn-primary")
                  ),
                  box(width = 8, title = "QC history", DTOutput("tbl_qc_batch"))
                )
              ),
              tabPanel(
                title = "Training",
                icon = icon("graduation-cap"),
                fluidRow(
                  box(
                    width = 4, title = "Training record",
                    textInput("tr_user", "User ID"),
                    textInput("tr_topic", "Topic", value = "EPA Method 1633"),
                    dateInput("tr_completed", "Completed", value = Sys.Date()),
                    textInput("tr_trainer", "Trainer"),
                    dateInput("tr_expiry", "Expiry (re-train by)", value = Sys.Date() + 365),
                    textInput("tr_evidence", "Evidence reference (SOP quiz, certificate #)"),
                    actionButton("btn_save_training", "Save training", class = "btn-primary")
                  ),
                  box(width = 8, title = "Training log", DTOutput("tbl_training"))
                )
              ),
              tabPanel(
                title = "Calibration",
                icon = icon("tachometer-alt"),
                fluidRow(
                  box(
                    width = 4, title = "Calibration entry",
                    textInput("cal_instrument", "Instrument ID"),
                    textInput("cal_parameter", "Parameter (e.g. mass axis, flow)"),
                    numericInput("cal_nominal", "Nominal", value = NA),
                    numericInput("cal_measured", "As-found / as-left", value = NA),
                    numericInput("cal_tol_pct", "Tolerance %", value = 5),
                    selectInput("cal_pass", "Within tolerance", choices = c("Pass" = "pass", "Fail" = "fail"), selected = "pass"),
                    dateInput("cal_next", "Next due", value = Sys.Date() + 180),
                    textInput("cal_cert", "Certificate reference"),
                    actionButton("btn_save_cal", "Save calibration", class = "btn-primary")
                  ),
                  box(width = 8, title = "Calibration log", DTOutput("tbl_calibration"))
                )
              )
            )
          )
        )
      ),
      tabItem(
        tabName = "iso_blind_spots",
        fluidRow(
          box(
            title = "ISO/IEC 17025 Readiness",
            width = 12,
            status = "warning",
            solidHeader = TRUE,
            tags$h4(style = "margin-top:0;", "Summary (", tags$code("iso_readiness_score.json"), ")"),
            verbatimTextOutput("iso_score_text"),
            br(),
            tags$h4("Blind spot register (", tags$code("iso_blind_spots_report.csv"), ")"),
            DT::dataTableOutput("iso_blindspots_table"),
            br(),
            htmlOutput("iso_disclaimer")
          )
        )
      ),
      tabItem(
        tabName = "scope",
        fluidRow(
          box(
            width = 12,
            title = "Scope, positioning, and limitations",
            status = "warning",
            solidHeader = TRUE,
            tags$div(
              style = "max-height: 78vh; overflow-y: auto; padding-right: 12px;",
              if (file.exists(DISCLAIMER_MD_PATH)) {
                includeMarkdown(DISCLAIMER_MD_PATH)
              } else {
                tagList(
                  tags$p(
                    "The file ",
                    tags$code("DISCLAIMER.md"),
                    " was not found under the application directory ",
                    tags$code(PROJECT_DIR),
                    ". Clone the full repository or copy ",
                    tags$code("DISCLAIMER.md"),
                    " next to ",
                    tags$code("app.R"),
                    "."
                  ),
                  tags$p(
                    "Canonical text in the meantime: ",
                    tags$a(href = DISCLAIMER_GITHUB_URL, target = "_blank", rel = "noopener noreferrer", DISCLAIMER_GITHUB_URL)
                  )
                )
              }
            )
          )
        )
      ),
      tabItem(
        tabName = "enterprise5",
        fluidRow(
          box(
            width = 12,
            title = "PFAS Enterprise 5.0 — Cloud screening API",
            status = "primary",
            solidHeader = TRUE,
            tags$p(
              "Screening decision-support only. ",
              tags$strong(
                "PFAS Enterprise 5.0 is a screening decision-support platform, not a certified laboratory replacement."
              )
            ),
            tags$p(
              "POST target: ",
              tags$code(PFAS_API_URL),
              ". Override with ",
              tags$code("PFAS_API_URL"),
              " (environment variable) before starting the app."
            )
          )
        ),
        fluidRow(
          box(
            width = 4,
            title = "Request",
            status = "info",
            solidHeader = TRUE,
            textInput("e5_sample_id", "Sample ID", "DEMO_001"),
            textInput("e5_dtxsid", "DTXSID", "DTXSID8030271"),
            selectInput("e5_method_id", "Method", c("EPA_533", "EPA_1633")),
            selectInput("e5_matrix", "Matrix", c("water", "sludge", "serum")),
            actionButton("e5_run", "Run screening", class = "btn-primary")
          ),
          box(
            width = 8,
            title = "Response",
            status = "success",
            solidHeader = TRUE,
            tabsetPanel(
              tabPanel(
                title = "Prediction",
                verbatimTextOutput("e5_result", placeholder = TRUE)
              ),
              tabPanel(
                title = "Sustainability",
                verbatimTextOutput("e5_sustainability", placeholder = TRUE)
              ),
              tabPanel(
                title = "Raw JSON",
                verbatimTextOutput("e5_raw", placeholder = TRUE)
              )
            )
          )
        )
      )
    )
  )
)

ui <- shinymanager::secure_app(
  ui_dashboard,
  enable_admin = TRUE,
  tags_top = NULL,
  language = "en"
)

# -------------------------------------------------------------------
# Server
# -------------------------------------------------------------------

server <- function(input, output, session) {
  iso_json_path <- file.path(PROJECT_DIR, "runs", "test_ucmr5_533", "iso_readiness_score.json")
  iso_csv_path <- file.path(PROJECT_DIR, "runs", "test_ucmr5_533", "iso_blind_spots_report.csv")

  ensure_valid_db_connection()
  auth <- shinymanager::secure_server(
    check_credentials = shinymanager::check_credentials(login_credentials_df),
    timeout = 60 * 12
  )

  op_id <- function() {
    use_login <- tryCatch(isolate(input$use_login_as_operator), error = function(e) TRUE)
    if (!isFALSE(use_login)) {
      uu <- tryCatch(isolate(auth$user), error = function(e) NULL)
      fn <- tryCatch(isolate(auth$full_name), error = function(e) NULL)
      if (!is.null(fn) && nzchar(as.character(fn))) return(as.character(fn))
      if (!is.null(uu) && nzchar(as.character(uu))) return(as.character(uu))
    }
    tryCatch(isolate(input$glp_operator_id), error = function(e) NULL) %||% "unknown"
  }

  observe({
    req(auth$user)
    updateTextInput(session, "glp_operator_id", value = as.character(auth$user))
  })

  output$auth_user_display <- renderPrint({
    req(auth$user)
    cat("Session user:", auth$user, "\n")
    if (!is.null(auth$full_name)) cat("Display name:", auth$full_name, "\n")
    if (!is.null(auth$admin)) cat("Administrator:", auth$admin, "\n")
  })

  output$worm_dir_status <- renderPrint({
    d <- Sys.getenv("PFAS_GLP_WORM_DIR", "")
    if (!nzchar(d)) {
      cat("PFAS_GLP_WORM_DIR is not set. Set it to a secured archive folder before using WORM export.\n")
    } else {
      cat("WORM archive directory:\n ", normalizePath(d, winslash = "/", mustWork = FALSE), "\n")
    }
  })

  observeEvent(input$btn_worm_archive, {
    req(auth$user)
    arc <- Sys.getenv("PFAS_GLP_WORM_DIR", "")
    if (!nzchar(arc)) {
      showNotification("Set PFAS_GLP_WORM_DIR to a dedicated archive path.", type = "error")
      return(invisible(NULL))
    }
    if (!exists("glp_worm_export_audit", mode = "function")) {
      showNotification("glp_audit_archive.R not loaded.", type = "error")
      return(invisible(NULL))
    }
    tryCatch(
      {
        res <- glp_worm_export_audit(con, arc, op_id())
        write_audit(
          "glp_audit_trail",
          basename(res$csv),
          "worm_archive",
          op_id(),
          "WORM audit snapshot",
          list(sha256 = res$digest, rows = res$rows, path = res$csv)
        )
        showNotification(paste("WORM export:", res$csv), type = "message")
      },
      error = function(e) {
        showNotification(conditionMessage(e), type = "error")
      }
    )
  })

  # Do not dbDisconnect(con) in session onStop: that runs on every browser refresh/tab
  # close and leaves the global SQLite handle invalid for the next Shiny session.

  # Dual audit: legacy audit_log + GLP hash-chained glp_audit_trail (session-aware)
  write_audit <- function(entity_type, entity_id, action_type, changed_by, change_notes = "", details = NULL, message = NULL) {
    ensure_valid_db_connection()
    notes_out <- if (!is.null(message)) as.character(message) else change_notes
    audit_row <- tibble::tibble(
      audit_id = make_id("AUD"),
      entity_type = entity_type,
      entity_id = as.character(entity_id),
      action_type = action_type,
      changed_by = changed_by %||% "unknown",
      changed_at = as.character(Sys.time()),
      change_notes = notes_out
    )
    tryCatch(
      DBI::dbWriteTable(con, "audit_log", audit_row, append = TRUE),
      error = function(e) {
        warning("audit_log write failed: ", conditionMessage(e))
        invisible(NULL)
      }
    )
    if (exists("glp_audit_append", mode = "function")) {
      try(
        glp_audit_append(
          con,
          session,
          APP_VERSION,
          entity_type,
          as.character(entity_id),
          action_type,
          changed_by %||% "unknown",
          notes_out,
          details %||% list(),
          regulatory_method = "EPA Method 1633"
        ),
        silent = TRUE
      )
    }
  }

  observe({
    req(auth$user)
    if (isTRUE(session$userData$glp_session_open_logged)) {
      return(invisible(NULL))
    }
    session$userData$glp_session_open_logged <- TRUE
    tok <- tryCatch(session$token, error = function(e) NULL)
    sid <- if (!is.null(tok)) {
      substr(digest::digest(tok, algo = "sha256", serialize = FALSE), 1, 16)
    } else {
      substr(digest::digest(as.character(Sys.time()), algo = "sha256", serialize = FALSE), 1, 16)
    }
    oid <- op_id()
    try(
      write_audit("session", sid, "session_open", oid, "Shiny session established", list(version = APP_VERSION)),
      silent = TRUE
    )
  })

  session$onSessionEnded(function() {
    try(
      {
        ensure_valid_db_connection()
        audit_row <- tibble::tibble(
          audit_id = make_id("AUD"),
          entity_type = "session",
          entity_id = "end",
          action_type = "session_close",
          changed_by = "system",
          changed_at = as.character(Sys.time()),
          change_notes = "Shiny session closed"
        )
        DBI::dbWriteTable(con, "audit_log", audit_row, append = TRUE)
        if (exists("glp_audit_append", mode = "function")) {
          glp_audit_append(
            con,
            NULL,
            APP_VERSION,
            "session",
            "end",
            "session_close",
            "system",
            "Shiny session closed",
            list(),
            regulatory_method = "EPA Method 1633"
          )
        }
      },
      silent = TRUE
    )
  })
  
  output$vb_compounds <- renderValueBox({
    valueBox(nrow(compounds), "Compounds", icon = icon("flask"), color = "aqua")
  })
  
  output$vb_datasets <- renderValueBox({
    valueBox(nrow(dataset_registry), "Endpoint Datasets", icon = icon("database"), color = "yellow")
  })
  
  output$vb_models <- renderValueBox({
    valueBox(nrow(model_registry), "Models", icon = icon("cubes"), color = "purple")
  })
  
  output$vb_inside_ad <- renderValueBox({
    valueBox(sum(compound_ad_summary$ad_status == "Inside"), "Inside AD", icon = icon("check"), color = "green")
  })
  
  output$vb_outside_ad <- renderValueBox({
    valueBox(sum(compound_ad_summary$ad_status == "Outside"), "Outside AD", icon = icon("exclamation-triangle"), color = "red")
  })
  
  output$vb_high_concern <- renderValueBox({
    valueBox(sum(weight_of_evidence$predicted_class == "Positive"), "Positive Flags", icon = icon("radiation"), color = "maroon")
  })
  
  render_dt <- function(df, pageLength = 8) {
    DT::datatable(df, options = list(pageLength = pageLength, scrollX = TRUE), rownames = FALSE)
  }

  read_results_csv <- function(file_name, results_subdir = NULL) {
    sub <- results_subdir
    if (is.null(sub) || length(sub) < 1L || !nzchar(trimws(as.character(sub)[[1]]))) {
      p <- file.path(PROJECT_DIR, "results", file_name)
    } else {
      s <- trimws(as.character(sub)[[1]])
      if (grepl("[.\\\\/]", s)) {
        p <- file.path(PROJECT_DIR, "results", file_name)
      } else {
        p <- file.path(PROJECT_DIR, "results", s, file_name)
      }
    }
    if (!file.exists(p)) return(NULL)
    tryCatch(
      read.csv(p, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e) NULL
    )
  }

  read_results_json <- function(file_name, results_subdir = NULL) {
    if (is.null(results_subdir) || length(results_subdir) < 1L || !nzchar(trimws(as.character(results_subdir)[[1]]))) {
      p <- file.path(PROJECT_DIR, "results", file_name)
    } else {
      s <- trimws(as.character(results_subdir)[[1]])
      if (grepl("[.\\\\/]", s)) {
        p <- file.path(PROJECT_DIR, "results", file_name)
      } else {
        p <- file.path(PROJECT_DIR, "results", s, file_name)
      }
    }
    if (!file.exists(p)) return(NULL)
    tryCatch(
      {
        txt <- paste(readLines(p, warn = FALSE), collapse = "\n")
        # Be tolerant to non-standard NaN/Infinity tokens from legacy runs.
        txt <- gsub("\\bNaN\\b", "null", txt)
        txt <- gsub("\\bInfinity\\b", "null", txt)
        txt <- gsub("\\b-Infinity\\b", "null", txt)
        jsonlite::fromJSON(txt)
      },
      error = function(e) NULL
    )
  }

  # Prefer evidence-governed results/; if only screening exists, or screening is newer, use results/screening/.
  pfas_resolve_train_metrics_paths <- function() {
    root_m <- file.path(PROJECT_DIR, "results", "nhanes_model_metrics.json")
    scr_m <- file.path(PROJECT_DIR, "results", "screening", "nhanes_model_metrics.json")
    er <- file.exists(root_m)
    es <- file.exists(scr_m)
    if (!er && !es) {
      return(list(subdir = "", banner = ""))
    }
    if (er && !es) {
      return(list(subdir = "", banner = ""))
    }
    if (!er && es) {
      return(list(
        subdir = "screening",
        banner = paste0(
          "Showing exploratory screening metrics under results/screening/ ",
          "(no evidence-governed nhanes_model_metrics.json in results/)."
        )
      ))
    }
    tr <- suppressWarnings(file.info(root_m)$mtime)
    ts <- suppressWarnings(file.info(scr_m)$mtime)
    if (inherits(ts, "POSIXct") && inherits(tr, "POSIXct") && !is.na(ts) && !is.na(tr) && ts > tr) {
      return(list(
        subdir = "screening",
        banner = paste0(
          "Newer metrics file is exploratory screening (results/screening/). ",
          "An evidence-governed copy also exists in results/."
        )
      ))
    }
    banner_ev <- if (es && inherits(ts, "POSIXct") && inherits(tr, "POSIXct") && !is.na(ts) && !is.na(tr) && ts <= tr) {
      paste0(
        "Showing evidence-governed metrics (results/). ",
        "An exploratory screening copy exists under results/screening/."
      )
    } else {
      ""
    }
    list(subdir = "", banner = banner_ev)
  }

  read_training_json <- function(file_name) {
    p <- file.path(PROJECT_DIR, "data", "training", file_name)
    if (!file.exists(p)) return(NULL)
    tryCatch(
      jsonlite::fromJSON(p),
      error = function(e) NULL
    )
  }

  read_training_csv <- function(file_name) {
    p <- file.path(PROJECT_DIR, "data", "training", file_name)
    if (!file.exists(p)) return(NULL)
    tryCatch(
      read.csv(p, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e) NULL
    )
  }

  read_label_derivation_audit_payload <- function() {
    rp <- pfas_resolve_train_metrics_paths()
    subdir_arg <- if (nzchar(rp$subdir %||% "")) rp$subdir else NULL
    read_results_json("label_derivation_audit.json", results_subdir = subdir_arg)
  }

  read_label_integrity_report_payload <- function() {
    read_results_json("label_integrity_report.json")
  }

  reconciliation_dataset_builder_stages <- function() {
    rec <- read_results_json("python_training_row_reconciliation.json")
    if (is.null(rec) || is.null(rec$dataset_builder_stages)) return(NULL)
    rec$dataset_builder_stages
  }

  cat_iso_holdout_metrics <- function(im, n_test_align = NA_integer_) {
    if (is.null(im) || !is.list(im)) return(invisible(NULL))
    if (!is.null(im$error)) {
      cat("\niso_holdout_metrics:", im$error, "\n")
      return(invisible(NULL))
    }
    # JSON fields may be null or length-0 vectors; if (is.finite(x)) must not see logical(0).
    iso_scalar_num <- function(x, default = NA_real_) {
      if (is.null(x)) return(default)
      v <- suppressWarnings(as.numeric(unlist(x, use.names = FALSE)))
      if (length(v) < 1L) return(default)
      v[[1L]]
    }
    iso_scalar_int <- function(x, default = NA_integer_) {
      n <- iso_scalar_num(x, NA_real_)
      if (!is.finite(n)) return(default)
      suppressWarnings(as.integer(round(n)))
    }
    fmt_int_or_na <- function(x) {
      xi <- iso_scalar_int(x, NA_integer_)
      if (is.na(xi)) "NA" else as.character(xi)
    }
    thr <- iso_scalar_num(im$probability_threshold, NA_real_)
    if (!is.finite(thr)) thr <- 0.25
    cat("\nHold-out decision metrics (positive class vs negative), P >= ", thr, "\n", sep = "")
    cat(
      " Confusion counts  TN FP | FN TP:",
      fmt_int_or_na(im$tn), fmt_int_or_na(im$fp), "|",
      fmt_int_or_na(im$fn), fmt_int_or_na(im$tp), "\n",
      sep = " "
    )
    tpv <- iso_scalar_int(im$tp, NA_integer_)
    fpv <- iso_scalar_int(im$fp, NA_integer_)
    tnv <- iso_scalar_int(im$tn, NA_integer_)
    fnv <- iso_scalar_int(im$fn, NA_integer_)
    na_pos <- iso_scalar_int(im$n_actual_positive, NA_integer_)
    na_neg <- iso_scalar_int(im$n_actual_negative, NA_integer_)
    if (!is.na(na_pos) || !is.na(na_neg)) {
      cat(
        " Actual class dist.  neg / pos:",
        if (is.na(na_neg)) "NA" else na_neg, "/",
        if (is.na(na_pos)) "NA" else na_pos, "\n",
        sep = ""
      )
    }
    rp <- iso_scalar_num(im$recall_positive, NA_real_)
    if (is.finite(rp)) {
      cat(" Recall (sensitivity, class 1):", round(rp, 4), "\n")
    } else {
      cat(" Recall (sensitivity, class 1): N/A (no positive labels in hold-out)\n")
    }
    pp <- iso_scalar_num(im$precision_positive, NA_real_)
    if (is.finite(pp)) {
      cat(" Precision (PPV, class 1)    :", round(pp, 4), "\n")
    } else {
      cat(" Precision (PPV, class 1)    : N/A (no positive predictions)\n")
    }
    sp <- iso_scalar_num(im$specificity, NA_real_)
    if (is.finite(sp)) cat(" Specificity (class 0)       :", round(sp, 4), "\n")
    npv <- iso_scalar_num(im$npv, NA_real_)
    if (is.finite(npv)) cat(" NPV (among pred. negative)   :", round(npv, 4), "\n")
    pred_pos <- iso_scalar_int(im$predicted_positive_count, NA_integer_)
    if (is.na(pred_pos) && !is.na(tpv) && !is.na(fpv)) pred_pos <- tpv + fpv
    cs <- iso_scalar_int(im$cm_sum, NA_integer_)
    if ((is.na(cs) || cs < 1L) && all(is.finite(c(tpv, fpv, tnv, fnv)))) {
      cs <- tpv + fpv + tnv + fnv
    }
    pred_frac_json <- iso_scalar_num(im$predicted_positive_fraction, NA_real_)
    f10k_json <- iso_scalar_num(im$flags_per_10k_holdout, NA_real_)
    fpr_json <- iso_scalar_num(im$false_positive_rate_negative, NA_real_)
    if (!is.na(pred_pos) && !is.na(cs) && cs > 0L) {
      frac_use <- pred_pos / cs
      if (is.finite(pred_frac_json)) frac_use <- pred_frac_json
      f10k_use <- if (is.finite(f10k_json)) f10k_json else pred_pos / cs * 10000
      cat(
        " Predicted positives (P>=tau):", pred_pos, "of", cs,
        sprintf(" (~%.2f%% flagged;", 100 * frac_use),
        sprintf(" ~%.1f per 10k hold-out scored)\n", f10k_use)
      )
    }
    fpr_use <- NA_real_
    if (is.finite(fpr_json)) {
      fpr_use <- fpr_json
    } else if (!is.na(na_neg) && na_neg > 0L && !is.na(fpv)) {
      fpr_use <- fpv / na_neg
    }
    if (is.finite(fpr_use)) {
      cat(" FP rate among true negatives (review burden on negatives):", round(fpr_use, 4), "\n")
    }
    nt <- iso_scalar_int(n_test_align, NA_integer_)
    if (!is.na(cs) && !is.na(nt)) {
      ok <- isTRUE(cs == nt)
      cat(
        " Confusion_matrix cell sum:", cs, "| n_test:", nt,
        if (ok) " (aligned)\n" else " (MISMATCH)\n",
        sep = ""
      )
    }
    invisible(NULL)
  }

  print_holdout_probability_debug <- function(hp) {
    if (is.null(hp) || !is.list(hp)) return(invisible(NULL))
    cat("\n--- Hold-out probability debug (results/holdout_probability_debug.json) ---\n")
    pe <- hp[["probability_exceedance_holdout"]]
    if (is.list(pe)) {
      cat(
        " P exceedance (hold-out): min=", pe$min %||% NA, " max=", pe$max %||% NA,
        " median=", pe$median %||% NA, " peak-to-trough=", pe$peak_to_trough %||% NA, "\n",
        sep = ""
      )
    }
    fc <- hp[["fraction_scores_ge_cutoff"]]
    if (is.list(fc)) {
      cat(
        " Fraction scores ≥ cutoff: 0.15=", fc[["0.15"]] %||% NA,
        " 0.25=", fc[["0.25"]] %||% NA, " 0.50=", fc[["0.50"]] %||% NA, "\n",
        sep = ""
      )
    }
    hints <- hp[["interpretation_hints"]]
    if (is.list(hints)) {
      if (isTRUE(hints[["all_hard_predictions_negative"]])) {
        cat(" Collapse: TP=0 with positives at current τ — model predicts all negative.\n")
      }
      if (isTRUE(hints[["max_score_below_threshold"]])) {
        cat(" Collapse: max(P) < τ — lower Hold-out threshold in Reports or --holdout-threshold.\n")
      }
      if (isTRUE(hints[["auc_near_random_or_worse"]])) {
        cat(" Signal: AUC < 0.56 — discrimination weak; fixing τ alone may not restore screening value.\n")
      }
      acts <- hints[["suggested_actions"]]
      if (length(acts) > 0L) {
        cat(" Next steps:\n")
        for (a in acts) cat("  - ", as.character(a), "\n", sep = "")
      }
    }
    invisible(NULL)
  }

  pfas_pipeline_log <- reactiveVal("Pipeline idle. Click a step or 'Run all steps'.")
  pfas_results_nonce <- reactiveVal(0L)
  source_bootstrap_note <- reactiveVal("Source folder bootstrap not run yet.")
  qc_pt_upload_status_note <- reactiveVal("QC/PT uploads not run yet.")
  iso_preflight_note <- reactiveVal("ISO preflight not run yet.")
  external_upload_raw <- reactiveVal(NULL)
  external_upload_name <- reactiveVal("")
  external_upload_report <- reactiveVal(NULL)
  external_upload_normalized <- reactiveVal(NULL)
  external_upload_save_note <- reactiveVal("No normalized upload saved yet.")
  external_upload_read_error <- reactiveVal("")
  external_upload_strict_result <- reactiveVal(NULL)
  external_reference_preflight <- reactiveVal(NULL)
  pipeline_last_error <- reactiveVal("")
  ml_workflow_train_context <- reactiveVal(list(
    workflow_mode = "idle",
    validation_scope = NA_character_,
    iso_governed = NA,
    results_artifact_subdir = "",
    note = "No model train completed in this session yet.",
    updated_at = NA_character_
  ))

  allowed_upload_ext <- c("csv", "tsv", "txt", "xlsx", "xls", "json", "parquet", "rds", "xpt")

  normalize_shiny_file_upload <- function(f) {
    if (is.null(f)) return(NULL)
    if (inherits(f, "data.frame")) {
      if (nrow(f) < 1L) return(NULL)
      f <- f[1L, , drop = FALSE]
    }
    nm <- suppressWarnings(trimws(as.character(f$name %||% "")[1]))
    if (length(nm) < 1L || is.na(nm)) nm <- ""
    dp <- suppressWarnings(trimws(as.character(f$datapath %||% "")[1]))
    if (length(dp) < 1L || is.na(dp)) dp <- ""
    sz_raw <- suppressWarnings((f$size %||% NA_integer_)[1])
    sz <- suppressWarnings(as.integer(sz_raw))
    if (length(sz) < 1L || is.na(sz)) sz <- NA_integer_
    list(name = nm, datapath = dp, size = sz)
  }
  upload_schema_cols <- c(
    "source", "source_dataset", "sample_id", "matrix", "sample_date",
    "analyte", "cas", "result_value", "result_unit", "qualifier",
    "mdl", "rl", "detect_flag", "state", "county", "latitude", "longitude",
    "region", "facility_water_type", "sample_point_type", "method_id",
    "collection_year", "collection_month", "pws_size", "facility_id", "sample_point_id",
    "health_endpoint", "health_value", "dataset_type", "upload_id", "uploaded_at",
    "pipeline_lane"
  )

  read_delimited_robust <- function(path, sep, header = TRUE, nrows = NA_integer_) {
    if (!nzchar(path %||% "") || !file.exists(path)) return(NULL)
    # latin1/CP1252 before UTF-8: EPA/Windows exports often use byte 0xB5 for µ in Units (e.g. µg/L);
    # read.table as UTF-8 can throw "invalid multibyte string" on those files.
    enc_candidates <- c("UTF-8-BOM", "latin1", "CP1252", "UTF-8", "UTF-16LE", "UTF-16BE")
    # Do not pass read.table(..., nrows = NA_integer_) — scan() errors internally ("missing TRUE/FALSE").
    nr_limit <- NA_integer_
    if (is.finite(nrows) && !is.na(nrows) && nrows > 0L) nr_limit <- as.integer(nrows)
    quote_modes <- list(
      default = "\"",
      none = ""
    )
    for (enc in enc_candidates) {
      for (qm in quote_modes) {
        qch <- qm
        args <- list(
          file = path,
          sep = sep,
          header = header,
          stringsAsFactors = FALSE,
          colClasses = "character",
          check.names = FALSE,
          quote = qch,
          comment.char = "",
          fill = TRUE,
          blank.lines.skip = TRUE,
          allowEscapes = FALSE,
          skipNul = TRUE,
          fileEncoding = enc,
          dec = ".",
          strip.white = TRUE
        )
        if (!is.na(nr_limit)) args$nrows <- nr_limit
        df <- tryCatch(
          suppressWarnings(do.call(utils::read.table, args)),
          error = function(e) NULL
        )
        if (!is.null(df) && is.data.frame(df) && ncol(df) >= 1L) return(df)
      }
    }
    NULL
  }

  read_first_line_robust <- function(path) {
    if (!nzchar(path %||% "") || !file.exists(path)) return("")
    read_one <- function(enc_raw) {
      tryCatch(
        suppressWarnings(readLines(path, n = 1L, warn = FALSE, encoding = enc_raw)),
        error = function(e) character(0)
      )
    }
    for (enc in c("latin1", "CP1252", "UTF-8")) {
      ln <- read_one(enc)
      if (length(ln) > 0 && nzchar(ln[[1]])) return(ln[[1]])
    }
    for (enc in c("UTF-16LE", "UTF-16BE")) {
      ln <- read_one(enc)
      if (length(ln) > 0 && nzchar(ln[[1]])) return(ln[[1]])
    }
    ln <- tryCatch(suppressWarnings(readLines(path, n = 1L, warn = FALSE)), error = function(e) "")
    if (length(ln) > 0) ln[[1]] else ""
  }

  # light=TRUE: skip per-cell iconv (huge uploads); UTF-8/latin1 CSV exports stay usable; colnames still normalized.
  sanitize_utf8_df <- function(df, light = FALSE) {
    strip_embedded_nul_chars <- function(v) {
      if (!is.character(v) || !length(v)) return(v)
      z <- intToUtf8(0L)
      hit <- !is.na(v) & nzchar(v) & grepl(z, v, fixed = TRUE)
      if (!any(hit, na.rm = TRUE)) return(v)
      out <- v
      out[hit] <- vapply(
        out[hit],
        function(s) paste(strsplit(s, z, fixed = TRUE)[[1]], collapse = ""),
        FUN.VALUE = "",
        USE.NAMES = FALSE
      )
      out
    }
    df <- as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)

    names(df) <- iconv(names(df), from = "", to = "UTF-8", sub = "")
    names(df) <- trimws(names(df))
    nn <- names(df)
    empty_nm <- is.na(nn) | !nzchar(nn)
    if (any(empty_nm)) nn[empty_nm] <- paste0("__unnamed_col_", which(empty_nm))
    nn <- make.unique(nn, sep = "__dup__")
    names(df) <- nn

    do_iconv <- !isTRUE(light)
    for (nm in names(df)) {
      col <- df[[nm]]
      if (is.character(col)) {
        if (do_iconv) {
          df[[nm]] <- iconv(col, from = "", to = "UTF-8", sub = "")
        }
        df[[nm]] <- strip_embedded_nul_chars(df[[nm]])
        df[[nm]] <- trimws(df[[nm]])
      } else if (is.factor(col)) {
        ch <- as.character(col)
        if (do_iconv) {
          ch <- iconv(ch, from = "", to = "UTF-8", sub = "")
        }
        ch <- strip_embedded_nul_chars(ch)
        df[[nm]] <- trimws(ch)
      }
    }

    df
  }

  stage_delimited_upload_file <- function(path, ext, peek_max_raw = 4L * 1024^2) {
    ext <- tolower(ext %||% "")
    sz <- suppressWarnings(as.integer(file.info(path)$size %||% 0))
    peek_n <- max(0L, min(sz, as.integer(peek_max_raw)))
    peek_has_nul <- FALSE
    if (peek_n > 0L) {
      buf <- tryCatch(readBin(path, what = "raw", n = peek_n), error = function(e) raw())
      peek_has_nul <- length(buf) > 0L && any(buf == as.raw(0L))
    }
    need_strip <- ext == "txt" && isTRUE(peek_has_nul)
    tmp <- tempfile(fileext = paste0(".", ext))
    # Caller unlinks tmp after read_upload_delimited_base (do not schedule on.exit here).
    if (need_strip && sz > 0L) {
      rawf <- tryCatch(readBin(path, what = "raw", n = sz), error = function(e) NULL)
      if (!is.null(rawf) && length(rawf) > 0L) {
        rawf <- rawf[rawf != as.raw(0L)]
        writeBin(rawf, tmp)
        return(tmp)
      }
      return("")
    }
    if (isTRUE(file.copy(path, tmp, overwrite = TRUE))) {
      return(tmp)
    }
    ""
  }

  read_upload_delimited_base <- function(path_clean, ext) {
    read_try_best <- function(order) {
      best <- NULL
      best_ncol <- -1L
      for (sep in order) {
        if (!nzchar(sep %||% "")) next
        df <- read_delimited_robust(path_clean, sep = sep)
        if (is.null(df) || !is.data.frame(df) || ncol(df) < 1L) next
        nc <- ncol(df)
        if (nc > best_ncol) {
          best <- df
          best_ncol <- as.integer(nc)
        }
        if (nc >= 2L) {
          return(df)
        }
      }
      best
    }

    sniff_order <- function() {
      first <- read_first_line_robust(path_clean)
      if (!nzchar(first)) {
        return(c(",", "\t", "|", ";"))
      }
      counts <- c(
        comma = lengths(regmatches(first, gregexpr(",", first, fixed = TRUE))),
        tab = lengths(regmatches(first, gregexpr("\t", first, fixed = TRUE))),
        semi = lengths(regmatches(first, gregexpr(";", first, fixed = TRUE))),
        pipe = lengths(regmatches(first, gregexpr("|", first, fixed = TRUE)))
      )
      mx <- suppressWarnings(max(counts, na.rm = TRUE))
      if (!is.finite(mx) || mx < 1L) {
        return(c(",", "\t", "|", ";"))
      }
      hits <- names(counts)[counts == mx]
      sep_map <- c(comma = ",", tab = "\t", semi = ";", pipe = "|")
      sniffed <- unname(sep_map[hits])
      unique(c(sniffed, ",", "\t", "|", ";"))
    }

    ext <- tolower(ext %||% "")
    all_seps <- c(",", "\t", "|", ";")
    if (ext == "csv") {
      # Many EPA/UCMR-style exports use .csv extension but are tab- or pipe-delimited; sniff first line.
      return(read_try_best(unique(c(sniff_order(), ",", all_seps))))
    }
    if (ext == "tsv") {
      return(read_try_best(unique(c("\t", all_seps))))
    }
    if (identical(ext, "txt")) {
      return(read_try_best(sniff_order()))
    }
    read_try_best(all_seps)
  }

  safe_read_upload <- function(path, filename = NULL) {
    tryCatch(
      {
        cat("SAFE_READ_UPLOAD START\n")
        cat("PATH:", path %||% "", "\n")

        fn <- filename %||% basename(path %||% "")
        cat("FILE:", fn, "\n")

        ext <- tolower(tools::file_ext(fn))

        if (!nzchar(path %||% "") || !file.exists(path) || file.size(path) == 0L) {
          stop("Uploaded file is empty or missing.")
        }

        if (ext %in% c("csv", "txt", "tsv")) {
      # Do not readBin() the whole file: doubles RAM (fatal for multi-hundred-MB CSV). Copy to temp; skipNul in read.table.
      tmp <- stage_delimited_upload_file(path, ext)
      if (is.null(tmp) || !nzchar(tmp) || !file.exists(tmp)) {
        stop("Could not stage uploaded file for parsing (disk or permission).")
      }
      on.exit(unlink(tmp), add = TRUE)

      # CSV/TSV/TXT: utils::read.table only — readr/stringi paths removed (fixes 'zero-length pattern' crashes).
      df <- read_upload_delimited_base(tmp, ext)

      if (is.null(df) || !is.data.frame(df) || ncol(df) < 1L) {
        stop(
          paste0(
            "Could not parse delimited upload as a table. ",
            "Expected a delimited text table (comma/tab/pipe/semicolon), UTF-8 or UTF-16. ",
            "UCMR supplemental/metadata files that are not uniform delimited tables will not load here; use occurrence files (e.g. UCMR5_ZIPs) for measurements. ",
            "Very large files need enough free RAM for one full in-memory parse; prefer a sampled CSV for Upload preview.",
            ifelse(ext %in% c("csv"), " Try read.csv(nrows=5000) in R to confirm the file parses.", "")
          )
        )
      }

      ncell <- nrow(df) * ncol(df)
      lite <- is.finite(ncell) && ncell > 1e6L
      df <- sanitize_utf8_df(as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE), light = lite)
      # Collapse headers to stable snake-ish tokens so EPA TitleCase / spaced columns match autodetect aliases.
      nm <- names(df)
      nm <- tolower(trimws(iconv(nm, from = "", to = "UTF-8", sub = "")))
      nm <- gsub("[^a-z0-9]+", "_", nm, perl = TRUE)
      nm <- gsub("^_+|_+$", "", nm, perl = TRUE)
      nm <- gsub("_+", "_", nm, perl = TRUE)
      names(df) <- nm
      return(df)
    }

    if (ext %in% c("xlsx", "xls")) {
      if (!requireNamespace("readxl", quietly = TRUE)) {
        stop("Package 'readxl' is required. Run install.packages('readxl').")
      }

      df <- tryCatch(
        readxl::read_excel(path, sheet = 1L),
        error = function(e) {
          stop(paste0("Excel read failed: ", conditionMessage(e)))
        }
      )
      return(sanitize_utf8_df(as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)))
    }

    if (ext == "json") {
      x <- jsonlite::fromJSON(path, flatten = TRUE)
      df <- if (is.data.frame(x)) x else as.data.frame(x, stringsAsFactors = FALSE, check.names = FALSE)
      return(sanitize_utf8_df(df))
    }

    if (ext == "parquet") {
      if (!requireNamespace("arrow", quietly = TRUE)) {
        stop("Package 'arrow' is required. Run install.packages('arrow').")
      }

      df <- arrow::read_parquet(path)
      return(sanitize_utf8_df(as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)))
    }

    if (ext == "rds") {
      df <- readRDS(path)
      if (!is.data.frame(df)) stop("RDS file must contain a data.frame.")
      return(sanitize_utf8_df(as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)))
    }

    if (ext == "xpt") {
      df <- if (requireNamespace("haven", quietly = TRUE)) {
        haven::read_xpt(path)
      } else if (requireNamespace("foreign", quietly = TRUE)) {
        foreign::read.xport(path)
      } else {
        stop("Install 'haven' or 'foreign' to read .xpt files.")
      }
      return(sanitize_utf8_df(as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)))
    }

        stop(paste("Unsupported file type:", ext))
      },
      error = function(e) {
        cat("SAFE_READ_UPLOAD ERROR:\n")
        cat(conditionMessage(e), "\n")
        traceback()
        flush.console()
        stop(conditionMessage(e), call. = FALSE)
      }
    )
  }

  normalize_upload_schema <- function(df, mapping, dataset_type) {
    parse_numeric_value <- function(x) parse_external_upload_numeric(x)
    normalize_name <- function(x) {
      tolower(gsub("[^a-z0-9]+", "", trimws(as.character(x))))
    }
    pfas_like <- function(x) {
      y <- tolower(trimws(as.character(x)))
      y <- gsub("[^a-z0-9]+", " ", y)
      safe_detect(
        y,
        "\\bpf[a-z0-9]{2,}\\b|perfluoro|polyfluoro|fluorotelomer|genx|hfpo|adona|fosa|fosaa|fts|pfas"
      )
    }
    col_names <- names(df)
    col_norm <- normalize_name(col_names)
    field_aliases <- list(
      source_dataset = c(
        "source_dataset", "source dataset", "dataset", "source", "source_name", "methodid", "method_id",
        "program", "datasource", "study", "ucmr_phase", "data_source"
      ),
      sample_id = c(
        "sample_id", "sample id", "sample", "id", "seqn", "station", "pwsid", "pws_id", "samplepointid", "sample_point_id",
        "sampleid", "sample_number", "samplenumber", "lab_sample_id", "labsampleid", "submission_id", "submissionid",
        "sample_identifier", "sampleidentifier", "public_water_system_id", "pwsidentifier", "water_system_no", "watersystemno"
      ),
      matrix = c(
        "matrix", "sample_matrix", "sample type", "facilitywatertype", "facility_water_type", "samplepointtype", "sample_point_type",
        "sampletype", "matrixtype", "media", "media_type", "matrix_code"
      ),
      date = c(
        "sample_date", "sample date", "collection_date", "collection date", "date", "activity_start_date",
        "activitystartdate", "collectiondate", "date_collected", "datecollected", "sample_collection_date"
      ),
      analyte = c(
        "analyte", "analyte_name", "parameter", "parameter_name", "constituent", "contaminant", "chemical", "chemical_name", "compound",
        "contaminant_name", "constituent_name", "analytename", "parametercode", "parameter_code", "chemical_name", "pollutant"
      ),
      cas = c("cas", "casrn", "cas_number", "cas_num", "casregistrynumber"),
      result_value = c(
        "result_value", "result value", "result", "result_clean", "resultclean", "result_ngl", "result ngl",
        "concentration", "concentration_ng_l", "concentration_ngl", "value", "value_ngl", "reported", "reported_result",
        "analyticalresultvalue", "analytical_result", "resultamount", "measurement_value", "level", "amount", "reading",
        "gm_result"
      ),
      unit = c(
        "result_unit", "result unit", "unit", "units", "uom", "result_units", "units_desc", "unit_desc", "uom_desc",
        "gm_result_unit"
      ),
      qualifier = c(
        "qualifier", "flag", "result_flag", "censor", "result_qualifier", "lab_qualifier", "detection_qualifier",
        "gm_result_modifier", "sample_event_result_type", "result_type", "result_qualifier_code", "qualifier_code"
      ),
      mdl = c("mdl", "method_detection_limit", "detection_limit", "method_detection_level", "minimum_reporting_level"),
      rl = c("rl", "reporting_limit", "report_limit", "practical_quantitation_limit", "pql", "reporting_level"),
      detect_flag = c("detect_flag", "detect", "detected", "detection_indicator", "is_detected"),
      state = c("state", "state_abbr", "state_code", "st", "stateprovince", "state_province"),
      county = c("county", "county_name", "countyname", "administrative_area"),
      facility_water_type = c("facilitywatertype", "facility_water_type", "water_type", "sourcetype", "source_type"),
      sample_point_type = c("samplepointtype", "sample_point_type", "location_type", "point_type"),
      method_id = c("methodid", "method_id", "analytical_method", "analyticalmethod", "method_code", "methodcode", "analytical_method_id"),
      collection_year = c("collectionyear", "collection_year", "year", "sample_year", "calendar_year"),
      facility_id = c("facilityid", "facility_id", "facility_code", "site_id", "siteid", "pws_id_number"),
      sample_point_id = c("samplepointid", "sample_point_id", "monitoring_point", "station_id", "stationid"),
      latitude = c("latitude", "lat", "lat_measure", "latmeasure", "dec_lat", "y_coord"),
      longitude = c("longitude", "lon", "lng", "long_measure", "longmeasure", "dec_lon", "x_coord")
    )
    resolve_col <- function(name) {
      mapped <- trimws(as.character(mapping[[name]] %||% ""))
      if (nzchar(mapped)) {
        mapped_norm <- tolower(mapped)
        if (identical(name, "result_value")) {
          bad <- safe_detect(
            mapped_norm,
            "modifier|qualifier|flag|vvl|tract|population|geoid|zip|pesticide|chemical|contaminant|name"
          )
          if (isTRUE(bad)) mapped <- ""
        } else if (identical(name, "analyte")) {
          bad <- safe_detect(
            mapped_norm,
            "modifier|qualifier|result|value|vvl|tract|population|geoid|zip"
          )
          if (isTRUE(bad)) mapped <- ""
        } else if (identical(name, "sample_id")) {
          bad <- safe_detect(
            mapped_norm,
            "pesticide|contaminant|chemical|analyte|result|value|tract|population|geoid|zip"
          )
          if (isTRUE(bad)) mapped <- ""
        }
      }
      if (nzchar(mapped) && mapped %in% col_names) return(mapped)
      aliases <- field_aliases[[name]] %||% name
      alias_norm <- normalize_name(aliases)
      scores <- rep(0, length(col_names))
      scores <- scores + ifelse(col_norm %in% alias_norm, 100, 0)
      for (a in alias_norm) {
        aa <- suppressWarnings(trimws(as.character(a)))
        if (length(aa) != 1L || is.na(aa) || !nzchar(aa)) next
        scores <- scores + ifelse(safe_detect(col_norm, aa), 35, 0)
      }

      if (identical(name, "result_value")) {
        numeric_rate <- vapply(col_names, function(cn) {
          vv <- parse_numeric_value(df[[cn]])
          mean(!is.na(vv))
        }, numeric(1))
        digit_rate <- vapply(col_names, function(cn) {
          vals <- as.character(df[[cn]])
          mean(safe_detect(vals, "[-+]?[0-9]*\\.?[0-9]+"), na.rm = TRUE)
        }, numeric(1))
        scores <- scores + 120 * numeric_rate
        scores <- scores + 45 * digit_rate
        scores <- scores + ifelse(safe_detect(col_norm, "result|concentration|value|ngl|clean"), 30, 0)
        scores <- scores - ifelse(safe_detect(col_norm, "modifier|qualifier|flag|vvl|code|id|tract|population|geoid|zip"), 90, 0)
      } else if (identical(name, "analyte")) {
        scores <- scores + ifelse(safe_detect(col_norm, "analyte|contaminant|parameter|chemical|compound|name"), 40, 0)
        scores <- scores - ifelse(safe_detect(col_norm, "modifier|vvl|id|code|flag"), 80, 0)
        text_pfas_rate <- vapply(col_names, function(cn) {
          col <- df[[cn]]
          if (!(is.character(col) || is.factor(col))) return(0)
          mean(pfas_like(col), na.rm = TRUE)
        }, numeric(1))
        scores <- scores + 120 * text_pfas_rate
      } else if (identical(name, "sample_id")) {
        scores <- scores + ifelse(safe_detect(col_norm, "sample|well|station|pws|^id$|_id$|id_"), 30, 0)
        scores <- scores - ifelse(safe_detect(col_norm, "result|value|concentration"), 40, 0)
        scores <- scores - ifelse(safe_detect(col_norm, "name|contaminant|chemical|pesticide"), 35, 0)
      } else if (identical(name, "state")) {
        scores <- scores + ifelse(safe_detect(col_norm, "^state$|stateabbr|statecode"), 50, 0)
      }

      if (all(!is.finite(scores))) return("")
      idx <- which.max(scores)
      if (length(idx) == 0 || !is.finite(scores[[idx]]) || scores[[idx]] <= 0) return("")
      if (identical(name, "result_value")) {
        best <- col_names[[idx]]
        best_num_rate <- mean(!is.na(parse_numeric_value(df[[best]])))
        best_name_ok <- safe_detect(normalize_name(best), "result|concentration|value|ngl|clean")
        if (!(isTRUE(best_name_ok) || best_num_rate >= 0.6)) return("")
      }
      col_names[[idx]]
    }
    pick <- function(name) {
      col <- resolve_col(name)
      if (!nzchar(col) || !(col %in% names(df))) return(rep(NA_character_, nrow(df)))
      as.character(df[[col]])
    }
    num_pick <- function(name) parse_numeric_value(pick(name))
    raw_result_chr <- pick("result_value")
    qualifier <- trimws(pick("qualifier"))
    qualifier[is.na(qualifier)] <- ""
    rv_l <- tolower(trimws(as.character(raw_result_chr)))
    rv_l[is.na(rv_l)] <- ""
    nd_infer <- !nzchar(qualifier) & nzchar(rv_l) & safe_detect(
      rv_l,
      "^nd$|^n\\.d\\.?$|^non[- ]?detect$|^bdl$|^u$|^uj$|^<"
    )
    qualifier <- ifelse(nd_infer, ifelse(safe_detect(rv_l, "^\\s*<"), "<", "ND"), qualifier)
    detect_raw <- tolower(trimws(pick("detect_flag")))
    detect_from_q <- !safe_detect(tolower(trimws(qualifier %||% "")), "^<|nd|non.?detect|bdl|u\\b|uj\\b")
    detect <- ifelse(
      nzchar(detect_raw),
      detect_raw %in% c("1", "true", "yes", "y", "detect", "detected"),
      detect_from_q
    )

    nrm <- nrow(df)
    tibble::tibble(
      source = "external_upload",
      source_dataset = pick("source_dataset"),
      sample_id = pick("sample_id"),
      matrix = pick("matrix"),
      sample_date = pick("date"),
      analyte = pick("analyte"),
      cas = pick("cas"),
      result_value = num_pick("result_value"),
      result_unit = normalize_external_result_unit_for_schema(pick("unit")),
      qualifier = qualifier,
      mdl = num_pick("mdl"),
      rl = num_pick("rl"),
      detect_flag = as.integer(detect),
      state = pick("state"),
      county = pick("county"),
      region = rep(NA_character_, nrm),
      facility_water_type = pick("facility_water_type"),
      sample_point_type = pick("sample_point_type"),
      method_id = pick("method_id"),
      collection_year = pick("collection_year"),
      collection_month = rep(NA_character_, nrm),
      pws_size = rep(NA_character_, nrm),
      facility_id = pick("facility_id"),
      sample_point_id = pick("sample_point_id"),
      latitude = num_pick("latitude"),
      longitude = num_pick("longitude"),
      health_endpoint = rep(NA_character_, nrm),
      health_value = rep(NA_real_, nrm),
      dataset_type = dataset_type,
      upload_id = NA_character_,
      uploaded_at = NA_character_,
      pipeline_lane = rep(NA_character_, nrm)
    )
  }

  normalize_analyte_key <- function(x) {
    y <- tolower(trimws(as.character(x)))
    y <- gsub("[^a-z0-9]+", " ", y)
    dplyr::case_when(
      safe_detect(y, "pfoa|perfluorooctanoic") ~ "pfoa",
      safe_detect(y, "pfos|perfluorooctane sulfon") ~ "pfos",
      safe_detect(y, "pfna|perfluorononanoic") ~ "pfna",
      safe_detect(y, "pfhxs|perfluorohexane sulfon") ~ "pfhxs",
      safe_detect(y, "pfba|perfluorobutanoic") ~ "pfba",
      safe_detect(y, "pfpea|perfluoropentanoic") ~ "pfpea",
      safe_detect(y, "pfhxa|perfluorohexanoic") ~ "pfhxa",
      safe_detect(y, "pfbs|perfluorobutane sulfon") ~ "pfbs",
      safe_detect(y, "pfda|perfluorodecanoic") ~ "pfda",
      safe_detect(y, "pfuna|pfunda|pfundecanoic|perfluoroundecanoic") ~ "pfuna",
      safe_detect(y, "genx|hfpo|adona") ~ "genx",
      TRUE ~ NA_character_
    )
  }

  is_pfas_like_label <- function(x) {
    y <- tolower(trimws(as.character(x)))
    y <- gsub("[^a-z0-9]+", " ", y)
    safe_detect(
      y,
      "\\bpf[a-z0-9]{2,}\\b|perfluoro|polyfluoro|fluorotelomer|genx|hfpo|adona|fosa|fosaa|fts|pfas"
    )
  }

  normalize_upload_schema_with_wide_fallback <- function(df, mapping, dataset_type) {
    parse_numeric_value <- function(x) parse_external_upload_numeric(x)
    base <- normalize_upload_schema(df, mapping, dataset_type)
    usable_base <- sum(
      !is.na(base$analyte) & nzchar(trimws(as.character(base$analyte))) & !is.na(base$result_value),
      na.rm = TRUE
    )
    if (usable_base > 0) return(base)

    canon_from_cols <- normalize_analyte_key(names(df))
    pfas_like_cols <- is_pfas_like_label(names(df))
    analyte_cols <- names(df)[!is.na(canon_from_cols) | pfas_like_cols]
    if (length(analyte_cols) == 0) return(base)
    canon_names <- setNames(canon_from_cols[match(analyte_cols, names(df))], analyte_cols)
    canon_names[is.na(canon_names)] <- gsub("[^a-z0-9]+", "_", tolower(trimws(analyte_cols[is.na(canon_names)])))

    if (nrow(df) == 0) return(base)
    keep_keys <- CORE_EXTERNAL_MAP_KEYS
    key_map <- setNames(lapply(keep_keys, function(k) base[[k]]), keep_keys)
    long_raw <- as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE) %>%
      tibble::as_tibble() %>%
      mutate(.row_id = seq_len(n())) %>%
      tidyr::pivot_longer(
        cols = dplyr::all_of(analyte_cols),
        names_to = "analyte_col",
        values_to = "result_value_raw"
      )
    if (nrow(long_raw) == 0) return(base)

    row_idx <- pmax(1L, pmin(as.integer(long_raw$.row_id), nrow(df)))
    pick_key <- function(k) {
      v <- key_map[[k]]
      if (is.null(v) || length(v) == 0) return(rep(NA_character_, nrow(long_raw)))
      as.character(v[row_idx])
    }
    qualifier_vec <- trimws(pick_key("qualifier"))
    qualifier_vec[is.na(qualifier_vec)] <- ""
    rvl <- tolower(trimws(as.character(long_raw$result_value_raw)))
    rvl[is.na(rvl)] <- ""
    nd_infer_l <- !nzchar(qualifier_vec) & nzchar(rvl) & safe_detect(
      rvl,
      "^nd$|^n\\.d\\.?$|^non[- ]?detect$|^bdl$|^u$|^uj$|^<"
    )
    qualifier_vec <- ifelse(nd_infer_l, ifelse(safe_detect(rvl, "^\\s*<"), "<", "ND"), qualifier_vec)
    detect_raw <- tolower(trimws(pick_key("detect_flag")))
    detect_from_q <- !safe_detect(tolower(trimws(qualifier_vec %||% "")), "^<|nd|non.?detect|bdl|u\\b|uj\\b")
    detect <- ifelse(
      nzchar(detect_raw),
      detect_raw %in% c("1", "true", "yes", "y", "detect", "detected"),
      detect_from_q
    )

    nlong <- nrow(long_raw)
    out <- tibble::tibble(
      source = "external_upload",
      source_dataset = pick_key("source_dataset"),
      sample_id = pick_key("sample_id"),
      matrix = pick_key("matrix"),
      sample_date = pick_key("date"),
      analyte = as.character(unname(canon_names[long_raw$analyte_col])),
      cas = pick_key("cas"),
      result_value = parse_numeric_value(long_raw$result_value_raw),
      result_unit = normalize_external_result_unit_for_schema(pick_key("unit")),
      qualifier = qualifier_vec,
      mdl = parse_numeric_value(pick_key("mdl")),
      rl = parse_numeric_value(pick_key("rl")),
      detect_flag = as.integer(detect),
      state = pick_key("state"),
      county = pick_key("county"),
      region = rep(NA_character_, nlong),
      facility_water_type = pick_key("facility_water_type"),
      sample_point_type = pick_key("sample_point_type"),
      method_id = pick_key("method_id"),
      collection_year = pick_key("collection_year"),
      collection_month = rep(NA_character_, nlong),
      pws_size = rep(NA_character_, nlong),
      facility_id = pick_key("facility_id"),
      sample_point_id = pick_key("sample_point_id"),
      latitude = parse_numeric_value(pick_key("latitude")),
      longitude = parse_numeric_value(pick_key("longitude")),
      health_endpoint = rep(NA_character_, nlong),
      health_value = rep(NA_real_, nlong),
      dataset_type = dataset_type,
      upload_id = NA_character_,
      uploaded_at = NA_character_,
      pipeline_lane = rep(NA_character_, nlong)
    ) %>%
      filter(!is.na(result_value))

    if (nrow(out) > 0) return(out)

    # Fallback for matrix-style uploads where analyte is in rows and sample IDs are column headers.
    char_cols <- names(df)[vapply(df, function(col) is.character(col) || is.factor(col), logical(1))]
    if (length(char_cols) == 0) return(base)
    analyte_hits <- lapply(char_cols, function(cn) {
      raw <- as.character(df[[cn]])
      mapped <- normalize_analyte_key(raw)
      looks <- is_pfas_like_label(raw)
      mapped[is.na(mapped) & looks] <- gsub("[^a-z0-9]+", "_", tolower(trimws(raw[is.na(mapped) & looks])))
      mapped
    })
    hit_counts <- vapply(analyte_hits, function(v) sum(!is.na(v), na.rm = TRUE), integer(1))
    if (length(hit_counts) == 0 || max(hit_counts, na.rm = TRUE) < 2) return(base)
    analyte_col <- char_cols[[which.max(hit_counts)]]
    analyte_key <- analyte_hits[[which.max(hit_counts)]]
    if (all(is.na(analyte_key))) return(base)

    meta_cols <- unique(c(
      analyte_col,
      trimws(as.character(mapping$source_dataset %||% "")),
      trimws(as.character(mapping$sample_id %||% "")),
      trimws(as.character(mapping$matrix %||% "")),
      trimws(as.character(mapping$date %||% "")),
      trimws(as.character(mapping$unit %||% "")),
      trimws(as.character(mapping$state %||% "")),
      trimws(as.character(mapping$county %||% "")),
      trimws(as.character(mapping$facility_water_type %||% "")),
      trimws(as.character(mapping$sample_point_type %||% "")),
      trimws(as.character(mapping$method_id %||% "")),
      trimws(as.character(mapping$collection_year %||% "")),
      trimws(as.character(mapping$facility_id %||% "")),
      trimws(as.character(mapping$sample_point_id %||% ""))
    ))
    meta_cols <- meta_cols[nzchar(meta_cols) & meta_cols %in% names(df)]
    candidate_cols <- setdiff(names(df), meta_cols)
    if (length(candidate_cols) == 0) return(base)
    numeric_like <- candidate_cols[vapply(candidate_cols, function(cn) {
      vals <- parse_numeric_value(df[[cn]])
      sum(!is.na(vals), na.rm = TRUE) >= 1
    }, logical(1))]
    if (length(numeric_like) == 0) return(base)

    long2 <- as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE) %>%
      tibble::as_tibble() %>%
      mutate(.row_id = seq_len(n()), analyte = analyte_key) %>%
      filter(!is.na(analyte)) %>%
      tidyr::pivot_longer(
        cols = dplyr::all_of(numeric_like),
        names_to = "sample_col",
        values_to = "result_value_raw"
      ) %>%
      mutate(result_value = parse_numeric_value(result_value_raw)) %>%
      filter(!is.na(result_value))
    if (nrow(long2) == 0) return(base)

    pick_matrix_meta <- function(col_name, idx) {
      if (!nzchar(col_name) || !(col_name %in% names(df))) return(rep(NA_character_, length(idx)))
      as.character(df[[col_name]][idx])
    }
    sample_map_col <- trimws(as.character(mapping$sample_id %||% ""))
    matrix_map_col <- trimws(as.character(mapping$matrix %||% ""))
    date_map_col <- trimws(as.character(mapping$date %||% ""))
    state_map_col <- trimws(as.character(mapping$state %||% ""))
    county_map_col <- trimws(as.character(mapping$county %||% ""))
    facility_water_type_map_col <- trimws(as.character(mapping$facility_water_type %||% ""))
    sample_point_type_map_col <- trimws(as.character(mapping$sample_point_type %||% ""))
    method_id_map_col <- trimws(as.character(mapping$method_id %||% ""))
    collection_year_map_col <- trimws(as.character(mapping$collection_year %||% ""))
    facility_id_map_col <- trimws(as.character(mapping$facility_id %||% ""))
    sample_point_id_map_col <- trimws(as.character(mapping$sample_point_id %||% ""))
    unit_map_col <- trimws(as.character(mapping$unit %||% ""))
    src_map_col <- trimws(as.character(mapping$source_dataset %||% ""))
    idx2 <- pmax(1L, pmin(as.integer(long2$.row_id), nrow(df)))
    n2 <- nrow(long2)

    out2 <- tibble::tibble(
      source = "external_upload",
      source_dataset = {
        v <- pick_matrix_meta(src_map_col, idx2)
        ifelse(is.na(v) | !nzchar(v), dataset_type, v)
      },
      sample_id = {
        v <- pick_matrix_meta(sample_map_col, idx2)
        ifelse(is.na(v) | !nzchar(v), as.character(long2$sample_col), v)
      },
      matrix = pick_matrix_meta(matrix_map_col, idx2),
      sample_date = pick_matrix_meta(date_map_col, idx2),
      analyte = as.character(long2$analyte),
      cas = NA_character_,
      result_value = long2$result_value,
      result_unit = normalize_external_result_unit_for_schema(pick_matrix_meta(unit_map_col, idx2)),
      qualifier = NA_character_,
      mdl = NA_real_,
      rl = NA_real_,
      detect_flag = as.integer(1),
      state = pick_matrix_meta(state_map_col, idx2),
      county = pick_matrix_meta(county_map_col, idx2),
      region = rep(NA_character_, n2),
      facility_water_type = pick_matrix_meta(facility_water_type_map_col, idx2),
      sample_point_type = pick_matrix_meta(sample_point_type_map_col, idx2),
      method_id = pick_matrix_meta(method_id_map_col, idx2),
      collection_year = pick_matrix_meta(collection_year_map_col, idx2),
      collection_month = rep(NA_character_, n2),
      pws_size = rep(NA_character_, n2),
      facility_id = pick_matrix_meta(facility_id_map_col, idx2),
      sample_point_id = pick_matrix_meta(sample_point_id_map_col, idx2),
      latitude = NA_real_,
      longitude = NA_real_,
      health_endpoint = NA_character_,
      health_value = NA_real_,
      dataset_type = dataset_type,
      upload_id = NA_character_,
      uploaded_at = NA_character_,
      pipeline_lane = rep(NA_character_, n2)
    )
    out2
  }

  append_pipeline_log <- function(...) {
    msg <- paste(..., collapse = "")
    stamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    pfas_pipeline_log(paste0(pfas_pipeline_log(), "\n[", stamp, "] ", msg))
  }

  bool_mark <- function(x) if (isTRUE(x)) "\u2705" else "\u274c"

  is_identifier_like_result_col <- function(col_name) {
    nm <- tolower(gsub("[^a-z0-9]+", "", trimws(as.character(col_name %||% ""))))
    if (!nzchar(nm)) return(FALSE)
    looks_result <- safe_detect(nm, "result|concentration|value|ngl|clean|analyticalresult")
    looks_id <- safe_detect(nm, "pws|well|station|sample|facility|point|(^id$)|id$")
    isTRUE(looks_id) && !isTRUE(looks_result)
  }

  resolve_pipeline_path <- function(raw_value, default_path) {
    p <- trimws(as.character(raw_value %||% ""))
    if (!nzchar(p)) p <- default_path
    p
  }

  path_file_count <- function(path) {
    if (is.null(path) || !nzchar(path)) return(0L)
    if (file.exists(path) && !dir.exists(path)) return(1L)
    if (!dir.exists(path)) return(0L)
    as.integer(length(list.files(path, full.names = TRUE)))
  }

  is_placeholder_preflight_template_basename <- function(bnm) {
    b <- tolower(as.character(bnm %||% ""))
    if (!nzchar(b)) return(FALSE)
    if (grepl("^iso17025_preflight_.*template\\.", b, perl = TRUE)) return(TRUE)
    if (grepl("_template\\.(csv|tsv|txt|xlsx|xls)$", b, perl = TRUE)) return(TRUE)
    if (grepl("preflight", b, fixed = TRUE) && grepl("template", b, fixed = TRUE)) return(TRUE)
    FALSE
  }

  latest_non_placeholder_file <- function(path) {
    if (is.null(path) || !nzchar(trimws(path))) return(NULL)
    path <- trimws(path)
    if (file.exists(path) && !dir.exists(path)) {
      if (is_placeholder_preflight_template_basename(basename(path))) return(NULL)
      return(path)
    }
    if (!dir.exists(path)) return(NULL)
    files <- list.files(path, full.names = TRUE, recursive = FALSE)
    exts <- tolower(tools::file_ext(files))
    files <- files[exts %in% c("csv", "tsv", "txt", "xlsx", "xls")]
    if (length(files) == 0L) return(NULL)
    files <- files[!vapply(basename(files), is_placeholder_preflight_template_basename, logical(1))]
    if (length(files) == 0L) return(NULL)
    info <- suppressWarnings(file.info(files))
    files[[which.max(info$mtime)]]
  }

  check_method_dataset_schema <- function(path_value = NULL) {
    default_method <- file.path(PROJECT_DIR, "data", "external", "method_data")
    method_path <- resolve_pipeline_path(path_value, default_method)
    mf <- latest_non_placeholder_file(method_path)
    if (is.null(mf)) return(list(ok = FALSE, path = method_path, file = NA_character_))
    md <- read_any_table(mf, max_rows = 2000)
    if (is.null(md) || nrow(md) == 0) return(list(ok = FALSE, path = method_path, file = basename(mf)))
    required_aliases <- list(
      method_id = c("Method_ID", "method_id", "MethodID"),
      matrix_type = c("Matrix_Type", "matrix_type", "MatrixType"),
      lod = c("Detection_Limit", "LOD", "detection_limit", "detection_limit_lod"),
      loq = c("Quantification_Limit", "LOQ", "quantification_limit", "reporting_limit")
    )
    found <- vapply(required_aliases, function(a) !is.null(pick_col(md, a)), logical(1))
    list(ok = all(found), path = method_path, file = basename(mf), found = found)
  }

  check_reference_dataset_schema <- function(path_value = NULL) {
    default_ref <- file.path(PROJECT_DIR, "data", "external", "method_validation")
    ref_path <- resolve_pipeline_path(path_value, default_ref)
    rf <- latest_non_placeholder_file(ref_path)
    if (is.null(rf)) return(list(ok = FALSE, path = ref_path, file = NA_character_))
    rd <- read_any_table(rf, max_rows = 2000)
    if (is.null(rd) || nrow(rd) == 0) return(list(ok = FALSE, path = ref_path, file = basename(rf)))
    target_col <- pick_col(rd, c("PFAS_Risk_Flag", "actual", "target", "risk_flag", "expected_pfas_risk_flag"))
    concentration_col <- pick_col(rd, c("result_value", "concentration", "known_concentration", "reference_concentration"))
    list(
      ok = !is.null(target_col) && !is.null(concentration_col),
      path = ref_path,
      file = basename(rf),
      found = c(target = !is.null(target_col), concentration = !is.null(concentration_col))
    )
  }

  check_qc_dataset_schema <- function(path_value = NULL) {
    default_qc <- file.path(PROJECT_DIR, "data", "external", "qc_datasets")
    qc_path <- resolve_pipeline_path(path_value, default_qc)
    qf <- latest_non_placeholder_file(qc_path)
    if (is.null(qf)) return(list(ok = FALSE, path = qc_path, file = NA_character_))
    qd <- read_any_table(qf, max_rows = 2000)
    if (is.null(qd) || nrow(qd) == 0) return(list(ok = FALSE, path = qc_path, file = basename(qf)))
    required_aliases <- list(
      qc_type = c("QC_Type", "qc_type", "qc"),
      recovery_percent = c("Recovery_Percent", "recovery_percent", "recovery_pct", "recovery"),
      rsd = c("RSD", "rsd", "relative_standard_deviation"),
      batch_id = c("Batch_ID", "batch_id", "batch"),
      analyst_id = c("Analyst_ID", "analyst_id", "analyst")
    )
    found <- vapply(required_aliases, function(a) !is.null(pick_col(qd, a)), logical(1))
    list(ok = all(found), path = qc_path, file = basename(qf), found = found)
  }

  check_pt_dataset_schema <- function(path_value = NULL) {
    default_pt <- file.path(PROJECT_DIR, "data", "external", "proficiency_testing")
    pt_path <- resolve_pipeline_path(path_value, default_pt)
    pf <- latest_non_placeholder_file(pt_path)
    if (is.null(pf)) return(list(ok = FALSE, path = pt_path, file = NA_character_))
    pd <- read_any_table(pf, max_rows = 2000)
    if (is.null(pd) || nrow(pd) == 0) return(list(ok = FALSE, path = pt_path, file = basename(pf)))
    expected_col <- pick_col(pd, c("expected_pfas_risk_flag", "expected_flag", "assigned_flag", "target"))
    z_col <- pick_col(pd, c("z_score", "zscore", "pt_zscore"))
    provider_col <- pick_col(pd, c("pt_provider", "provider", "scheme_provider", "program"))
    list(
      ok = (!is.null(expected_col) || !is.null(z_col)) && !is.null(provider_col),
      path = pt_path,
      file = basename(pf),
      found = c(expected_or_z = (!is.null(expected_col) || !is.null(z_col)), provider = !is.null(provider_col))
    )
  }

  run_iso_preflight_check <- function() {
    ref <- check_reference_dataset_schema(input$pfas_ref_path)
    method <- check_method_dataset_schema(input$pfas_method_path)
    qc <- check_qc_dataset_schema(input$pfas_qc_path)
    pt <- check_pt_dataset_schema(input$pfas_pt_path)
    checks <- c(reference = isTRUE(ref$ok), method = isTRUE(method$ok), qc = isTRUE(qc$ok), pt = isTRUE(pt$ok))
    list(
      ok = all(checks),
      checks = checks,
      ref = ref,
      method = method,
      qc = qc,
      pt = pt
    )
  }

  iso_preflight_failed_paths_note <- function(pf) {
    failed <- names(pf$checks)[!pf$checks]
    if (length(failed) == 0L) {
      return("")
    }
    one <- function(tag, comp) {
      fn <- comp$file %||% ""
      if (length(fn) != 1L) fn <- fn[[1]]
      fn <- as.character(fn)[1]
      if (is.na(fn)) fn <- ""
      fp <- as.character(comp$path %||% "")[1]
      paste0(tag, "=", fp, if (nzchar(fn)) paste0("(", fn, ")") else "(no_eligible_file)")
    }
    bits <- character(0)
    if ("reference" %in% failed) bits <- c(bits, one("ref", pf$ref))
    if ("method" %in% failed) bits <- c(bits, one("method", pf$method))
    if ("qc" %in% failed) bits <- c(bits, one("qc", pf$qc))
    if ("pt" %in% failed) bits <- c(bits, one("pt", pf$pt))
    paste(bits, collapse = "; ")
  }

  enforce_iso_preflight <- function(action_label = "This action") {
    skip <- trimws(Sys.getenv("PFAS_SKIP_ISO_PREFLIGHT", ""))
    if (nzchar(skip) && tolower(skip) %in% c("1", "true", "yes")) {
      iso_preflight_note(paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " SKIPPED (PFAS_SKIP_ISO_PREFLIGHT)"))
      append_pipeline_log("ISO preflight skipped (PFAS_SKIP_ISO_PREFLIGHT) for ", action_label)
      return(TRUE)
    }
    pf <- run_iso_preflight_check()
    if (isTRUE(pf$ok)) {
      iso_preflight_note(paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " PASS"))
      return(TRUE)
    }
    failed <- names(pf$checks)[!pf$checks]
    iso_preflight_note(paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " BLOCK (", paste(failed, collapse = ", "), ")"))
    showNotification(
      paste0(action_label, " blocked: ISO preflight failed (", paste(failed, collapse = ", "), ")."),
      type = "error",
      duration = 10
    )
    append_pipeline_log(
      "ISO preflight BLOCK for ", action_label, " | failed=", paste(failed, collapse = ", "),
      " | ", iso_preflight_failed_paths_note(pf)
    )
    FALSE
  }

  pipeline_component_status <- reactive({
    pfas_results_nonce()
    has_icis_dmr <- length(Sys.glob(file.path(PROJECT_DIR, "data", "processed", "npdes_dmr_pfas_fy*.csv"))) > 0L
    has_raw_occurrence <- {
      p1 <- file.path(PROJECT_DIR, "data", "training", "pfas_multisource_training.csv")
      p2 <- file.path(PROJECT_DIR, "data", "processed", "pfas_training_master.csv")
      (file.exists(p1) && tryCatch(nrow(read.csv(p1, nrows = 1)) >= 0, error = function(e) FALSE)) ||
        (file.exists(p2) && tryCatch(nrow(read.csv(p2, nrows = 1)) >= 0, error = function(e) FALSE)) ||
        isTRUE(has_icis_dmr)
    }
    has_regulatory <- {
      cfg <- file.path(PROJECT_DIR, "data", "config", "pfas_regulatory_limits.csv")
      file.exists(cfg)
    }
    has_certified_validation <- isTRUE(check_reference_dataset_schema(input$pfas_ref_path)$ok)
    has_qc <- isTRUE(check_qc_dataset_schema(input$pfas_qc_path)$ok)
    has_pt <- isTRUE(check_pt_dataset_schema(input$pfas_pt_path)$ok)
    has_method_structure <- isTRUE(check_method_dataset_schema(input$pfas_method_path)$ok)
    tibble::tibble(
      Component = c(
        "Occurrence / training tables",
        "ICIS-NPDES PFAS-filtered DMR CSV (processed/)",
        "Regulatory limits (config file)",
        "Reference folder: CSV schema (real data, not templates)",
        "QC folder: CSV schema (real lab QC, not templates)",
        "Method metadata folder: CSV schema",
        "PT folder: CSV schema (real PT, not templates)"
      ),
      schema_check = c(
        bool_mark(has_raw_occurrence),
        bool_mark(has_icis_dmr),
        bool_mark(has_regulatory),
        bool_mark(has_certified_validation),
        bool_mark(has_qc),
        bool_mark(has_method_structure),
        bool_mark(has_pt)
      )
    )
  })

  read_any_table <- function(path, max_rows = Inf) {
    ext <- tolower(tools::file_ext(path))
    if (!file.exists(path)) return(NULL)
    nr_limit <- if (is.finite(max_rows) && max_rows > 0) max_rows else NA_integer_
    if (ext %in% c("csv")) {
      return(read_delimited_robust(path, sep = ",", header = TRUE, nrows = nr_limit))
    }
    if (ext %in% c("tsv")) {
      return(read_delimited_robust(path, sep = "\t", header = TRUE, nrows = nr_limit))
    }
    if (ext %in% c("txt")) {
      first <- read_first_line_robust(path)
      sep <- if (!nzchar(first)) "," else {
        counts <- c(
          comma = lengths(regmatches(first, gregexpr(",", first, fixed = TRUE))),
          tab = lengths(regmatches(first, gregexpr("\t", first, fixed = TRUE))),
          semi = lengths(regmatches(first, gregexpr(";", first, fixed = TRUE))),
          pipe = lengths(regmatches(first, gregexpr("|", first, fixed = TRUE)))
        )
        c(comma = ",", tab = "\t", semi = ";", pipe = "|")[names(which.max(counts))]
      }
      return(read_delimited_robust(path, sep = sep, header = TRUE, nrows = nr_limit))
    }
    if (ext %in% c("xlsx", "xls")) {
      if (!requireNamespace("readxl", quietly = TRUE)) return(NULL)
      return(tryCatch(as.data.frame(readxl::read_excel(path, n_max = max_rows)), error = function(e) NULL))
    }
    if (ext %in% c("json")) {
      if (!requireNamespace("jsonlite", quietly = TRUE)) return(NULL)
      return(tryCatch(as.data.frame(jsonlite::fromJSON(path, flatten = TRUE)), error = function(e) NULL))
    }
    NULL
  }

  normalize_names <- function(x) tolower(gsub("[^a-z0-9]+", "", as.character(x %||% "")))

  pick_col <- function(df, aliases) {
    if (is.null(df) || nrow(df) < 0) return(NULL)
    nms <- names(df)
    if (length(nms) == 0) return(NULL)
    nn <- normalize_names(nms)
    aa <- normalize_names(aliases)
    idx <- match(aa, nn)
    idx <- idx[!is.na(idx)]
    if (length(idx) == 0) return(NULL)
    nms[idx[[1]]]
  }

  ensure_uploaded_artifact <- function(file_input, target_dir, fallback_name) {
    if (is.null(file_input) || is.null(file_input$datapath) || !file.exists(file_input$datapath)) return(NULL)
    dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
    safe_name <- gsub("[^A-Za-z0-9._-]", "_", basename(file_input$name %||% fallback_name))
    dest <- file.path(target_dir, paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_", safe_name))
    ok <- tryCatch(file.copy(file_input$datapath, dest, overwrite = TRUE), error = function(e) FALSE)
    if (!isTRUE(ok)) return(NULL)
    dest
  }

  latest_file <- function(path) {
    if (is.null(path) || !nzchar(path)) return(NULL)
    if (file.exists(path) && !dir.exists(path)) return(path)
    if (!dir.exists(path)) return(NULL)
    files <- list.files(path, full.names = TRUE)
    if (length(files) == 0) return(NULL)
    info <- file.info(files)
    files[[which.max(info$mtime)]]
  }

  load_qc_method_thresholds <- function() {
    defaults <- tibble::tibble(
      method_key = c("EPA_533", "EPA_537_1", "EPA_1633", "GENERIC"),
      recovery_min = c(70, 70, 50, 70),
      recovery_max = c(130, 130, 150, 130),
      rpd_max = c(30, 30, 40, 30),
      blank_abs_max = c(1e-3, 1e-3, 1e-3, 1e-3)
    )
    cfg <- file.path(PROJECT_DIR, "data", "config", "qc_method_thresholds.csv")
    if (!file.exists(cfg)) {
      attr(defaults, "threshold_source") <- "built_in_defaults"
      return(defaults)
    }

    raw <- tryCatch(utils::read.csv(cfg, stringsAsFactors = FALSE, check.names = FALSE), error = function(e) NULL)
    required <- c("method_key", "recovery_min", "recovery_max", "rpd_max", "blank_abs_max")
    if (is.null(raw) || !all(required %in% names(raw))) {
      append_pipeline_log("QC thresholds config invalid; using built-in defaults.")
      attr(defaults, "threshold_source") <- "built_in_defaults_invalid_config"
      return(defaults)
    }

    cleaned <- raw[, required, drop = FALSE]
    cleaned$method_key <- toupper(gsub("[^A-Za-z0-9]+", "_", trimws(as.character(cleaned$method_key))))
    cleaned$recovery_min <- suppressWarnings(as.numeric(cleaned$recovery_min))
    cleaned$recovery_max <- suppressWarnings(as.numeric(cleaned$recovery_max))
    cleaned$rpd_max <- suppressWarnings(as.numeric(cleaned$rpd_max))
    cleaned$blank_abs_max <- suppressWarnings(as.numeric(cleaned$blank_abs_max))
    cleaned <- cleaned[
      nzchar(cleaned$method_key) &
        !is.na(cleaned$recovery_min) &
        !is.na(cleaned$recovery_max) &
        !is.na(cleaned$rpd_max) &
        !is.na(cleaned$blank_abs_max),
      ,
      drop = FALSE
    ]
    if (nrow(cleaned) == 0) {
      append_pipeline_log("QC thresholds config has no valid rows; using built-in defaults.")
      attr(defaults, "threshold_source") <- "built_in_defaults_empty_config"
      return(defaults)
    }
    cleaned <- cleaned[!duplicated(cleaned$method_key), , drop = FALSE]
    if (!("GENERIC" %in% cleaned$method_key)) {
      cleaned <- rbind(cleaned, defaults[defaults$method_key == "GENERIC", , drop = FALSE])
    }
    out <- tibble::as_tibble(cleaned)
    attr(out, "threshold_source") <- cfg
    out
  }

  step_validate_reference_dataset <- function() {
    ref_path <- resolve_pipeline_path(input$pfas_ref_path, file.path(PROJECT_DIR, "data", "external", "method_validation"))
    ref_file <- latest_non_placeholder_file(ref_path)
    if (is.null(ref_file)) {
      pipeline_last_error("No reference dataset found at PFAS Reference Data Path.")
      return(FALSE)
    }
    ref_df <- read_any_table(ref_file)
    if (is.null(ref_df) || nrow(ref_df) == 0) {
      pipeline_last_error("Reference dataset could not be read or is empty.")
      return(FALSE)
    }
    pred_file <- file.path(PROJECT_DIR, "results", "prediction_output.csv")
    val_file <- file.path(PROJECT_DIR, "results", "validation_summary.csv")
    model_df <- if (file.exists(pred_file)) read_any_table(pred_file) else read_any_table(val_file)
    if (is.null(model_df) || nrow(model_df) == 0) {
      pipeline_last_error("No model output found (results/prediction_output.csv or validation_summary.csv).")
      return(FALSE)
    }

    ref_target_col <- pick_col(ref_df, c("PFAS_Risk_Flag", "actual", "target", "risk_flag"))
    mdl_pred_col <- pick_col(model_df, c("predicted_PFAS_Risk_Flag", "predicted", "prediction", "pred"))
    mdl_prob_col <- pick_col(model_df, c("probability_exceedance", "prob", "score"))
    if (is.null(ref_target_col) || (is.null(mdl_pred_col) && is.null(mdl_prob_col))) {
      pipeline_last_error("Reference/model files are missing target or prediction columns required for validation.")
      return(FALSE)
    }

    n_eval <- min(nrow(ref_df), nrow(model_df))
    ref_target <- suppressWarnings(as.integer(as.numeric(ref_df[[ref_target_col]][seq_len(n_eval)])))
    if (!is.null(mdl_pred_col)) {
      mdl_pred <- suppressWarnings(as.integer(as.numeric(model_df[[mdl_pred_col]][seq_len(n_eval)])))
    } else {
      mdl_prob <- suppressWarnings(as.numeric(model_df[[mdl_prob_col]][seq_len(n_eval)]))
      mdl_pred <- as.integer(mdl_prob >= 0.5)
    }
    keep <- !(is.na(ref_target) | is.na(mdl_pred))
    eval_rows <- sum(keep)
    if (eval_rows < 10) {
      pipeline_last_error("Insufficient overlap rows for reference validation (<10 comparable rows).")
      return(FALSE)
    }
    accuracy <- mean(ref_target[keep] == mdl_pred[keep])

    summary_df <- tibble::tibble(
      reference_path = ref_path,
      reference_file = basename(ref_file),
      model_file = if (file.exists(pred_file)) basename(pred_file) else basename(val_file),
      evaluated_rows = eval_rows,
      agreement_accuracy = round(accuracy, 4),
      status = ifelse(accuracy >= 0.70, "PASS", "REVIEW")
    )
    out_file <- file.path(PROJECT_DIR, "results", "reference_validation_summary.csv")
    try(utils::write.csv(summary_df, out_file, row.names = FALSE), silent = TRUE)
    append_pipeline_log("Reference dataset loaded/validated: rows=", eval_rows, ", accuracy=", sprintf("%.3f", accuracy), ".")
    pipeline_last_error("")
    TRUE
  }

  step_qc_validation_check <- function() {
    qc_path <- resolve_pipeline_path(input$pfas_qc_path, file.path(PROJECT_DIR, "data", "external", "qc_datasets"))
    qf <- latest_non_placeholder_file(qc_path)
    if (is.null(qf)) {
      pipeline_last_error("No QC dataset found at PFAS QC Data Path.")
      return(FALSE)
    }
    qd <- read_any_table(qf)
    if (is.null(qd) || nrow(qd) == 0) {
      pipeline_last_error("QC dataset could not be read or is empty.")
      return(FALSE)
    }
    qc_required <- list(
      qc_type = c("QC_Type", "qc_type", "qc"),
      recovery_percent = c("Recovery_Percent", "recovery_percent", "recovery_pct", "recovery"),
      rsd = c("RSD", "rsd", "relative_standard_deviation"),
      batch_id = c("Batch_ID", "batch_id", "batch"),
      analyst_id = c("Analyst_ID", "analyst_id", "analyst")
    )
    qc_required_found <- vapply(qc_required, function(a) !is.null(pick_col(qd, a)), logical(1))
    if (!all(qc_required_found)) {
      missing <- names(qc_required_found)[!qc_required_found]
      pipeline_last_error(paste0("QC dataset missing required ISO columns: ", paste(missing, collapse = ", ")))
      return(FALSE)
    }
    rec_col <- pick_col(qd, c("recovery_pct", "recovery", "percent_recovery", "spike_recovery", "lcs_recovery", "ms_recovery"))
    rpd_col <- pick_col(qd, c("duplicate_rpd", "rpd", "relative_percent_difference", "dup_rpd"))
    blank_col <- pick_col(qd, c("blank_result", "method_blank", "blank_ngl", "blank", "mb_result"))
    method_col <- pick_col(qd, c("method_id", "methodid", "method", "epa_method", "analytical_method"))
    rl_col <- pick_col(qd, c("rl", "reporting_limit", "quantitation_limit", "loq"))
    mdl_col <- pick_col(qd, c("mdl", "method_detection_limit", "detection_limit"))

    if (is.null(method_col)) {
      method_key <- rep("GENERIC", nrow(qd))
    } else {
      raw_method <- toupper(trimws(as.character(qd[[method_col]])))
      method_key <- ifelse(grepl("1633", raw_method), "EPA_1633",
                    ifelse(grepl("537\\.1|5371", raw_method), "EPA_537_1",
                    ifelse(grepl("533", raw_method), "EPA_533", "GENERIC")))
    }

    thresholds <- load_qc_method_thresholds()
    threshold_source <- as.character(attr(thresholds, "threshold_source") %||% "built_in_defaults")
    th_map <- thresholds[match(method_key, thresholds$method_key), , drop = FALSE]

    rec <- if (is.null(rec_col)) rep(NA_real_, nrow(qd)) else suppressWarnings(as.numeric(qd[[rec_col]]))
    rpd <- if (is.null(rpd_col)) rep(NA_real_, nrow(qd)) else suppressWarnings(as.numeric(qd[[rpd_col]]))
    b <- if (is.null(blank_col)) rep(NA_real_, nrow(qd)) else suppressWarnings(as.numeric(qd[[blank_col]]))
    rl <- if (is.null(rl_col)) rep(NA_real_, nrow(qd)) else suppressWarnings(as.numeric(qd[[rl_col]]))
    mdl <- if (is.null(mdl_col)) rep(NA_real_, nrow(qd)) else suppressWarnings(as.numeric(qd[[mdl_col]]))
    blank_limit <- ifelse(!is.na(rl), rl, ifelse(!is.na(mdl), mdl, th_map$blank_abs_max))

    rec_ok <- if (is.null(rec_col)) rep(NA, nrow(qd)) else (rec >= th_map$recovery_min & rec <= th_map$recovery_max)
    rpd_ok <- if (is.null(rpd_col)) rep(NA, nrow(qd)) else (rpd <= th_map$rpd_max)
    blank_ok <- if (is.null(blank_col)) rep(NA, nrow(qd)) else (abs(b) <= blank_limit)

    checks_present <- sum(!is.na(c(
      if (all(is.na(rec_ok))) NA else mean(rec_ok, na.rm = TRUE),
      if (all(is.na(rpd_ok))) NA else mean(rpd_ok, na.rm = TRUE),
      if (all(is.na(blank_ok))) NA else mean(blank_ok, na.rm = TRUE)
    )))
    if (checks_present == 0) {
      pipeline_last_error("QC dataset missing recognizable QC metric columns (recovery/rpd/blank).")
      return(FALSE)
    }

    detail <- tibble::tibble(
      method_key = method_key,
      recovery_ok = rec_ok,
      rpd_ok = rpd_ok,
      blank_ok = blank_ok
    )

    summary_by_method <- detail |>
      dplyr::group_by(method_key) |>
      dplyr::summarise(
        rows = dplyr::n(),
        recovery_pass_rate = if (all(is.na(recovery_ok))) NA_real_ else mean(recovery_ok, na.rm = TRUE),
        duplicate_rpd_pass_rate = if (all(is.na(rpd_ok))) NA_real_ else mean(rpd_ok, na.rm = TRUE),
        blank_pass_rate = if (all(is.na(blank_ok))) NA_real_ else mean(blank_ok, na.rm = TRUE),
        .groups = "drop"
      ) |>
      dplyr::left_join(thresholds, by = "method_key") |>
      dplyr::mutate(
        overall_qc_pass_rate = rowMeans(dplyr::across(c(recovery_pass_rate, duplicate_rpd_pass_rate, blank_pass_rate)), na.rm = TRUE),
        status = ifelse(overall_qc_pass_rate >= 0.80, "PASS", "REVIEW"),
        qc_file = basename(qf),
        qc_path = qc_path,
        threshold_source = threshold_source
      ) |>
      dplyr::select(
        qc_file, method_key, rows,
        threshold_source,
        recovery_min, recovery_max, rpd_max, blank_abs_max,
        recovery_pass_rate, duplicate_rpd_pass_rate, blank_pass_rate,
        overall_qc_pass_rate, status
      )

    overall <- weighted.mean(summary_by_method$overall_qc_pass_rate, w = summary_by_method$rows, na.rm = TRUE)
    out <- summary_by_method
    out_file <- file.path(PROJECT_DIR, "results", "qc_validation_summary.csv")
    try(utils::write.csv(out, out_file, row.names = FALSE), silent = TRUE)
    append_pipeline_log(
      "QC validation complete: overall pass rate=", sprintf("%.3f", overall),
      " | methods=", paste(unique(summary_by_method$method_key), collapse = ", "),
      " | thresholds=", threshold_source, "."
    )
    pipeline_last_error("")
    TRUE
  }

  step_applicability_domain_check <- function() {
    pred_file <- file.path(PROJECT_DIR, "results", "prediction_output.csv")
    val_file <- file.path(PROJECT_DIR, "results", "validation_summary.csv")
    df <- if (file.exists(pred_file)) read_any_table(pred_file) else read_any_table(val_file)
    if (is.null(df) || nrow(df) == 0) {
      pipeline_last_error("No prediction/validation output available for applicability-domain check.")
      return(FALSE)
    }
    ad_col <- pick_col(df, c("applicability_domain", "ad_status"))
    unc_col <- pick_col(df, c("uncertainty_score", "uncertainty"))
    review_col <- pick_col(df, c("manual_review_required", "review_required"))

    outside_rate <- NA_real_
    if (!is.null(ad_col)) {
      ad <- tolower(as.character(df[[ad_col]]))
      outside_rate <- mean(grepl("outside|review", ad), na.rm = TRUE)
    }
    high_uncertainty_rate <- NA_real_
    if (!is.null(unc_col)) {
      u <- suppressWarnings(as.numeric(df[[unc_col]]))
      high_uncertainty_rate <- mean(u > 0.50, na.rm = TRUE)
    }
    manual_review_rate <- NA_real_
    if (!is.null(review_col)) {
      mr <- tolower(as.character(df[[review_col]]))
      manual_review_rate <- mean(mr %in% c("true", "1", "yes"), na.rm = TRUE)
    }

    metrics <- c(outside_rate, high_uncertainty_rate, manual_review_rate)
    if (all(is.na(metrics))) {
      pipeline_last_error("Applicability-domain fields missing (need AD, uncertainty, or review columns).")
      return(FALSE)
    }
    risk_rate <- max(metrics, na.rm = TRUE)
    out <- tibble::tibble(
      evaluated_rows = nrow(df),
      outside_ad_rate = outside_rate,
      high_uncertainty_rate = high_uncertainty_rate,
      manual_review_rate = manual_review_rate,
      ad_risk_rate = risk_rate,
      status = ifelse(is.finite(risk_rate) && risk_rate <= 0.30, "PASS", "REVIEW")
    )
    out_file <- file.path(PROJECT_DIR, "results", "applicability_domain_check.csv")
    try(utils::write.csv(out, out_file, row.names = FALSE), silent = TRUE)
    append_pipeline_log("Applicability-domain check complete: risk rate=", sprintf("%.3f", risk_rate), ".")
    pipeline_last_error("")
    TRUE
  }

  step_external_pt_validation <- function() {
    pt_path <- resolve_pipeline_path(input$pfas_pt_path, file.path(PROJECT_DIR, "data", "external", "proficiency_testing"))
    pf <- latest_non_placeholder_file(pt_path)
    if (is.null(pf)) {
      pipeline_last_error("No PT dataset found at PFAS Proficiency Test Path.")
      return(FALSE)
    }
    ptd <- read_any_table(pf)
    if (is.null(ptd) || nrow(ptd) == 0) {
      pipeline_last_error("PT dataset could not be read or is empty.")
      return(FALSE)
    }

    pred_file <- file.path(PROJECT_DIR, "results", "prediction_output.csv")
    val_file <- file.path(PROJECT_DIR, "results", "validation_summary.csv")
    model_df <- if (file.exists(pred_file)) read_any_table(pred_file) else read_any_table(val_file)
    if (is.null(model_df) || nrow(model_df) == 0) {
      pipeline_last_error("No model output available for PT external validation.")
      return(FALSE)
    }

    pt_expected_flag_col <- pick_col(ptd, c("expected_pfas_risk_flag", "expected_flag", "assigned_flag", "target"))
    pt_z_col <- pick_col(ptd, c("z_score", "zscore", "pt_zscore"))
    mdl_pred_col <- pick_col(model_df, c("predicted_PFAS_Risk_Flag", "predicted", "prediction"))
    if (is.null(pt_expected_flag_col) && is.null(pt_z_col)) {
      pipeline_last_error("PT dataset missing expected result columns (expected flag or z-score).")
      return(FALSE)
    }
    if (is.null(mdl_pred_col) && is.null(pt_z_col)) {
      pipeline_last_error("Model output missing predicted flag required for PT concordance.")
      return(FALSE)
    }

    n_eval <- min(nrow(ptd), nrow(model_df))
    concordance <- NA_real_
    if (!is.null(pt_expected_flag_col) && !is.null(mdl_pred_col)) {
      expected <- suppressWarnings(as.integer(as.numeric(ptd[[pt_expected_flag_col]][seq_len(n_eval)])))
      pred <- suppressWarnings(as.integer(as.numeric(model_df[[mdl_pred_col]][seq_len(n_eval)])))
      keep <- !(is.na(expected) | is.na(pred))
      if (sum(keep) > 0) concordance <- mean(expected[keep] == pred[keep])
    }
    z_pass_rate <- NA_real_
    if (!is.null(pt_z_col)) {
      z <- suppressWarnings(as.numeric(ptd[[pt_z_col]][seq_len(n_eval)]))
      z_pass_rate <- mean(abs(z) <= 2, na.rm = TRUE)
    }
    metrics <- c(concordance, z_pass_rate)
    if (all(is.na(metrics))) {
      pipeline_last_error("PT external validation has no evaluable rows.")
      return(FALSE)
    }
    score <- max(metrics, na.rm = TRUE)
    out <- tibble::tibble(
      pt_path = pt_path,
      pt_file = basename(pf),
      evaluated_rows = n_eval,
      concordance_rate = concordance,
      zscore_pass_rate = z_pass_rate,
      external_validation_score = score,
      status = ifelse(is.finite(score) && score >= 0.80, "PASS", "REVIEW")
    )
    out_file <- file.path(PROJECT_DIR, "results", "pt_external_validation_summary.csv")
    try(utils::write.csv(out, out_file, row.names = FALSE), silent = TRUE)
    append_pipeline_log("PT external validation complete: score=", sprintf("%.3f", score), ".")
    pipeline_last_error("")
    TRUE
  }

  step_generate_iso_compliance_report <- function() {
    ref_file <- file.path(PROJECT_DIR, "results", "reference_validation_summary.csv")
    qc_file <- file.path(PROJECT_DIR, "results", "qc_validation_summary.csv")
    ad_file <- file.path(PROJECT_DIR, "results", "applicability_domain_check.csv")
    pt_file <- file.path(PROJECT_DIR, "results", "pt_external_validation_summary.csv")
    ref_df <- if (file.exists(ref_file)) read_any_table(ref_file) else NULL
    qc_df <- if (file.exists(qc_file)) read_any_table(qc_file) else NULL
    ad_df <- if (file.exists(ad_file)) read_any_table(ad_file) else NULL
    pt_df <- if (file.exists(pt_file)) read_any_table(pt_file) else NULL
    comp <- pipeline_component_status()
    component_pass <- all(comp$schema_check == "\u2705")
    method_ok <- isTRUE(check_method_dataset_schema(input$pfas_method_path)$ok)
    ref_ok <- !is.null(ref_df) && nrow(ref_df) > 0 && toupper(as.character(ref_df$status[[1]] %||% "REVIEW")) == "PASS"
    qc_ok <- !is.null(qc_df) && nrow(qc_df) > 0 && all(toupper(as.character(qc_df$status %||% "REVIEW")) == "PASS")
    ad_ok <- !is.null(ad_df) && nrow(ad_df) > 0 && toupper(as.character(ad_df$status[[1]] %||% "REVIEW")) == "PASS"
    pt_ok <- !is.null(pt_df) && nrow(pt_df) > 0 && toupper(as.character(pt_df$status[[1]] %||% "REVIEW")) == "PASS"
    overall <- component_pass && method_ok && ref_ok && qc_ok && ad_ok && pt_ok

    out_json <- list(
      generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
      iso_mode = TRUE,
      pipeline_components_complete = component_pass,
      method_dataset_schema = if (method_ok) "PASS" else "REVIEW",
      reference_validation = if (ref_ok) "PASS" else "REVIEW",
      qc_validation = if (qc_ok) "PASS" else "REVIEW",
      applicability_domain = if (ad_ok) "PASS" else "REVIEW",
      proficiency_testing_validation = if (pt_ok) "PASS" else "REVIEW",
      overall_status = if (overall) "READY_FOR_REVIEW" else "ACTION_REQUIRED"
    )
    json_path <- file.path(PROJECT_DIR, "results", "iso_compliance_report.json")
    txt_path <- file.path(PROJECT_DIR, "results", "iso_compliance_report.txt")
    if (requireNamespace("jsonlite", quietly = TRUE)) {
      try(jsonlite::write_json(out_json, json_path, pretty = TRUE, auto_unbox = TRUE), silent = TRUE)
    } else {
      try(utils::write.csv(as.data.frame(out_json, stringsAsFactors = FALSE), file.path(PROJECT_DIR, "results", "iso_compliance_report_fallback.csv"), row.names = FALSE), silent = TRUE)
    }
    lines <- c(
      "PFAS Enterprise 4.0 - ISO Compliance Report",
      paste0("Generated: ", out_json$generated_at),
      "",
      paste0("Schema / folder row checks (not lab validation): ", if (component_pass) "all pass" else "gaps remain"),
      paste0("Method dataset schema: ", out_json$method_dataset_schema),
      paste0("Reference dataset validation: ", out_json$reference_validation),
      paste0("QC validation check: ", out_json$qc_validation),
      paste0("Applicability-domain check: ", out_json$applicability_domain),
      paste0("External validation (PT): ", out_json$proficiency_testing_validation),
      "",
      paste0("Overall status: ", out_json$overall_status),
      "Note: Screening-level decision support only; ISO/IEC 17025 accredited analytical release still requires laboratory validation and analyst approval."
    )
    try(writeLines(lines, con = txt_path), silent = TRUE)
    append_pipeline_log("ISO compliance report generated: ", normalizePath(txt_path, winslash = "/", mustWork = FALSE))
    pipeline_last_error("")
    TRUE
  }

  run_local_cmd <- function(exec, args, step_name, extra_env = NULL) {
    append_pipeline_log("START ", step_name, ": ", exec, " ", paste(args, collapse = " "))
    old_wd <- getwd()
    on.exit(setwd(old_wd), add = TRUE)

    if (!is.null(extra_env) && length(extra_env) > 0) {
      env_names <- names(extra_env)
      old_env <- Sys.getenv(env_names, unset = NA_character_)
      restore_env <- function() {
        for (i in seq_along(env_names)) {
          nm <- env_names[[i]]
          oldv <- old_env[[i]]
          if (is.na(oldv)) {
            Sys.unsetenv(nm)
          } else {
            do.call(Sys.setenv, setNames(list(oldv), nm))
          }
        }
      }
      on.exit(restore_env(), add = TRUE)
      do.call(Sys.setenv, as.list(extra_env))
    }

    setwd(PROJECT_DIR)
    out <- tryCatch(
      system2(exec, args = args, stdout = TRUE, stderr = TRUE),
      error = function(e) structure(paste("ERROR:", conditionMessage(e)), status = 999L)
    )
    status <- as.integer(attr(out, "status") %||% 0L)
    if (length(out) > 0) append_pipeline_log(paste(out, collapse = "\n"))
    if (status == 0L) {
      pipeline_last_error("")
      append_pipeline_log("DONE ", step_name)
      write_audit(
        "pfas_pipeline",
        step_name,
        "execute_success",
        op_id(),
        "PFAS pipeline step completed",
        list(step = step_name, status = status, command = exec, args = args)
      )
      TRUE
    } else {
      pipeline_last_error(paste0(step_name, " exited with code ", status))
      append_pipeline_log("FAIL ", step_name, " (exit ", status, ")")
      write_audit(
        "pfas_pipeline",
        step_name,
        "execute_failure",
        op_id(),
        "PFAS pipeline step failed",
        list(step = step_name, status = status, command = exec, args = args)
      )
      FALSE
    }
  }

  pipeline_env <- function() {
    out <- c(
      PFAS_ECHO_URLS = trimws(input$epa_echo_urls %||% ""),
      PFAS_SDWIS_URLS = trimws(input$sdwis_urls %||% "")
    )
    out[nzchar(out)]
  }

  run_r_script_step <- function(script_name, label, extra_env = NULL) {
    rscript_exec <- "Rscript"
    on_path <- Sys.which(rscript_exec)
    if (!nzchar(on_path)) {
      r_bin <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
      if (file.exists(r_bin)) rscript_exec <- r_bin
    } else {
      rscript_exec <- on_path
    }
    run_local_cmd(rscript_exec, c(file.path("scripts", script_name)), label, extra_env = extra_env)
  }

  run_r_script_in_process <- function(script_name, label, extra_env = NULL) {
    append_pipeline_log("START ", label, " (in-process source)")
    old_wd <- getwd()
    on.exit(setwd(old_wd), add = TRUE)
    setwd(PROJECT_DIR)
    script_path <- file.path("scripts", script_name)
    env_names <- character(0)
    old_env <- character(0)
    if (!is.null(extra_env) && length(extra_env) > 0) {
      env_names <- names(extra_env)
      old_env <- Sys.getenv(env_names, unset = NA_character_)
      do.call(Sys.setenv, as.list(extra_env))
      on.exit(
        {
          for (i in seq_along(env_names)) {
            nm <- env_names[[i]]
            oldv <- old_env[[i]]
            if (is.na(oldv)) {
              Sys.unsetenv(nm)
            } else {
              do.call(Sys.setenv, setNames(list(oldv), nm))
            }
          }
        },
        add = TRUE
      )
    }
    ok <- tryCatch(
      {
        local_env <- new.env(parent = .GlobalEnv)
        source(script_path, local = local_env, echo = FALSE, chdir = FALSE)
        pipeline_last_error("")
        TRUE
      },
      error = function(e) {
        pipeline_last_error(conditionMessage(e))
        append_pipeline_log("ERROR ", label, ": ", conditionMessage(e))
        FALSE
      }
    )
    if (ok) {
      append_pipeline_log("DONE ", label, " (in-process)")
      write_audit(
        "pfas_pipeline",
        label,
        "execute_success",
        op_id(),
        "PFAS pipeline step completed (in-process)",
        list(step = label, mode = "in_process")
      )
      TRUE
    } else {
      append_pipeline_log("FAIL ", label, " (in-process)")
      write_audit(
        "pfas_pipeline",
        label,
        "execute_failure",
        op_id(),
        "PFAS pipeline step failed (in-process)",
        list(step = label, mode = "in_process")
      )
      FALSE
    }
  }

  resolve_python_exec <- function(py_exec_raw) {
    py_exec <- trimws(py_exec_raw %||% "")
    if (!nzchar(py_exec)) {
      py_exec <- if (file.exists(LOCAL_PYTHON_DEFAULT)) LOCAL_PYTHON_DEFAULT else "python"
    }
    # Direct path (Windows/local) or command on PATH.
    if (file.exists(py_exec)) return(py_exec)
    on_path <- Sys.which(py_exec)
    if (nzchar(on_path)) return(on_path)
    ""
  }

  pfas_screening_train_extra_env <- function() {
    c(
      PFAS_WORKFLOW_MODE = "screening",
      PFAS_VALIDATION_SCOPE = "exploratory",
      PFAS_ISO_GOVERNED = "false",
      PFAS_TRAIN_RESULTS_SUBDIR = "screening"
    )
  }

  record_train_workflow_context <- function(workflow_mode, iso_governed, ok) {
    vs <- if (isTRUE(iso_governed)) "evidence_governed" else "exploratory"
    ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    outcome <- if (isTRUE(ok)) "success" else "failure"
    ra_sub <- if (identical(workflow_mode, "screening")) "screening" else ""
    lst <- list(
      workflow_mode = workflow_mode,
      validation_scope = vs,
      iso_governed = isTRUE(iso_governed),
      results_artifact_subdir = ra_sub,
      train_outcome = outcome,
      updated_at = ts,
      app_version = APP_VERSION
    )
    note_txt <- paste0(
      if (identical(workflow_mode, "screening")) {
        "Exploratory screening — ISO gates not enforced on this path."
      } else if (identical(workflow_mode, "evidence_governed")) {
        "Evidence-governed train path (ISO preflight required before train)."
      } else {
        "Idle."
      },
      " Last train outcome: ", outcome, " at ", ts, "."
    )
    ml_workflow_train_context(list(
      workflow_mode = workflow_mode,
      validation_scope = vs,
      iso_governed = isTRUE(iso_governed),
      results_artifact_subdir = ra_sub,
      note = note_txt,
      updated_at = ts
    ))
    jp <- file.path(PROJECT_DIR, "results", "last_train_workflow_context.json")
    try(
      {
        d <- dirname(jp)
        if (!dir.exists(d)) dir.create(d, recursive = TRUE)
        jsonlite::write_json(lst, jp, pretty = TRUE, auto_unbox = TRUE)
      },
      silent = TRUE
    )
  }

  run_python_step <- function(extra_env = NULL) {
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    train_script <- file.path("scripts", "train_pfas_model.py")
    if (!file.exists(file.path(PROJECT_DIR, train_script))) {
      train_script <- file.path("scripts", "train_nhanes_model.py")
    }
    # Remove stale per-task artifacts before retrain so freshness/status reflects current run.
    res_sub <- ""
    if (!is.null(extra_env) && !is.null(extra_env[["PFAS_TRAIN_RESULTS_SUBDIR"]])) {
      res_sub <- trimws(as.character(extra_env[["PFAS_TRAIN_RESULTS_SUBDIR"]])[[1]])
    }
    if (length(res_sub) != 1L || grepl("[.\\\\/]", res_sub)) {
      res_sub <- ""
    }
    res_dir <- if (nzchar(res_sub)) file.path(PROJECT_DIR, "results", res_sub) else file.path(PROJECT_DIR, "results")
    if (!dir.exists(res_dir)) {
      dir.create(res_dir, recursive = TRUE, showWarnings = FALSE)
    }
    stale_files <- c(
      "nhanes_model_metrics_by_task.json",
      "nhanes_model_metrics.json",
      "nhanes_feature_importance.csv",
      "nhanes_test_predictions.csv"
    )
    stale_paths <- file.path(res_dir, stale_files)
    for (sp in stale_paths[file.exists(stale_paths)]) {
      try(unlink(sp, force = TRUE), silent = TRUE)
    }
    stale_task <- list.files(
      res_dir,
      pattern = "^nhanes_model_metrics_task_.*\\.json$",
      full.names = TRUE
    )
    if (length(stale_task) > 0) {
      for (sp in stale_task) {
        try(unlink(sp, force = TRUE), silent = TRUE)
      }
    }
    step_label <- basename(train_script)
    if (!nzchar(py_exec)) {
      append_pipeline_log(
        "SKIP ", step_label, ": Python executable not found in this runtime. ",
        "Run training locally (desktop R session), then redeploy results/ artifacts."
      )
      return(FALSE)
    }
    train_extra <- character(0)
    if (isTRUE(input$pfas_train_strict %||% TRUE)) train_extra <- c(train_extra, "--strict")
    if (isTRUE(input$pfas_train_verbose %||% FALSE)) train_extra <- c(train_extra, "-v")
    mr_txt <- trimws(input$pfas_train_min_recall_positive %||% "")
    if (nzchar(mr_txt)) {
      mv <- suppressWarnings(as.numeric(mr_txt))
      if (is.finite(mv) && mv >= 0 && mv <= 1) {
        train_extra <- c(train_extra, "--min-recall-positive", as.character(mv))
      }
    }
    ht <- suppressWarnings(as.numeric(input$pfas_holdout_threshold %||% 0.25))
    if (!is.finite(ht) || ht < 0.01 || ht > 0.99) ht <- 0.25
    train_extra <- c(train_extra, "--holdout-threshold", sprintf("%.6g", ht))
    run_local_cmd(py_exec, c(train_script, train_extra), step_label, extra_env = extra_env)
  }

  run_ml_validation_report_step <- function() {
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    report_script <- file.path("scripts", "generate_validation_report.py")
    if (!nzchar(py_exec)) {
      append_pipeline_log(
        "SKIP generate_validation_report.py: Python executable not found in this runtime."
      )
      return(FALSE)
    }
    if (!file.exists(file.path(PROJECT_DIR, report_script))) {
      append_pipeline_log("SKIP generate_validation_report.py: scripts/generate_validation_report.py not found.")
      return(FALSE)
    }
    pr_arg <- normalizePath(PROJECT_DIR, winslash = "/", mustWork = FALSE)
    run_local_cmd(py_exec, c(report_script, "--project-root", pr_arg), "generate_validation_report.py")
  }

  run_pfas_prediction_step <- function() {
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    pred_script <- file.path("scripts", "predict_pfas.py")
    if (!nzchar(py_exec)) {
      append_pipeline_log(
        "SKIP predict_pfas.py: Python executable not found in this runtime."
      )
      return(FALSE)
    }
    if (!file.exists(file.path(PROJECT_DIR, pred_script))) {
      append_pipeline_log("SKIP predict_pfas.py: scripts/predict_pfas.py not found.")
      return(FALSE)
    }
    run_local_cmd(py_exec, c(pred_script), "predict_pfas.py")
  }

  run_nist_reference_validation_step <- function() {
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    nist_script <- file.path("scripts", "validate_nist_pfas_reference.py")
    if (!nzchar(py_exec)) {
      pipeline_last_error("NIST reference validation: Python executable not found.")
      append_pipeline_log("SKIP validate_nist_pfas_reference.py: Python executable not found.")
      return(FALSE)
    }
    if (!file.exists(file.path(PROJECT_DIR, nist_script))) {
      pipeline_last_error("NIST reference validation: scripts/validate_nist_pfas_reference.py not found.")
      append_pipeline_log("SKIP validate_nist_pfas_reference.py: script missing.")
      return(FALSE)
    }
    ref_primary <- file.path(PROJECT_DIR, "data", "reference", "nist_srm1957_pfas_reference.csv")
    ref_nested_serum <- file.path(PROJECT_DIR, "data", "reference", "nist", "srm1957", "serum_pfas.csv")
    ref_fallback <- file.path(PROJECT_DIR, "data", "reference", "nist_srm1957_pfas.csv")
    ref_fallback2 <- file.path(PROJECT_DIR, "data", "reference", "nist_srm1957_pfas_noncertified.csv")
    ref_csv <- if (file.exists(ref_primary)) {
      ref_primary
    } else if (file.exists(ref_nested_serum)) {
      ref_nested_serum
    } else if (file.exists(ref_fallback)) {
      ref_fallback
    } else {
      ref_fallback2
    }
    if (!file.exists(ref_csv)) {
      pipeline_last_error(
        "NIST reference validation: data/reference/nist_srm1957_pfas_reference.csv (or nist/srm1957/serum_pfas.csv, nist_srm1957_pfas.csv, _noncertified.csv) not found."
      )
      append_pipeline_log("SKIP NIST reference validation: reference CSV missing.")
      return(FALSE)
    }
    pr_arg <- normalizePath(PROJECT_DIR, winslash = "/", mustWork = FALSE)
    ref_arg <- normalizePath(ref_csv, winslash = "/", mustWork = FALSE)
    pred_csv <- file.path(PROJECT_DIR, "results", "prediction_output.csv")
    args <- c(nist_script, "--project-root", pr_arg, "--reference-csv", ref_arg)
    if (file.exists(pred_csv)) {
      args <- c(args, "--predictions-csv", normalizePath(pred_csv, winslash = "/", mustWork = FALSE))
    }
    run_local_cmd(py_exec, args, "validate_nist_pfas_reference.py")
  }

  run_icis_dmr_filter_step <- function() {
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    filt_script <- file.path("scripts", "filter_npdes_dmr_pfas.py")
    if (!nzchar(py_exec)) {
      append_pipeline_log("SKIP filter_npdes_dmr_pfas.py: Python executable not found.")
      return(FALSE)
    }
    if (!file.exists(file.path(PROJECT_DIR, filt_script))) {
      append_pipeline_log("SKIP filter_npdes_dmr_pfas.py: script missing.")
      return(FALSE)
    }
    fy <- trimws(input$epa_icis_filter_fy %||% "2024")
    if (!grepl("^[0-9]{4}$", fy)) {
      append_pipeline_log("SKIP filter_npdes_dmr_pfas.py: invalid fiscal year (need 4 digits).")
      showNotification("DMR filter FY must be four digits (e.g. 2024).", type = "error")
      return(FALSE)
    }
    out_rel <- file.path("data", "processed", sprintf("npdes_dmr_pfas_fy%s.csv", fy))
    dir.create(file.path(PROJECT_DIR, "data", "processed"), recursive = TRUE, showWarnings = FALSE)
    args <- c(
      filt_script,
      "--fiscal-year", fy,
      "--out-csv", out_rel
    )
    run_local_cmd(py_exec, args, sprintf("filter_npdes_dmr_pfas.py FY%s", fy))
  }

  output$pfas_pipeline_log <- renderPrint({
    cat(pfas_pipeline_log(), "\n")
  })

  output$nist_reference_audit_table <- renderTable(
    {
      pfas_results_nonce()
      jp <- file.path(PROJECT_DIR, "results", "nist_reference_validation_report.json")
      if (!file.exists(jp)) {
        return(NULL)
      }
      j <- tryCatch(jsonlite::fromJSON(jp, simplifyVector = TRUE), error = function(e) NULL)
      if (is.null(j) || is.null(j$reference_metadata)) {
        return(NULL)
      }
      m <- j$reference_metadata
      ord <- c(
        "software_benchmarking_statement",
        "validation_scope",
        "reference_source",
        "reference_material",
        "reference_type",
        "value_status",
        "value_status_csv",
        "matrix",
        "analytical_basis",
        "interlaboratory",
        "uncertainty",
        "coverage_factor",
        "traceability",
        "isomer_reporting",
        "linear_isomer",
        "branched_isomer",
        "combined_isomer_reporting",
        "external_lab_source",
        "weighted_mean_basis",
        "consensus_mean_note",
        "nist_documentation"
      )
      nm <- names(m)
      keys <- c(ord[ord %in% nm], nm[!nm %in% ord])
      data.frame(
        Field = keys,
        Value = vapply(keys, function(k) paste(as.character(m[[k]]), collapse = ", "), character(1)),
        stringsAsFactors = FALSE
      )
    },
    striped = TRUE,
    spacing = "s",
    align = "l",
    digits = 4
  )

  output$source_bootstrap_status <- renderPrint({
    cat(source_bootstrap_note(), "\n")
  })

  iso_badge <- function(ok, label_ok = "READY", label_bad = "MISSING / INVALID") {
    if (isTRUE(ok)) {
      tags$span(
        style = "display:inline-block;padding:3px 10px;border-radius:999px;background:#2e7d32;color:#fff;font-size:12px;font-weight:600;",
        paste0("\u2705 ", label_ok)
      )
    } else {
      tags$span(
        style = "display:inline-block;padding:3px 10px;border-radius:999px;background:#c62828;color:#fff;font-size:12px;font-weight:600;",
        paste0("\u274c ", label_bad)
      )
    }
  }

  matrix_hint_chip <- function(label, bg = "#37474f") {
    tags$span(
      style = sprintf(
        "display:inline-block;margin:4px 6px 0 0;padding:2px 8px;border-radius:4px;background:%s;color:#fff;font-size:11px;font-weight:500;",
        bg
      ),
      label
    )
  }

  scan_reference_folder_matrix_chips <- function(resolved_path) {
    if (!nzchar(resolved_path %||% "") || !dir.exists(resolved_path)) {
      return(tagList(matrix_hint_chip("path missing — set a folder with matrix-tagged reference CSVs", "#9e9e9e")))
    }
    fl <- tryCatch(
      list.files(resolved_path, pattern = "\\.(csv|tsv|txt)$", ignore.case = TRUE, full.names = TRUE, recursive = TRUE),
      error = function(e) character(0)
    )
    if (length(fl) < 1L) {
      return(tagList(matrix_hint_chip("no CSV/TSV/TXT — cannot infer matrix mix from filenames", "#9e9e9e")))
    }
    fl <- utils::head(fl, 80L)
    bn <- tolower(basename(fl))
    chips <- list()
    add <- function(cond, lab, col) {
      if (isTRUE(cond)) {
        chips[[length(chips) + 1L]] <<- matrix_hint_chip(lab, col)
      }
    }
    add(any(grepl("srm.?1957|1957_serum|serum|plasma|blood|nhanes", bn, perl = TRUE)), "physiological benchmark (serum/plasma style)", "#1b5e20")
    add(any(grepl("8446|methanol|calibration|cal_?std|cal.?line", bn, perl = TRUE)), "calibration standard (solution line)", "#01579b")
    add(any(grepl("8690|afff|foam|firefight|fire.?fight", bn, perl = TRUE)), "source-material reference (AFFF/foam)", "#4a148c")
    add(any(grepl("ucmr|occurrence|raw.?water|gw|sdwis|finished.?water|tap", bn, perl = TRUE)), "environmental occurrence (monitoring-style)", "#e65100")
    add(any(grepl("sludge|biosolid|wwtp|residual|soil", bn, perl = TRUE)), "biosolids/soil/environmental (non-ingestion matrix)", "#5d4037")
    if (length(chips) == 0L) {
      chips <- list(matrix_hint_chip("matrix role not inferred — use filenames (e.g. serum_pfas, srm1957, ucmr) or a matrix column", "#757575"))
    }
    do.call(tagList, chips)
  }

  iso_path_badge_screening_optional <- function(short_label) {
    tags$span(
      style = "display:inline-block;padding:3px 10px;border-radius:999px;background:#757575;color:#fff;font-size:12px;font-weight:500;",
      paste0("\u2014 ", short_label, " (optional \u2014 screening / desk use)")
    )
  }

  lab_schema_badges_enabled <- function() {
    isTRUE(input$pfas_show_lab_artifact_schema_badges %||% FALSE)
  }

  output$pfas_ref_path_badge <- renderUI({
    ref_path <- resolve_pipeline_path(input$pfas_ref_path, file.path(PROJECT_DIR, "data", "external", "method_validation"))
    top <- if (!lab_schema_badges_enabled()) {
      iso_path_badge_screening_optional("Reference pack")
    } else {
      chk <- check_reference_dataset_schema(input$pfas_ref_path)
      iso_badge(chk$ok, "Reference ready", "Reference missing/invalid")
    }
    tagList(
      div(style = "display:flex;flex-wrap:wrap;align-items:center;gap:8px;", top),
      div(style = "margin-top:6px;display:flex;flex-wrap:wrap;align-items:center;", scan_reference_folder_matrix_chips(ref_path))
    )
  })

  output$pfas_method_path_badge <- renderUI({
    top <- if (!lab_schema_badges_enabled()) {
      iso_path_badge_screening_optional("Method pack")
    } else {
      chk <- check_method_dataset_schema(input$pfas_method_path)
      iso_badge(chk$ok, "Method schema ready", "Method schema missing")
    }
    tagList(
      div(style = "display:flex;flex-wrap:wrap;align-items:center;gap:8px;", top),
      div(
        style = "margin-top:6px;display:flex;flex-wrap:wrap;align-items:center;",
        matrix_hint_chip("method governance / metadata (EPA 533 / 537 / 1633-style) — NOT wet-lab validation evidence", "#006064")
      )
    )
  })

  output$pfas_qc_path_badge <- renderUI({
    top <- if (!lab_schema_badges_enabled()) {
      iso_path_badge_screening_optional("QC pack")
    } else {
      chk <- check_qc_dataset_schema(input$pfas_qc_path)
      iso_badge(chk$ok, "QC schema ready", "QC schema missing")
    }
    tagList(
      div(style = "display:flex;flex-wrap:wrap;align-items:center;gap:8px;", top),
      div(
        style = "margin-top:6px;display:flex;flex-wrap:wrap;align-items:center;",
        matrix_hint_chip("informational QA references / templates — NOT accreditation or batch QC evidence", "#5d4037")
      )
    )
  })

  output$pfas_pt_path_badge <- renderUI({
    top <- if (!lab_schema_badges_enabled()) {
      iso_path_badge_screening_optional("PT pack")
    } else {
      chk <- check_pt_dataset_schema(input$pfas_pt_path)
      iso_badge(chk$ok, "PT schema ready", "PT schema missing")
    }
    tagList(
      div(style = "display:flex;flex-wrap:wrap;align-items:center;gap:8px;", top),
      div(
        style = "margin-top:6px;display:flex;flex-wrap:wrap;align-items:center;",
        matrix_hint_chip("PT summaries / benchmarking — useful science; NOT proof of this operator's lab competence", "#283593")
      )
    )
  })

  output$iso_data_paths_status <- renderPrint({
    ref_path <- resolve_pipeline_path(input$pfas_ref_path, file.path(PROJECT_DIR, "data", "external", "method_validation"))
    method_path <- resolve_pipeline_path(input$pfas_method_path, file.path(PROJECT_DIR, "data", "external", "method_data"))
    qc_path <- resolve_pipeline_path(input$pfas_qc_path, file.path(PROJECT_DIR, "data", "external", "qc_datasets"))
    pt_path <- resolve_pipeline_path(input$pfas_pt_path, file.path(PROJECT_DIR, "data", "external", "proficiency_testing"))
    method_check <- check_method_dataset_schema(method_path)
    cat("ISO data paths\n")
    cat("Reference :", ref_path, "| files:", path_file_count(ref_path), "\n")
    cat("Method    :", method_path, "| files:", path_file_count(method_path), "| schema:", bool_mark(method_check$ok), "\n")
    cat("QC        :", qc_path, "| files:", path_file_count(qc_path), "\n")
    cat("PT        :", pt_path, "| files:", path_file_count(pt_path), "\n")
    if (!isTRUE(method_check$ok)) {
      cat("Method path requirement: Method_ID, Matrix_Type, Detection_Limit (LOD), Quantification_Limit (LOQ)\n")
    }
  })

  output$iso_preflight_status <- renderPrint({
    pf <- run_iso_preflight_check()
    cat("Strict ISO preflight gate\n")
    cat("Overall:", if (isTRUE(pf$ok)) "PASS" else "BLOCK", "\n")
    cat("Reference dataset :", bool_mark(pf$checks[["reference"]]), "\n")
    cat("Method dataset    :", bool_mark(pf$checks[["method"]]), "\n")
    cat("QC dataset        :", bool_mark(pf$checks[["qc"]]), "\n")
    cat("PT dataset        :", bool_mark(pf$checks[["pt"]]), "\n")

    print_preflight_detail <- function(title, comp) {
      cat("\n--- ", title, " ---\n", sep = "")
      cat("  path: ", comp$path %||% "", "\n", sep = "")
      fn <- comp$file %||% ""
      cat("  file: ", if (nzchar(as.character(fn))) as.character(fn) else "(none — no eligible CSV/TSV/XLS after excluding *template* names)", "\n", sep = "")
      cat("  ok:   ", isTRUE(comp$ok), "\n", sep = "")
      fd <- comp$found
      if (!is.null(fd) && length(fd) > 0L) {
        cat("  column / schema flags:\n")
        for (nm in names(fd)) {
          cat("    ", nm, ": ", fd[[nm]], "\n", sep = "")
        }
      }
    }
    print_preflight_detail("Reference (labels + concentration)", pf$ref)
    print_preflight_detail("Method (LOD/LOQ + matrix + method id)", pf$method)
    print_preflight_detail("QC (recovery, RSD, batch, analyst)", pf$qc)
    print_preflight_detail("PT (expected or z-score + provider)", pf$pt)

    cat("\nLast preflight run:\n", iso_preflight_note(), "\n", sep = "")
  })

  output$ml_workflow_mode_badge <- renderUI({
    st <- ml_workflow_train_context()
    wm <- st$workflow_mode %||% "idle"
    ras <- trimws(as.character(st$results_artifact_subdir %||% "")[[1]])
    sub_note <- if (nzchar(ras)) {
      paste0(" Metrics CSV/JSON for that run are under results/", ras, "/.")
    } else {
      ""
    }
    lab <- if (identical(wm, "screening")) {
      "Last model train: exploratory screening (iso_governed = false)"
    } else if (identical(wm, "evidence_governed")) {
      "Last model train: evidence-governed (iso_governed = true)"
    } else {
      "Last model train: none completed in this session"
    }
    col <- if (identical(wm, "screening")) "#01579b" else if (identical(wm, "evidence_governed")) "#1b5e20" else "#455a64"
    tagList(
      tags$p(style = paste0("margin:0;font-weight:700;color:", col, ";"), lab),
      tags$p(style = "margin:4px 0 0 0;font-size:13px;line-height:1.35;", st$note %||% "", sub_note)
    )
  })

  output$qc_pt_upload_status <- renderPrint({
    cat(qc_pt_upload_status_note(), "\n")
  })

  output$tbl_pipeline_component_status <- DT::renderDT({
    st <- pipeline_component_status()
    DT::datatable(
      st,
      colnames = c("Component", "Structure / schema (not scientific validation)"),
      rownames = FALSE,
      options = list(
        dom = "t",
        paging = FALSE,
        ordering = FALSE,
        searching = FALSE,
        info = FALSE
      )
    )
  })

  output$tbl_matrix_pipeline_sop <- DT::renderDT({
    sop <- file.path(PROJECT_DIR, "data", "config", "matrix_pipeline_sop.csv")
    if (!file.exists(sop)) {
      return(DT::datatable(
        tibble::tibble(Note = "Missing data/config/matrix_pipeline_sop.csv"),
        rownames = FALSE,
        options = list(dom = "t", paging = FALSE, ordering = FALSE, searching = FALSE, info = FALSE)
      ))
    }
    df <- utils::read.csv(sop, stringsAsFactors = FALSE, check.names = FALSE)
    label_map <- c(
      matrix              = "Matrix",
      canonical_datasets  = "Canonical datasets",
      pipeline_id         = "Pipeline ID (software)",
      lane_kind           = "Lane kind"
    )
    cn <- vapply(names(df), function(k) label_map[[k]] %||% k, character(1), USE.NAMES = FALSE)
    DT::datatable(
      df,
      colnames = cn,
      rownames = FALSE,
      options = list(dom = "t", paging = FALSE, ordering = FALSE, searching = FALSE, info = FALSE)
    )
  })

  matrix_pipeline_nonce <- reactiveVal(0L)
  matrix_pipeline_status <- reactiveVal("Per-lane builder has not been run yet in this session.")

  read_matrix_pipeline_manifest <- function(pipeline_id) {
    p <- file.path(PROJECT_DIR, "data", "training", pipeline_id, "manifest.json")
    if (!file.exists(p)) return(NULL)
    tryCatch(jsonlite::fromJSON(p, simplifyVector = TRUE), error = function(e) NULL)
  }

  collect_matrix_pipeline_outputs <- function() {
    sop <- file.path(PROJECT_DIR, "data", "config", "matrix_pipeline_sop.csv")
    if (!file.exists(sop)) {
      return(tibble::tibble(note = "Missing data/config/matrix_pipeline_sop.csv"))
    }
    df <- utils::read.csv(sop, stringsAsFactors = FALSE, check.names = FALSE)
    rows <- lapply(seq_len(nrow(df)), function(i) {
      pid <- trimws(as.character(df$pipeline_id[i]))
      mat <- trimws(as.character(df$matrix[i]))
      ds <- trimws(as.character(df$canonical_datasets[i]))
      lk_sop <- if ("lane_kind" %in% names(df)) trimws(as.character(df$lane_kind[i])) else NA_character_
      man <- read_matrix_pipeline_manifest(pid)
      training_csv <- file.path("data", "training", pid, "training.csv")
      training_exists <- file.exists(file.path(PROJECT_DIR, training_csv))
      rows_written <- if (!is.null(man$rows_written)) as.integer(man$rows_written) else NA_integer_
      gen_at <- if (!is.null(man$generated_at_utc)) as.character(man$generated_at_utc) else NA_character_
      note_vec <- if (!is.null(man$notes)) as.character(man$notes) else character(0)
      lk_man <- if (!is.null(man$lane_kind)) as.character(man$lane_kind) else NA_character_
      lk_show <- if (!is.na(lk_sop) && nzchar(lk_sop)) lk_sop else (lk_man %||% NA_character_)
      tibble::tibble(
        Matrix = mat,
        `Pipeline ID` = pid,
        `Lane kind` = lk_show %||% NA_character_,
        `Canonical datasets` = ds,
        `Rows written` = rows_written,
        `Training CSV exists` = training_exists,
        `Generated at (UTC)` = gen_at %||% "",
        Notes = if (length(note_vec)) paste(note_vec, collapse = " | ") else ""
      )
    })
    do.call(rbind, rows)
  }

  governance_nonce <- reactiveVal(0L)

  collect_governance_matrix_inventory <- function() {
    sop <- file.path(PROJECT_DIR, "data", "config", "matrix_pipeline_sop.csv")
    if (!file.exists(sop)) {
      return(tibble::tibble(Note = "Missing data/config/matrix_pipeline_sop.csv"))
    }
    s <- utils::read.csv(sop, stringsAsFactors = FALSE, check.names = FALSE)
    idx_path <- file.path(PROJECT_DIR, "data", "ad_models", "index.json")
    lanes_df <- NULL
    if (file.exists(idx_path)) {
      lanes_df <- tryCatch({
        js <- jsonlite::fromJSON(idx_path, simplifyDataFrame = TRUE)
        if (!is.null(js$lanes) && is.data.frame(js$lanes)) js$lanes else NULL
      }, error = function(e) NULL)
    }
    pid <- trimws(as.character(s$pipeline_id))
    ad_method <- rep(NA_character_, length(pid))
    ad_version <- rep(NA_character_, length(pid))
    ad_sha12 <- rep(NA_character_, length(pid))
    idx_status <- rep(NA_character_, length(pid))
    if (!is.null(lanes_df) && nrow(lanes_df) > 0L) {
      pl <- trimws(as.character(lanes_df$pipeline_lane))
      for (i in seq_along(pid)) {
        hit <- which(pl == pid[[i]])
        if (length(hit) == 1L) {
          j <- hit[[1]]
          ad_method[[i]] <- as.character(lanes_df$ad_method[j] %||% "")
          ad_version[[i]] <- as.character(lanes_df$ad_model_version[j] %||% "")
          sha <- as.character(lanes_df$ad_model_sha256[j] %||% "")
          ad_sha12[[i]] <- if (nzchar(sha)) substr(sha, 1L, 12L) else ""
          idx_status[[i]] <- as.character(lanes_df$status[j] %||% "")
        }
      }
    }
    tibble::tibble(
      Matrix = trimws(as.character(s$matrix)),
      `Pipeline ID` = pid,
      `Canonical datasets` = trimws(as.character(s$canonical_datasets)),
      `AD index status` = idx_status,
      `AD method` = ad_method,
      `AD model version` = ad_version,
      `AD model SHA (12)` = ad_sha12
    )
  }

  collect_governance_registry_table <- function() {
    reg <- file.path(PROJECT_DIR, "data", "reference", "registry", "reference_registry.csv")
    if (!file.exists(reg)) {
      return(tibble::tibble(Note = "Missing reference_registry.csv"))
    }
    df <- utils::read.csv(reg, stringsAsFactors = FALSE, check.names = FALSE)
    keep <- intersect(
      names(df),
      c("source_org", "document_type", "document_id", "matrix_domain", "local_path", "sha256", "intended_use")
    )
    if (!length(keep)) return(tibble::tibble(Note = "Unexpected registry schema"))
    out <- df[, keep, drop = FALSE]
    if ("sha256" %in% names(out)) {
      out$sha256 <- vapply(as.character(out$sha256), function(x) {
        if (is.na(x) || !nzchar(x)) return("")
        if (nchar(x) > 12L) paste0(substr(x, 1L, 12L), "\u2026") else x
      }, character(1L))
    }
    out
  }

  governance_threshold_and_scope_text <- function() {
    ucmr <- file.path(PROJECT_DIR, "data", "config", "ucmr_analyte_limits_ngl.csv")
    th <- if (file.exists(ucmr)) {
      h <- tryCatch(
        digest::digest(file = ucmr, algo = "sha256", serialize = FALSE),
        error = function(e) "digest_error"
      )
      paste0("UCMR analyte limits file: ", basename(ucmr),
             "\n  SHA-256 (full): ", h,
             "\n  threshold_version prefix (first 12): ", substr(h, 1L, 12L))
    } else {
      "UCMR analyte limits file: (missing) data/config/ucmr_analyte_limits_ngl.csv"
    }
    mf <- file.path(PROJECT_DIR, "validation", "scope_freeze", "v1.0", "freeze_manifest.json")
    sc <- if (file.exists(mf)) {
      js <- tryCatch(jsonlite::fromJSON(mf, simplifyVector = TRUE), error = function(e) NULL)
      if (is.null(js)) {
        "\nScope freeze v1.0 manifest: (unreadable JSON)"
      } else {
        paste0(
          "\nScope freeze v1.0 manifest: ", basename(mf),
          "\n  status: ", js$status %||% "?",
          "\n  git_head_sha: ", js$git_head_sha %||% "?",
          "\n  built_at_utc: ", js$built_at_utc %||% "?",
          "\n  operator: ", js$operator %||% "null",
          "\n  scientific_reviewer: ", js$scientific_reviewer %||% "null"
        )
      }
    } else {
      "\nScope freeze: no validation/scope_freeze/v1.0/freeze_manifest.json in this checkout."
    }
    paste(th, sc, sep = "")
  }

  governance_blind_index_tail <- function() {
    p <- file.path(
      PROJECT_DIR, "validation", "blind_external", "manifests", "submissions_index.jsonl"
    )
    if (!file.exists(p)) {
      return("(no file) validation/blind_external/manifests/submissions_index.jsonl")
    }
    lines <- readLines(p, warn = FALSE)
    if (!length(lines)) return("(empty submissions index)")
    tail_lines <- tail(lines, 15L)
    paste(tail_lines, collapse = "\n")
  }

  governance_results_recent <- function() {
    rd <- file.path(PROJECT_DIR, "results")
    if (!dir.exists(rd)) {
      return(tibble::tibble(Note = "No results/ directory"))
    }
    pat <- "\\.(json|csv)$"
    ff <- list.files(rd, pattern = pat, full.names = TRUE, recursive = FALSE, ignore.case = TRUE)
    if (!length(ff)) return(tibble::tibble(Note = "No JSON/CSV files directly under results/"))
    info <- file.info(ff)
    info$path <- ff
    info$name <- basename(ff)
    ord <- order(info$mtime, decreasing = TRUE)
    info <- info[ord, , drop = FALSE]
    info <- head(info, 20L)
    tibble::tibble(
      file = info$name,
      `modified (local)` = format(info$mtime, usetz = TRUE),
      bytes = as.integer(info$size)
    )
  }

  governance_matrix_isolation_text <- function() {
    sop <- file.path(PROJECT_DIR, "data", "config", "matrix_pipeline_sop.csv")
    sop_m <- if (file.exists(sop)) format(file.info(sop)$mtime, usetz = TRUE) else "(missing)"
    summ <- file.path(PROJECT_DIR, "data", "training", "matrix_pipeline_summary.json")
    summ_l <- if (file.exists(summ)) format(file.info(summ)$mtime, usetz = TRUE) else "(missing)"
    paste0(
      "SOP CSV last modified: ", sop_m,
      "\nmatrix_pipeline_summary.json last modified: ", summ_l,
      "\n",
      "\nEnforcement (not re-run from this tab):",
      "\n  * R: prepare_multisource_training.R :: enforce_sop_single_pipeline()",
      "\n  * Python: scripts/run_matrix_pipeline.py (per-lane training.csv + manifest.json)",
      "\n  * API: POST /v1/predict requires matrix_lane; unknown lane -> 400 ad_lane_unknown",
      "\n  * Shiny upload: semantic-type hard-block for program-metadata lanes (ICIS-AIR bulk, etc.)",
      "\n",
      "\nRegression evidence: scripts/smoke_sop_matrix_separation.R"
    )
  }

  output$tbl_matrix_pipeline_outputs <- DT::renderDT({
    matrix_pipeline_nonce()
    df <- collect_matrix_pipeline_outputs()
    DT::datatable(
      df,
      rownames = FALSE,
      options = list(dom = "t", paging = FALSE, ordering = FALSE, searching = FALSE, info = FALSE)
    )
  })

  output$matrix_pipeline_status <- renderText({
    matrix_pipeline_nonce()
    matrix_pipeline_status()
  })

  observeEvent(input$btn_governance_refresh, {
    governance_nonce(governance_nonce() + 1L)
  })

  output$tbl_governance_matrix_inventory <- DT::renderDT({
    governance_nonce()
    df <- collect_governance_matrix_inventory()
    DT::datatable(
      df,
      rownames = FALSE,
      options = list(pageLength = 12, scrollX = TRUE, dom = "ftip")
    )
  })

  output$tbl_governance_manifest_status <- DT::renderDT({
    governance_nonce()
    df <- collect_matrix_pipeline_outputs()
    DT::datatable(
      df,
      rownames = FALSE,
      options = list(pageLength = 12, scrollX = TRUE, dom = "ftip")
    )
  })

  output$tbl_governance_registry <- DT::renderDT({
    governance_nonce()
    df <- collect_governance_registry_table()
    DT::datatable(
      df,
      rownames = FALSE,
      options = list(pageLength = 10, scrollX = TRUE, dom = "ftip")
    )
  })

  output$txt_governance_threshold_scope <- renderText({
    governance_nonce()
    governance_threshold_and_scope_text()
  })

  output$tbl_governance_ad_trends <- DT::renderDT({
    governance_nonce()
    if (!ensure_ad_guard_loaded()) {
      return(DT::datatable(
        tibble::tibble(Note = "AD helper not loaded; open Data & Endpoints matrix section and use AD controls once, or source scripts/run_ad_guard.R."),
        rownames = FALSE,
        options = list(dom = "t", paging = FALSE)
      ))
    }
    df <- tryCatch(
      read_ad_audit(project_root = PROJECT_DIR, tail_n = 5000L),
      error = function(e) data.frame(error = conditionMessage(e))
    )
    if (!is.data.frame(df) || !nrow(df) || "error" %in% names(df)) {
      return(DT::datatable(
        tibble::tibble(Note = "No AD audit rows in tail, or read error."),
        rownames = FALSE,
        options = list(dom = "t", paging = FALSE)
      ))
    }
    if (!all(c("reference_lane", "ad_status") %in% names(df))) {
      return(DT::datatable(df, rownames = FALSE, options = list(dom = "t", scrollX = TRUE)))
    }
    agg <- as.data.frame(table(df$reference_lane, df$ad_status), stringsAsFactors = FALSE)
    names(agg) <- c("reference_lane", "ad_status", "n")
    agg <- agg[order(agg$reference_lane, agg$ad_status), , drop = FALSE]
    rownames(agg) <- NULL
    DT::datatable(
      agg,
      rownames = FALSE,
      options = list(pageLength = 25, dom = "ftip")
    )
  })

  output$txt_governance_blind_tail <- renderText({
    governance_nonce()
    governance_blind_index_tail()
  })

  output$tbl_governance_sqlite_audit <- DT::renderDT({
    governance_nonce()
    df <- tryCatch(
      {
        if (!DBI::dbIsValid(con)) {
          tibble::tibble(Note = "SQLite connection invalid")
        } else if (!DBI::dbExistsTable(con, "audit_log")) {
          tibble::tibble(Note = "audit_log table missing")
        } else {
          DBI::dbGetQuery(
            con,
            "SELECT audit_id, entity_type, entity_id, action_type, changed_by, changed_at, change_notes
             FROM audit_log ORDER BY changed_at DESC LIMIT 80"
          )
        }
      },
      error = function(e) tibble::tibble(error = conditionMessage(e))
    )
    DT::datatable(
      df,
      rownames = FALSE,
      options = list(pageLength = 15, scrollX = TRUE, dom = "ftip")
    )
  })

  output$tbl_governance_upload_validation <- DT::renderDT({
    governance_nonce()
    df <- tryCatch(
      {
        if (!DBI::dbIsValid(con)) {
          tibble::tibble(Note = "SQLite connection invalid")
        } else if (!DBI::dbExistsTable(con, "upload_validation_run")) {
          tibble::tibble(Note = "upload_validation_run table missing")
        } else {
          DBI::dbGetQuery(
            con,
            "SELECT run_id, phase, status, validated_at, validated_by, file_name, row_count, rows_pass, rows_fail
             FROM upload_validation_run ORDER BY validated_at DESC LIMIT 40"
          )
        }
      },
      error = function(e) tibble::tibble(error = conditionMessage(e))
    )
    DT::datatable(
      df,
      rownames = FALSE,
      options = list(pageLength = 12, scrollX = TRUE, dom = "ftip")
    )
  })

  output$tbl_governance_ingestion_failures <- DT::renderDT({
    governance_nonce()
    df <- tryCatch(
      {
        if (!DBI::dbIsValid(con) || !DBI::dbExistsTable(con, "upload_validation_run")) {
          tibble::tibble(Note = "upload_validation_run not available")
        } else {
          DBI::dbGetQuery(
            con,
            "SELECT run_id, phase, status, validated_at, validated_by, file_name, row_count, rows_pass, rows_fail, metrics_json
             FROM upload_validation_run
             WHERE (LOWER(status) NOT IN ('ok','pass','passed','success'))
                OR (rows_fail IS NOT NULL AND rows_fail > 0)
             ORDER BY validated_at DESC LIMIT 30"
          )
        }
      },
      error = function(e) tibble::tibble(error = conditionMessage(e))
    )
    DT::datatable(
      df,
      rownames = FALSE,
      options = list(pageLength = 10, scrollX = TRUE, dom = "ftip")
    )
  })

  output$tbl_governance_results_recent <- DT::renderDT({
    governance_nonce()
    df <- governance_results_recent()
    DT::datatable(
      df,
      rownames = FALSE,
      options = list(pageLength = 15, dom = "ftip")
    )
  })

  output$txt_governance_matrix_isolation <- renderText({
    governance_nonce()
    governance_matrix_isolation_text()
  })

  resolve_pfas_python <- function() {
    cand <- trimws(Sys.getenv("PFAS_PYTHON", unset = ""))
    if (nzchar(cand) && file.exists(cand)) return(cand)
    if (file.exists(LOCAL_PYTHON_DEFAULT)) return(LOCAL_PYTHON_DEFAULT)
    onp <- suppressWarnings(Sys.which("python"))
    if (nzchar(onp) && file.exists(onp)) return(onp)
    NA_character_
  }

  run_matrix_pipeline_lane <- function(lane) {
    py <- resolve_pfas_python()
    if (is.na(py)) {
      matrix_pipeline_status(
        paste0("Cannot find Python executable. Set PFAS_PYTHON, install Python, or run scripts/run_matrix_pipeline.py ",
               "from a shell directly. Requested lane: ", lane)
      )
      matrix_pipeline_nonce(matrix_pipeline_nonce() + 1L)
      return(invisible(FALSE))
    }
    script <- file.path(PROJECT_DIR, "scripts", "run_matrix_pipeline.py")
    if (!file.exists(script)) {
      matrix_pipeline_status(paste0("Missing scripts/run_matrix_pipeline.py at ", script))
      matrix_pipeline_nonce(matrix_pipeline_nonce() + 1L)
      return(invisible(FALSE))
    }
    args <- c(script, "--lane", lane, "--project-root", PROJECT_DIR)
    out <- tryCatch(
      system2(py, args = args, stdout = TRUE, stderr = TRUE),
      error = function(e) paste0("system2 error: ", conditionMessage(e))
    )
    st <- attr(out, "status")
    status_msg <- paste(
      paste0("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] lane=", lane,
             if (!is.null(st) && !identical(as.integer(st), 0L)) paste0(" (exit ", st, ")") else " (ok)"),
      paste(out, collapse = "\n"),
      sep = "\n"
    )
    matrix_pipeline_status(status_msg)
    matrix_pipeline_nonce(matrix_pipeline_nonce() + 1L)
    append_pipeline_log("Matrix lane '", lane, "' build: ",
                        if (!is.null(st) && !identical(as.integer(st), 0L)) "FAIL" else "OK")
    invisible(is.null(st) || identical(as.integer(st), 0L))
  }

  observeEvent(input$btn_lane_drinking_water, { run_matrix_pipeline_lane("drinking_water") })
  observeEvent(input$btn_lane_serum, { run_matrix_pipeline_lane("serum") })
  observeEvent(input$btn_lane_biosolids_sludge, { run_matrix_pipeline_lane("biosolids_sludge") })
  observeEvent(input$btn_lane_afff, { run_matrix_pipeline_lane("afff") })
  observeEvent(input$btn_lane_methanol_standards, { run_matrix_pipeline_lane("methanol_standards") })
  observeEvent(input$btn_lane_air_emissions, { run_matrix_pipeline_lane("air_emissions") })
  observeEvent(input$btn_lane_all, { run_matrix_pipeline_lane("all") })

  # ------------------------------------------------------------------ #
  # V1 serum PFOS/PFOA contextualization (src/v1/)                     #
  # ------------------------------------------------------------------ #

  v1_runner_loaded <- reactiveVal(FALSE)
  v1_context_status <- reactiveVal("Upload a governed V1 CSV or use the template, then click Run.")
  v1_report_df <- reactiveVal(NULL)
  v1_last_paths <- reactiveVal(list())

  ensure_v1_runner_loaded <- function() {
    if (isTRUE(v1_runner_loaded())) return(invisible(TRUE))
    helper <- file.path(PROJECT_DIR, "scripts", "run_v1_contextualization.R")
    if (!file.exists(helper)) {
      v1_context_status(paste0("Missing ", helper))
      return(invisible(FALSE))
    }
    source(helper, local = FALSE)
    v1_runner_loaded(TRUE)
    invisible(TRUE)
  }

  output$btn_download_v1_template <- downloadHandler(
    filename = function() "governed_serum_pfos_pfoa_input_template.csv",
    content = function(file) {
      src <- file.path(PROJECT_DIR, V1_INPUT_TEMPLATE_REL)
      if (!file.exists(src)) {
        stop("V1 template not found at ", src)
      }
      file.copy(src, file, overwrite = TRUE)
    }
  )

  output$btn_download_v1_report_csv <- downloadHandler(
    filename = function() {
      p <- v1_last_paths()
      if (!is.null(p$csv_path) && file.exists(p$csv_path)) {
        return(basename(p$csv_path))
      }
      "v1_report.csv"
    },
    content = function(file) {
      p <- v1_last_paths()
      if (is.null(p$csv_path) || !file.exists(p$csv_path)) {
        stop("No V1 report CSV available. Run contextualization first.")
      }
      file.copy(p$csv_path, file, overwrite = TRUE)
    }
  )

  output$btn_download_v1_report_pdf <- downloadHandler(
    filename = function() {
      p <- v1_last_paths()
      if (!is.null(p$pdf_path) && file.exists(p$pdf_path)) {
        return(basename(p$pdf_path))
      }
      "v1_report.pdf"
    },
    content = function(file) {
      p <- v1_last_paths()
      if (is.null(p$pdf_path) || !file.exists(p$pdf_path)) {
        stop("No V1 report PDF available. Run contextualization first.")
      }
      file.copy(p$pdf_path, file, overwrite = TRUE)
    }
  )

  output$btn_download_v1_manifest <- downloadHandler(
    filename = function() {
      p <- v1_last_paths()
      if (!is.null(p$manifest_path) && file.exists(p$manifest_path)) {
        return(basename(p$manifest_path))
      }
      "v1_manifest.json"
    },
    content = function(file) {
      p <- v1_last_paths()
      if (is.null(p$manifest_path) || !file.exists(p$manifest_path)) {
        stop("No V1 manifest available. Run contextualization first.")
      }
      file.copy(p$manifest_path, file, overwrite = TRUE)
    }
  )

  observeEvent(input$btn_v1_run, {
    req(input$v1_input_csv)
    if (!ensure_v1_runner_loaded()) return()

    upload_dir <- file.path(PROJECT_DIR, "data", "v1", "uploads")
    out_dir <- file.path(PROJECT_DIR, "data", "v1", "outputs")
    dir.create(upload_dir, recursive = TRUE, showWarnings = FALSE)
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

    stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    in_path <- file.path(upload_dir, paste0("v1_upload_", stamp, ".csv"))
    ok_copy <- file.copy(input$v1_input_csv$datapath, in_path, overwrite = TRUE)
    if (!isTRUE(ok_copy)) {
      v1_context_status("Failed to stage uploaded CSV for V1 run.")
      return()
    }

    preflight <- tryCatch({
      hdr <- names(utils::read.csv(in_path, nrows = 1L, check.names = FALSE))
      has_sex <- "sex" %in% hdr
      has_age <- "age_years" %in% hdr
      if (!has_sex || !has_age) {
        paste0(
          "Input preflight: ",
          if (!has_sex) "column 'sex' missing (1=male, 2=female) → sex_stratum will be 'all'. " else "",
          if (!has_age) "column 'age_years' missing → age_group_stratum will be 'all_ages'. " else "",
          "Add columns or use scripts/enrich_v1_input_demographics.py.\n"
        )
      } else {
        ""
      }
    }, error = function(e) "")

    v1_context_status(paste0(
      "[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] Running V1 (",
      V1_CONTEXTUALIZATION_VERSION, ") …"
    ))

    cycle <- input$v1_default_cycle %||% "J"
    res <- run_v1_serum_contextualization(
      input_csv = in_path,
      output_dir = out_dir,
      project_root = PROJECT_DIR,
      python_exec = input$pfas_python_exec %||% "",
      default_cycle = cycle
    )

    if (!isTRUE(res$ok)) {
      v1_context_status(paste0(
        "V1 run FAILED: ", res$message, "\n\n",
        res$log
      ))
      v1_report_df(NULL)
      v1_last_paths(list())
      append_pipeline_log("V1 contextualization: FAIL — ", res$message)
      return()
    }

    sm <- res$summary
    v1_last_paths(list(
      csv_path = sm$csv_path,
      pdf_path = sm$pdf_path,
      manifest_path = sm$manifest_path,
      run_id = sm$run_id,
      output_csv_sha256 = sm$output_csv_sha256
    ))

    rep_df <- tryCatch(
      utils::read.csv(sm$csv_path, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e) NULL
    )
    v1_report_df(rep_df)

    pdf_note <- if (isTRUE(sm$pdf_skipped) || is.null(sm$pdf_path) || !nzchar(sm$pdf_path %||% "")) {
      "PDF: skipped (pip install reportlab in PFAS Python env)\n"
    } else {
      paste0("PDF: ", sm$pdf_path, "\n")
    }
    strata_note <- ""
    if (!is.null(rep_df) && nrow(rep_df) > 0L && all(c("ad_status", "sex_stratum", "age_group_stratum") %in% names(rep_df))) {
      in_dom <- rep_df[rep_df$ad_status == "in_domain", , drop = FALSE]
      if (nrow(in_dom) > 0L) {
        n_sex_all <- sum(in_dom$sex_stratum == "all", na.rm = TRUE)
        n_age_all <- sum(in_dom$age_group_stratum == "all_ages", na.rm = TRUE)
        analyte_tbl <- table(in_dom$analyte)
        analyte_line <- paste(names(analyte_tbl), analyte_tbl, sep = "=", collapse = ", ")
        strata_note <- paste0(
          "Strata (in_domain): sex=all on ", n_sex_all, "/", nrow(in_dom),
          " rows; age=all_ages on ", n_age_all, "/", nrow(in_dom),
          " rows. Analytes: ", analyte_line, ".\n",
          "Tip: add sex (1/2) and age_years to input for stratified percentiles.\n"
        )
      }
    }
    demo_note <- ""
    if (!is.null(sm$input_demographics)) {
      d <- sm$input_demographics
      demo_note <- paste0(
        "Input demographics: sex filled on ", d$n_with_sex %||% 0, "/", d$n_rows %||% sm$n_rows,
        " rows; age_years on ", d$n_with_age_years %||% 0, "/", d$n_rows %||% sm$n_rows,
        " rows.\n"
      )
    }
    v1_context_status(paste0(
      preflight,
      "V1 run OK (run_id=", sm$run_id, ")\n",
      "Rows: ", sm$n_rows, " | in_domain: ", sm$n_in_domain,
      " | refused: ", sm$n_refused, "\n",
      demo_note,
      strata_note,
      "output_csv_sha256: ", sm$output_csv_sha256, "\n",
      "report: ", sm$csv_path, "\n",
      pdf_note,
      "manifest: ", sm$manifest_path, "\n\n",
      "RUO only — not diagnostic, clinical, or regulatory."
    ))
    append_pipeline_log(
      "V1 contextualization OK run_id=", sm$run_id,
      " sha256=", substr(sm$output_csv_sha256, 1, 16), "…"
    )
  })

  output$v1_context_status <- renderPrint({
    cat(v1_context_status(), "\n")
  })

  v1_report_preview_df <- function(df) {
    preferred <- c(
      "row_index", "sample_matrix", "analyte", "result_value", "ad_status", "ad_code",
      "reference_cycle", "sex_stratum", "age_group_stratum",
      "percentile", "bracket_low_pct", "bracket_high_pct",
      "n_reference", "n_weighted", "pct_below_lod_reference",
      "result_unit", "source_program", "ad_reason", "offending_field",
      "imputed_below_lod_value_ng_per_mL", "query_below_imputed_lod", "lod_context_flag"
    )
    cols <- c(intersect(preferred, names(df)), setdiff(names(df), preferred))
    df[, cols, drop = FALSE]
  }

  output$tbl_v1_report <- DT::renderDataTable({
    df <- v1_report_df()
    if (is.null(df) || nrow(df) < 1L) {
      return(DT::datatable(
        tibble::tibble(note = "No V1 report yet. Upload CSV and click Run."),
        rownames = FALSE,
        options = list(dom = "t", paging = FALSE)
      ))
    }
    show <- v1_report_preview_df(df)
    DT::datatable(
      show,
      rownames = FALSE,
      options = list(pageLength = 15, scrollX = TRUE)
    )
  })

  # ------------------------------------------------------------------ #
  # V2 cross-cycle temporal contextualization (src/v2/)                #
  # ------------------------------------------------------------------ #

  v2_runner_loaded <- reactiveVal(FALSE)
  v2_context_status <- reactiveVal("Upload a V1.1 governed CSV (reference_cycle required), then click Run V2.")
  v2_report_df <- reactiveVal(NULL)
  v2_last_paths <- reactiveVal(list())

  ensure_v2_runner_loaded <- function() {
    if (isTRUE(v2_runner_loaded())) return(invisible(TRUE))
    helper <- file.path(PROJECT_DIR, "scripts", "run_v2_contextualization.R")
    if (!file.exists(helper)) {
      v2_context_status(paste0("Missing ", helper))
      return(invisible(FALSE))
    }
    source(helper, local = FALSE)
    v2_runner_loaded(TRUE)
    invisible(TRUE)
  }

  output$btn_download_v2_report_csv <- downloadHandler(
    filename = function() {
      p <- v2_last_paths()
      if (!is.null(p$csv_path) && file.exists(p$csv_path)) {
        return(basename(p$csv_path))
      }
      "v2_report.csv"
    },
    content = function(file) {
      p <- v2_last_paths()
      if (is.null(p$csv_path) || !file.exists(p$csv_path)) {
        stop("No V2 report CSV available. Run contextualization first.")
      }
      file.copy(p$csv_path, file, overwrite = TRUE)
    }
  )

  output$btn_download_v2_report_pdf <- downloadHandler(
    filename = function() {
      p <- v2_last_paths()
      if (!is.null(p$pdf_path) && file.exists(p$pdf_path)) {
        return(basename(p$pdf_path))
      }
      "v2_report.pdf"
    },
    content = function(file) {
      p <- v2_last_paths()
      if (is.null(p$pdf_path) || !file.exists(p$pdf_path)) {
        stop("No V2 report PDF available. Run contextualization first.")
      }
      file.copy(p$pdf_path, file, overwrite = TRUE)
    }
  )

  output$btn_download_v2_manifest <- downloadHandler(
    filename = function() {
      p <- v2_last_paths()
      if (!is.null(p$manifest_path) && file.exists(p$manifest_path)) {
        return(basename(p$manifest_path))
      }
      "v2_manifest.json"
    },
    content = function(file) {
      p <- v2_last_paths()
      if (is.null(p$manifest_path) || !file.exists(p$manifest_path)) {
        stop("No V2 manifest available. Run contextualization first.")
      }
      file.copy(p$manifest_path, file, overwrite = TRUE)
    }
  )

  observeEvent(input$btn_v2_run, {
    req(input$v2_input_csv)
    if (!ensure_v2_runner_loaded()) return()

    upload_dir <- file.path(PROJECT_DIR, "data", "v2", "uploads")
    out_dir <- file.path(PROJECT_DIR, "data", "v2", "outputs")
    dir.create(upload_dir, recursive = TRUE, showWarnings = FALSE)
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

    stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    in_path <- file.path(upload_dir, paste0("v2_upload_", stamp, ".csv"))
    ok_copy <- file.copy(input$v2_input_csv$datapath, in_path, overwrite = TRUE)
    if (!isTRUE(ok_copy)) {
      v2_context_status("Failed to stage uploaded CSV for V2 run.")
      return()
    }

    preflight <- tryCatch({
      hdr <- names(utils::read.csv(in_path, nrows = 1L, check.names = FALSE))
      if (!"reference_cycle" %in% hdr) {
        paste0(
          "V2 preflight: column 'reference_cycle' missing (required anchor I/J/P). ",
          "Use data/v1/fixtures/nhanes_j_governed_v1_input.csv as a model.\n"
        )
      } else {
        ""
      }
    }, error = function(e) "")

    v2_context_status(paste0(
      "[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] Running V2 (",
      V2_CONTEXTUALIZATION_VERSION, ") …"
    ))

    res <- run_v2_serum_contextualization(
      input_csv = in_path,
      output_dir = out_dir,
      project_root = PROJECT_DIR,
      python_exec = input$pfas_python_exec %||% ""
    )

    if (!isTRUE(res$ok)) {
      v2_context_status(paste0(
        "V2 run FAILED: ", res$message, "\n\n",
        res$log
      ))
      v2_report_df(NULL)
      v2_last_paths(list())
      append_pipeline_log("V2 contextualization: FAIL — ", res$message)
      return()
    }

    sm <- res$summary
    v2_last_paths(list(
      csv_path = sm$csv_path,
      pdf_path = sm$pdf_path,
      manifest_path = sm$manifest_path,
      run_id = sm$run_id,
      output_csv_sha256 = sm$output_csv_sha256
    ))

    rep_df <- tryCatch(
      utils::read.csv(sm$csv_path, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e) NULL
    )
    v2_report_df(rep_df)

    pdf_note <- if (is.null(sm$pdf_path) || !nzchar(sm$pdf_path %||% "")) {
      "PDF: skipped\n"
    } else {
      paste0("PDF: ", sm$pdf_path, "\n")
    }
    demo_note <- ""
    if (!is.null(sm$input_demographics)) {
      d <- sm$input_demographics
      demo_note <- paste0(
        "Demographics: sex=", d$n_with_sex %||% 0, "/", d$n_rows %||% sm$n_rows,
        " age=", d$n_with_age_years %||% 0,
        " race=", d$n_with_race_ethnicity %||% 0, "\n"
      )
    }
    v2_context_status(paste0(
      preflight,
      "V2 run OK (run_id=", sm$run_id, ")\n",
      "Rows: ", sm$n_rows, " | in_domain: ", sm$n_in_domain,
      " | refused: ", sm$n_refused, "\n",
      "Cross-cycle shift >=15 pts: ", sm$n_cross_cycle_shift_ge_15 %||% 0, "\n",
      demo_note,
      "output_csv_sha256: ", sm$output_csv_sha256, "\n",
      "report: ", sm$csv_path, "\n",
      pdf_note,
      "manifest: ", sm$manifest_path, "\n\n",
      "Population cross-cycle comparison only — not individual longitudinal follow-up."
    ))
    append_pipeline_log(
      "V2 contextualization OK run_id=", sm$run_id,
      " sha256=", substr(sm$output_csv_sha256, 1, 16), "…"
    )
  })

  output$v2_context_status <- renderPrint({
    cat(v2_context_status(), "\n")
  })

  v2_report_preview_df <- function(df) {
    preferred <- c(
      "row_index", "analyte", "result_value", "anchor_cycle",
      "percentile_cycle_I", "percentile_cycle_J", "percentile_cycle_P",
      "anchor_percentile", "percentile_delta_J_minus_I", "percentile_delta_P_minus_J",
      "sex_stratum", "age_group_stratum", "race_ethnicity_stratum",
      "temporal_context_flag", "ad_status"
    )
    cols <- c(intersect(preferred, names(df)), setdiff(names(df), preferred))
    df[, cols, drop = FALSE]
  }

  output$tbl_v2_report <- DT::renderDataTable({
    df <- v2_report_df()
    if (is.null(df) || nrow(df) < 1L) {
      return(DT::datatable(
        tibble::tibble(note = "No V2 report yet. Upload CSV and click Run V2."),
        rownames = FALSE,
        options = list(dom = "t", paging = FALSE)
      ))
    }
    show <- v2_report_preview_df(df)
    DT::datatable(
      show,
      rownames = FALSE,
      options = list(pageLength = 15, scrollX = TRUE)
    )
  })

  # ------------------------------------------------------------------ #
  # Applicability-domain (AD) enforcement                              #
  # Backed by scripts/run_ad_guard.R (source once; lazy-loaded).       #
  # ------------------------------------------------------------------ #

  ad_guard_loaded <- reactiveVal(FALSE)
  ad_guard_status <- reactiveVal("AD guard has not been run yet in this session.")
  ad_guard_counts <- reactiveVal(NULL)
  ad_guard_output_df <- reactiveVal(NULL)
  ad_audit_nonce <- reactiveVal(0L)

  ensure_ad_guard_loaded <- function() {
    if (isTRUE(ad_guard_loaded())) return(invisible(TRUE))
    helper <- file.path(PROJECT_DIR, "scripts", "run_ad_guard.R")
    if (!file.exists(helper)) {
      ad_guard_status(paste0("Missing scripts/run_ad_guard.R at ", helper))
      return(invisible(FALSE))
    }
    sys.source(helper, envir = globalenv())
    ad_guard_loaded(TRUE)
    invisible(TRUE)
  }

  observeEvent(input$btn_ad_rebuild_all, {
    if (!ensure_ad_guard_loaded()) return(NULL)
    res <- tryCatch(
      rebuild_ad_models(project_root = PROJECT_DIR, lane = "all"),
      error = function(e) list(rc = -1L, log_text = conditionMessage(e))
    )
    msg <- paste(
      paste0("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] rebuild_ad_models all"),
      paste0("  exit_code=", res$rc),
      res$log_text,
      sep = "\n"
    )
    ad_guard_status(msg)
    append_pipeline_log("AD models rebuild: ",
                        if (identical(as.integer(res$rc %||% -1L), 0L)) "OK" else "FAIL")
    ad_audit_nonce(ad_audit_nonce() + 1L)
  })

  observeEvent(input$btn_ad_refresh_audit, {
    ad_audit_nonce(ad_audit_nonce() + 1L)
  })

  observeEvent(input$btn_ad_run_guard, {
    if (!ensure_ad_guard_loaded()) return(NULL)
    fi <- input$ad_input_csv
    if (is.null(fi) || is.null(fi$datapath) || !file.exists(fi$datapath)) {
      ad_guard_status("No candidate CSV uploaded. Pick a file first.")
      return(NULL)
    }
    lane <- trimws(as.character(input$ad_lane_select %||% ""))
    mode <- as.character(input$ad_mode %||% "strict")
    out_csv <- file.path(dirname(fi$datapath),
                         paste0(tools::file_path_sans_ext(basename(fi$datapath)),
                                ".ad_annotated.csv"))

    res <- tryCatch(
      run_ad_guard(
        input_csv = fi$datapath,
        output_csv = out_csv,
        lane = if (nzchar(lane)) lane else NULL,
        mode = mode,
        project_root = PROJECT_DIR,
        audit = TRUE
      ),
      error = function(e) list(rc = -1L, log_text = conditionMessage(e),
                               output_csv = out_csv, summary = list())
    )

    counts <- res$summary$counts %||% list()
    ad_guard_counts(counts)
    msg <- paste(
      paste0("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] AD guard  lane=",
             if (nzchar(lane)) lane else "(auto)", "  mode=", mode, "  rc=", res$rc),
      res$log_text,
      sep = "\n"
    )
    ad_guard_status(msg)

    if (!is.null(res$output_csv) && file.exists(res$output_csv)) {
      df <- tryCatch(
        utils::read.csv(res$output_csv, stringsAsFactors = FALSE, check.names = FALSE),
        error = function(e) NULL
      )
      if (!is.null(df)) {
        ad_guard_output_df(utils::head(df, 200))
      }
    } else {
      ad_guard_output_df(NULL)
    }

    rejected <- as.integer(counts$reject %||% 0L)
    append_pipeline_log("AD guard ", mode, " on ", basename(fi$name),
                        " -> rejected=", rejected,
                        if (rejected > 0L) " (refusal active)" else "")
    ad_audit_nonce(ad_audit_nonce() + 1L)
  })

  output$ad_guard_status <- renderText({ ad_guard_status() })

  output$ad_guard_counts <- renderUI({
    counts <- ad_guard_counts()
    if (is.null(counts) || !length(counts)) {
      return(tags$div(class = "text-muted",
                      "Counts will appear here after the guard runs."))
    }
    pill <- function(label, n, bg) {
      tags$span(
        style = sprintf("display:inline-block;padding:6px 10px;margin:2px 4px 2px 0;border-radius:14px;background:%s;color:#fff;font-weight:600;", bg),
        sprintf("%s: %d", label, as.integer(n %||% 0L))
      )
    }
    tags$div(
      style = "margin:6px 0 8px 0;",
      pill("in_domain", counts$in_domain %||% 0L, "#2e7d32"),
      pill("warning",   counts$warning   %||% 0L, "#ef6c00"),
      pill("reject",    counts$reject    %||% 0L, "#c62828"),
      if (!is.null(counts$no_lane) && as.integer(counts$no_lane %||% 0L) > 0L)
        pill("no_lane", counts$no_lane, "#455a64")
    )
  })

  output$tbl_ad_guard_output <- DT::renderDT({
    df <- ad_guard_output_df()
    if (is.null(df) || !nrow(df)) {
      return(DT::datatable(
        tibble::tibble(Note = "Upload a CSV and run the AD guard to populate this table."),
        rownames = FALSE,
        options = list(dom = "t", paging = FALSE, ordering = FALSE,
                       searching = FALSE, info = FALSE)
      ))
    }
    show_cols <- intersect(c("pipeline_lane", "analyte", "result_value_numeric",
                             "result_unit", "ad_status", "ad_distance", "ad_reason",
                             "reference_lane", "training_range_version",
                             "ad_model_version", "ad_method"), colnames(df))
    if (!length(show_cols)) show_cols <- colnames(df)[seq_len(min(10, ncol(df)))]
    DT::datatable(
      df[, show_cols, drop = FALSE],
      rownames = FALSE,
      options = list(pageLength = 15, scrollX = TRUE)
    ) |>
      DT::formatStyle(
        "ad_status",
        target = "row",
        backgroundColor = DT::styleEqual(
          c("reject", "warning", "in_domain"),
          c("#fdecea", "#fff4e5", "#e8f5e9")
        )
      )
  })

  output$tbl_ad_audit <- DT::renderDT({
    ad_audit_nonce()
    if (!ensure_ad_guard_loaded()) {
      return(DT::datatable(
        tibble::tibble(Note = "AD helper not loaded; click 'Rebuild AD models' first."),
        rownames = FALSE,
        options = list(dom = "t", paging = FALSE, ordering = FALSE,
                       searching = FALSE, info = FALSE)
      ))
    }
    df <- tryCatch(read_ad_audit(project_root = PROJECT_DIR, tail_n = 100L),
                   error = function(e) data.frame(error = conditionMessage(e)))
    if (!is.data.frame(df) || !nrow(df)) {
      return(DT::datatable(
        tibble::tibble(Note = "No AD decisions logged yet (data/audit/ad_decisions.jsonl is empty)."),
        rownames = FALSE,
        options = list(dom = "t", paging = FALSE, ordering = FALSE,
                       searching = FALSE, info = FALSE)
      ))
    }
    DT::datatable(
      df,
      rownames = FALSE,
      options = list(pageLength = 10, order = list(list(0, "desc")), scrollX = TRUE)
    )
  })

  # ------------------------------------------------------------------ #
  # Sealed external blind-validation harness                           #
  # ------------------------------------------------------------------ #

  bv_loaded <- reactiveVal(FALSE)
  bv_status <- reactiveVal("No blind-validation action taken in this session.")
  bv_last_metrics <- reactiveVal(NULL)
  bv_nonce <- reactiveVal(0L)

  ensure_bv_loaded <- function() {
    if (isTRUE(bv_loaded())) return(invisible(TRUE))
    helper <- file.path(PROJECT_DIR, "scripts", "run_blind_validation.R")
    if (!file.exists(helper)) {
      bv_status(paste0("Missing scripts/run_blind_validation.R at ", helper))
      return(invisible(FALSE))
    }
    sys.source(helper, envir = globalenv())
    bv_loaded(TRUE)
    invisible(TRUE)
  }

  bv_refresh_submission_choices <- function() {
    if (!ensure_bv_loaded()) return(invisible(NULL))
    info <- tryCatch(bv_list(project_root = PROJECT_DIR),
                     error = function(e) list(submissions = character(0)))
    updateSelectInput(session, "bv_submission_id", choices = info$submissions,
                      selected = if (length(info$submissions))
                        info$submissions[length(info$submissions)] else NULL)
  }

  observeEvent(input$btn_bv_refresh, {
    bv_refresh_submission_choices()
    bv_nonce(bv_nonce() + 1L)
  })

  observeEvent(input$btn_bv_seal, {
    if (!ensure_bv_loaded()) return(NULL)
    fi <- input$bv_input_csv
    if (is.null(fi) || is.null(fi$datapath)) {
      bv_status("Upload a candidate CSV first.")
      return(NULL)
    }
    if (!nzchar(input$bv_submitted_by %||% "") ||
        !nzchar(input$bv_model_version %||% "")) {
      bv_status("Provide both 'Submitted by' and 'Model version'.")
      return(NULL)
    }
    res <- tryCatch(
      bv_build_pack(
        input_csv = fi$datapath,
        lane = input$bv_lane,
        truth_column = input$bv_truth_col,
        submitted_by = input$bv_submitted_by,
        model_version = input$bv_model_version,
        predicted_score_column = input$bv_score_col,
        predicted_label_column = input$bv_label_col,
        note = input$bv_note,
        project_root = PROJECT_DIR
      ),
      error = function(e) list(rc = -1L, log = conditionMessage(e),
                               parsed = list(status = "ERROR"))
    )
    msg <- paste(
      paste0("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] seal rc=", res$rc),
      res$log,
      sep = "\n"
    )
    bv_status(msg)
    if (identical(res$parsed$status, "sealed")) {
      append_pipeline_log("Blind-validation seal: ", res$parsed$submission_id)
      bv_refresh_submission_choices()
    } else {
      append_pipeline_log("Blind-validation seal FAILED")
    }
    bv_nonce(bv_nonce() + 1L)
  })

  bv_run_score <- function(force) {
    if (!ensure_bv_loaded()) return(NULL)
    sub_id <- trimws(as.character(input$bv_submission_id %||% ""))
    if (!nzchar(sub_id)) {
      bv_status("Pick a sealed submission to score.")
      return(NULL)
    }
    res <- tryCatch(
      bv_score(sub_id, force = force, project_root = PROJECT_DIR),
      error = function(e) list(rc = -1L, log = conditionMessage(e), parsed = list())
    )
    msg <- paste(
      paste0("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] score rc=", res$rc,
             if (force) " (forced)" else ""),
      res$log,
      sep = "\n"
    )
    bv_status(msg)
    if (identical(res$parsed$status, "REVEALED") ||
        identical(res$parsed$status, "ALREADY_REVEALED")) {
      bv_last_metrics(res$parsed$metrics)
      append_pipeline_log("Blind-validation reveal: ", sub_id,
                          if (isTRUE(res$parsed$ad_policy_drift) ||
                              isTRUE(res$parsed$threshold_drift))
                            " (freeze drift recorded)" else "")
    } else if (identical(res$parsed$status, "REFUSED")) {
      bv_last_metrics(NULL)
      append_pipeline_log("Blind-validation REFUSED: ",
                          res$parsed$reason %||% "unknown")
    }
    bv_nonce(bv_nonce() + 1L)
  }

  observeEvent(input$btn_bv_score,       { bv_run_score(force = FALSE) })
  observeEvent(input$btn_bv_force_score, { bv_run_score(force = TRUE)  })

  output$bv_status <- renderText({ bv_status() })

  output$bv_score_pills <- renderUI({
    m <- bv_last_metrics()
    if (is.null(m) || !length(m)) {
      return(tags$div(class = "text-muted",
                      "Metrics will appear here after the next reveal."))
    }
    pill <- function(label, val, bg) {
      v <- if (is.null(val)) "NA" else
        if (is.numeric(val) || (is.character(val) && grepl("^[-0-9.]+$", val)))
          format(round(as.numeric(val), 4), nsmall = 0, scientific = FALSE)
      else as.character(val)
      tags$span(
        style = sprintf("display:inline-block;padding:6px 10px;margin:2px 4px 2px 0;border-radius:14px;background:%s;color:#fff;font-weight:600;", bg),
        sprintf("%s: %s", label, v)
      )
    }
    tags$div(
      style = "margin:6px 0 10px 0;",
      pill("ROC AUC",      m$roc_auc,          "#1565c0"),
      pill("precision",    m$precision,        "#2e7d32"),
      pill("recall",       m$recall,           "#2e7d32"),
      pill("F1",           m$f1,               "#558b2f"),
      pill("flags / 10k",  m$flags_per_10k,    "#6d4c41"),
      pill("FP / TP",      m$FP_per_TP,        "#bf360c"),
      pill("AD in_domain", m$ad_in_domain_count, "#2e7d32"),
      pill("AD warning",   m$ad_warning_count, "#ef6c00"),
      pill("AD reject",    m$ad_reject_count,  "#c62828")
    )
  })

  output$tbl_bv_submissions <- DT::renderDT({
    bv_nonce()
    if (!ensure_bv_loaded()) {
      return(DT::datatable(
        tibble::tibble(Note = "Blind-validation helper not loaded yet."),
        rownames = FALSE,
        options = list(dom = "t", paging = FALSE, ordering = FALSE,
                       searching = FALSE, info = FALSE)
      ))
    }
    df <- tryCatch(bv_read_submissions_index(project_root = PROJECT_DIR, tail_n = 100L),
                   error = function(e) data.frame())
    if (!is.data.frame(df) || !nrow(df)) {
      return(DT::datatable(
        tibble::tibble(Note = "No submissions sealed yet."),
        rownames = FALSE,
        options = list(dom = "t", paging = FALSE, ordering = FALSE,
                       searching = FALSE, info = FALSE)
      ))
    }
    DT::datatable(df, rownames = FALSE,
                  options = list(pageLength = 8, scrollX = TRUE,
                                 order = list(list(1, "desc"))))
  })

  output$tbl_bv_reveals <- DT::renderDT({
    bv_nonce()
    if (!ensure_bv_loaded()) {
      return(DT::datatable(
        tibble::tibble(Note = "Blind-validation helper not loaded yet."),
        rownames = FALSE,
        options = list(dom = "t", paging = FALSE, ordering = FALSE,
                       searching = FALSE, info = FALSE)
      ))
    }
    df <- tryCatch(bv_read_reveals_index(project_root = PROJECT_DIR, tail_n = 100L),
                   error = function(e) data.frame())
    if (!is.data.frame(df) || !nrow(df)) {
      return(DT::datatable(
        tibble::tibble(Note = "No reveals yet."),
        rownames = FALSE,
        options = list(dom = "t", paging = FALSE, ordering = FALSE,
                       searching = FALSE, info = FALSE)
      ))
    }
    DT::datatable(df, rownames = FALSE,
                  options = list(pageLength = 8, scrollX = TRUE,
                                 order = list(list(1, "desc")))) |>
      DT::formatStyle("ad_policy_drift",
                      target = "row",
                      backgroundColor = DT::styleEqual(
                        c("TRUE", "FALSE"), c("#fff4e5", "#ffffff")))
  })

  iso_preflight_button_handler <- function() {
    pf <- run_iso_preflight_check()
    failed <- names(pf$checks)[!pf$checks]
    if (isTRUE(pf$ok)) {
      iso_preflight_note(paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " PASS"))
      append_pipeline_log("ISO preflight PASS (reference, method, qc, pt).")
      showNotification("ISO preflight passed.", type = "message")
      write_audit(
        "pfas_pipeline",
        "iso_preflight",
        "execute_success",
        op_id(),
        "ISO preflight passed",
        list(checks = as.list(pf$checks))
      )
    } else {
      iso_preflight_note(paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " BLOCK (", paste(failed, collapse = ", "), ")"))
      append_pipeline_log(
        "ISO preflight BLOCK: ", paste(failed, collapse = ", "),
        " | ", iso_preflight_failed_paths_note(pf)
      )
      showNotification(paste0("ISO preflight blocked: ", paste(failed, collapse = ", ")), type = "error")
      write_audit(
        "pfas_pipeline",
        "iso_preflight",
        "execute_failure",
        op_id(),
        "ISO preflight blocked",
        list(checks = as.list(pf$checks), failed = failed)
      )
    }
    pfas_results_nonce(pfas_results_nonce() + 1L)
  }

  observeEvent(input$btn_iso_preflight, {
    iso_preflight_button_handler()
  })

  observeEvent(input$btn_pfas_pipeline_iso_preflight, {
    iso_preflight_button_handler()
  })

  observeEvent(input$btn_bootstrap_source_folders, {
    src_root <- file.path(PROJECT_DIR, "data", "external")
    src_dirs <- c(
      "nhanes", "epa_ucmr5", "epa_echo_pfas", "sdwis", "external_uploads",
      "method_validation", "method_data", "qc_datasets", "proficiency_testing",
      "ca_waterboards", "mi_egle", "epa_1633_mdl", "echo",
      "echo_epa_gov", "epa_gov_water", "data_ca_gov", "michigan_gov", "nj_gov", "denix_osd_mil",
      "epa_gov_sludge_soil", "sciencebase_gov", "pca_state_mn_us", "data_nal_usda_gov",
      "wwwn_cdc_gov", "atsdr_cdc_gov", "biomonitoring_ca_gov", "nyc_gov", "nist_gov", "hbm4eu_eu",
      "epa_gov_air", "ww2_arb_ca_gov", "norman_network_net"
    )
    created <- character(0)
    for (d in src_dirs) {
      p <- file.path(src_root, d)
      if (!dir.exists(p)) {
        dir.create(p, recursive = TRUE, showWarnings = FALSE)
        created <- c(created, d)
      }
      readme <- file.path(p, "README_DROP_HERE.txt")
      if (!file.exists(readme)) {
        writeLines(
          c(
            paste("Source folder:", d),
            "",
            "Drop source files here (CSV preferred).",
            "Then run: 6) Build multi-source training table.",
            "Reference schema hints: data/external/SOURCE_INTAKE_TEMPLATE.csv"
          ),
          con = readme
        )
      }
    }
    template_path <- file.path(src_root, "SOURCE_INTAKE_TEMPLATE.csv")
    note <- paste0(
      "Bootstrap complete.\n",
      "Root: ", normalizePath(src_root, winslash = "/", mustWork = FALSE), "\n",
      "New folders created: ", length(created), if (length(created) > 0) paste0(" [", paste(created, collapse = ", "), "]") else "", "\n",
      "Template: ", normalizePath(template_path, winslash = "/", mustWork = FALSE)
    )
    source_bootstrap_note(note)
    write_audit(
      "external_sources",
      "bootstrap_folders",
      "execute_success",
      op_id(),
      "External source folders bootstrapped",
      list(created_folders = created, total_folders = length(src_dirs))
    )
    showNotification("External source folders bootstrapped.", type = "message")
    raw_icis <- file.path(PROJECT_DIR, "data", "raw", "epa_icis_npdes")
    if (!dir.exists(raw_icis)) {
      dir.create(raw_icis, recursive = TRUE, showWarnings = FALSE)
    }
    ricis_readme <- file.path(raw_icis, "README_ICIS_NPDES.txt")
    if (!file.exists(ricis_readme)) {
      writeLines(
        c(
          "EPA ICIS-NPDES bulk downloads land here (see scripts/download_epa_icis_npdes.R).",
          "Mirror: download_epa_icis_npdes_ml.ps1 in project root.",
          "ECHO index: https://echo.epa.gov/tools/data-downloads",
          "PFAS DMR slice: python scripts/filter_npdes_dmr_pfas.py --fiscal-year YYYY"
        ),
        con = ricis_readme
      )
    }
  })

  observeEvent(input$external_ml_file, {
    # Must match UI fileInput id "external_ml_file".
    f <- normalize_shiny_file_upload(input$external_ml_file)
    external_upload_raw(NULL)
    external_upload_report(NULL)
    external_upload_normalized(NULL)
    external_upload_read_error("")
    external_upload_strict_result(NULL)
    external_reference_preflight(NULL)
    # Reset any sticky prior mappings so new uploads re-run auto-detection.
    map_keys <- c(
      "source_dataset", "sample_id", "matrix", "date", "analyte", "cas",
      "result_value", "unit", "qualifier", "mdl", "rl", "detect_flag",
      "state", "county", "region", "facility_water_type", "sample_point_type",
      "method_id", "collection_year", "collection_month", "pws_size", "facility_id", "sample_point_id",
      "latitude", "longitude", "health_endpoint", "health_value",
      REFERENCE_EXTRA_MAP_KEYS
    )
    for (k in map_keys) {
      try(updateSelectInput(session, paste0("map_", k), selected = ""), silent = TRUE)
    }
    if (is.null(f)) return(invisible(NULL))
    ext <- tolower(tools::file_ext(f$name))
    external_upload_name(f$name)
    if (!(ext %in% allowed_upload_ext)) {
      msg <- paste0("Unsafe/unsupported file type: .", ext)
      external_upload_read_error(msg)
      showNotification(msg, type = "error")
      return(invisible(NULL))
    }
    if (!nzchar(f$datapath) || !isTRUE(file.exists(f$datapath))) {
      msg <- "No file uploaded yet (server temp path missing or expired)."
      external_upload_read_error(msg)
      showNotification(msg, type = "error")
      return(invisible(NULL))
    }
    dat <- tryCatch(
      safe_read_upload(f$datapath, f$name),
      error = function(e) {
        msg <- paste("Upload read failed:", conditionMessage(e))
        external_upload_read_error(msg)
        external_upload_raw(NULL)
        showNotification(msg, type = "error")
        NULL
      }
    )
    if (is.null(dat)) return(invisible(NULL))
    if (!is.data.frame(dat) || nrow(dat) == 0) {
      msg <- "Upload rejected: file has no rows or unreadable table structure."
      external_upload_read_error(msg)
      showNotification(msg, type = "error")
      return(invisible(NULL))
    }
    external_upload_read_error("")
    external_upload_raw(dat)
    showNotification(paste("Loaded upload:", f$name %||% "", "rows:", nrow(dat)), type = "message")
    if (isTRUE(detect_icis_air_bulk_program_table(names(dat), f$name %||% ""))) {
      showNotification(
        paste(
          "ICIS-AIR program metadata detected. PFAS occurrence auto-mapping is DISABLED for this file.",
          "Validate / Normalize / Save / Train will refuse. Use scripts/filter_icis_air_pfas.py or OTM-50 for air measurements."
        ),
        type = "error",
        duration = 20
      )
      # Hard reset: blank every PFAS-occurrence map dropdown so prior
      # auto-detect picks (pollutant_code -> result_value, CAS -> state, etc.)
      # cannot survive into validate/save.
      for (k in PFAS_OCCURRENCE_MAP_FIELDS) {
        try(updateSelectInput(session, paste0("map_", k), selected = ""), silent = TRUE)
      }
    }
    if (isTRUE(detect_nhanes_serum_biomonitoring(names(dat), f$name %||% ""))) {
      showNotification(
        paste(
          "NHANES serum biomonitoring detected (matrix: human serum, ng/mL, wide format).",
          "PFAS occurrence auto-mapping is DISABLED for this file.",
          "Validate / Normalize / Save / Train will refuse. The serum lane is governed by",
          "validation/serum_v1/; use scripts/convert_nhanes_xpt_to_csv.R for the documented",
          "ingestion path. Cross-matrix combination is not authorized (schema_contract.md \u00a75)."
        ),
        type = "error",
        duration = 20
      )
      # Hard reset: blank every PFAS-occurrence map dropdown so prior
      # auto-detect picks (SEQN -> result_value, lbxnfoa -> analyte, etc.)
      # cannot survive into validate/save.
      for (k in PFAS_OCCURRENCE_MAP_FIELDS) {
        try(updateSelectInput(session, paste0("map_", k), selected = ""), silent = TRUE)
      }
    }
  })

  # Derived: which semantic-type lane is this upload routed to?
  # Used by get_upload_mapping() to control which fields auto-fill, and by
  # btn_external_* handlers to refuse hard when the lane does not allow
  # PFAS-occurrence training.
  upload_dataset_semantic_type <- reactive({
    df <- external_upload_raw()
    nm <- external_upload_name() %||% ""
    if (is.null(df) || !is.data.frame(df) || ncol(df) < 1L) {
      return("pfas_occurrence_or_other")
    }
    if (isTRUE(detect_icis_air_bulk_program_table(names(df), nm))) {
      return("air_program_metadata")
    }
    if (isTRUE(detect_nhanes_serum_biomonitoring(names(df), nm))) {
      return("serum_biomonitoring")
    }
    "pfas_occurrence_or_other"
  })

  # True when the current upload is on a non-occurrence governance lane
  # (program metadata or human-serum biomonitoring) that must NOT be
  # normalized through the PFAS environmental-occurrence schema. The
  # function name is retained for backward compatibility with existing
  # call sites; the semantic widening to include `serum_biomonitoring` is
  # intentional and matches validation/serum_v1/schema_contract.md \u00a75
  # (matrix isolation) and applicability_domain.txt R5 (mixed-matrix refusal).
  upload_is_metadata_lane <- reactive({
    sem <- upload_dataset_semantic_type()
    identical(sem, "air_program_metadata") ||
      identical(sem, "biosolids_program_metadata") ||
      identical(sem, "serum_biomonitoring")
  })

  # Convenience helper for the action handlers: refuse with one consistent
  # message + audit entry, and return TRUE so callers can early-return. The
  # message branches per semantic type so the operator is pointed at the
  # correct ingestion path / governance contract.
  refuse_pfas_op_on_metadata_lane <- function(op_label) {
    sem <- upload_dataset_semantic_type()
    if (!isTRUE(upload_is_metadata_lane())) return(FALSE)
    msg <- if (identical(sem, "serum_biomonitoring")) {
      paste0(
        op_label,
        " blocked: this upload is '", sem,
        "', a human-serum biomonitoring dataset (ng/mL, wide format). It must ",
        "not be mapped through the environmental PFAS-occurrence schema. See ",
        "validation/serum_v1/ for the serum lane governance, and use ",
        "scripts/convert_nhanes_xpt_to_csv.R for the documented ingestion path. ",
        "Cross-matrix combination is not authorized by ",
        "validation/serum_v1/schema_contract.md \u00a75."
      )
    } else {
      paste0(
        op_label,
        " blocked: this upload is '", sem,
        "', not PFAS occurrence data. Use scripts/filter_icis_air_pfas.py for ",
        "curated air program reference, or OTM-50 for air emissions measurements."
      )
    }
    audit_tag <- if (identical(sem, "serum_biomonitoring")) {
      "serum_biomonitoring_refusal"
    } else {
      "icis_air_metadata_refusal"
    }
    external_upload_save_note(msg)
    showNotification(msg, type = "error", duration = 18)
    # For the serum branch, attach the physiological-guard verdict to
    # the audit entry. The upload itself carries no classification
    # stamp (it is a raw NHANES XPT-derived CSV), so the guard returns
    # missing_field; that is the correct verdict and tells a reviewer
    # exactly which lane-contract fields would have been required for
    # the row to be admitted into the serum lane. The refusal message
    # is unchanged; the audit payload gets richer.
    guard_payload <- list()
    if (identical(sem, "serum_biomonitoring")) {
      df_now <- external_upload_raw()
      upload_row_like <- list()
      if (!is.null(df_now) && is.data.frame(df_now) && ncol(df_now) > 0L) {
        for (k in PHYSIOLOGICAL_CLASSIFICATION_FIELDS) {
          col_match <- names(df_now)[tolower(names(df_now)) == k]
          if (length(col_match) > 0L) {
            v <- df_now[[col_match[[1]]]]
            v <- as.character(v[!is.na(v)])
            if (length(v) > 0L) upload_row_like[[k]] <- v[[1]]
          }
        }
      }
      g <- physiological_guard(upload_row_like, lane = "serum")
      guard_payload <- list(
        physiological_guard = list(
          ok          = isTRUE(g$ok),
          code        = g$code %||% "",
          missing     = g$missing,
          mismatched  = g$mismatched,
          expected    = g$expected,
          observed    = g$observed,
          governance_ref = "validation/serum_v1/schema_contract.md \u00a79"
        )
      )
    }
    try(
      write_audit(
        "external_upload",
        audit_tag,
        "op_refused_metadata_lane",
        op_id(),
        msg,
        c(
          list(
            operation = op_label,
            semantic_type = sem,
            file_name = external_upload_name() %||% ""
          ),
          guard_payload
        )
      ),
      silent = TRUE
    )
    TRUE
  }

  output$icis_air_external_upload_banner <- renderUI({
    df <- external_upload_raw()
    nm <- external_upload_name() %||% ""
    if (is.null(df) || !is.data.frame(df) || ncol(df) < 1L) {
      return(NULL)
    }
    if (!isTRUE(detect_icis_air_bulk_program_table(names(df), nm))) {
      return(NULL)
    }
    tags$div(
      class = "alert",
      style = paste0(
        "background:#ffebee;border:2px solid #c62828;color:#4e342e;",
        "padding:14px 16px;border-radius:4px;margin:10px 0 12px 0;"
      ),
      tags$p(
        style = "margin:0 0 10px 0;font-size:15px;",
        tags$strong(style = "color:#b71c1c;", "ICIS-AIR metadata dataset detected. Automatic PFAS occurrence mapping disabled."),
        tags$span(
          style = "font-size:11px;color:#6d4c41;margin-left:8px;",
          paste0("(", ICIS_AIR_UPLOAD_BANNER_VERSION, ")")
        )
      ),
      tags$p(
        style = "margin:0 0 8px 0;",
        "Column headers match the EPA ",
        tags$code("ICIS-AIR_POLLUTANTS"),
        " program listing (facility × reported pollutant). ",
        tags$strong("This is not a PFAS-in-air concentration table."),
        " Rows are governance metadata (a facility ",
        tags$em("reports"),
        " or ",
        tags$em("permits"),
        " a pollutant), not analytical results."
      ),
      tags$p(
        style = "margin:0 0 8px 0;",
        tags$strong("Mapping safeguards now active:"),
        tags$ul(
          style = "margin:6px 0 0 18px;padding:0;",
          tags$li(
            tags$code("pollutant_code"),
            " is blocked from ",
            tags$code("result_value"),
            " (a regulatory code is not a concentration)."
          ),
          tags$li(
            tags$code("chemical_abstract_service_nmbr"),
            " is blocked from ",
            tags$code("state"),
            " (a CAS number is not a geography)."
          ),
          tags$li(
            "All occurrence fields (",
            tags$code("result_value"),
            ", ",
            tags$code("unit"),
            ", ",
            tags$code("analyte"),
            ", ",
            tags$code("date"),
            ", ",
            tags$code("mdl"),
            ", ",
            tags$code("rl"),
            ", ",
            tags$code("detect_flag"),
            ", ",
            tags$code("state"),
            ", ...) are force-blanked on load."
          ),
          tags$li(
            tags$strong("Validate / Normalize / Save / Train refuse with HTTP-style hard errors"),
            " — the file cannot enter PFAS training or threshold analysis."
          )
        )
      ),
      tags$p(
        style = "margin:0 0 8px 0;",
        tags$strong("Use instead: "),
        tags$ul(
          style = "margin:6px 0 0 18px;padding:0;",
          tags$li(
            "Curated PFAS-relevant slice: ",
            tags$code("python scripts/filter_icis_air_pfas.py"),
            " → ",
            tags$code("data/processed/epa_icis_air/icis_air_pfas_pollutants.csv"),
            " (",
            tags$em("air program reference / governance joins — still not concentrations"),
            ")."
          ),
          tags$li(
            "Measured stack / source emissions: OTM-50 workbooks (",
            tags$code("air_emissions"),
            " lane; see ",
            tags$code("data/external/epa_otm50/README.md"),
            ")."
          )
        )
      ),
      tags$p(
        style = "margin:0;font-size:12px;color:#5d4037;",
        tags$strong("Semantic type: "),
        tags$code("air_program_metadata"),
        ". Each upload semantic type now has its own mapping policy; concentration and metadata never share the normalization mapper."
      )
    )
  })

  output$serum_external_upload_banner <- renderUI({
    df <- external_upload_raw()
    nm <- external_upload_name() %||% ""
    if (is.null(df) || !is.data.frame(df) || ncol(df) < 1L) {
      return(NULL)
    }
    if (!isTRUE(detect_nhanes_serum_biomonitoring(names(df), nm))) {
      return(NULL)
    }
    tags$div(
      class = "alert",
      style = paste0(
        "background:#fff3e0;border:2px solid #e65100;color:#3e2723;",
        "padding:14px 16px;border-radius:4px;margin:10px 0 12px 0;"
      ),
      tags$p(
        style = "margin:0 0 10px 0;font-size:15px;",
        tags$strong(style = "color:#bf360c;", "NHANES serum biomonitoring dataset detected. Automatic PFAS occurrence mapping disabled."),
        tags$span(
          style = "font-size:11px;color:#6d4c41;margin-left:8px;",
          paste0("(", SERUM_UPLOAD_BANNER_VERSION, ")")
        )
      ),
      tags$p(
        style = "margin:0 0 8px 0;",
        "Column headers match the NHANES PFAS Special Subsample (",
        tags$code("SEQN"), ", ", tags$code("WTSB2YR"), ", ",
        tags$code("LBXNFOA"), ", ", tags$code("LBDNFOAL"), ", ", "..., ",
        "or their lowercase snake_case CSV equivalents). ",
        tags$strong("This is human serum biomonitoring data (matrix: human serum, units: ng/mL, wide format),"),
        " not environmental PFAS-occurrence data (matrix: drinking water / biosolids / AFFF / air, units: ng/L, long format)."
      ),
      tags$p(
        style = "margin:0 0 8px 0;",
        tags$strong("Mapping safeguards now active:"),
        tags$ul(
          style = "margin:6px 0 0 18px;padding:0;",
          tags$li(
            tags$code("SEQN"),
            " is blocked from ",
            tags$code("result_value"),
            " (a respondent ID is not a concentration; values \u2248 93,000\u2013125,000 are not ng/L PFAS)."
          ),
          tags$li(
            tags$code("WTSB2YR"),
            " is blocked from ",
            tags$code("result_value"),
            " (a NHANES survey weight is not a concentration)."
          ),
          tags$li(
            "All occurrence fields (",
            tags$code("result_value"),
            ", ",
            tags$code("unit"),
            ", ",
            tags$code("analyte"),
            ", ",
            tags$code("date"),
            ", ",
            tags$code("mdl"),
            ", ",
            tags$code("rl"),
            ", ",
            tags$code("detect_flag"),
            ", ",
            tags$code("state"),
            ", ...) are force-blanked on load."
          ),
          tags$li(
            tags$strong("Validate / Normalize / Save / Train refuse with HTTP-style hard errors"),
            " \u2014 the file cannot enter PFAS occurrence training, threshold analysis, or the evidence-governed corpus."
          )
        )
      ),
      tags$p(
        style = "margin:0 0 8px 0;",
        tags$strong("Use instead:"),
        tags$ul(
          style = "margin:6px 0 0 18px;padding:0;",
          tags$li(
            "Documented ingestion path: ",
            tags$code("Rscript scripts/convert_nhanes_xpt_to_csv.R"),
            " \u2192 ",
            tags$code("data/training/serum/nhanes_serum_pfas_2017_2018.csv"),
            " (lane governance: ",
            tags$code("validation/serum_v1/"),
            ")."
          ),
          tags$li(
            "Cross-matrix combination of serum with any environmental lane requires an explicit harmonization artifact (see ",
            tags$code("validation/serum_v1/schema_contract.md"),
            " \u00a75) and is ",
            tags$strong("not authorized"),
            " by this upload path."
          )
        )
      ),
      tags$p(
        style = "margin:0;font-size:12px;color:#4e342e;",
        tags$strong("Semantic type: "),
        tags$code("serum_biomonitoring"),
        ". Lane governance: ",
        tags$code("validation/serum_v1/"),
        " (intended_use, applicability_domain, schema_contract, limitations, provenance, data_dictionary)."
      )
    )
  })

  # Physiological-sample autodetect summary: rendered INLINE next to the
  # column-mapping dropdowns when a NHANES serum biomonitoring file is
  # detected. Where the environmental autodetect blanks every dropdown on
  # a serum file (because there is nothing it can validly map), this
  # block shows the operator the affirmative per-column classification
  # (SEQN \u2192 respondent_id, WTSB2YR \u2192 survey_weight, LBX\u2026 \u2192 ng/mL,
  # LBD\u2026L \u2192 0/1 LOD code) and the paired LBX/LBD coverage for the
  # 9-analyte NHANES PFAS panel.
  output$serum_external_autodetect_summary <- renderUI({
    df <- external_upload_raw()
    nm <- external_upload_name() %||% ""
    if (is.null(df) || !is.data.frame(df) || ncol(df) < 1L) return(NULL)
    if (!isTRUE(detect_nhanes_serum_biomonitoring(names(df), nm))) return(NULL)
    auto <- autodetect_physiological_serum_columns(names(df))
    cnt <- auto$counts
    role_label <- function(r) {
      switch(
        r,
        respondent_id          = "respondent_id (NHANES SEQN)",
        survey_weight          = "survey_weight (NHANES WTSB2YR/WTMEC2YR)",
        analyte_concentration  = "analyte_concentration (ng/mL)",
        analyte_detection_code = "analyte_detection_code (0/1)",
        unknown                = "unknown",
        r
      )
    }
    cls_rows <- auto$columns
    cls_tbl_rows <- if (is.null(cls_rows) || nrow(cls_rows) == 0L) {
      list(tags$tr(tags$td(colspan = 6, "(no columns)")))
    } else {
      lapply(seq_len(nrow(cls_rows)), function(i) {
        r <- cls_rows[i, , drop = FALSE]
        bg <- if (identical(r$role, "unknown")) "#fafafa" else "#fff8e1"
        tags$tr(
          style = paste0("background:", bg, ";"),
          tags$td(style = "padding:4px 8px;font-family:monospace;", r$column %||% ""),
          tags$td(style = "padding:4px 8px;",
                  role_label(as.character(r$role %||% "unknown"))),
          tags$td(style = "padding:4px 8px;", r$analyte %||% ""),
          tags$td(style = "padding:4px 8px;font-family:monospace;",
                  r$paired_with %||% ""),
          tags$td(style = "padding:4px 8px;", r$units %||% ""),
          tags$td(style = "padding:4px 8px;font-size:12px;color:#5d4037;",
                  r$notes %||% "")
        )
      })
    }
    paired_rows <- if (length(auto$paired_lbx_lbd) > 0L) {
      lapply(auto$paired_lbx_lbd, function(p) {
        tags$tr(
          tags$td(style = "padding:4px 8px;", p$analyte %||% ""),
          tags$td(style = "padding:4px 8px;font-family:monospace;",
                  p$lbx_column %||% ""),
          tags$td(style = "padding:4px 8px;font-family:monospace;",
                  p$lbd_column %||% "")
        )
      })
    } else {
      list(tags$tr(tags$td(colspan = 3, "(none recognized)")))
    }
    stamp <- auto$classification_stamp
    stamp_rows <- if (is.null(stamp) || length(stamp) == 0L) {
      list(tags$tr(tags$td(colspan = 3, "(no classification stamp)")))
    } else {
      stamp_descr <- list(
        sample_domain       = "Top-level domain: physiological body burden, not environmental occurrence",
        sample_matrix       = "Concrete biological matrix (serum, vs. drinking water / biosolids / air / AFFF / methanol)",
        measurement_context = "Why the sample was measured: internal exposure (biomonitoring), not source-contamination tracking",
        source_program      = "Authoritative source program (NHANES cycle J, CDC/NCHS public release)",
        units               = "Concentration units (ng/mL, not ng/L; ng/L would imply environmental water)"
      )
      lapply(PHYSIOLOGICAL_CLASSIFICATION_FIELDS, function(k) {
        tags$tr(
          style = "background:#fff8e1;",
          tags$td(style = "padding:4px 8px;font-family:monospace;", k),
          tags$td(style = "padding:4px 8px;font-family:monospace;",
                  as.character(stamp[[k]] %||% "")),
          tags$td(style = "padding:4px 8px;font-size:12px;color:#5d4037;",
                  stamp_descr[[k]] %||% "")
        )
      })
    }
    tags$div(
      class = "alert",
      style = paste0(
        "background:#fffde7;border:1px solid #fbc02d;color:#3e2723;",
        "padding:12px 14px;border-radius:4px;margin:6px 0 12px 0;"
      ),
      tags$p(
        style = "margin:0 0 8px 0;font-size:14px;",
        tags$strong(style = "color:#bf360c;",
                    "Physiological-sample autodetect (NHANES serum biomonitoring)"),
        tags$span(
          style = "font-size:11px;color:#6d4c41;margin-left:8px;",
          paste0("(", SERUM_BIOMONITORING_AUTODETECT_VERSION, ")")
        )
      ),
      tags$p(style = "margin:8px 0 4px 0;",
             tags$strong("Lane-stamped physiological classification"),
             tags$span(
               style = "font-size:12px;color:#6d4c41;margin-left:6px;",
               "(",
               tags$code("validation/serum_v1/schema_contract.md \u00a79"),
               ", auto-mapped \u2014 not from upload columns)"
             )),
      tags$table(
        style = "border-collapse:collapse;width:auto;font-size:13px;margin:0 0 10px 0;",
        tags$thead(
          tags$tr(
            style = "background:#fff3e0;color:#3e2723;",
            tags$th(style = "padding:4px 8px;text-align:left;", "field"),
            tags$th(style = "padding:4px 8px;text-align:left;", "lane-stamped value"),
            tags$th(style = "padding:4px 8px;text-align:left;", "why this field")
          )
        ),
        tags$tbody(stamp_rows)
      ),
      tags$p(
        style = "margin:0 0 10px 0;font-size:12px;color:#4e342e;",
        tags$strong("Physiological guard: "),
        "the same five fields are verified on every Validate / Normalize / Save / Train ",
        "(refusal codes ",
        tags$code("physiological_classification_missing"),
        " and ",
        tags$code("physiological_classification_mismatch"),
        "). A row without the stamp, or with a value that disagrees with this table, ",
        "is refused at the serum lane boundary (",
        tags$code("schema_contract.md \u00a79.2"),
        ")."
      ),
      tags$ul(
        style = "margin:0 0 8px 18px;padding:0;line-height:1.45;",
        tags$li(tags$strong("Lane: "),    tags$code(auto$lane %||% "")),
        tags$li(tags$strong("Matrix: "),  auto$matrix %||% ""),
        tags$li(tags$strong("Method: "),  auto$method %||% ""),
        tags$li(tags$strong("Concentration units: "), auto$units %||% ""),
        tags$li(tags$strong("Table format: "), auto$format %||% ""),
        tags$li(
          tags$strong("Recognized columns: "),
          sprintf(
            "respondent_id=%d, survey_weight=%d, analyte_concentration=%d, analyte_detection_code=%d, unknown=%d",
            cnt$respondent_id %||% 0L,
            cnt$survey_weight %||% 0L,
            cnt$analyte_concentration %||% 0L,
            cnt$analyte_detection_code %||% 0L,
            cnt$unknown %||% 0L
          )
        )
      ),
      tags$p(style = "margin:8px 0 4px 0;",
             tags$strong("Per-column classification")),
      tags$table(
        style = "border-collapse:collapse;width:100%;font-size:13px;",
        tags$thead(
          tags$tr(
            style = "background:#fff3e0;color:#3e2723;",
            tags$th(style = "padding:4px 8px;text-align:left;", "column"),
            tags$th(style = "padding:4px 8px;text-align:left;", "role"),
            tags$th(style = "padding:4px 8px;text-align:left;", "analyte"),
            tags$th(style = "padding:4px 8px;text-align:left;", "paired_with"),
            tags$th(style = "padding:4px 8px;text-align:left;", "units"),
            tags$th(style = "padding:4px 8px;text-align:left;", "notes")
          )
        ),
        tags$tbody(cls_tbl_rows)
      ),
      tags$p(style = "margin:10px 0 4px 0;",
             tags$strong("Paired LBX/LBD analyte coverage")),
      tags$table(
        style = "border-collapse:collapse;width:auto;font-size:13px;",
        tags$thead(
          tags$tr(
            style = "background:#fff3e0;color:#3e2723;",
            tags$th(style = "padding:4px 8px;text-align:left;", "analyte"),
            tags$th(style = "padding:4px 8px;text-align:left;", "concentration column (ng/mL)"),
            tags$th(style = "padding:4px 8px;text-align:left;", "LOD-code column (0/1)")
          )
        ),
        tags$tbody(paired_rows)
      ),
      tags$p(
        style = "margin:10px 0 0 0;font-size:12px;color:#4e342e;",
        tags$strong("Why the PFAS-occurrence dropdowns are blank below: "),
        "this is wide-format physiological data, not long-format environmental occurrence. ",
        "The serum lane has its own training table at ",
        tags$code("data/training/serum/training.csv"),
        " (manifest: ",
        tags$code("data/training/serum/manifest.json"),
        ", AD model: ",
        tags$code("data/ad_models/serum/ad_model.json"),
        "). Cross-matrix combination is refused by ",
        tags$code("validation/serum_v1/schema_contract.md \u00a75"),
        "."
      )
    )
  })

  output$external_file_meta <- renderPrint({
    cat("Upload reader:", UPLOAD_READER_VERSION, "\n")
    cat("ICIS-NPDES UI:", ICIS_NPDES_UI_VERSION, "\n")
    cat("Mapping engine version:", MAPPING_ENGINE_VERSION, "\n")
    cat("(Delimited files) SAFE_READ_UPLOAD diagnostics go to the R console, not this panel.\n")
    cat("\n")
    f <- normalize_shiny_file_upload(input$external_ml_file)
    df <- external_upload_raw()
    read_err <- external_upload_read_error() %||% ""
    if (nzchar(read_err)) {
      cat("Upload error:", read_err, "\n")
      if (grepl("zero-length pattern", read_err, fixed = TRUE)) {
        cat(
          "Hint: redeploy LatestPFAS.R — delimited uploads use base R read.table only.\n",
          "Console must show SAFE_READ_UPLOAD START; Upload reader line must contain 'delimited-base-only'.\n",
          "Smoke file: data/test_upload/test_upload.csv . UCMR5_AddtlDataElem is supplemental metadata, not occurrence results.\n"
        )
      }
    }
    if (is.null(f) || is.null(df)) {
      if (is.null(f)) {
        cat("No file selected.\n")
      } else if (nzchar(read_err)) {
        cat("Preview not available (read failed; see error above).\n")
      } else {
        cat("No data in preview yet.\n")
      }
      return(invisible(NULL))
    }
    ext <- tolower(tools::file_ext(f$name))
    cat("File:", f$name %||% "", "\n")
    cat("Size (bytes):", f$size %||% NA, "\n")
    cat("Extension:", ext, "\n")
    cat("Rows:", nrow(df), "\n")
    cat("Columns:", ncol(df), "\n")
  })

  output$external_reference_preflight_status <- renderPrint({
    cat("Reference material preflight (governance)\n")
    cat("-------------------------------------------\n")
    cat(
      "PASS: required maps + numeric uncertainty; REVIEW: provenance/matrix notes; ",
      "BLOCK: bench table as occurrence type, or missing required reference fields.\n\n"
    )
    pf <- external_reference_preflight()
    if (is.null(pf)) {
      cat("No preflight result yet — upload a file, set Dataset type + Map columns, then click Validate.\n")
      return(invisible(NULL))
    }
    cat("Status:", pf$status %||% "unknown", "\n")
    if (length(pf$codes)) {
      cat("Codes:", paste(pf$codes, collapse = ", "), "\n")
    }
    if (length(pf$messages)) {
      cat("\nDetail:\n")
      for (m in pf$messages) {
        cat(" - ", m, "\n", sep = "")
      }
    }
  })

  output$tbl_external_preview <- renderDT({
    df <- external_upload_raw()
    if (is.null(df) || nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "Upload a supported file to preview first 20 rows."), rownames = FALSE))
    }
    render_dt(utils::head(df, 20), 20)
  })

  output$external_map_ui <- renderUI({
    df <- external_upload_raw()
    if (is.null(df)) {
      return(tags$p("Upload a file to configure column mapping."))
    }
    cols <- names(df)
    norm_name <- function(x) tolower(gsub("[^a-z0-9]+", "", trimws(as.character(x))))
    parse_num <- function(x) {
      y <- trimws(as.character(x))
      y[y %in% c("", "NA", "N/A", "na", "n/a", "NULL", "null")] <- NA_character_
      y <- gsub(",", "", y, fixed = TRUE)
      y <- gsub("^<\\s*", "", y)
      y <- gsub("^>\\s*", "", y)
      direct <- suppressWarnings(as.numeric(y))
      need_extract <- is.na(direct) & !is.na(y) & nzchar(y)
      if (any(need_extract, na.rm = TRUE)) {
        tok <- stringr::str_extract(y[need_extract], "[-+]?[0-9]*\\.?[0-9]+(?:[eE][-+]?[0-9]+)?")
        direct[need_extract] <- suppressWarnings(as.numeric(tok))
      }
      direct
    }
    is_bad_result_col <- function(cname) {
      if (!nzchar(cname) || !(cname %in% cols)) return(TRUE)
      key <- norm_name(cname)
      vals <- as.character(df[[cname]])
      vals <- vals[!is.na(vals)]
      if (length(vals) == 0) return(TRUE)
      vals <- utils::head(vals, 250)
      numeric_rate <- mean(!is.na(parse_num(vals)), na.rm = TRUE)
      letter_rate <- mean(safe_detect(vals, "[A-Za-z]"), na.rm = TRUE)
      looks_result_name <- safe_detect(key, "result|concentration|value|ngl|clean|meas|amount")
      looks_id_name <- safe_detect(key, "pws|well|station|sample|_id$|^id$|id")
      if (looks_id_name && !looks_result_name) return(TRUE)
      if (numeric_rate < 0.20) return(TRUE)
      if (letter_rate > 0.70 && !looks_result_name) return(TRUE)
      FALSE
    }
    choose_col <- function(field_name, aliases) {
      if (length(cols) == 0) return("")
      cn <- cols
      cn_norm <- norm_name(cn)
      al_norm <- norm_name(aliases)
      scores <- rep(0, length(cn))
      scores <- scores + ifelse(cn_norm %in% al_norm, 100, 0)
      for (a in al_norm) {
        aa <- suppressWarnings(trimws(as.character(a)))
        if (length(aa) != 1L || is.na(aa) || !nzchar(aa)) next
        scores <- scores + ifelse(safe_detect(cn_norm, aa), 35, 0)
      }
      if (identical(field_name, "result_value")) {
        numeric_rate <- vapply(cn, function(cname) mean(!is.na(parse_num(df[[cname]]))), numeric(1))
        digit_rate <- vapply(cn, function(cname) {
          vv <- as.character(df[[cname]])
          mean(safe_detect(vv, "[-+]?[0-9]*\\.?[0-9]+"), na.rm = TRUE)
        }, numeric(1))
        scores <- scores + 120 * numeric_rate
        scores <- scores + 45 * digit_rate
        scores <- scores + ifelse(safe_detect(cn_norm, "result|concentration|value|ngl|clean"), 30, 0)
        scores <- scores - ifelse(safe_detect(cn_norm, "modifier|qualifier|flag|vvl|code|id|pws|well|station|sample|tract|population|geoid|zip"), 120, 0)
      } else if (identical(field_name, "analyte")) {
        scores <- scores + ifelse(safe_detect(cn_norm, "analyte|contaminant|parameter|chemical|compound|name"), 40, 0)
        scores <- scores - ifelse(safe_detect(cn_norm, "modifier|vvl|id|code|flag"), 80, 0)
        pfas_rate <- vapply(cn, function(cname) {
          col <- df[[cname]]
          if (!(is.character(col) || is.factor(col))) return(0)
          mean(pfas_like(col), na.rm = TRUE)
        }, numeric(1))
        scores <- scores + 120 * pfas_rate
      } else if (identical(field_name, "sample_id")) {
        scores <- scores + ifelse(safe_detect(cn_norm, "sample|well|station|pws|^id$|_id$|id_"), 30, 0)
        scores <- scores - ifelse(safe_detect(cn_norm, "result|value|concentration"), 40, 0)
        scores <- scores - ifelse(safe_detect(cn_norm, "name|contaminant|chemical|pesticide"), 35, 0)
      } else if (identical(field_name, "uncertainty")) {
        numeric_rate <- vapply(cn, function(cname) mean(!is.na(parse_num(df[[cname]]))), numeric(1))
        scores <- scores + 100 * numeric_rate
        scores <- scores + ifelse(safe_detect(cn_norm, "uncertainty|expanded|u_exp|std|error|k2"), 45, 0)
      } else if (identical(field_name, "reference_id")) {
        scores <- scores + ifelse(safe_detect(cn_norm, "reference|srm|rm|nist|document|catalog|material|source"), 55, 0)
      }
      idx <- which.max(scores)
      if (length(idx) == 0 || !is.finite(scores[[idx]]) || scores[[idx]] <= 0) return("")
      if (identical(field_name, "result_value")) {
        best <- cn[[idx]]
        best_num_rate <- mean(!is.na(parse_num(df[[best]])))
        best_name_ok <- safe_detect(norm_name(best), "result|concentration|value|ngl|clean")
        if (isTRUE(is_bad_result_col(best))) return("")
        if (!(isTRUE(best_name_ok) || best_num_rate >= 0.6)) return("")
      }
      cn[[idx]]
    }
    pfas_like <- function(x) {
      y <- tolower(trimws(as.character(x)))
      y <- gsub("[^a-z0-9]+", " ", y)
      safe_detect(
        y,
        "\\bpf[a-z0-9]{2,}\\b|perfluoro|polyfluoro|fluorotelomer|genx|hfpo|adona|fosa|fosaa|fts|pfas"
      )
    }
    opts <- c("(not mapped)" = "", stats::setNames(cols, cols))
    fields <- CORE_EXTERNAL_MAP_KEYS
    labels <- c(
      source_dataset = "source_dataset",
      sample_id = "sample_id",
      matrix = "matrix",
      date = "sample_date/date",
      analyte = "analyte",
      cas = "cas (optional)",
      result_value = "result_value",
      unit = "result_unit",
      qualifier = "qualifier",
      mdl = "mdl",
      rl = "rl",
      detect_flag = "detect_flag",
      state = "state",
      county = "county",
      facility_water_type = "FacilityWaterType",
      sample_point_type = "SamplePointType",
      method_id = "MethodID",
      collection_year = "CollectionYear",
      facility_id = "FacilityID",
      sample_point_id = "SamplePointID",
      latitude = "latitude",
      longitude = "longitude"
    )
    aliases <- list(
      source_dataset = c("source_dataset", "source dataset", "dataset", "source", "source_name", "program", "datasource", "study"),
      sample_id = c(
        "sample_id", "sample id", "sample", "id", "seqn", "station", "pwsid", "pws_id", "samplepointid",
        "sampleid", "sample_number", "samplenumber", "lab_sample_id", "labsampleid", "submission_id", "submissionid",
        "sample_identifier", "sampleidentifier", "public_water_system_id", "pwsidentifier", "water_system_no", "watersystemno"
      ),
      matrix = c("matrix", "sample_matrix", "sample type", "sampletype", "matrixtype", "media", "media_type"),
      date = c(
        "sample_date", "sample date", "collection_date", "collection date", "date", "activity_start_date",
        "activitystartdate", "collectiondate", "date_collected", "datecollected", "sample_collection_date"
      ),
      analyte = c(
        "analyte", "analyte_name", "parameter", "parameter_name", "constituent", "contaminant", "chemical", "chemical_name", "compound",
        "contaminant_name", "constituent_name", "analytename", "parametercode", "parameter_code", "pollutant"
      ),
      cas = c("cas", "casrn", "cas_number", "cas_num", "casregistrynumber"),
      result_value = c(
        "result_value", "result value", "result", "result_clean", "resultclean", "result_ngl", "result ngl",
        "concentration", "concentration_ng_l", "concentration_ngl", "value", "value_ngl", "reported", "reported_result",
        "analyticalresultvalue", "analytical_result", "resultamount", "measurement_value", "level", "amount", "reading",
        "gm_result"
      ),
      unit = c(
        "result_unit", "result unit", "unit", "units", "uom", "result_units", "units_desc", "unit_desc",
        "gm_result_unit"
      ),
      qualifier = c(
        "qualifier", "flag", "result_flag", "censor", "result_qualifier", "lab_qualifier", "detection_qualifier",
        "gm_result_modifier", "sample_event_result_type", "result_type", "result_qualifier_code", "qualifier_code"
      ),
      mdl = c("mdl", "method_detection_limit", "detection_limit", "method_detection_level", "minimum_reporting_level"),
      rl = c("rl", "reporting_limit", "report_limit", "practical_quantitation_limit", "pql", "reporting_level"),
      detect_flag = c("detect_flag", "detect", "detected", "detection_indicator", "is_detected"),
      state = c("state", "state_abbr", "state_code", "st", "stateprovince", "state_province"),
      county = c("county", "county_name", "countyname", "administrative_area"),
      facility_water_type = c("facilitywatertype", "facility_water_type", "water_type", "sourcetype", "source_type"),
      sample_point_type = c("samplepointtype", "sample_point_type", "location_type", "point_type"),
      method_id = c("methodid", "method_id", "analytical_method", "analyticalmethod", "method_code", "methodcode", "analytical_method_id"),
      collection_year = c("collectionyear", "collection_year", "year", "sample_year", "calendar_year"),
      facility_id = c("facilityid", "facility_id", "facility_code", "site_id", "siteid", "pws_id_number"),
      sample_point_id = c("samplepointid", "sample_point_id", "monitoring_point", "station_id", "stationid"),
      latitude = c("latitude", "lat", "lat_measure", "latmeasure", "dec_lat", "y_coord"),
      longitude = c("longitude", "lon", "lng", "long_measure", "longmeasure", "dec_lon", "x_coord")
    )
    if (identical(trimws(input$external_dataset_type %||% ""), REFERENCE_MATERIAL_DATASET_TYPE)) {
      fields <- c(fields, REFERENCE_EXTRA_MAP_KEYS)
      labels <- c(labels, c(
        uncertainty = "uncertainty (expanded U)",
        reference_id = "reference_id / catalog (SRM/RM)"
      ))
      aliases <- c(aliases, list(
        uncertainty = c("uncertainty", "expanded_uncertainty", "u_expanded", "u", "u_exp", "expanded_u"),
        reference_id = c("reference_id", "reference_material", "srm_id", "document_id", "reference_source", "catalog_id")
      ))
    }
    guessed <- setNames(lapply(fields, function(k) choose_col(k, aliases[[k]] %||% k)), fields)
    # Schema-specific fallback for common GAMA/GM-style exports (case-insensitive).
    col_by_norm <- function(nm) {
      hit <- which(norm_name(cols) == norm_name(nm))
      if (length(hit) > 0) cols[[hit[[1]]]] else ""
    }
    if (!nzchar(guessed$analyte)) {
      x <- col_by_norm("gm_chemical_name")
      if (nzchar(x)) guessed$analyte <- x
    }
    if (!nzchar(guessed$result_value)) {
      x <- col_by_norm("gm_result")
      if (nzchar(x) && !isTRUE(is_bad_result_col(x))) guessed$result_value <- x
    }
    if (!nzchar(guessed$sample_id)) {
      x <- col_by_norm("gm_well_id")
      if (nzchar(x)) guessed$sample_id <- x
    }
    if (!nzchar(guessed$state)) {
      x <- col_by_norm("gm_state")
      if (!nzchar(x)) x <- col_by_norm("state")
      if (nzchar(x)) guessed$state <- x
    }
    if (!nzchar(guessed$unit)) {
      x <- col_by_norm("gm_result_unit")
      if (nzchar(x)) guessed$unit <- x
    }
    if (!nzchar(guessed$qualifier)) {
      x <- col_by_norm("gm_result_modifier")
      if (nzchar(x)) guessed$qualifier <- x
    }
    # If analyte column name isn't obvious, infer from PFAS-like values in character columns.
    if (!nzchar(guessed$analyte)) {
      char_cols <- cols[vapply(df, function(col) is.character(col) || is.factor(col), logical(1))]
      if (length(char_cols) > 0) {
        hit_counts <- vapply(char_cols, function(cn) sum(pfas_like(df[[cn]]), na.rm = TRUE), integer(1))
        if (length(hit_counts) > 0 && max(hit_counts, na.rm = TRUE) >= 2) {
          guessed$analyte <- char_cols[[which.max(hit_counts)]]
        }
      }
    }
    # If result column name isn't obvious, infer first numeric-like column not used as analyte.
    if (!nzchar(guessed$result_value)) {
      candidate_cols <- setdiff(cols, guessed$analyte)
      if (length(candidate_cols) > 0) {
        candidate_cols <- candidate_cols[!vapply(candidate_cols, is_bad_result_col, logical(1))]
        numeric_like <- vapply(candidate_cols, function(cn) sum(!is.na(parse_num(df[[cn]])), na.rm = TRUE), integer(1))
        if (length(numeric_like) > 0 && max(numeric_like, na.rm = TRUE) >= 1) {
          guessed$result_value <- candidate_cols[[which.max(numeric_like)]]
        } else {
          # Final fallback: choose column with highest count of numeric-like tokens.
          token_like <- vapply(candidate_cols, function(cn) {
            vals <- as.character(df[[cn]])
            sum(safe_detect(vals, "[-+]?[0-9]*\\.?[0-9]+"), na.rm = TRUE)
          }, integer(1))
          if (length(token_like) > 0 && max(token_like, na.rm = TRUE) >= 1) {
            guessed$result_value <- candidate_cols[[which.max(token_like)]]
          }
        }
      }
    }
    # Never auto-select identifier-like columns as result_value (e.g., PWSID may parse as numeric).
    if (nzchar(guessed$result_value %||% "") && isTRUE(is_identifier_like_result_col(guessed$result_value))) {
      guessed$result_value <- ""
    }
    tagList(
      tags$h4("Column mapping"),
      lapply(fields, function(k) {
        selected_now <- input[[paste0("map_", k)]] %||% ""
        # Auto-correct clearly wrong sticky mappings for key fields.
        if (identical(k, "result_value")) {
          if (nzchar(selected_now) && isTRUE(is_identifier_like_result_col(selected_now))) {
            selected_now <- ""
          }
          bad_result_pick <- safe_detect(
            tolower(selected_now),
            "modifier|qualifier|flag|vvl|tract|population|geoid|zip"
          )
          if (isTRUE(bad_result_pick)) selected_now <- ""
        }
        if (identical(k, "analyte")) {
          bad_analyte_pick <- safe_detect(
            tolower(selected_now),
            "modifier|qualifier|result|value|vvl|id|code|tract|population|geoid|zip"
          )
          if (isTRUE(bad_analyte_pick)) selected_now <- ""
        }
        if (identical(k, "sample_id")) {
          bad_sample_pick <- safe_detect(
            tolower(selected_now),
            "pesticide|contaminant|chemical|analyte|result|value|tract|population|geoid|zip"
          )
          if (isTRUE(bad_sample_pick)) selected_now <- ""
        }
        if (!nzchar(selected_now) || !(selected_now %in% cols)) {
          g <- guessed[[k]] %||% ""
          if (identical(k, "result_value")) {
            if (nzchar(g) && !isTRUE(is_identifier_like_result_col(g)) && !isTRUE(is_bad_result_col(g))) {
              selected_now <- g
            } else {
              selected_now <- ""
            }
          } else {
            selected_now <- g
          }
        }
        selectInput(paste0("map_", k), labels[[k]], choices = opts, selected = selected_now)
      })
    )
  })

  observeEvent(input$map_result_value, {
    rv <- trimws(as.character(input$map_result_value %||% ""))
    if (!nzchar(rv)) return(invisible(NULL))
    if (!isTRUE(is_identifier_like_result_col(rv))) return(invisible(NULL))
    updateSelectInput(session, "map_result_value", selected = "")
    showNotification(
      "result_value reset: that column is identifier-like (not a PFAS measurement). Pick a numeric result column.",
      type = "warning",
      duration = 8
    )
  }, ignoreNULL = TRUE)

  output$pfas_python_status <- renderPrint({
    py_exec_raw <- trimws(input$pfas_python_exec %||% "")
    if (!nzchar(py_exec_raw)) {
      cat("Python path is empty.\n")
      return(invisible(NULL))
    }
    py_exec <- resolve_python_exec(py_exec_raw)
    exists_exec <- nzchar(py_exec)
    cat("Configured path:", py_exec_raw, "\n")
    cat("Exists:", if (exists_exec) "yes" else "no", "\n")
    if (!exists_exec) {
      cat("Python is not available in this runtime.\n")
      cat("For hosted server: run step 9 (Train PFAS Exceedance Model) locally and redeploy results/ artifacts.\n")
      return(invisible(NULL))
    }
    ver <- tryCatch(
      system2(py_exec, args = "--version", stdout = TRUE, stderr = TRUE),
      error = function(e) {
        paste("ERROR:", conditionMessage(e))
      }
    )
    if (length(ver) > 0) cat(paste(ver, collapse = "\n"), "\n")
  })

  intake_api_health <- reactiveVal(check_intake_api_health(LINK_DATASET_FORM, PFAS_INTAKE_STAGING_TOKEN))

  output$intake_api_health_status <- renderPrint({
    h <- intake_api_health()
    cat("Status:", h$summary, "\n")
    cat("Endpoint:", h$endpoint, "\n")
    cat("Detail:", h$detail, "\n")
    cat("Smoke test:", h$smoke$summary, "\n")
    if (!is.null(h$smoke$http_status) && !is.na(h$smoke$http_status)) {
      cat("Smoke HTTP status:", h$smoke$http_status, "\n")
    }
    cat("Smoke detail:", h$smoke$detail, "\n")
    cat("Checked:", h$checked_at, "\n")
  })
  
  compound_choices <- reactive({
    df <- safe_table("compound_registry")
    if (nrow(df) == 0) return(setNames("", "No compounds yet"))
    setNames(df$compound_id, paste(df$compound_name, df$compound_id, sep = " | "))
  })
  
  sample_choices <- reactive({
    df <- safe_table("sample_registry")
    if (nrow(df) == 0) return(setNames("", "No samples yet"))
    setNames(df$sample_id, paste(df$sample_id, df$matrix, sep = " | "))
  })
  
  output$compound_select_ui <- renderUI({
    selectInput("measurement_compound_id", "Compound", choices = compound_choices())
  })
  
  output$sample_select_ui <- renderUI({
    selectInput("measurement_sample_id", "Sample", choices = sample_choices())
  })
  
  output$label_compound_select_ui <- renderUI({
    selectInput("label_compound_id", "Compound", choices = compound_choices())
  })
  
  observeEvent(input$save_compound, {
    req(input$compound_name, input$smiles, input$compound_created_by)
    
    existing <- safe_table("compound_registry")
    dup <- existing |>
      dplyr::filter(
        tolower(compound_name) == tolower(input$compound_name) |
          (!is.na(smiles) & smiles == input$smiles) |
          (!is.na(cas) & cas == input$cas & input$cas != "")
      )
    
    if (nrow(dup) > 0) {
      showNotification("Possible duplicate compound found. Review before saving.", type = "warning")
      return(NULL)
    }
    
    compound_id <- make_id("CMP")
    
    compound_row <- tibble::tibble(
      compound_id = compound_id,
      compound_name = input$compound_name,
      smiles = input$smiles,
      cas = input$cas,
      pfas_subclass = input$pfas_subclass,
      source_type = input$source_type,
      source_reference = input$source_reference,
      created_at = as.character(Sys.time()),
      created_by = input$compound_created_by,
      review_status = input$compound_review_status
    )
    
    DBI::dbWriteTable(con, "compound_registry", compound_row, append = TRUE)
    write_audit("compound", compound_id, "create", input$compound_created_by, "Compound saved")
    showNotification("Compound saved.", type = "message")
  })
  
  observeEvent(input$save_sample, {
    req(input$sample_id, input$matrix)
    
    existing <- safe_table("sample_registry")
    if (input$sample_id %in% existing$sample_id) {
      showNotification("Sample ID already exists.", type = "error")
      return(NULL)
    }
    
    sample_row <- tibble::tibble(
      sample_id = input$sample_id,
      project_id = input$project_id,
      client_id = input$client_id,
      matrix = input$matrix,
      sample_type = input$sample_type,
      collection_date = as.character(input$collection_date),
      batch_id = input$batch_id,
      instrument_id = input$instrument_id,
      method_id = input$method_id,
      operator = input$operator,
      notes = input$sample_notes
    )
    
    DBI::dbWriteTable(con, "sample_registry", sample_row, append = TRUE)
    write_audit("sample", input$sample_id, "create", input$operator %||% "unknown", "Sample saved")
    showNotification("Sample saved.", type = "message")
  })
  
  observeEvent(input$save_measurement, {
    req(input$measurement_compound_id, input$measurement_sample_id, input$measurement_created_by)
    
    measurement_id <- make_id("MSR")
    
    measurement_row <- tibble::tibble(
      measurement_id = measurement_id,
      compound_id = input$measurement_compound_id,
      sample_id = input$measurement_sample_id,
      retention_time = input$retention_time,
      precursor_mz = input$precursor_mz,
      product_mz = input$product_mz,
      peak_area = input$peak_area,
      signal_to_noise = input$signal_to_noise,
      concentration = input$concentration,
      concentration_unit = input$concentration_unit,
      lod = input$lod,
      loq = input$loq,
      internal_standard = input$internal_standard,
      result_flag = input$result_flag,
      qc_flag = input$qc_flag,
      created_at = as.character(Sys.time()),
      created_by = input$measurement_created_by
    )
    
    DBI::dbWriteTable(con, "analytical_measurements", measurement_row, append = TRUE)
    write_audit("measurement", measurement_id, "create", input$measurement_created_by, "Measurement saved")
    showNotification("Measurement saved.", type = "message")
  })
  
  observeEvent(input$save_label, {
    req(input$label_compound_id, input$endpoint, input$label_value, input$curator)
    
    existing <- safe_table("endpoint_labels")
    dup <- existing |>
      dplyr::filter(
        compound_id == input$label_compound_id,
        endpoint == input$endpoint
      )
    
    if (nrow(dup) > 0) {
      showNotification("A label for this compound + endpoint already exists.", type = "error")
      return(NULL)
    }
    
    label_id <- make_id("LBL")
    
    label_row <- tibble::tibble(
      label_id = label_id,
      compound_id = input$label_compound_id,
      endpoint = input$endpoint,
      label_value = as.integer(input$label_value),
      label_source = input$label_source,
      assay_id = input$assay_id,
      source_reference = input$label_reference,
      confidence_score = input$confidence_score,
      curator = input$curator,
      review_status = input$label_review_status,
      notes = input$label_notes,
      created_at = as.character(Sys.time())
    )
    
    DBI::dbWriteTable(con, "endpoint_labels", label_row, append = TRUE)
    write_audit("label", label_id, "create", input$curator, "Endpoint label saved")
    showNotification("Label saved.", type = "message")
  })
  
  recent_entries <- reactive({
    compounds_df <- safe_table("compound_registry") |> dplyr::mutate(entry_type = "compound")
    samples_df <- safe_table("sample_registry") |> dplyr::mutate(entry_type = "sample")
    labels_df <- safe_table("endpoint_labels") |> dplyr::mutate(entry_type = "label")
    measurements_df <- safe_table("analytical_measurements") |> dplyr::mutate(entry_type = "measurement")
    
    bind_rows(
      compounds_df |> dplyr::select(entry_type, created_at, dplyr::everything()),
      samples_df |> dplyr::mutate(created_at = collection_date) |> dplyr::select(entry_type, created_at, dplyr::everything()),
      labels_df |> dplyr::select(entry_type, created_at, dplyr::everything()),
      measurements_df |> dplyr::select(entry_type, created_at, dplyr::everything())
    ) |>
      dplyr::arrange(dplyr::desc(created_at))
  })
  
  ml_export <- reactive({
    compounds_df <- safe_table("compound_registry")
    labels_df <- safe_table("endpoint_labels")
    measurements_df <- safe_table("analytical_measurements")
    samples_df <- safe_table("sample_registry")
    
    if (nrow(compounds_df) == 0 || nrow(labels_df) == 0) return(tibble::tibble())
    
    labels_df <- labels_df |>
      dplyr::filter(review_status == "approved")
    
    compounds_df <- compounds_df |>
      dplyr::filter(review_status == "approved")
    
    labels_df |>
      dplyr::inner_join(compounds_df, by = "compound_id") |>
      dplyr::left_join(measurements_df, by = "compound_id") |>
      dplyr::left_join(samples_df, by = "sample_id") |>
      dplyr::select(
        compound_id, compound_name, smiles, cas, pfas_subclass,
        matrix, sample_type, retention_time, precursor_mz, product_mz,
        peak_area, signal_to_noise, concentration, concentration_unit,
        lod, loq, internal_standard,
        endpoint, label_value, label_source, confidence_score,
        review_status, source_type, source_reference
      )
  })

  ucmr533_preview_df <- eventReactive(input$ucmr533_load_btn, {
    ov <- tryCatch(trimws(input$ucmr533_path_override %||% ""), error = function(e) "")
    p <- if (nzchar(ov)) ov else resolve_ucmr5_533_txt(PROJECT_DIR)
    if (length(p) != 1L || is.na(p) || !nzchar(p) || !file.exists(p)) {
      showNotification(
        paste(
          "UCMR5_533.txt not found. Use path override, Sys.setenv(\"UCMR5_533_TXT\"),",
          "options(pfas.ucmr5_533_path), or copy to data/external/epa_ucmr5/UCMR5_533.txt."
        ),
        type = "error"
      )
      return(NULL)
    }
    ncap <- suppressWarnings(as.integer(input$ucmr533_preview_rows))
    if (is.na(ncap) || ncap < 100L) {
      ncap <- 5000L
    }
    ncap <- min(50000L, max(100L, ncap))
    tryCatch(
      {
        read.delim(
          p,
          sep = "\t",
          quote = "",
          fill = TRUE,
          stringsAsFactors = FALSE,
          fileEncoding = "latin1",
          nrows = ncap
        )
      },
      error = function(e) {
        showNotification(conditionMessage(e), type = "error")
        NULL
      }
    )
  })

  output$ucmr533_resolve_status <- renderPrint({
    if (is.null(input$ucmr533_load_btn) || input$ucmr533_load_btn < 1L) {
      cat(
        "Set optional path or rely on UCMR5_533_TXT / options(pfas.ucmr5_533_path) / ",
        "data/external/epa_ucmr5/UCMR5_533.txt, then click Load preview.\n"
      )
      return(invisible(NULL))
    }
    d <- ucmr533_preview_df()
    ov <- tryCatch(trimws(input$ucmr533_path_override %||% ""), error = function(e) "")
    p <- if (nzchar(ov)) ov else resolve_ucmr5_533_txt(PROJECT_DIR)
    if (length(p) != 1L || is.na(p) || !nzchar(p)) {
      cat("No file resolved.\n")
      return(invisible(NULL))
    }
    if (!file.exists(p)) {
      cat("Path not found:", p, "\n")
      return(invisible(NULL))
    }
    cat("Source:", normalizePath(p, winslash = "/", mustWork = TRUE), "\n")
    if (!is.null(d)) {
      cat("Loaded preview:", nrow(d), "rows x", ncol(d), "columns\n")
    }
  })

  output$ucmr533_preview_tbl <- renderDT({
    if (is.null(input$ucmr533_load_btn) || input$ucmr533_load_btn < 1L) {
      return(
        datatable(
          data.frame(Note = "Click Load preview after configuring path (optional)."),
          rownames = FALSE,
          options = list(dom = "t", ordering = FALSE),
          selection = "none"
        )
      )
    }
    d <- ucmr533_preview_df()
    if (is.null(d)) {
      return(
        datatable(
          data.frame(Message = "Load failed or no data."),
          rownames = FALSE,
          options = list(dom = "t", ordering = FALSE),
          selection = "none"
        )
      )
    }
    datatable(d, options = list(scrollX = TRUE, pageLength = 15), rownames = FALSE)
  })

  ucmr_pipeline_priority_df <- eventReactive(input$ucmr_pipeline_load_btn, {
    rid <- tryCatch(trimws(input$ucmr_pipeline_run_id %||% ""), error = function(e) "")
    if (!nzchar(rid)) {
      showNotification("Enter a run ID (for example test_ucmr5_533).", type = "error")
      return(NULL)
    }
    root <- tryCatch(trimws(input$ucmr_pipeline_output_root %||% "runs"), error = function(e) "runs")
    if (!nzchar(root)) {
      root <- "runs"
    }
    p <- ucmr_pipeline_priority_csv(PROJECT_DIR, root, rid)
    if (is.na(p) || !nzchar(p) || !file.exists(p)) {
      showNotification(paste0("priority_report.csv not found at:\n", p), type = "error")
      return(NULL)
    }
    ncap <- suppressWarnings(as.integer(input$ucmr_pipeline_preview_rows))
    if (is.na(ncap) || ncap < 100L) {
      ncap <- 5000L
    }
    ncap <- min(50000L, max(100L, ncap))
    tryCatch(
      {
        read.csv(p, nrows = ncap, stringsAsFactors = FALSE, check.names = FALSE, fileEncoding = "UTF-8")
      },
      error = function(e) {
        showNotification(conditionMessage(e), type = "error")
        NULL
      }
    )
  })

  output$ucmr_pipeline_status <- renderPrint({
    if (is.null(input$ucmr_pipeline_load_btn) || input$ucmr_pipeline_load_btn < 1L) {
      cat(
        "Run: python pipeline/process_ucmr5.py <UCMR5.txt> --run-id YOUR_ID\n",
        "Then enter the same YOUR_ID above and click Load priority report.\n"
      )
      return(invisible(NULL))
    }
    rid <- tryCatch(trimws(input$ucmr_pipeline_run_id %||% ""), error = function(e) "")
    root <- tryCatch(trimws(input$ucmr_pipeline_output_root %||% "runs"), error = function(e) "runs")
    p <- ucmr_pipeline_priority_csv(PROJECT_DIR, root, rid)
    cat("Expected file:", p, "\n")
    cat("Exists:", isTRUE(length(p) == 1L && nzchar(p) && file.exists(p)), "\n")
    d <- ucmr_pipeline_priority_df()
    if (!is.null(d)) {
      cat("Loaded preview:", nrow(d), "rows x", ncol(d), "columns\n")
    }
  })

  output$ucmr_pipeline_priority_tbl <- renderDT({
    if (is.null(input$ucmr_pipeline_load_btn) || input$ucmr_pipeline_load_btn < 1L) {
      return(
        datatable(
          data.frame(Note = "Enter run ID and click Load priority report."),
          rownames = FALSE,
          options = list(dom = "t", ordering = FALSE),
          selection = "none"
        )
      )
    }
    d <- ucmr_pipeline_priority_df()
    if (is.null(d)) {
      return(
        datatable(
          data.frame(Message = "Load failed or file missing."),
          rownames = FALSE,
          options = list(dom = "t", ordering = FALSE),
          selection = "none"
        )
      )
    }
    datatable(d, options = list(scrollX = TRUE, pageLength = 15), rownames = FALSE)
  })

  output$tbl_system_readiness <- renderDT(render_dt(system_readiness, 10))
  output$tbl_oecd_home <- renderDT(render_dt(oecd_checklist, 5))
  output$tbl_dataset_registry <- renderDT(render_dt(dataset_registry, 8))
  output$tbl_endpoint_definitions <- renderDT(render_dt(endpoint_definitions, 6))
  output$tbl_proxy_assays <- renderDT(render_dt(proxy_assay_table, 6))
  output$tbl_descriptor_schema <- renderDT(render_dt(descriptor_schema, 10))
  output$tbl_fingerprint_schema <- renderDT(render_dt(fingerprint_schema, 5))
  output$tbl_structural_alerts <- renderDT(render_dt(structural_alert_table, 8))
  output$tbl_compounds <- renderDT(render_dt(compounds, 8))
  output$tbl_model_registry <- renderDT(render_dt(model_registry, 8))
  output$tbl_baseline_comparison <- renderDT(render_dt(baseline_comparison, 8))
  output$tbl_hyperparameters <- renderDT(render_dt(hyperparameter_summary, 10))
  output$tbl_validation_summary <- renderDT(render_dt(validation_summary, 8))
  output$tbl_error_buckets <- renderDT(render_dt(error_buckets, 8))
  output$tbl_performance_metrics <- renderDT(render_dt(performance_metrics, 8))
  output$tbl_predictions <- renderDT(render_dt(predictions, 10))

  # Enterprise 5.0 — cloud screening API (FastAPI /predict; see PFAS_API_URL)
  e5_api_last <- reactiveVal(NULL)
  observeEvent(input$e5_run, {
    req(auth$user)
    api_base <- trimws(Sys.getenv("PFAS_API_URL", PFAS_API_URL))
    api_base <- sub("/+$", "", api_base)
    payload <- list(
      sample_id = input$e5_sample_id,
      dtxsid = input$e5_dtxsid,
      method_id = input$e5_method_id,
      matrix = input$e5_matrix
    )
    res <- tryCatch(
      httr::POST(
        paste0(api_base, "/predict"),
        body = payload,
        encode = "json",
        httr::content_type_json(),
        httr::timeout(45)
      ),
      error = function(e) {
        list(error = TRUE, message = conditionMessage(e))
      }
    )
    if (isTRUE(res$error)) {
      e5_api_last(list(status = 0L, text = "", err = res$message, parsed = NULL))
      showNotification(res$message, type = "error")
      return(invisible(NULL))
    }
    sc <- httr::status_code(res)
    txt <- tryCatch(httr::content(res, "text", encoding = "UTF-8"), error = function(e) "")
    parsed <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)
    e5_api_last(list(status = sc, text = txt, err = NULL, parsed = parsed))
    if (sc < 400) {
      write_audit(
        "cloud_api_predict",
        as.character(input$e5_sample_id %||% "unknown"),
        "screening_request",
        op_id(),
        paste0("Enterprise 5.0 POST /predict (", api_base, ")"),
        details = list(
          dtxsid = input$e5_dtxsid,
          method_id = input$e5_method_id,
          matrix = input$e5_matrix,
          run_id = if (!is.null(parsed)) parsed$run_id else NA_character_
        )
      )
    } else {
      showNotification(paste0("API HTTP ", sc), type = "warning")
    }
  }, ignoreInit = TRUE)

  output$e5_result <- renderPrint({
    r <- e5_api_last()
    req(r)
    if (!is.null(r$err)) {
      cat("Request failed: ", r$err, "\n", sep = "")
      return(invisible(NULL))
    }
    if (r$status >= 400) {
      cat("HTTP ", r$status, "\n", r$text, "\n", sep = "")
      return(invisible(NULL))
    }
    p <- r$parsed
    if (is.null(p)) {
      cat(r$text)
      return(invisible(NULL))
    }
    keep <- c("run_id", "prediction", "confidence", "ad_warning", "intended_use")
    show <- p[intersect(keep, names(p))]
    print(show)
  })

  output$e5_sustainability <- renderPrint({
    r <- e5_api_last()
    req(r)
    p <- r$parsed
    if (is.null(p)) {
      cat("(no parsed response)\n")
      return(invisible(NULL))
    }
    if (!is.null(p$sustainability)) {
      print(p$sustainability)
    } else {
      cat("(no sustainability block)\n")
    }
  })

  output$e5_raw <- renderPrint({
    r <- e5_api_last()
    req(r)
    if (nzchar(r$text %||% "")) {
      cat(r$text)
    } else if (!is.null(r$err)) {
      cat(r$err)
    } else {
      cat("(empty)\n")
    }
  })

  output$tbl_ad_registry <- renderDT(render_dt(ad_registry, 8))
  output$tbl_ad_summary <- renderDT(render_dt(compound_ad_summary, 10))
  output$tbl_analog_support <- renderDT(render_dt(analog_support, 8))
  output$tbl_mechanistic_rationale <- renderDT(render_dt(mechanistic_rationale, 8))
  output$tbl_woe <- renderDT(render_dt(weight_of_evidence, 10))
  output$tbl_oecd_checklist <- renderDT(render_dt(oecd_checklist, 8))
  output$tbl_model_cards <- renderDT(render_dt(model_cards, 8))
  output$pfas_metrics_status <- renderPrint({
    pfas_results_nonce()
    rp <- pfas_resolve_train_metrics_paths()
    if (nzchar(rp$banner %||% "")) {
      cat(rp$banner, "\n\n")
    }
    subdir_arg <- if (nzchar(rp$subdir %||% "")) rp$subdir else NULL
    m <- read_results_json("nhanes_model_metrics.json", results_subdir = subdir_arg)
    task_counts <- read_training_csv("model_matrix_task_counts.csv")

    matrix_n_train <- NA_integer_
    matrix_n_test <- NA_integer_
    if (!is.null(task_counts) && nrow(task_counts) > 0) {
      matrix_n_train <- as.integer(sum(suppressWarnings(as.numeric(task_counts$rows_train)), na.rm = TRUE))
      matrix_n_test <- as.integer(sum(suppressWarnings(as.numeric(task_counts$rows_test)), na.rm = TRUE))
    }

    metrics_n_train <- if (!is.null(m) && !is.null(m$n_train)) {
      suppressWarnings(as.integer(m$n_train))
    } else {
      NA_integer_
    }
    metrics_n_test <- if (!is.null(m) && !is.null(m$n_test)) {
      suppressWarnings(as.integer(m$n_test))
    } else {
      NA_integer_
    }

    # Prefer counts from nhanes_model_metrics.json — they match accuracy/AUC/confusion_matrix_0_1.
    # Summed model_matrix_task_counts.csv can reflect a broader multi-task matrix than the sklearn hold-out slice.
    show_n_train <- if (!is.na(metrics_n_train)) metrics_n_train else matrix_n_train
    show_n_test <- if (!is.na(metrics_n_test)) metrics_n_test else matrix_n_test

    if (!is.na(show_n_train)) cat("n_train:", show_n_train, "\n")
    if (!is.na(show_n_test)) cat("n_test :", show_n_test, "\n")
    if (
      !is.na(metrics_n_train) && !is.na(matrix_n_train) &&
        (!is.na(matrix_n_test) && !is.na(metrics_n_test)) &&
        (metrics_n_train != matrix_n_train || metrics_n_test != matrix_n_test)
    ) {
      cat(
        "Note: model_matrix_task_counts.csv totals (train:",
        matrix_n_train,
        ", test:",
        matrix_n_test,
        ") differ from the evaluation split above.\n"
      )
    }

    if (is.null(m) && is.na(matrix_n_train) && is.na(matrix_n_test)) {
      cat("No PFAS exceedance model metrics found in results/ or results/screening/.\n")
      cat("Run: 9) Train (Evidence-Governed) or Screening — Train (Exploratory); python scripts/train_pfas_model.py\n")
      return(invisible(NULL))
    }

    if (!is.null(m)) {
      if (is.null(m$group_split_enabled)) {
        cat("WARNING: Legacy metrics artifact detected (no anti-leakage metadata).\n")
        cat("Re-run: 9) Train PFAS Exceedance Model to generate group-split validated metrics.\n\n")
      }
      # Accuracy/AUC are produced by Python metrics; keep showing them when available.
      if (!is.null(m$accuracy)) cat("accuracy:", round(as.numeric(m$accuracy), 4), "\n")
      if (!is.null(m$auc)) cat("auc     :", round(as.numeric(m$auc), 4), "\n")
      if (!is.null(m$group_split_enabled)) cat("group_split_enabled:", as.logical(m$group_split_enabled), "\n")
      if (!is.null(m$group_overlap_count)) cat("group_overlap_count :", as.integer(m$group_overlap_count), "\n")
      if (!is.null(m$min_recall_positive_cli) && is.finite(suppressWarnings(as.numeric(m$min_recall_positive_cli)))) {
        cat("min_recall_positive (CLI):", m$min_recall_positive_cli, "\n")
      }
      cat_iso_holdout_metrics(m$iso_holdout_metrics, n_test_align = m$n_test)
      sint <- trimws(as.character(m$screening_interpretation %||% ""))
      if (nzchar(sint)) {
        cat("\nInterpretation: ", sint, "\n", sep = "")
      }
      print_holdout_probability_debug(m$holdout_probability_debug)
      if (!is.null(m$leakage_warnings) && length(m$leakage_warnings) > 0) {
        cat("leakage_warnings:\n")
        for (w in m$leakage_warnings) cat(" -", as.character(w), "\n")
      }
      if (!is.null(m$auc_note)) cat("note    :", m$auc_note, "\n")
      if (!is.null(m$confusion_matrix_0_1)) {
        cat("\nconfusion_matrix_0_1:\n")
        print(m$confusion_matrix_0_1)
      }
    }

    metrics_path <- if (nzchar(rp$subdir %||% "")) {
      file.path(PROJECT_DIR, "results", rp$subdir, "nhanes_model_metrics.json")
    } else {
      file.path(PROJECT_DIR, "results", "nhanes_model_metrics.json")
    }
    matrix_counts_path <- file.path(PROJECT_DIR, "data", "training", "model_matrix_task_counts.csv")
    if (file.exists(matrix_counts_path) && file.exists(metrics_path)) {
      mt_metrics <- file.info(metrics_path)$mtime
      mt_matrix <- file.info(matrix_counts_path)$mtime
      if (is.finite(as.numeric(mt_metrics)) && is.finite(as.numeric(mt_matrix)) && mt_matrix > mt_metrics) {
        cat("\nNote: matrix counts are newer than Python metrics.\n")
      }
    }
  })

  output$pfas_label_integrity_banner <- renderUI({
    pfas_results_nonce()
    rep <- read_label_integrity_report_payload()
    show_big <- isTRUE(rep$show_prominent_operator_warning)
    txt <- trimws(rep$prominent_operator_warning %||% "")
    if (!nzchar(txt)) {
      txt <- paste0(
        "Label integrity warning: This model used incomplete or placeholder PFAS limit data. ",
        "Predictions are suitable only for screening/development, not compliance or ISO 17025 decision-making."
      )
    }
    if (show_big) {
      tags$div(class = "alert alert-warning", style = "font-weight:600;", txt)
    } else if (!is.null(rep) && length(rep$warnings %||% character(0)) > 0L) {
      tags$div(
        class = "alert alert-info",
        "Review ",
        tags$code("results/label_integrity_report.json"),
        " — advisory warnings were emitted during training."
      )
    } else {
      invisible(NULL)
    }
  })

  output$pfas_label_integrity_summary <- renderPrint({
    pfas_results_nonce()
    a <- read_label_derivation_audit_payload()
    st <- reconciliation_dataset_builder_stages()
    dropped <- NA_real_
    if (!is.null(st) && !is.null(st$rows_dropped_no_usable_limit_or_result)) {
      dropped <- suppressWarnings(as.numeric(st$rows_dropped_no_usable_limit_or_result[[1]]))
    }
    if (is.null(a)) {
      cat("No results/label_derivation_audit.json yet.\n")
      cat("Run step 9 (Train PFAS Exceedance Model); requires train script v3.2.4+.\n")
      return(invisible(NULL))
    }
    cat("Train script (audit): ", a$train_script_version %||% "?", "\n", sep = "")
    cat("missing_limit_after_join:", a$missing_limit_after_join %||% NA, "\n")
    if (is.finite(dropped)) {
      cat("rows_dropped_no_usable_limit_or_result:", dropped, "\n")
    } else {
      cat("rows_dropped_no_usable_limit_or_result: (open python_training_row_reconciliation.json)\n")
    }
    pr <- suppressWarnings(as.numeric(a$positive_rate_after_derive))
    cat("positive_rate_after_derive:", if (is.finite(pr)) format(pr, digits = 10) else "NA", "\n")
    ta <- a$top_analytes_missing_limit_among_rows_with_result
    cat("\nTop analytes missing limit (first 15 of audit histogram):\n")
    if (is.null(ta) || length(ta) == 0L) {
      cat(" — none —\n")
    } else {
      nm <- names(ta)
      vv <- unlist(ta, use.names = FALSE)
      n_show <- min(15L, length(vv))
      if (length(nm) != length(vv)) {
        cat(" — (malformed histogram in JSON) —\n")
      } else {
        for (i in seq_len(n_show)) {
          cat(sprintf("  %s : %s\n", nm[[i]], as.character(vv[[i]])))
        }
        if (length(vv) > n_show) {
          cat(sprintf(" ... %d more rows in JSON\n", length(vv) - n_show))
        }
      }
    }
    cat(
      "\nIf missing limits or drops are large relative to ingest, labels may not reflect real regulatory comparisons.\n",
      "Do not treat placeholder limits in data/config/pfas_regulatory_limits.csv as compliance MCLs.\n"
    )
  })

  output$tbl_pfas_label_integrity_missing <- renderDT({
    pfas_results_nonce()
    a <- read_label_derivation_audit_payload()
    ta <- if (!is.null(a)) a$top_analytes_missing_limit_among_rows_with_result else NULL
    if (is.null(ta) || length(ta) == 0L) {
      return(DT::datatable(tibble::tibble(note = "No histogram in label_derivation_audit.json yet."), rownames = FALSE))
    }
    nm <- names(ta)
    vv <- suppressWarnings(as.integer(unlist(ta, use.names = FALSE)))
    df <- tibble::tibble(normalized_analyte = nm, rows_missing_limit = vv)
    df <- df[order(-df$rows_missing_limit), , drop = FALSE]
    DT::datatable(df, rownames = FALSE, options = list(pageLength = 15L, scrollX = TRUE))
  })

  render_task_metrics <- function(task_key) {
    pfas_results_nonce()
    rp <- pfas_resolve_train_metrics_paths()
    if (nzchar(rp$banner %||% "")) {
      cat(rp$banner, "\n\n")
    }
    subdir_arg <- if (nzchar(rp$subdir %||% "")) rp$subdir else NULL
    m <- read_results_json("nhanes_model_metrics_by_task.json", results_subdir = subdir_arg)
    if (is.null(m) || is.null(m[[task_key]])) {
      cat("No metrics yet.\nRun: 9) Train PFAS Exceedance Model\n")
      return(invisible(NULL))
    }
    t <- m[[task_key]]
    if (!is.null(t$n_train)) cat("n_train:", t$n_train, "\n")
    if (!is.null(t$n_test)) cat("n_test :", t$n_test, "\n")
    if (!is.null(t$accuracy)) cat("accuracy:", round(as.numeric(t$accuracy), 4), "\n")
    if (!is.null(t$auc)) cat("auc     :", round(as.numeric(t$auc), 4), "\n")
    if (!is.null(t$auc_note)) cat("note    :", t$auc_note, "\n")
    cat_iso_holdout_metrics(t$iso_holdout_metrics, n_test_align = t$n_test)
    sint_t <- trimws(as.character(t$screening_interpretation %||% ""))
    if (nzchar(sint_t)) {
      cat("\nInterpretation: ", sint_t, "\n", sep = "")
    }
  }

  output$pfas_task_human_status <- renderPrint({
    render_task_metrics("task_human_health")
  })
  output$pfas_task_environment_status <- renderPrint({
    render_task_metrics("task_environmental_occurrence")
  })
  output$pfas_task_facility_status <- renderPrint({
    render_task_metrics("task_facility_risk_enrichment")
  })
  output$tbl_pfas_task_comparison <- renderDT({
    pfas_results_nonce()
    rp <- pfas_resolve_train_metrics_paths()
    subdir_arg <- if (nzchar(rp$subdir %||% "")) rp$subdir else NULL
    m <- read_results_json("nhanes_model_metrics_by_task.json", results_subdir = subdir_arg)
    if (is.null(m) || length(m) == 0) {
      return(DT::datatable(
        tibble::tibble(note = "No per-task metrics found. Run: 9) Train PFAS Exceedance Model"),
        rownames = FALSE
      ))
    }

    task_keys <- names(m)
    labels <- c(
      task_human_health = "Human Health",
      task_environmental_occurrence = "Environmental Occurrence",
      task_facility_risk_enrichment = "Facility Risk Enrichment"
    )
    rows <- lapply(task_keys, function(k) {
      x <- m[[k]]
      im <- x$iso_holdout_metrics
      rec1 <- NA_real_
      prec1 <- NA_real_
      f10k <- NA_real_
      if (is.list(im) && is.null(im$error)) {
        rv <- suppressWarnings(as.numeric(unlist(im$recall_positive, use.names = FALSE)))
        if (length(rv) >= 1L && is.finite(rv[[1]])) rec1 <- round(rv[[1]], 4)
        pv <- suppressWarnings(as.numeric(unlist(im$precision_positive, use.names = FALSE)))
        if (length(pv) >= 1L && is.finite(pv[[1]])) prec1 <- round(pv[[1]], 4)
        fv <- suppressWarnings(as.numeric(unlist(im$flags_per_10k_holdout, use.names = FALSE)))
        if (length(fv) >= 1L && is.finite(fv[[1]])) {
          f10k <- round(fv[[1]], 2)
        } else {
          tpv <- suppressWarnings(as.numeric(unlist(im$tp, use.names = FALSE)))
          fpv <- suppressWarnings(as.numeric(unlist(im$fp, use.names = FALSE)))
          csv <- suppressWarnings(as.numeric(unlist(im$cm_sum, use.names = FALSE)))
          if (length(tpv) >= 1L && length(fpv) >= 1L && length(csv) >= 1L) {
            pred_pos <- as.integer(round(tpv[[1]]) + round(fpv[[1]]))
            cs <- as.integer(round(csv[[1]]))
            if (!is.na(cs) && cs > 0L && !is.na(pred_pos)) {
              f10k <- round(pred_pos / cs * 10000, 2)
            }
          }
        }
      }
      tibble::tibble(
        task = unname(labels[k] %||% k),
        auc = (if (!is.null(x$auc)) round(as.numeric(x$auc), 4) else NA_real_),
        accuracy = (if (!is.null(x$accuracy)) round(as.numeric(x$accuracy), 4) else NA_real_),
        recall_pos = rec1,
        precision_pos = prec1,
        flags_per_10k_holdout = f10k,
        n_train = (if (!is.null(x$n_train)) as.integer(x$n_train) else NA_integer_),
        n_test = (if (!is.null(x$n_test)) as.integer(x$n_test) else NA_integer_)
      )
    })
    df <- dplyr::bind_rows(rows)
    render_dt(df, 10)
  })
  output$pfas_target_status <- renderPrint({
    pfas_results_nonce()
    p <- read_training_json("pfas_training_target_progress.json")
    if (is.null(p)) {
      cat("No target progress file found.\nRun: 3) Build multi-source training table\n")
      return(invisible(NULL))
    }
    fmt_int <- function(x) {
      xv <- suppressWarnings(as.numeric(x))
      if (!is.finite(xv)) return(as.character(x))
      format(xv, big.mark = ",", scientific = FALSE, trim = TRUE)
    }
    fmt_pct <- function(x) {
      xv <- suppressWarnings(as.numeric(x))
      if (!is.finite(xv)) return(as.character(x))
      digits <- if (xv < 1) 6 else 2
      paste0(formatC(xv, format = "f", digits = digits), "%")
    }
    if (!is.null(p$current_rows) && !is.null(p$target_rows)) {
      cat("Rows:", fmt_int(p$current_rows), "/", fmt_int(p$target_rows), "\n")
    }
    if (!is.null(p$pct_of_target_raw)) {
      cat("Percent:", fmt_pct(p$pct_of_target_raw), "\n")
    } else if (!is.null(p$pct_of_target)) {
      cat("Percent:", fmt_pct(p$pct_of_target), "\n")
    }
    if (!is.null(p$rows_remaining)) cat("Rows remaining:", fmt_int(p$rows_remaining), "\n")
    if (!is.null(p$rows_above_target) && isTRUE(as.numeric(p$rows_above_target) > 0)) {
      cat("Rows above target:", fmt_int(p$rows_above_target), "\n")
    }
    if (!is.null(p$generated_at_utc)) cat("Generated at (UTC):", p$generated_at_utc, "\n")
  })
  output$pfas_last_training_status <- renderPrint({
    pfas_results_nonce()
    res_root <- file.path(PROJECT_DIR, "results")
    res_screen <- file.path(PROJECT_DIR, "results", "screening")
    dirs <- unique(c(res_root, res_screen)[dir.exists(c(res_root, res_screen))])
    if (length(dirs) == 0L) {
      cat("No results directory found.\n")
      return(invisible(NULL))
    }

    primary <- c(
      "nhanes_model_metrics.json",
      "nhanes_model_metrics_by_task.json",
      "nhanes_feature_importance.csv",
      "nhanes_test_predictions.csv"
    )
    primary_paths <- unlist(lapply(dirs, function(d) file.path(d, primary)), use.names = FALSE)
    existing_primary <- primary_paths[file.exists(primary_paths)]

    task_metric_files <- unlist(
      lapply(dirs, function(d) {
        if (!dir.exists(d)) {
          return(character(0))
        }
        list.files(d, pattern = "^nhanes_model_metrics_task_.*\\.json$", full.names = TRUE)
      }),
      use.names = FALSE
    )

    all_files <- c(existing_primary, task_metric_files)
    if (length(all_files) == 0) {
      cat("No Python train metric files yet under results/ or results/screening/\n")
      cat("(expected: nhanes_model_metrics.json, nhanes_model_metrics_by_task.json, feature importance, test predictions).\n")
      mc <- file.path(PROJECT_DIR, "data", "training", "model_matrix_task_counts.csv")
      if (file.exists(mc)) {
        cat(
          "\nNote: model_matrix_task_counts.csv exists. The ML summary above may show n_train/n_test ",
          "from that matrix file even though Python metrics artifacts have not been written.\n",
          sep = ""
        )
      }
      cat("\nRun step 9 (Evidence-Governed) or Screening — Train (Exploratory) to emit metrics JSON/CSV.\n")
      return(invisible(NULL))
    }

    fi <- file.info(all_files)
    mt <- fi$mtime
    idx <- which.max(mt)
    newest <- all_files[[idx]]
    newest_time <- mt[[idx]]
    age_mins <- as.numeric(difftime(Sys.time(), newest_time, units = "mins"))
    freshness <- if (is.finite(age_mins) && age_mins <= 60) {
      "fresh (<= 60 min)"
    } else if (is.finite(age_mins) && age_mins <= 24 * 60) {
      "recent (<= 24 h)"
    } else {
      "stale (> 24 h)"
    }

    cat("Newest artifact:", basename(newest), "\n")
    cat("Modified (local server time):", format(newest_time, "%Y-%m-%d %H:%M:%S"), "\n")
    cat("Age (minutes):", round(age_mins, 1), "\n")
    cat("Freshness:", freshness, "\n")
    cat("Artifacts detected:", length(all_files), "\n")
  })
  output$tbl_task_row_availability <- renderDT({
    pfas_results_nonce()
    p <- file.path(PROJECT_DIR, "data", "training", "model_matrix_task_counts.csv")
    if (!file.exists(p)) {
      return(DT::datatable(
        tibble::tibble(note = "No task count file yet. Run: 7) Build model matrix"),
        rownames = FALSE
      ))
    }
    df <- tryCatch(read.csv(p, stringsAsFactors = FALSE, check.names = FALSE), error = function(e) NULL)
    if (is.null(df) || nrow(df) == 0) {
      return(DT::datatable(
        tibble::tibble(note = "Task count file is empty. Check upstream source data."),
        rownames = FALSE
      ))
    }
    if (!("task_type" %in% names(df))) {
      return(render_dt(df, 10))
    }
    labels <- c(
      task_human_health = "Human Health",
      task_environmental_occurrence = "Environmental Occurrence",
      task_facility_risk_enrichment = "Facility Risk Enrichment"
    )
    df$task <- ifelse(is.na(labels[df$task_type]), df$task_type, unname(labels[df$task_type]))
    keep <- intersect(c("task", "task_type", "rows_input", "rows_train", "rows_test"), names(df))
    render_dt(df[, keep, drop = FALSE], 10)
  })
  output$tbl_pfas_feature_importance <- renderDT({
    pfas_results_nonce()
    rp <- pfas_resolve_train_metrics_paths()
    subdir_arg <- if (nzchar(rp$subdir %||% "")) rp$subdir else NULL
    df <- read_results_csv("nhanes_feature_importance.csv", results_subdir = subdir_arg)
    if (is.null(df) || nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "Run python scripts/train_pfas_model.py to generate feature importance."), rownames = FALSE))
    }
    if ("feature" %in% names(df)) {
      leak_hits <- safe_detect(
        tolower(as.character(df$feature)),
        "result_value|log_result|analyticalresult|resultngl|resultclean"
      )
      if (any(leak_hits, na.rm = TRUE)) {
        return(DT::datatable(
          tibble::tibble(
            note = "Detected stale leakage-style feature artifacts (result_value/log_result_value). Re-run 9) Train PFAS Exceedance Model after app restart."
          ),
          rownames = FALSE
        ))
      }
    }
    render_dt(df, 10)
  })
  output$tbl_pfas_test_predictions <- renderDT({
    pfas_results_nonce()
    rp <- pfas_resolve_train_metrics_paths()
    subdir_arg <- if (nzchar(rp$subdir %||% "")) rp$subdir else NULL
    df <- read_results_csv("nhanes_test_predictions.csv", results_subdir = subdir_arg)
    if (is.null(df) || nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "Run python scripts/train_pfas_model.py to generate test predictions."), rownames = FALSE))
    }
    render_dt(df, 10)
  })

  get_upload_mapping <- reactive({
    keys <- CORE_EXTERNAL_MAP_KEYS
    if (identical(trimws(input$external_dataset_type %||% ""), REFERENCE_MATERIAL_DATASET_TYPE)) {
      keys <- c(keys, REFERENCE_EXTRA_MAP_KEYS)
    }
    vals <- lapply(keys, function(k) input[[paste0("map_", k)]] %||% "")
    names(vals) <- keys
    # Guard against sticky bad picks in UI state.
    if (nzchar(vals$result_value %||% "")) {
      rv <- tolower(trimws(as.character(vals$result_value)))
      if (is_identifier_like_result_col(rv) ||
          safe_detect(rv, "modifier|qualifier|flag|vvl|tract|population|geoid|zip|pesticide|chemical|contaminant|name")) {
        vals$result_value <- ""
      }
    }
    if (nzchar(vals$analyte %||% "")) {
      av <- tolower(vals$analyte)
      if (safe_detect(av, "modifier|qualifier|result|value|vvl|tract|population|geoid|zip")) {
        vals$analyte <- ""
      }
    }
    if (nzchar(vals$sample_id %||% "")) {
      sv <- tolower(vals$sample_id)
      if (safe_detect(sv, "pesticide|contaminant|chemical|analyte|result|value|tract|population|geoid|zip")) {
        vals$sample_id <- ""
      }
    }

    # Backend auto-detect fallback (independent of UI state), case-insensitive.
    df <- external_upload_raw()
    # --- Semantic-type-aware mapping enforcement -----------------------
    # When the upload is governance/program metadata (e.g. ICIS-AIR), the
    # PFAS occurrence mapper must NOT auto-populate fields like result_value,
    # state, unit, etc. We force them blank here regardless of any auto-detect
    # results, regardless of any sticky UI picks, and regardless of dataset_type
    # the user selected. The downstream button handlers refuse separately.
    if (isTRUE(upload_is_metadata_lane())) {
      for (k in PFAS_OCCURRENCE_MAP_FIELDS) {
        if (k %in% names(vals)) vals[[k]] <- ""
      }
      return(vals)
    }
    if (!is.null(df) && is.data.frame(df) && ncol(df) > 0) {
      cn <- names(df)
      norm <- function(x) tolower(gsub("[^a-z0-9]+", "", trimws(as.character(x))))
      cn_norm <- norm(cn)
      parse_num <- function(x) {
        y <- trimws(as.character(x))
        y[y %in% c("", "NA", "N/A", "na", "n/a", "NULL", "null")] <- NA_character_
        y <- gsub(",", "", y, fixed = TRUE)
        y <- gsub("^<\\s*", "", y)
        y <- gsub("^>\\s*", "", y)
        direct <- suppressWarnings(as.numeric(y))
        need_extract <- is.na(direct) & !is.na(y) & nzchar(y)
        if (any(need_extract, na.rm = TRUE)) {
          tok <- stringr::str_extract(y[need_extract], "[-+]?[0-9]*\\.?[0-9]+(?:[eE][-+]?[0-9]+)?")
          direct[need_extract] <- suppressWarnings(as.numeric(tok))
        }
        direct
      }
      is_bad_result_col <- function(cname) {
        if (!nzchar(cname) || !(cname %in% cn)) return(TRUE)
        nkey <- norm(cname)
        vals <- as.character(df[[cname]])
        vals <- vals[!is.na(vals)]
        if (length(vals) == 0) return(TRUE)
        vals <- utils::head(vals, 250)
        letter_rate <- mean(safe_detect(vals, "[A-Za-z]"), na.rm = TRUE)
        numeric_rate <- mean(!is.na(parse_num(vals)), na.rm = TRUE)
        looks_result_name <- safe_detect(nkey, "result|concentration|value|ngl|clean")
        looks_id_name <- safe_detect(nkey, "pws|well|station|sample|_id$|^id$|id")
        if (looks_id_name && !looks_result_name) return(TRUE)
        if (letter_rate > 0.70 && !looks_result_name) return(TRUE)
        if (numeric_rate < 0.20) return(TRUE)
        FALSE
      }
      col_by_alias <- function(aliases) {
        a <- norm(aliases)
        hit <- which(cn_norm %in% a)
        if (length(hit) > 0) return(cn[[hit[[1]]]])
        for (ax in a) {
          axx <- suppressWarnings(trimws(as.character(ax)))
          if (length(axx) != 1L || is.na(axx) || !nzchar(axx)) next
          hp <- which(safe_detect(cn_norm, axx))
          if (length(hp) > 0) return(cn[[hp[[1]]]])
        }
        ""
      }
      col_by_norm <- function(nm) {
        hit <- which(cn_norm == norm(nm))
        if (length(hit) > 0) cn[[hit[[1]]]] else ""
      }

      if (!nzchar(vals$analyte %||% "")) {
        vals$analyte <- col_by_norm("gm_chemical_name")
        if (!nzchar(vals$analyte)) {
          vals$analyte <- col_by_alias(c("analyte", "analyte_name", "contaminant", "chemical_name", "parameter", "compound", "name"))
        }
      }
      if (!nzchar(vals$result_value %||% "")) {
        vals$result_value <- col_by_norm("gm_result")
        if (!nzchar(vals$result_value)) vals$result_value <- col_by_norm("result_ngl")
        if (!nzchar(vals$result_value)) vals$result_value <- col_by_norm("result_clean")
        if (nzchar(vals$result_value) && isTRUE(is_bad_result_col(vals$result_value))) vals$result_value <- ""
        if (!nzchar(vals$result_value)) {
          pref <- col_by_alias(c("result", "result_value", "concentration", "value", "ngl", "clean"))
          if (nzchar(pref) && !isTRUE(is_bad_result_col(pref))) {
            vals$result_value <- pref
          } else {
            # Final fallback: most numeric-like column (avoid obvious ID/demographic fields).
            candidates <- cn[!safe_detect(cn_norm, "id|pws|well|station|sample|tract|population|geoid|zip|lat|lon")]
            if (length(candidates) == 0) candidates <- cn
            candidates <- candidates[!vapply(candidates, is_bad_result_col, logical(1))]
            rates <- vapply(candidates, function(cname) mean(!is.na(parse_num(df[[cname]]))), numeric(1))
            if (length(rates) > 0 && is.finite(max(rates, na.rm = TRUE)) && max(rates, na.rm = TRUE) > 0.3) {
              vals$result_value <- candidates[[which.max(rates)]]
            }
          }
        }
      }
      if (!nzchar(vals$sample_id %||% "")) {
        vals$sample_id <- col_by_norm("gm_well_id")
        if (!nzchar(vals$sample_id)) vals$sample_id <- col_by_alias(c("sample_id", "sampleid", "well_id", "pwsid", "station_id", "id"))
      }
      if (!nzchar(vals$state %||% "")) {
        vals$state <- col_by_norm("gm_state")
        if (!nzchar(vals$state)) vals$state <- col_by_alias(c("state", "state_abbr", "state_code"))
      }
      if (!nzchar(vals$county %||% "")) {
        vals$county <- col_by_alias(c("county"))
      }
      if (!nzchar(vals$facility_water_type %||% "")) {
        vals$facility_water_type <- col_by_alias(c("facilitywatertype", "facility_water_type"))
      }
      if (!nzchar(vals$sample_point_type %||% "")) {
        vals$sample_point_type <- col_by_alias(c("samplepointtype", "sample_point_type"))
      }
      if (!nzchar(vals$method_id %||% "")) {
        vals$method_id <- col_by_alias(c("methodid", "method_id"))
      }
      if (!nzchar(vals$collection_year %||% "")) {
        vals$collection_year <- col_by_alias(c("collectionyear", "collection_year", "year"))
      }
      if (!nzchar(vals$facility_id %||% "")) {
        vals$facility_id <- col_by_alias(c("facilityid", "facility_id"))
      }
      if (!nzchar(vals$sample_point_id %||% "")) {
        vals$sample_point_id <- col_by_alias(c("samplepointid", "sample_point_id"))
      }
      if (!nzchar(vals$unit %||% "")) {
        vals$unit <- col_by_norm("gm_result_unit")
        if (!nzchar(vals$unit)) vals$unit <- col_by_alias(c("unit", "units", "uom"))
      }
      if (!nzchar(vals$qualifier %||% "")) {
        vals$qualifier <- col_by_norm("gm_result_modifier")
        if (!nzchar(vals$qualifier)) vals$qualifier <- col_by_alias(c("qualifier", "modifier", "flag"))
      }
      if (identical(trimws(input$external_dataset_type %||% ""), REFERENCE_MATERIAL_DATASET_TYPE)) {
        if (!nzchar(vals$uncertainty %||% "")) {
          vals$uncertainty <- col_by_alias(c(
            "uncertainty", "expanded_uncertainty", "u_expanded", "u", "u_exp", "expanded_u"
          ))
        }
        if (!nzchar(vals$reference_id %||% "")) {
          vals$reference_id <- col_by_alias(c(
            "reference_id", "reference_material", "srm_id", "document_id", "catalog_id", "reference_source"
          ))
        }
      }
      # Final hard-stop: identifier-like columns must never survive as result_value.
      if (nzchar(vals$result_value %||% "") && isTRUE(is_bad_result_col(vals$result_value))) {
        vals$result_value <- ""
      }
    }
    vals
  })

  observeEvent(input$btn_external_validate, {
    df <- external_upload_raw()
    req(!is.null(df))
    if (refuse_pfas_op_on_metadata_lane("Validate")) return(invisible(NULL))
    ds_type <- input$external_dataset_type %||% "unknown/custom"
    external_reference_preflight(NULL)
    raw_sha <- ""
    uf <- normalize_shiny_file_upload(input$external_ml_file)
    if (!is.null(uf) && nzchar(uf$datapath)) {
      raw_sha <- external_upload_raw_digest(uf$datapath)
    }
    schema_cfg <- load_external_upload_schema()
    mapping <- get_upload_mapping()
    mapped_result_col <- trimws(as.character(mapping$result_value %||% ""))

    audit_strict <- function(sch_done, notes) {
      write_audit(
        "external_upload",
        sch_done$run_id %||% "none",
        ifelse(isTRUE(sch_done$ok), "strict_schema_pass", "strict_schema_fail"),
        op_id(),
        notes,
        list(
          schema_version = sch_done$schema_version,
          metrics = sch_done$metrics,
          violations = sch_done$violations,
          raw_sha256 = raw_sha,
          dataset_type = ds_type
        )
      )
    }

    if (nzchar(mapped_result_col) && isTRUE(is_identifier_like_result_col(mapped_result_col))) {
      sch_res <- list(
        ok = FALSE,
        schema_version = schema_cfg$schema_version,
        row_count = 0L,
        rows_pass = 0L,
        rows_fail = 0L,
        metrics = list(reason = "IDENTIFIER_RESULT_MAPPING", mapped_column = mapped_result_col),
        violations = list(list(rule = "RESULT_VALUE_IDENTIFIER")),
        run_id = NA_character_
      )
      sch_done <- persist_upload_validation_run(con, "validate_ui", sch_res, op_id(), external_upload_name() %||% "", raw_sha, ds_type)
      external_upload_strict_result(sch_done)
      audit_strict(sch_done, "Blocked: result_value mapped to identifier-like column")
      showNotification(
        paste0(
          "Mapped result_value column looks like an identifier (",
          mapped_result_col,
          "). Please map result_value to a numeric measurement column."
        ),
        type = "error",
        duration = 10
      )
      return(invisible(NULL))
    }

    norm <- normalize_upload_schema_with_wide_fallback(df, mapping, ds_type)

    ref_pf <- run_reference_material_preflight(norm, mapping, df, ds_type, external_upload_name() %||% "")
    external_reference_preflight(ref_pf)
    if (identical(ref_pf$status, "BLOCK")) {
      sch_res <- list(
        ok = FALSE,
        schema_version = schema_cfg$schema_version,
        row_count = as.integer(nrow(norm)),
        rows_pass = 0L,
        rows_fail = as.integer(max(nrow(norm), 1L)),
        metrics = list(reference_material_preflight = ref_pf),
        violations = list(list(
          rule = "REFERENCE_PREFLIGHT_BLOCK",
          detail = paste(ref_pf$messages, collapse = " | ")
        )),
        run_id = NA_character_
      )
      sch_done <- persist_upload_validation_run(con, "validate_ui", sch_res, op_id(), external_upload_name() %||% "", raw_sha, ds_type)
      external_upload_strict_result(sch_done)
      audit_strict(sch_done, "Reference material preflight BLOCK")
      showNotification(
        paste0("Reference material preflight BLOCK: ", ref_pf$messages[[1]]),
        type = "error",
        duration = 16
      )
      return(invisible(NULL))
    }

    nrmv <- nrow(norm)
    qv_heur <- if (nrmv > 0L) tolower(trimws(as.character(norm$qualifier %||% rep("", nrmv)))) else character(0)
    qv_heur[is.na(qv_heur)] <- ""
    nd_from_qual_heur <- if (nrmv > 0L) {
      safe_detect(qv_heur, "^<|\\bnd\\b|non[- ]?detect|\\bbdl\\b|not\\s+detected|\\babsent\\b|^u\\b|^uj\\b")
    } else {
      logical(0)
    }
    nd_from_detect_heur <- if (nrmv > 0L && "detect_flag" %in% names(norm)) {
      dfv <- suppressWarnings(as.integer(norm$detect_flag))
      !is.na(dfv) & dfv == 0L
    } else {
      rep(FALSE, nrmv)
    }
    nd_row_heur <- nd_from_qual_heur | nd_from_detect_heur
    missing_required <- if (nrmv == 0L) {
      0L
    } else {
      sum(
        is.na(norm$analyte) | trimws(as.character(norm$analyte %||% "")) == "" |
          (is.na(norm$result_value) & !nd_row_heur),
        na.rm = TRUE
      )
    }
    numeric_invalid <- 0L
    if (nzchar(mapped_result_col) && (mapped_result_col %in% names(df))) {
      raw_vals <- trimws(as.character(df[[mapped_result_col]]))
      raw_vals[raw_vals %in% c("", "NA", "N/A", "na", "n/a", "NULL", "null")] <- NA_character_
      parsed_vals <- parse_external_upload_numeric(raw_vals)
      numeric_invalid <- sum(!is.na(raw_vals) & is.na(parsed_vals), na.rm = TRUE)
    }
    dup_n <- sum(duplicated(paste(norm$sample_id, norm$sample_date, norm$analyte, norm$result_value, sep = "||")))
    au <- schema_cfg$allowed_result_units %||% default_external_upload_schema()$allowed_result_units
    allowed_units <- unique(normalize_external_result_unit_for_schema(as.character(au)))
    if (identical(ds_type, REFERENCE_MATERIAL_DATASET_TYPE)) {
      extra_ref <- c(
        "ug/kg", "mg/kg", "ng/kg", "g/kg", "ug/g", "mg/g", "ng/g", "g/g",
        "ppm", "ppt", "ppb", "ppq", "ng/l", "ug/l", "mg/l", "mg/ml", "ug/ml", "ng/ml"
      )
      allowed_units <- unique(c(allowed_units, normalize_external_result_unit_for_schema(extra_ref)))
    }
    unit_clean <- normalize_external_result_unit_for_schema(norm$result_unit %||% "")
    unsupported_units <- sum(nzchar(unit_clean) & !(unit_clean %in% allowed_units), na.rm = TRUE)
    nd_count <- sum(safe_detect(tolower(trimws(norm$qualifier %||% "")), "^<|nd|non.?detect|bdl|u\\b|uj\\b"), na.rm = TRUE)

    report <- list(
      rows = nrow(norm),
      missing_required_fields = missing_required,
      invalid_numeric_results = numeric_invalid,
      duplicate_rows = dup_n,
      unsupported_units = unsupported_units,
      non_detect_qualifier_rows = nd_count
    )
    external_upload_report(report)
    external_upload_normalized(norm)

    no_required_mapping <- !nzchar(trimws(mapping$analyte %||% "")) || !nzchar(trimws(mapping$result_value %||% ""))
    if (isTRUE(no_required_mapping) || missing_required >= nrow(norm)) {
      sch_res <- list(
        ok = FALSE,
        schema_version = schema_cfg$schema_version,
        row_count = as.integer(nrow(norm)),
        rows_pass = 0L,
        rows_fail = as.integer(max(nrow(norm), 1L)),
        metrics = list(
          block_reason = "MAPPING_OR_HEURISTIC",
          missing_required_fields = missing_required,
          heuristic_rows = report$rows
        ),
        violations = list(list(rule = "MAPPING_REQUIRED_FIELDS")),
        run_id = NA_character_
      )
      sch_done <- persist_upload_validation_run(con, "validate_ui", sch_res, op_id(), external_upload_name() %||% "", raw_sha, ds_type)
      external_upload_strict_result(sch_done)
      audit_strict(sch_done, "Heuristic validation blocked before strict schema")
      showNotification(
        paste0(
          "No valid analyte/result mapping found for this file. ",
          "Current mapping analyte='", mapping$analyte %||% "", "', result_value='", mapping$result_value %||% "", "'. ",
          "If this is a summary/demographic table (e.g., Census Tract), upload the PFAS measurement table instead."
        ),
        type = "error",
        duration = 12
      )
      return(invisible(NULL))
    }

    sch_res <- strict_validate_normalized_external(norm, schema_cfg, ds_type)
    sch_done <- persist_upload_validation_run(con, "validate_ui", sch_res, op_id(), external_upload_name() %||% "", raw_sha, ds_type)
    external_upload_strict_result(sch_done)
    audit_strict(sch_done, "Strict schema validation (Validate button)")

    if (nrow(norm) == 0 || report$rows == 0) {
      showNotification("Validation failed: no usable rows.", type = "error")
    } else if (!isTRUE(sch_done$ok)) {
      showNotification(
        "Strict schema validation FAILED. Review Strict schema panel; fix rows/units or adjust data/config/external_upload_schema.json.",
        type = "error",
        duration = 14
      )
    } else {
      if (identical(ref_pf$status, "REVIEW")) {
        showNotification(
          paste0("Validation PASS with REVIEW: ", ref_pf$messages[[1]]),
          type = "warning",
          duration = 14
        )
      } else {
        showNotification("Validation completed (heuristic + strict schema PASS).", type = "message")
      }
    }
  })

  observeEvent(input$btn_external_normalize, {
    df <- external_upload_raw()
    req(!is.null(df))
    if (refuse_pfas_op_on_metadata_lane("Normalize")) return(invisible(NULL))
    mapping <- get_upload_mapping()
    norm <- normalize_upload_schema_with_wide_fallback(df, mapping, input$external_dataset_type %||% "unknown/custom")
    external_upload_normalized(norm)
    external_upload_strict_result(NULL)
    external_reference_preflight(NULL)
    showNotification("Normalization completed. Re-run Validate for strict schema + SQLite record.", type = "message")
  })

  observeEvent(input$btn_external_save, {
    if (refuse_pfas_op_on_metadata_lane("Save")) return(invisible(NULL))
    mapping <- get_upload_mapping()
    mapped_result_col <- trimws(as.character(mapping$result_value %||% ""))
    if (nzchar(mapped_result_col) && isTRUE(is_identifier_like_result_col(mapped_result_col))) {
      external_upload_save_note(
        paste0(
          "Save blocked: mapped result_value column '",
          mapped_result_col,
          "' appears to be an identifier (not a numeric measurement)."
        )
      )
      showNotification(
        paste0(
          "Save blocked: result_value column '",
          mapped_result_col,
          "' looks like an identifier. Map result_value to a numeric PFAS result column first."
        ),
        type = "error",
        duration = 12
      )
      return(invisible(NULL))
    }
    norm <- external_upload_normalized()
    req(!is.null(norm), nrow(norm) > 0)

    ds_type <- input$external_dataset_type %||% "unknown/custom"
    df0 <- external_upload_raw()
    if (!is.null(df0)) {
      ref_pf <- run_reference_material_preflight(norm, mapping, df0, ds_type, external_upload_name() %||% "")
      external_reference_preflight(ref_pf)
      if (identical(ref_pf$status, "BLOCK")) {
        external_upload_save_note(
          paste0("Save blocked: reference material preflight BLOCK — ", ref_pf$messages[[1]])
        )
        showNotification(
          paste0("Save blocked: reference material preflight. ", ref_pf$messages[[1]]),
          type = "error",
          duration = 16
        )
        return(invisible(NULL))
      }
      if (identical(ref_pf$status, "REVIEW")) {
        showNotification(
          paste0("Save: reference material preflight REVIEW — ", ref_pf$messages[[1]]),
          type = "warning",
          duration = 12
        )
      }
    }
    raw_sha <- ""
    uf <- normalize_shiny_file_upload(input$external_ml_file)
    if (!is.null(uf) && nzchar(uf$datapath)) {
      raw_sha <- external_upload_raw_digest(uf$datapath)
    }
    schema_cfg <- load_external_upload_schema()
    sch_res <- strict_validate_normalized_external(norm, schema_cfg, ds_type)
    sch_gate <- persist_upload_validation_run(con, "save_gate", sch_res, op_id(), external_upload_name() %||% "", raw_sha, ds_type)
    external_upload_strict_result(sch_gate)

    if (!isTRUE(sch_res$ok)) {
      external_upload_save_note(
        paste0(
          "Save blocked: strict schema validation FAILED (run_id=", sch_gate$run_id %||% "n/a", "). ",
          "Click Validate after fixes or edit data/config/external_upload_schema.json."
        )
      )
      write_audit(
        "external_upload",
        sch_gate$run_id %||% "none",
        "save_blocked_strict_schema",
        op_id(),
        "Save blocked: normalized table failed strict schema gate",
        list(metrics = sch_res$metrics, violations = sch_res$violations)
      )
      showNotification(
        "Save blocked: strict schema validation failed. Run Validate and fix issues.",
        type = "error",
        duration = 14
      )
      return(invisible(NULL))
    }

    rows_before_dedup <- nrow(norm)
    norm <- norm %>%
      distinct(sample_id, sample_date, analyte, result_value, .keep_all = TRUE)
    dedup_removed <- rows_before_dedup - nrow(norm)
    if (nrow(norm) == 0L) {
      external_upload_save_note(
        "Save blocked: 0 rows after de-duplication (sample_id, sample_date, analyte, result_value). Check keys and data quality."
      )
      showNotification(
        "Save blocked: no rows left after de-duplication. Adjust mapping or source data.",
        type = "error"
      )
      return(invisible(NULL))
    }
    usable_rows <- sum(
      !is.na(norm$analyte) & nzchar(trimws(as.character(norm$analyte))) & !is.na(norm$result_value),
      na.rm = TRUE
    )
    if (usable_rows == 0) {
      external_upload_save_note(
        "Save blocked: 0 usable rows (analyte + numeric result_value). Use Map/Validate and confirm required fields are populated."
      )
      showNotification(
        "Save blocked: no usable analyte/result rows detected. Map columns, Validate, then Normalize again.",
        type = "error"
      )
      return(invisible(NULL))
    }
    upload_id <- paste0(
      "UPL-",
      format(Sys.time(), "%Y%m%d%H%M%S"),
      "-",
      substr(digest::digest(as.character(runif(1)), serialize = FALSE), 1, 6)
    )
    ts <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    n_norm_rows <- nrow(norm)
    # Length must match nrow(norm): assigning a scalar to a 0-row frame triggers
    # "[<-: replacement has 1 row, data has 0".
    norm$upload_id <- rep_len(upload_id, n_norm_rows)
    norm$uploaded_at <- rep_len(ts, n_norm_rows)
    ds_fallback <- input$external_dataset_type %||% "unknown/custom"
    src_ds <- as.character(norm$source_dataset)
    empty_ds <- is.na(src_ds) | src_ds == ""
    norm$source_dataset <- ifelse(empty_ds, rep_len(ds_fallback, n_norm_rows), src_ds)
    external_upload_normalized(norm)

    dir_uploads <- file.path(PROJECT_DIR, "data", "external_uploads")
    dir_processed <- file.path(PROJECT_DIR, "data", "processed")
    dir_external_ingest <- file.path(PROJECT_DIR, "data", "external", "external_uploads")
    dir.create(dir_uploads, recursive = TRUE, showWarnings = FALSE)
    dir.create(dir_processed, recursive = TRUE, showWarnings = FALSE)
    dir.create(dir_external_ingest, recursive = TRUE, showWarnings = FALSE)

    out_norm <- file.path(dir_uploads, paste0(upload_id, "_normalized.csv"))
    out_ingest <- file.path(dir_external_ingest, paste0(upload_id, "_normalized.csv"))
    utils::write.csv(norm, out_norm, row.names = FALSE)
    utils::write.csv(norm, out_ingest, row.names = FALSE)

    master_path <- file.path(dir_processed, "pfas_training_master.csv")
    master <- if (file.exists(master_path)) {
      tryCatch(
        utils::read.csv(master_path, stringsAsFactors = FALSE, check.names = FALSE),
        error = function(e) {
          data.frame(stringsAsFactors = FALSE, check.names = FALSE)
        }
      )
    } else {
      data.frame(stringsAsFactors = FALSE, check.names = FALSE)
    }

    # Base data.frames only: tibble/dplyr subsetting can make [[<- fail on 0-row binds.
    master <- as.data.frame(master, stringsAsFactors = FALSE)
    norm <- as.data.frame(norm, stringsAsFactors = FALSE)
    nr_master <- nrow(master)
    nr_norm <- nrow(norm)
    if (length(nr_master) != 1L || is.na(nr_master) || nr_master < 0L) {
      nr_master <- 0L
    }
    if (length(nr_norm) != 1L || is.na(nr_norm) || nr_norm < 0L) {
      nr_norm <- 0L
    }

    for (cn in upload_schema_cols) {
      if (!cn %in% names(master)) {
        master[[cn]] <- rep(NA_character_, nr_master)
      }

      if (!cn %in% names(norm)) {
        norm[[cn]] <- rep(NA_character_, nr_norm)
      }
    }

    master_aligned <- as.data.frame(master[, upload_schema_cols, drop = FALSE], stringsAsFactors = FALSE)
    norm_aligned <- as.data.frame(norm[, upload_schema_cols, drop = FALSE], stringsAsFactors = FALSE)
    nr_ma <- nrow(master_aligned)
    nr_na <- nrow(norm_aligned)

    for (cn in upload_schema_cols) {
      if (!cn %in% names(master_aligned)) {
        master_aligned[[cn]] <- rep(NA_character_, nr_ma)
      }

      if (!cn %in% names(norm_aligned)) {
        norm_aligned[[cn]] <- rep(NA_character_, nr_na)
      }
    }

    master_aligned <- master_aligned[, upload_schema_cols, drop = FALSE]
    norm_aligned <- norm_aligned[, upload_schema_cols, drop = FALSE]

    master_aligned[] <- lapply(master_aligned, function(x) {
      as.character(x)
    })

    norm_aligned[] <- lapply(norm_aligned, function(x) {
      as.character(x)
    })

    combined <- rbind(master_aligned, norm_aligned)
    utils::write.csv(combined, master_path, row.names = FALSE)

    log_path <- file.path(dir_uploads, "upload_log.csv")
    log_row <- tibble::tibble(
      upload_id = upload_id,
      uploaded_at = ts,
      file_name = external_upload_name() %||% NA_character_,
      dataset_type = input$external_dataset_type %||% "unknown/custom",
      rows_saved = nrow(norm),
      dedup_rows_removed = dedup_removed,
      normalized_file = basename(out_norm),
      appended_master = basename(master_path)
    )
    if (file.exists(log_path)) {
      old <- tryCatch(
        utils::read.csv(log_path, stringsAsFactors = FALSE, check.names = FALSE),
        error = function(e) {
          data.frame()
        }
      )
      old <- dplyr::bind_rows(old, log_row)
      utils::write.csv(old, log_path, row.names = FALSE)
    } else {
      utils::write.csv(log_row, log_path, row.names = FALSE)
    }

    write_audit(
      "external_upload",
      upload_id,
      "normalized_save_success",
      op_id(),
      paste0("Saved ", nrow(norm), " normalized rows to master"),
      list(
        upload_id = upload_id,
        strict_gate_run_id = sch_gate$run_id,
        dedup_removed = dedup_removed,
        raw_sha256 = raw_sha,
        dataset_type = ds_type
      )
    )

    external_upload_save_note(
      paste(
        "Saved normalized rows:", nrow(norm), "\n",
        "De-duplicated rows removed:", dedup_removed, "\n",
        "Upload file:", out_norm, "\n",
        "External ingest copy:", out_ingest, "\n",
        "Master updated:", master_path, "\n",
        "Upload log:", log_path
      )
    )
    showNotification(
      paste0("Upload saved. ", nrow(norm), " rows kept; ", dedup_removed, " duplicate rows removed."),
      type = "message"
    )
  })

  observeEvent(input$btn_external_train, {
    if (refuse_pfas_op_on_metadata_lane("Train (Evidence-Governed)")) return(invisible(NULL))
    if (!enforce_iso_preflight("External train")) return(invisible(NULL))
    # Use in-process execution for R steps to avoid runtime issues resolving subprocess Rscript.
    ok_m <- run_r_script_in_process("prepare_multisource_training.R", "prepare_multisource_training.R")
    ok_b <- if (ok_m) run_r_script_in_process("build_model_matrix.R", "build_model_matrix.R") else FALSE
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    python_available <- nzchar(py_exec)
    ok_t <- if (ok_b && python_available) run_python_step() else FALSE
    overall_ok <- ok_m && ok_b && (!python_available || ok_t)
    record_train_workflow_context("evidence_governed", TRUE, overall_ok)

    if (ok_m && ok_b && (!python_available || ok_t)) {
      if (!python_available) {
        showNotification(
          "Data refresh completed (prepare + matrix). Python executable not found, so model retrain was skipped.",
          type = "warning",
          duration = 10
        )
      } else if (!ok_t) {
        showNotification(
          "Data refresh completed, but Python model retrain failed. Check PFAS pipeline log.",
          type = "warning",
          duration = 10
        )
      } else {
        showNotification("Training completed from uploaded/merged sources.", type = "message")
      }
      # Refresh UI artifacts (target tracker and any updated results files).
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else if (!ok_m) {
      showNotification(
        paste0(
          "Training failed at prepare_multisource_training.R: ",
          pipeline_last_error() %||% "unknown error"
        ),
        type = "error",
        duration = 12
      )
    } else if (!ok_b) {
      showNotification(
        paste0(
          "Training failed at build_model_matrix.R: ",
          pipeline_last_error() %||% "unknown error"
        ),
        type = "error",
        duration = 12
      )
    } else {
      showNotification(
        paste0("Training failed: ", pipeline_last_error() %||% "unknown error"),
        type = "error",
        duration = 12
      )
    }
  })

  observeEvent(input$btn_external_train_screening, {
    if (refuse_pfas_op_on_metadata_lane("Screening — Train (Exploratory)")) return(invisible(NULL))
    oid <- op_id()
    append_pipeline_log(
      "SCREENING exploratory: External train (prepare_multisource + matrix + python) — ISO preflight skipped by explicit user action."
    )
    write_audit(
      "pfas_pipeline",
      "screening_external_train",
      "screening_train_started",
      oid,
      "Exploratory external-linked train started",
      list(
        workflow_mode = "screening",
        validation_scope = "exploratory",
        iso_governed = FALSE,
        route = "external_upload_train"
      )
    )
    ex <- pfas_screening_train_extra_env()
    ok_m <- run_r_script_in_process("prepare_multisource_training.R", "prepare_multisource_training.R", extra_env = ex)
    ok_b <- if (ok_m) run_r_script_in_process("build_model_matrix.R", "build_model_matrix.R", extra_env = ex) else FALSE
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    python_available <- nzchar(py_exec)
    ok_t <- if (ok_b && python_available) run_python_step(extra_env = ex) else FALSE
    overall_ok <- ok_m && ok_b && (!python_available || ok_t)
    write_audit(
      "pfas_pipeline",
      "screening_external_train",
      if (overall_ok) "screening_train_completed" else "screening_train_failed",
      oid,
      if (overall_ok) "Exploratory external-linked train finished" else "Exploratory external-linked train failed",
      list(
        workflow_mode = "screening",
        validation_scope = "exploratory",
        iso_governed = FALSE,
        success = overall_ok,
        ok_prepare = ok_m,
        ok_matrix = ok_b,
        ok_python = ok_t,
        python_skipped = !python_available
      )
    )
    record_train_workflow_context("screening", FALSE, overall_ok)

    if (ok_m && ok_b && (!python_available || ok_t)) {
      if (!python_available) {
        showNotification(
          "Data refresh completed (prepare + matrix). Python executable not found, so model retrain was skipped.",
          type = "warning",
          duration = 10
        )
      } else if (!ok_t) {
        showNotification(
          "Data refresh completed, but Python model retrain failed. Check PFAS pipeline log.",
          type = "warning",
          duration = 10
        )
      } else {
        showNotification("Screening (exploratory) training completed from uploaded/merged sources.", type = "message")
      }
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else if (!ok_m) {
      showNotification(
        paste0(
          "Screening train failed at prepare_multisource_training.R: ",
          pipeline_last_error() %||% "unknown error"
        ),
        type = "error",
        duration = 12
      )
    } else if (!ok_b) {
      showNotification(
        paste0(
          "Screening train failed at build_model_matrix.R: ",
          pipeline_last_error() %||% "unknown error"
        ),
        type = "error",
        duration = 12
      )
    } else {
      showNotification(
        paste0("Screening train failed: ", pipeline_last_error() %||% "unknown error"),
        type = "error",
        duration = 12
      )
    }
  })

  observeEvent(input$train_pfas_model, {
    if (!enforce_iso_preflight("PFAS model training")) return(invisible(NULL))
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    if (!nzchar(py_exec)) {
      record_train_workflow_context("evidence_governed", TRUE, FALSE)
      showNotification(
        "Python executable not found. Set 'Python executable' then retry PFAS model training.",
        type = "error",
        duration = 10
      )
      return(invisible(NULL))
    }
    ok <- run_python_step()
    record_train_workflow_context("evidence_governed", TRUE, ok)
    if (ok) {
      showNotification("PFAS exceedance model training completed.", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification("PFAS model training failed; check PFAS pipeline log.", type = "error")
    }
  })

  observeEvent(input$train_pfas_model_screening, {
    oid <- op_id()
    append_pipeline_log(
      "SCREENING exploratory: train_pfas_model.py — ISO preflight skipped by explicit user action (not evidence-governed)."
    )
    write_audit(
      "pfas_pipeline",
      "screening_train",
      "screening_train_started",
      oid,
      "Exploratory screening PFAS model train started",
      list(
        workflow_mode = "screening",
        validation_scope = "exploratory",
        iso_governed = FALSE,
        python_step = "train_pfas_model.py"
      )
    )
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    if (!nzchar(py_exec)) {
      write_audit(
        "pfas_pipeline",
        "screening_train",
        "screening_train_failed",
        oid,
        "Exploratory screening PFAS model train aborted (Python not configured)",
        list(workflow_mode = "screening", validation_scope = "exploratory", iso_governed = FALSE, reason = "no_python")
      )
      record_train_workflow_context("screening", FALSE, FALSE)
      showNotification(
        "Python executable not found. Set 'Python executable' then retry exploratory screening train.",
        type = "error",
        duration = 10
      )
      return(invisible(NULL))
    }
    ok <- run_python_step(extra_env = pfas_screening_train_extra_env())
    write_audit(
      "pfas_pipeline",
      "screening_train",
      if (ok) "screening_train_completed" else "screening_train_failed",
      oid,
      if (ok) "Exploratory screening PFAS model train finished" else "Exploratory screening PFAS model train failed",
      list(
        workflow_mode = "screening",
        validation_scope = "exploratory",
        iso_governed = FALSE,
        success = ok
      )
    )
    record_train_workflow_context("screening", FALSE, ok)
    if (ok) {
      showNotification("Exploratory screening train finished (not ISO-governed).", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification("Exploratory screening train failed; check PFAS pipeline log.", type = "error")
    }
  })

  observeEvent(input$btn_generate_ml_validation_report, {
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    if (!nzchar(py_exec)) {
      showNotification(
        "Python executable not found. Set 'Python executable' then regenerate the ML validation report.",
        type = "error",
        duration = 10
      )
      return(invisible(NULL))
    }
    ok <- run_ml_validation_report_step()
    if (ok) {
      showNotification(
        "ML validation report generated: results/ISO17025_ML_Validation_Report.html",
        type = "message",
        duration = 12
      )
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification("ML validation report step failed; check PFAS pipeline log.", type = "error")
    }
  })

  observeEvent(input$run_pfas_prediction, {
    if (!enforce_iso_preflight("PFAS prediction")) return(invisible(NULL))
    py_exec <- resolve_python_exec(input$pfas_python_exec %||% "")
    if (!nzchar(py_exec)) {
      showNotification(
        "Python executable not found. Set 'Python executable' then retry prediction.",
        type = "error",
        duration = 10
      )
      return(invisible(NULL))
    }
    ok <- run_pfas_prediction_step()
    if (ok) {
      showNotification("PFAS prediction run completed.", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification("PFAS prediction failed; check PFAS pipeline log.", type = "error")
    }
  })

  observeEvent(input$qc_dataset_file, {
    qc_path <- resolve_pipeline_path(input$pfas_qc_path, file.path(PROJECT_DIR, "data", "external", "qc_datasets"))
    qc_stage_dir <- if (file.exists(qc_path) && !dir.exists(qc_path)) dirname(qc_path) else qc_path
    dest <- ensure_uploaded_artifact(input$qc_dataset_file, qc_stage_dir, "qc_dataset.csv")
    if (is.null(dest)) return(invisible(NULL))
    qc_pt_upload_status_note(paste0("QC dataset staged: ", normalizePath(dest, winslash = "/", mustWork = FALSE)))
    append_pipeline_log("QC input staged: ", basename(dest))
    pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$pt_dataset_file, {
    pt_path <- resolve_pipeline_path(input$pfas_pt_path, file.path(PROJECT_DIR, "data", "external", "proficiency_testing"))
    pt_stage_dir <- if (file.exists(pt_path) && !dir.exists(pt_path)) dirname(pt_path) else pt_path
    dest <- ensure_uploaded_artifact(input$pt_dataset_file, pt_stage_dir, "pt_dataset.csv")
    if (is.null(dest)) return(invisible(NULL))
    qc_pt_upload_status_note(paste0("PT dataset staged: ", normalizePath(dest, winslash = "/", mustWork = FALSE)))
    append_pipeline_log("PT input staged: ", basename(dest))
    pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$btn_validate_reference_dataset, {
    ok <- step_validate_reference_dataset()
    write_audit(
      "pfas_pipeline",
      "validate_reference_dataset",
      ifelse(ok, "execute_success", "execute_failure"),
      op_id(),
      ifelse(ok, "Reference dataset loaded/validated", "Reference dataset load/validation failed"),
      list(error = pipeline_last_error() %||% "")
    )
    if (ok) {
      showNotification("Reference dataset loaded/validated.", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification(paste0("Reference step failed: ", pipeline_last_error() %||% "unknown error"), type = "error")
    }
  })

  observeEvent(input$btn_nist_reference_validation, {
    ok <- run_nist_reference_validation_step()
    write_audit(
      "pfas_pipeline",
      "nist_reference_validation",
      ifelse(ok, "execute_success", "execute_failure"),
      op_id(),
      ifelse(ok, "NIST reference validation completed", "NIST reference validation failed"),
      list(error = pipeline_last_error() %||% "")
    )
    if (ok) {
      showNotification(
        "NIST SRM 1957 Table A2 reference-data validation completed (non-certified benchmarking only; see results/nist_reference_validation_report.json).",
        type = "message"
      )
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification(paste0("NIST reference validation failed: ", pipeline_last_error() %||% "unknown error"), type = "error")
    }
  })

  observeEvent(input$btn_qc_validation_check, {
    ok <- step_qc_validation_check()
    write_audit(
      "pfas_pipeline",
      "qc_validation_check",
      ifelse(ok, "execute_success", "execute_failure"),
      op_id(),
      ifelse(ok, "QC validation check completed", "QC validation check failed"),
      list(error = pipeline_last_error() %||% "")
    )
    if (ok) {
      showNotification("QC validation check completed.", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification(paste0("QC validation check failed: ", pipeline_last_error() %||% "unknown error"), type = "error")
    }
  })

  observeEvent(input$btn_applicability_domain_check, {
    ok <- step_applicability_domain_check()
    write_audit(
      "pfas_pipeline",
      "applicability_domain_check",
      ifelse(ok, "execute_success", "execute_failure"),
      op_id(),
      ifelse(ok, "Applicability-domain check completed", "Applicability-domain check failed"),
      list(error = pipeline_last_error() %||% "")
    )
    if (ok) {
      showNotification("Applicability-domain check completed.", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification(paste0("Applicability-domain check failed: ", pipeline_last_error() %||% "unknown error"), type = "error")
    }
  })

  observeEvent(input$btn_external_pt_validation, {
    ok <- step_external_pt_validation()
    write_audit(
      "pfas_pipeline",
      "external_pt_validation",
      ifelse(ok, "execute_success", "execute_failure"),
      op_id(),
      ifelse(ok, "External PT validation completed", "External PT validation failed"),
      list(error = pipeline_last_error() %||% "")
    )
    if (ok) {
      showNotification("External PT validation completed.", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification(paste0("External PT validation failed: ", pipeline_last_error() %||% "unknown error"), type = "error")
    }
  })

  observeEvent(input$btn_generate_iso_compliance_report, {
    ok <- step_generate_iso_compliance_report()
    write_audit(
      entity_type = "pfas_pipeline",
      entity_id = "generate_iso_compliance_report",
      action_type = ifelse(ok, "execute_success", "execute_failure"),
      changed_by = op_id(),
      message = ifelse(ok, "ISO compliance report generated", "ISO compliance report generation failed"),
      details = list(error = pipeline_last_error() %||% "")
    )
    if (ok) {
      showNotification("ISO compliance report generated.", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification(paste0("ISO compliance report failed: ", pipeline_last_error() %||% "unknown error"), type = "error")
    }
  })

  output$external_quality_status <- renderPrint({
    rep <- external_upload_report()
    mapping <- get_upload_mapping()
    cat("Mapping engine version:", MAPPING_ENGINE_VERSION, "\n")
    # Physiological-sample autodetect: when the upload is recognized as
    # NHANES serum biomonitoring, the environmental long-format mapper
    # cannot describe it. Surface the affirmative classification here so
    # the operator sees what was recognized (instead of an all-blank
    # "Current mapping" block).
    sem_now <- tryCatch(upload_dataset_semantic_type(),
                        error = function(e) "pfas_occurrence_or_other")
    if (identical(sem_now, "serum_biomonitoring")) {
      df_now <- external_upload_raw()
      auto <- autodetect_physiological_serum_columns(
        if (is.null(df_now)) character(0) else names(df_now)
      )
      cat("Autodetect engine     : ", auto$autodetect_version, "\n", sep = "")
      cat("Semantic type         : ", auto$semantic_type %||% "", "\n", sep = "")
      cat("Lane (matrix pipeline): ", auto$lane %||% "", "\n", sep = "")
      cat("Matrix                : ", auto$matrix %||% "", "\n", sep = "")
      cat("Method                : ", auto$method %||% "", "\n", sep = "")
      cat("Concentration units   : ", auto$units %||% "", "\n", sep = "")
      cat("Table format          : ", auto$format %||% "", "\n", sep = "")
      stamp <- auto$classification_stamp
      cat("\nLane-stamped physiological classification (auto-mapped from lane contract,\n")
      cat(  "not from upload columns; verified by physiological_guard() on validate/\n")
      cat(  "normalize/save/train; see validation/serum_v1/schema_contract.md \u00a79):\n")
      if (!is.null(stamp)) {
        for (k in PHYSIOLOGICAL_CLASSIFICATION_FIELDS) {
          cat(sprintf("  %-22s: %s\n", k, as.character(stamp[[k]] %||% "")))
        }
      } else {
        cat("  (no classification stamp registered for this lane)\n")
      }
      guard_in <- list()
      if (!is.null(stamp)) for (k in names(stamp)) guard_in[[k]] <- stamp[[k]]
      g <- physiological_guard(guard_in, lane = "serum")
      cat(sprintf(
        "  guard self-test       : ok=%s, code=%s\n",
        as.character(isTRUE(g$ok)), g$code %||% ""
      ))
      cnt <- auto$counts
      cat(sprintf(
        "Column counts         : respondent_id=%d, survey_weight=%d, analyte_concentration=%d, analyte_detection_code=%d, unknown=%d\n",
        cnt$respondent_id %||% 0L,
        cnt$survey_weight %||% 0L,
        cnt$analyte_concentration %||% 0L,
        cnt$analyte_detection_code %||% 0L,
        cnt$unknown %||% 0L
      ))
      cat("\nPer-column classification\n")
      cat(sprintf("  %-12s  %-23s  %-15s  %-12s  %-6s  %s\n",
                  "column", "role", "analyte", "paired_with", "units", "notes"))
      if (nrow(auto$columns) > 0L) {
        for (i in seq_len(nrow(auto$columns))) {
          r <- auto$columns[i, , drop = FALSE]
          cat(sprintf(
            "  %-12s  %-23s  %-15s  %-12s  %-6s  %s\n",
            substr(r$column %||% "", 1, 12),
            r$role %||% "",
            substr(r$analyte %||% "", 1, 15),
            substr(r$paired_with %||% "", 1, 12),
            r$units %||% "",
            r$notes %||% ""
          ))
        }
      }
      cat("\nPaired LBX/LBD analyte coverage\n")
      if (length(auto$paired_lbx_lbd) > 0L) {
        for (p in auto$paired_lbx_lbd) {
          cat(sprintf("  - %-15s  conc=%-12s  lod_code=%-12s\n",
                      p$analyte %||% "", p$lbx_column %||% "", p$lbd_column %||% ""))
        }
      } else {
        cat("  (none recognized)\n")
      }
      cat("\nPFAS-occurrence dropdowns (long-format ng/L environmental schema)\n")
      cat("  Disabled for this upload. The serum lane is wide-format ng/mL\n")
      cat("  physiological biomonitoring; cross-matrix mapping is refused by\n")
      cat("  validation/serum_v1/schema_contract.md \u00a75 and applicability_domain.txt R5.\n")
      cat("  Documented ingestion path : scripts/convert_nhanes_xpt_to_csv.R\n")
      cat("  Governance boundary       : validation/serum_v1/\n")
      cat("  Existing training table   : data/training/serum/training.csv (manifest.json)\n")
      cat("  Applicability-domain model: data/ad_models/serum/ad_model.json\n")
      cat("\n")
      if (is.null(rep)) {
        cat("No PFAS-occurrence validation report applicable (serum lane is governed separately).\n")
        return(invisible(NULL))
      }
      cat("(PFAS-occurrence validation report ignored on this lane.)\n")
      return(invisible(NULL))
    }
    cat("Current mapping (ISO/PFAS core MVP \u2014 same order as Map dropdowns)\n")
    map_keys_show <- CORE_EXTERNAL_MAP_KEYS
    if (identical(trimws(input$external_dataset_type %||% ""), REFERENCE_MATERIAL_DATASET_TYPE)) {
      map_keys_show <- c(map_keys_show, REFERENCE_EXTRA_MAP_KEYS)
    }
    for (k in map_keys_show) {
      v <- mapping[[k]]
      if (is.null(v) || length(v) == 0) {
        v <- ""
      } else {
        v <- paste(as.character(v), collapse = ", ")
      }
      cat(sprintf("%-26s: %s\n", k, v))
    }
    cat("\n")
    mapped_result_col <- trimws(as.character(mapping$result_value %||% ""))
    if (nzchar(mapped_result_col) && isTRUE(is_identifier_like_result_col(mapped_result_col))) {
      cat("WARNING: result_value appears to be an identifier column and is invalid for training.\n\n")
    }
    if (is.null(rep)) {
      cat("No validation report yet.\n")
      return(invisible(NULL))
    }
    cat("Validation summary\n")
    cat("Rows:", rep$rows, "\n")
    cat("Missing required fields (analyte/result_value):", rep$missing_required_fields, "\n")
    cat("Invalid numeric results:", rep$invalid_numeric_results, "\n")
    cat("Duplicate rows:", rep$duplicate_rows, "\n")
    cat("Unsupported units:", rep$unsupported_units, "\n")
    cat("Non-detect qualifier rows:", rep$non_detect_qualifier_rows, "\n")
    rpf <- external_reference_preflight()
    if (!is.null(rpf)) {
      cat("\nReference material preflight:", rpf$status %||% "?", "\n")
      if (length(rpf$messages)) {
        for (m in rpf$messages) cat("  ", m, "\n", sep = "")
      }
    }
  })

  output$external_strict_schema_status <- renderPrint({
    sr <- external_upload_strict_result()
    schema_now <- load_external_upload_schema()
    cat("Schema file:", file.path(PROJECT_DIR, "data", "config", "external_upload_schema.json"), "\n")
    cat("Active schema_version:", schema_now$schema_version %||% "unknown", "\n\n")
    if (is.null(sr)) {
      cat("No strict validation recorded yet for this session (click Validate after upload/map).\n")
      return(invisible(NULL))
    }
    cat("Last validation record\n")
    cat(" run_id       :", sr$run_id %||% "", "\n")
    cat(" schema_version:", sr$schema_version %||% "", "\n")
    cat(" strict OK    :", isTRUE(sr$ok), "\n")
    cat(" rows (total) :", sr$row_count %||% NA, "\n")
    cat(" rows PASS    :", sr$rows_pass %||% NA, "\n")
    cat(" rows FAIL    :", sr$rows_fail %||% NA, "\n")
    if (!is.null(sr$metrics) && length(sr$metrics) > 0) {
      cat("\nMetrics:\n")
      print(sr$metrics)
    }
    if (!is.null(sr$violations) && length(sr$violations) > 0) {
      cat("\nViolations:\n")
      print(sr$violations)
    }
    cat("\nSQLite table:", "upload_validation_run", "(controlled validation evidence).\n")
  })

  output$external_save_status <- renderPrint({
    cat(external_upload_save_note(), "\n")
  })

  observeEvent(input$btn_pfas_download, {
    ok <- run_r_script_step("download_echo_nhanes.R", "download_echo_nhanes.R")
    if (ok) pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$btn_pfas_prepare, {
    ok <- run_r_script_step("prepare_nhanes_training.R", "prepare_nhanes_training.R")
    if (ok) pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$btn_epa_ucmr5_download, {
    ok <- run_r_script_step("download_epa_ucmr5.R", "download_epa_ucmr5.R")
    if (ok) pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$btn_epa_echo_download, {
    ok <- run_r_script_step("download_epa_echo_api.R", "download_epa_echo_api.R", extra_env = pipeline_env())
    if (ok) pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$btn_epa_sdwis_download, {
    ok <- run_r_script_step("download_epa_sdwis.R", "download_epa_sdwis.R", extra_env = pipeline_env())
    if (ok) pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$btn_epa_icis_npdes_download, {
    lim <- if (isTRUE(input$epa_icis_include_limits)) "1" else "0"
    ok <- run_r_script_step(
      "download_epa_icis_npdes.R",
      "download_epa_icis_npdes.R",
      extra_env = c(
        PFAS_ICIS_DMR_YEARS = trimws(input$epa_icis_dmr_years %||% "2024,2025"),
        PFAS_ICIS_INCLUDE_LIMITS = lim
      )
    )
    if (ok) {
      showNotification("ICIS-NPDES ECHO downloads completed (see data/raw/epa_icis_npdes).", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification("ICIS-NPDES download failed; see PFAS pipeline log.", type = "error")
    }
  })

  observeEvent(input$btn_epa_icis_filter_dmr, {
    ok <- run_icis_dmr_filter_step()
    if (ok) {
      showNotification("DMR PFAS filter completed (data/processed/npdes_dmr_pfas_fy*.csv).", type = "message")
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      showNotification("DMR PFAS filter failed; check Python path and FY ZIP present.", type = "error")
    }
  })

  observeEvent(input$btn_pfas_matrix, {
    ok <- run_r_script_step("build_model_matrix.R", "build_model_matrix.R")
    if (ok) pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$btn_pfas_multisource, {
    ok <- run_r_script_step("prepare_multisource_training.R", "prepare_multisource_training.R")
    if (ok) pfas_results_nonce(pfas_results_nonce() + 1L)
  })

  observeEvent(input$btn_validate_python_exec, {
    py_exec_raw <- trimws(input$pfas_python_exec %||% "")
    if (!nzchar(py_exec_raw)) {
      showNotification("Python path is empty.", type = "error")
      return(invisible(NULL))
    }
    py_exec <- resolve_python_exec(py_exec_raw)
    exists_exec <- nzchar(py_exec)
    if (!exists_exec) {
      append_pipeline_log("Python validate: ", py_exec_raw, " | exists=FALSE")
      showNotification("Python not found in this runtime.", type = "error")
      return(invisible(NULL))
    }
    ver <- tryCatch(
      system2(py_exec, args = "--version", stdout = TRUE, stderr = TRUE),
      error = function(e) {
        paste("ERROR:", conditionMessage(e))
      }
    )
    append_pipeline_log("Python validate: ", py_exec, " | exists=", exists_exec, " | ", paste(ver, collapse = " "))
    if (exists_exec && !any(grepl("^ERROR:", ver))) {
      showNotification(paste("Python validated:", paste(ver, collapse = " ")), type = "message")
    } else {
      showNotification("Python validation failed. Check path or environment.", type = "error")
    }
  })

  observeEvent(input$btn_check_intake_api_health, {
    h <- check_intake_api_health(LINK_DATASET_FORM, PFAS_INTAKE_STAGING_TOKEN)
    intake_api_health(h)
    level_to_type <- c(ok = "message", pending = "warning", warning = "warning", disabled = "warning", error = "error")
    notify_type <- level_to_type[[h$level]]
    if (is.null(notify_type)) notify_type <- "warning"
    showNotification(paste(h$summary, "|", h$smoke$summary), type = notify_type)
    append_pipeline_log(
      "Intake API health check: ",
      h$summary,
      " | smoke=",
      h$smoke$status %||% "unknown",
      " | http=",
      as.character(h$smoke$http_status %||% NA),
      " | endpoint=",
      h$endpoint
    )
  })

  observeEvent(input$btn_pfas_run_all, {
    if (!enforce_iso_preflight("Run all steps")) return(invisible(NULL))
    write_audit(
      "pfas_pipeline",
      "run_all",
      "execute_start",
      op_id(),
      "PFAS one-click pipeline started",
      list(trigger = "btn_pfas_run_all")
    )
    ok1 <- run_r_script_step("download_echo_nhanes.R", "download_echo_nhanes.R")
    ok2 <- if (ok1) run_r_script_step("download_epa_ucmr5.R", "download_epa_ucmr5.R") else FALSE
    ok3 <- if (ok2) run_r_script_step("download_epa_echo_api.R", "download_epa_echo_api.R", extra_env = pipeline_env()) else FALSE
    ok4 <- if (ok3) run_r_script_step("download_epa_sdwis.R", "download_epa_sdwis.R", extra_env = pipeline_env()) else FALSE
    ok5 <- if (ok4) run_r_script_step("prepare_nhanes_training.R", "prepare_nhanes_training.R") else FALSE
    ok6 <- if (ok5) run_r_script_step("prepare_multisource_training.R", "prepare_multisource_training.R") else FALSE
    ok7 <- if (ok6) run_r_script_step("build_model_matrix.R", "build_model_matrix.R") else FALSE
    ok8 <- if (ok7) run_python_step() else FALSE
    ok9 <- if (ok8) run_pfas_prediction_step() else FALSE
    ok9a <- if (ok8) run_nist_reference_validation_step() else FALSE
    ok10 <- if (ok9 && ok9a) step_validate_reference_dataset() else FALSE
    ok11 <- if (ok10) step_qc_validation_check() else FALSE
    ok12 <- if (ok11) step_applicability_domain_check() else FALSE
    ok13 <- if (ok12) step_external_pt_validation() else FALSE
    ok14 <- if (ok13) step_generate_iso_compliance_report() else FALSE
    ok15 <- if (ok14) run_ml_validation_report_step() else FALSE
    if (ok1 && ok2 && ok3 && ok4 && ok5 && ok6 && ok7 && ok8 && ok9 && ok9a && ok10 && ok11 && ok12 && ok13 && ok14 && ok15) {
      append_pipeline_log("Pipeline completed successfully.")
      write_audit(
        "pfas_pipeline",
        "run_all",
        "execute_success",
        op_id(),
        "PFAS one-click pipeline completed successfully",
        list(
          download_nhanes = ok1,
          download_ucmr5 = ok2,
          download_echo = ok3,
          download_sdwis = ok4,
          prepare_nhanes = ok5,
          prepare_multisource = ok6,
          matrix = ok7,
          train = ok8,
          predict = ok9,
          nist_reference_validation = ok9a,
          validate_reference_dataset = ok10,
          qc_validation_check = ok11,
          applicability_domain_check = ok12,
          external_pt_validation = ok13,
          generate_iso_compliance_report = ok14,
          generate_ml_validation_report = ok15
        )
      )
      pfas_results_nonce(pfas_results_nonce() + 1L)
    } else {
      append_pipeline_log("Pipeline stopped due to step failure.")
      write_audit(
        "pfas_pipeline",
        "run_all",
        "execute_failure",
        op_id(),
        "PFAS one-click pipeline stopped due to failure",
        list(
          download_nhanes = ok1,
          download_ucmr5 = ok2,
          download_echo = ok3,
          download_sdwis = ok4,
          prepare_nhanes = ok5,
          prepare_multisource = ok6,
          matrix = ok7,
          train = ok8,
          predict = ok9,
          nist_reference_validation = ok9a,
          validate_reference_dataset = ok10,
          qc_validation_check = ok11,
          applicability_domain_check = ok12,
          external_pt_validation = ok13,
          generate_iso_compliance_report = ok14,
          generate_ml_validation_report = ok15
        )
      )
    }
  })

  output$tbl_recent_entries <- renderDT({
    DT::datatable(recent_entries(), options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })
  
  output$tbl_feature_importance <- renderDT({
    df <- feature_importance |>
      dplyr::filter(endpoint == input$mechanistic_endpoint)
    render_dt(df, 8)
  })
  
  output$plot_missingness <- renderPlot(plot_missingness())
  output$plot_class_balance <- renderPlot(plot_class_balance())
  output$plot_bal_acc <- renderPlot(plot_validation_metrics("Balanced_Accuracy"))
  output$plot_prediction_risk <- renderPlot(plot_prediction_risk())
  output$plot_ad_distribution <- renderPlot(plot_ad_distribution())
  output$plot_feature_importance <- renderPlot(plot_feature_importance(input$mechanistic_endpoint))
  
  output$download_ml_export <- downloadHandler(
    filename = function() {
      paste0("pfas_ml_export_", Sys.Date(), ".csv")
    },
    content = function(file) {
      oid <- op_id()
      write_audit(
        "ml_export",
        basename(file),
        "export",
        oid,
        "ML training CSV export",
        list(rows = nrow(ml_export()))
      )
      write.csv(ml_export(), file, row.names = FALSE)
    }
  )

  output$dl_ml_validation_report <- downloadHandler(
    filename = function() {
      "ISO17025_ML_Validation_Report.html"
    },
    content = function(file) {
      src <- file.path(PROJECT_DIR, "results", "ISO17025_ML_Validation_Report.html")
      oid <- op_id()
      if (!file.exists(src)) {
        write_audit(
          "pfas_pipeline",
          "ml_validation_report_download",
          "export_missing",
          oid,
          "ML validation HTML missing at download time",
          list(expected_path = src)
        )
        writeLines(
          c(
            "ISO17025_ML_Validation_Report.html was not found.",
            paste0("Expected: ", normalizePath(src, winslash = "/", mustWork = FALSE)),
            "Use Reports -> 16) Generate ML validation report (HTML), then retry download."
          ),
          con = file
        )
      } else {
        write_audit(
          "pfas_pipeline",
          "ml_validation_report_download",
          "export",
          oid,
          "ML validation HTML downloaded",
          list(source_path = normalizePath(src, winslash = "/", mustWork = FALSE))
        )
        file.copy(src, file, overwrite = TRUE)
      }
    }
  )

  # --- ISO 17025 / EPA 1633 validation UI ---------------------------------
  observe({
    df <- safe_table("epa1633_test_case")
    if (nrow(df) == 0) {
      updateSelectInput(session, "v_test_case_id", choices = c("Run seed or restore DB" = ""))
    } else {
      updateSelectInput(
        session,
        "v_test_case_id",
        choices = stats::setNames(df$test_case_id, paste(df$test_case_id, df$category))
      )
    }
  })

  output$apr_select_ui <- renderUI({
    df <- safe_table("approval_record")
    pend <- df[df$status == "pending", , drop = FALSE]
    if (nrow(pend) == 0) {
      return(selectInput("apr_pick", "Pending approval", choices = c("(none)" = "")))
    }
    selectInput(
      "apr_pick",
      "Pending approval",
      choices = stats::setNames(
        pend$approval_id,
        paste(pend$approval_step, pend$object_type, pend$object_id)
      )
    )
  })

  observeEvent(input$btn_save_validation_result, {
    oid <- op_id()
    req(nzchar(input$v_test_case_id %||% ""))
    tc <- safe_table("epa1633_test_case")
    row <- tc[tc$test_case_id == input$v_test_case_id, , drop = FALSE]
    exp <- if (nrow(row) == 1) row$acceptance_criteria[[1]] else NA_character_
    rid <- make_id("VTR")
    out <- tibble::tibble(
      result_id = rid,
      test_case_id = input$v_test_case_id,
      protocol_ref = input$v_protocol_ref %||% "",
      run_at = as.character(Sys.time()),
      operator = oid,
      expected_result = as.character(exp %||% ""),
      actual_result = input$v_pass_fail,
      pass_fail = input$v_pass_fail,
      evidence_notes = input$v_evidence_notes %||% ""
    )
    DBI::dbWriteTable(con, "validation_test_result", out, append = TRUE)
    write_audit("validation_test_result", rid, "create", oid, "EPA 1633 validation test recorded", list(test = input$v_test_case_id))
    showNotification("Validation result saved.", type = "message")
  })

  observeEvent(input$btn_save_capa, {
    oid <- op_id()
    req(nzchar(input$capa_title %||% ""))
    cid <- make_id("CAPA")
    row <- tibble::tibble(
      capa_id = cid,
      title = input$capa_title,
      description = input$capa_description %||% "",
      status = "open",
      priority = input$capa_priority %||% "Medium",
      opened_at = as.character(Sys.time()),
      opened_by = oid,
      root_cause = NA_character_,
      corrective_action = NA_character_,
      preventive_action = NA_character_,
      effectiveness_check = NA_character_,
      closed_at = NA_character_,
      closed_by = NA_character_,
      linked_entity_type = input$capa_linked_type %||% "",
      linked_entity_id = input$capa_linked_id %||% ""
    )
    DBI::dbWriteTable(con, "capa", row, append = TRUE)
    write_audit("capa", cid, "create", oid, "CAPA opened", list(title = input$capa_title))
    showNotification("CAPA opened.", type = "message")
  })

  observeEvent(input$btn_request_approval, {
    oid <- op_id()
    req(nzchar(input$apr_object_id %||% ""))
    aid <- make_id("APR")
    row <- tibble::tibble(
      approval_id = aid,
      object_type = input$apr_object_type %||% "record",
      object_id = input$apr_object_id,
      approval_step = input$apr_step %||% "QC review",
      status = "pending",
      requested_at = as.character(Sys.time()),
      requested_by = oid,
      decided_at = NA_character_,
      decided_by = NA_character_,
      rationale = NA_character_,
      esig_meaning = NA_character_
    )
    DBI::dbWriteTable(con, "approval_record", row, append = TRUE)
    write_audit("approval_record", aid, "create", oid, "Approval requested", list(step = input$apr_step))
    showNotification("Approval request recorded.", type = "message")
  })

  observeEvent(input$btn_decide_approval, {
    oid <- op_id()
    pick <- input$apr_pick %||% ""
    req(nzchar(pick))
    dec <- input$apr_decision %||% "approved"
    DBI::dbExecute(
      con,
      "UPDATE approval_record SET status = ?, decided_at = ?, decided_by = ?, rationale = ? WHERE approval_id = ?",
      params = list(dec, as.character(Sys.time()), oid, input$apr_rationale %||% "", pick)
    )
    write_audit("approval_record", pick, "update", oid, paste("Approval", dec), list(decision = dec))
    showNotification("Approval decision recorded.", type = "message")
  })

  observeEvent(input$btn_esig, {
    oid <- op_id()
    req(nzchar(input$esig_record_id %||% ""))
    sid <- make_id("ESIG")
    row <- tibble::tibble(
      signature_id = sid,
      record_type = input$esig_record_type %||% "record",
      record_id = input$esig_record_id,
      meaning = input$esig_meaning %||% "signoff",
      signer_id = oid,
      signed_at = as.character(Sys.time()),
      witness_id = NA_character_,
      method_note = "PFAS Enterprise 4.0 UI attestation (map to 21 CFR Part 11 SOP)"
    )
    DBI::dbWriteTable(con, "electronic_signature", row, append = TRUE)
    write_audit("electronic_signature", sid, "create", oid, "Electronic signature applied", list(record = input$esig_record_id))
    showNotification("Electronic signature recorded.", type = "message")
  })

  observeEvent(input$btn_save_qc, {
    oid <- op_id()
    req(nzchar(input$qc_batch_id %||% ""))
    qid <- make_id("QC")
    row <- tibble::tibble(
      qc_id = qid,
      batch_id = input$qc_batch_id,
      method_ref = "EPA 1633",
      matrix = input$qc_matrix %||% "",
      run_date = as.character(input$qc_run_date),
      analyst = oid,
      blanks_ok = as.integer(isTRUE(input$qc_blanks_ok)),
      checks_ok = as.integer(isTRUE(input$qc_checks_ok)),
      cal_verified = as.integer(isTRUE(input$qc_cal_ok)),
      overall_status = input$qc_overall %||% "Accept",
      notes = input$qc_notes %||% "",
      created_at = as.character(Sys.time())
    )
    DBI::dbWriteTable(con, "qc_batch", row, append = TRUE)
    write_audit("qc_batch", qid, "create", oid, "QC batch logged", list(batch = input$qc_batch_id))
    showNotification("QC batch saved.", type = "message")
  })

  observeEvent(input$btn_save_training, {
    oid <- op_id()
    req(nzchar(input$tr_user %||% ""))
    tid <- make_id("TRN")
    row <- tibble::tibble(
      training_id = tid,
      user_id = input$tr_user,
      topic = input$tr_topic %||% "",
      method_ref = "EPA 1633",
      completed_at = as.character(input$tr_completed),
      trainer = input$tr_trainer %||% "",
      expiry_date = if (inherits(input$tr_expiry, "Date") && !is.na(input$tr_expiry)) {
        as.character(input$tr_expiry)
      } else {
        NA_character_
      },
      evidence_ref = input$tr_evidence %||% "",
      quiz_score = NA_real_
    )
    DBI::dbWriteTable(con, "training_record", row, append = TRUE)
    write_audit("training_record", tid, "create", oid, "Training recorded", list(user = input$tr_user))
    showNotification("Training record saved.", type = "message")
  })

  observeEvent(input$btn_save_cal, {
    oid <- op_id()
    req(nzchar(input$cal_instrument %||% ""))
    cid <- make_id("CAL")
    pass <- identical(input$cal_pass, "pass")
    row <- tibble::tibble(
      cal_id = cid,
      instrument_id = input$cal_instrument,
      parameter = input$cal_parameter %||% "",
      nominal_value = input$cal_nominal,
      measured_value = input$cal_measured,
      tolerance_pct = input$cal_tol_pct,
      result_pass = as.integer(pass),
      performed_at = as.character(Sys.time()),
      performed_by = oid,
      standard_ref = "NIST-traceable / vendor SOP",
      cert_ref = input$cal_cert %||% "",
      next_due = if (inherits(input$cal_next, "Date") && !is.na(input$cal_next)) {
        as.character(input$cal_next)
      } else {
        NA_character_
      }
    )
    DBI::dbWriteTable(con, "calibration_log", row, append = TRUE)
    write_audit("calibration_log", cid, "create", oid, "Calibration entry", list(instrument = input$cal_instrument))
    showNotification("Calibration saved.", type = "message")
  })

  output$tbl_epa1633_cases <- renderDT({
    input$btn_save_validation_result
    df <- safe_table("epa1633_test_case")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "No EPA 1633 test cases in DB."), rownames = FALSE))
    }
    render_dt(df, 12)
  })

  output$tbl_validation_results <- renderDT({
    input$btn_save_validation_result
    df <- safe_table("validation_test_result")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "No validation runs recorded."), rownames = FALSE))
    }
    render_dt(df, 10)
  })

  output$tbl_capa <- renderDT({
    input$btn_save_capa
    df <- safe_table("capa")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "No CAPA records."), rownames = FALSE))
    }
    render_dt(df, 10)
  })

  output$tbl_approvals <- renderDT({
    input$btn_decide_approval
    input$btn_request_approval
    df <- safe_table("approval_record")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "No approvals."), rownames = FALSE))
    }
    render_dt(df, 10)
  })

  output$tbl_esig <- renderDT({
    input$btn_esig
    df <- safe_table("electronic_signature")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "No signatures."), rownames = FALSE))
    }
    render_dt(df, 10)
  })

  output$tbl_qc_batch <- renderDT({
    input$btn_save_qc
    df <- safe_table("qc_batch")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "No QC batches."), rownames = FALSE))
    }
    render_dt(df, 10)
  })

  output$tbl_training <- renderDT({
    input$btn_save_training
    df <- safe_table("training_record")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "No training records."), rownames = FALSE))
    }
    render_dt(df, 10)
  })

  output$tbl_calibration <- renderDT({
    input$btn_save_cal
    df <- safe_table("calibration_log")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(note = "No calibration rows."), rownames = FALSE))
    }
    render_dt(df, 10)
  })

  iq_path <- function(...) file.path(PROJECT_DIR, "validation", ...)

  output$dl_iq_template_md <- downloadHandler(
    filename = function() {
      "Installation_Qualification_Template.md"
    },
    content = function(file) {
      p <- iq_path("IQ", "Installation_Qualification_Template.md")
      if (!file.exists(p)) {
        writeLines("# IQ template missing from repository.", file)
      } else {
        file.copy(p, file, overwrite = TRUE)
      }
      oid <- op_id()
      write_audit("iq_template", "Installation_Qualification_Template.md", "export", oid, "IQ template download", list())
    }
  )

  output$dl_epa1633_protocol_md <- downloadHandler(
    filename = function() {
      "EPA_Method_1633_Validation_Protocol.md"
    },
    content = function(file) {
      p <- iq_path("test_cases", "EPA_Method_1633_Validation_Protocol.md")
      if (!file.exists(p)) {
        writeLines("# Protocol missing from repository.", file)
      } else {
        file.copy(p, file, overwrite = TRUE)
      }
      oid <- op_id()
      write_audit("validation_protocol", "EPA_Method_1633_Validation_Protocol.md", "export", oid, "Validation protocol download", list())
    }
  )

  output$dl_epa1633_tests_csv <- downloadHandler(
    filename = function() {
      "EPA_Method_1633_Test_Cases.csv"
    },
    content = function(file) {
      p <- iq_path("test_cases", "EPA_Method_1633_Test_Cases.csv")
      if (!file.exists(p)) {
        utils::write.csv(safe_table("epa1633_test_case"), file, row.names = FALSE)
      } else {
        file.copy(p, file, overwrite = TRUE)
      }
      oid <- op_id()
      write_audit("epa1633_tests", "EPA_Method_1633_Test_Cases.csv", "export", oid, "EPA 1633 test case CSV export", list())
    }
  )

  output$tbl_glp_audit <- renderDT({
    input$glp_verify_chain_btn
    df <- safe_table("glp_audit_trail")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(message = "No GLP audit rows yet."), rownames = FALSE))
    }
    DT::datatable(df, options = list(pageLength = 15, scrollX = TRUE, order = list(list(0, "desc"))), rownames = FALSE)
  })

  output$iso_score_text <- renderPrint({
    if (!file.exists(iso_json_path)) {
      cat("ISO readiness score file not found.\n")
      return(invisible(NULL))
    }
    x <- jsonlite::fromJSON(iso_json_path)
    cat("Readiness score:", x$score, "\n")
    cat("Rating:", x$rating, "\n")
    cat("Critical open findings:", x$open_critical, "\n")
    cat("High open findings:", x$open_high, "\n")
  })

  output$iso_blindspots_table <- DT::renderDataTable({
    if (!file.exists(iso_csv_path)) {
      return(data.frame(message = "No ISO blind spot report found"))
    }
    utils::read.csv(iso_csv_path, stringsAsFactors = FALSE, check.names = FALSE)
  })

  output$iso_disclaimer <- renderUI({
    if (!file.exists(iso_json_path)) {
      return(NULL)
    }
    x <- jsonlite::fromJSON(iso_json_path)
    tags$div(
      style = "margin-top:15px;color:#aa0000;",
      tags$strong("Disclaimer: "),
      x$disclaimer
    )
  })

  output$tbl_legacy_audit <- renderDT({
    input$glp_verify_chain_btn
    df <- safe_table("audit_log")
    if (nrow(df) == 0) {
      return(DT::datatable(tibble::tibble(message = "No legacy audit rows."), rownames = FALSE))
    }
    DT::datatable(df, options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE)
  })

  load_partner_intake_admin <- function(limit_n = 50L) {
    limit_n <- suppressWarnings(as.integer(limit_n %||% 50L))
    if (is.na(limit_n) || limit_n < 10L) limit_n <- 50L
    if (limit_n > 500L) limit_n <- 500L

    src <- "none"
    raw_df <- tibble::tibble()

    if (nzchar(PFAS_PARTNER_AUDIT_SQLITE_TABLE)) {
      tbl_df <- tryCatch(
        safe_table(PFAS_PARTNER_AUDIT_SQLITE_TABLE),
        error = function(e) {
          tibble::tibble()
        }
      )
      if (nrow(tbl_df) > 0) {
        raw_df <- tbl_df
        src <- paste0("SQLite table: ", PFAS_PARTNER_AUDIT_SQLITE_TABLE)
      }
    }

    if (nrow(raw_df) == 0 && nzchar(PFAS_PARTNER_AUDIT_MIRROR_CSV) && file.exists(PFAS_PARTNER_AUDIT_MIRROR_CSV)) {
      csv_df <- tryCatch(
        read.csv(PFAS_PARTNER_AUDIT_MIRROR_CSV, stringsAsFactors = FALSE, check.names = FALSE),
        error = function(e) {
          tibble::tibble()
        }
      )
      if (nrow(csv_df) > 0) {
        raw_df <- tibble::as_tibble(csv_df)
        src <- paste0("CSV mirror: ", normalizePath(PFAS_PARTNER_AUDIT_MIRROR_CSV, winslash = "/", mustWork = FALSE))
      }
    }

    if (nrow(raw_df) == 0) {
      legacy <- tryCatch(
        safe_table("audit_log"),
        error = function(e) {
          tibble::tibble()
        }
      )
      if (nrow(legacy) > 0 && all(c("entity_type", "action_type") %in% names(legacy))) {
        legacy <- dplyr::filter(
          legacy,
          (tolower(entity_type %||% "") %in% c("partner_intake", "partner_intake_submit")) |
            (tolower(action_type %||% "") %in% c("partner_intake", "partner_intake_submit"))
        )
        if (nrow(legacy) > 0) {
          raw_df <- legacy
          src <- "legacy audit_log"
        }
      }
    }

    if (nrow(raw_df) == 0) {
      return(list(
        df = tibble::tibble(note = "No partner intake records found in configured mirrors."),
        status = "No records available. Mirror DynamoDB submissions into SQLite or CSV for this view.",
        source = src,
        rows = 0L
      ))
    }

    names(raw_df) <- tolower(names(raw_df))
    details_col <- intersect(c("details", "detail", "payload", "payload_json"), names(raw_df))
    details_col <- if (length(details_col) > 0) details_col[[1]] else NA_character_

    parse_detail <- function(x) {
      if (is.null(x) || length(x) == 0 || all(is.na(x))) return(list())
      if (is.list(x) && !is.data.frame(x)) return(x)
      sx <- as.character(x)[1]
      if (!nzchar(sx)) return(list())
      tryCatch(
        jsonlite::fromJSON(sx, simplifyVector = TRUE),
        error = function(e) {
          list()
        }
      )
    }
    details_list <- if (!is.na(details_col)) {
      lapply(raw_df[[details_col]], parse_detail)
    } else {
      vector("list", nrow(raw_df))
    }

    detail_field <- function(key) {
      vapply(details_list, function(dd) {
        vv <- dd[[key]]
        if (is.null(vv) || length(vv) == 0 || all(is.na(vv))) "" else as.character(vv)[1]
      }, character(1))
    }

    event_time <- if ("changed_at" %in% names(raw_df)) {
      as.character(raw_df$changed_at)
    } else if ("created_at" %in% names(raw_df)) {
      as.character(raw_df$created_at)
    } else if ("timestamp" %in% names(raw_df)) {
      as.character(raw_df$timestamp)
    } else if ("sk" %in% names(raw_df)) {
      sub("^TS#([^#]+).*$", "\\1", as.character(raw_df$sk))
    } else {
      rep("", nrow(raw_df))
    }

    email <- if ("email" %in% names(raw_df)) as.character(raw_df$email) else detail_field("email")
    if ("pk" %in% names(raw_df)) {
      from_pk <- sub("^CONTACT#", "", as.character(raw_df$pk))
      email <- ifelse(nzchar(email), email, from_pk)
    }

    nr <- nrow(raw_df)
    ip_vec <- if ("ip" %in% names(raw_df)) as.character(raw_df$ip) else rep("", nr)
    msg_raw <- if ("message" %in% names(raw_df)) as.character(raw_df$message) else detail_field("message")

    # Precompute vectors: nested if/else-if inside tibble() can confuse the R parser
    # ("possible missing comma" / sourcing failure on some builds).
    status_vec <- if ("status" %in% names(raw_df)) {
      as.character(raw_df$status)
    } else if ("action_type" %in% names(raw_df)) {
      as.character(raw_df$action_type)
    } else {
      rep("", nr)
    }
    action_vec <- if ("action" %in% names(raw_df)) {
      as.character(raw_df$action)
    } else if ("action_type" %in% names(raw_df)) {
      as.character(raw_df$action_type)
    } else {
      rep("", nr)
    }

    name_vec <- if ("name" %in% names(raw_df)) as.character(raw_df$name) else detail_field("name")
    organization_vec <- if ("organization" %in% names(raw_df)) {
      as.character(raw_df$organization)
    } else {
      detail_field("organization")
    }
    submission_id_vec <- if ("submission_id" %in% names(raw_df)) {
      as.character(raw_df$submission_id)
    } else {
      detail_field("submission_id")
    }
    row_source_vec <- if ("source" %in% names(raw_df)) {
      as.character(raw_df$source)
    } else {
      detail_field("source")
    }

    out <- tibble::tibble(
      event_time = event_time,
      status = status_vec,
      email = email,
      name = name_vec,
      organization = organization_vec,
      submission_id = submission_id_vec,
      source = row_source_vec,
      action = action_vec,
      ip = ip_vec,
      message_excerpt = substr(msg_raw, 1L, 180L)
    ) |>
      dplyr::arrange(dplyr::desc(event_time)) |>
      utils::head(limit_n)

    list(
      df = out,
      status = paste0("Source: ", src, " | Rows shown: ", nrow(out), " | Checked: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
      source = src,
      rows = nrow(out)
    )
  }

  partner_audit_snapshot <- reactiveVal(load_partner_intake_admin(50L))
  partner_audit_bootstrapped <- reactiveVal(FALSE)

  observe({
    if (isTRUE(partner_audit_bootstrapped())) return(invisible(NULL))
    partner_audit_bootstrapped(TRUE)
    partner_audit_snapshot(load_partner_intake_admin(isolate(input$partner_audit_limit %||% 50L)))
  })

  observeEvent(input$btn_partner_audit_refresh, {
    if (!isTRUE(auth$admin)) {
      showNotification("Admin privileges are required for partner intake operational review.", type = "error")
      return(invisible(NULL))
    }
    snap <- load_partner_intake_admin(input$partner_audit_limit %||% 50L)
    partner_audit_snapshot(snap)
    showNotification("Partner intake admin view refreshed.", type = "message")
  })

  output$partner_audit_status <- renderPrint({
    req(auth$user)
    if (!isTRUE(auth$admin)) {
      cat("Admin access required for this panel.\n")
      return(invisible(NULL))
    }
    snap <- partner_audit_snapshot()
    cat(snap$status %||% "No status available.", "\n")
    if (!identical(snap$source, "none")) {
      cat("Tip: set PFAS_PARTNER_AUDIT_SQLITE_TABLE or PFAS_PARTNER_AUDIT_MIRROR_CSV to control data source.\n")
    }
  })

  output$tbl_partner_intake_admin <- renderDT({
    req(auth$user)
    if (!isTRUE(auth$admin)) {
      return(DT::datatable(tibble::tibble(note = "Admin access required."), rownames = FALSE))
    }
    snap <- partner_audit_snapshot()
    render_dt(snap$df, 10)
  })

  output$glp_chain_status <- renderPrint({
    if (is.null(input$glp_verify_chain_btn) || input$glp_verify_chain_btn == 0) {
      cat("Click 'Re-verify hash chain' to validate SHA-256 linkage from GENESIS.\n")
      return(invisible(NULL))
    }
    if (!exists("glp_verify_chain", mode = "function")) {
      cat("glp_audit.R not loaded.\n")
      return(invisible(NULL))
    }
    print(glp_verify_chain(con))
  })

  output$dl_glp_audit_csv <- downloadHandler(
    filename = function() {
      paste0("glp_audit_trail_", Sys.Date(), ".csv")
    },
    content = function(file) {
      oid <- op_id()
      write_audit(
        "glp_audit_trail",
        "full_table",
        "export",
        oid,
        "GLP audit trail CSV export",
        list(rows = nrow(safe_table("glp_audit_trail")))
      )
      utils::write.csv(safe_table("glp_audit_trail"), file, row.names = FALSE)
    }
  )
}

shinyApp(ui, server)
