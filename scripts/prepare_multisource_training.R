# Merge normalized external uploads, training master, and EPA ICIS-NPDES PFAS-filtered DMR exports
# into data/training/pfas_multisource_training.csv + progress JSON for the Shiny target tracker.
#
# Inputs (optional):
#   data/processed/pfas_training_master.csv
#   data/external_uploads/*_normalized.csv
#   data/processed/npdes_dmr_pfas_fy*.csv   (from scripts/filter_npdes_dmr_pfas.py)
#
# Does not mix NHANES serum XPT rows with environmental tables (different universe).

root <- getwd()
proc_dir <- file.path(root, "data", "processed")
train_dir <- file.path(root, "data", "training")
ext_upload_dir <- file.path(root, "data", "external_uploads")
dir.create(train_dir, recursive = TRUE, showWarnings = FALSE)

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

schema_cols <- c(
  "source", "source_dataset", "sample_id", "matrix", "sample_date",
  "analyte", "cas", "result_value", "result_unit", "qualifier",
  "mdl", "rl", "detect_flag", "state", "county", "latitude", "longitude",
  "region", "facility_water_type", "sample_point_type", "method_id",
  "collection_year", "collection_month", "pws_size", "facility_id", "sample_point_id",
  "health_endpoint", "health_value", "dataset_type", "upload_id", "uploaded_at"
)

empty_frame <- function() {
  df <- as.data.frame(matrix(ncol = length(schema_cols), nrow = 0L))
  names(df) <- schema_cols
  df
}

read_csv_try <- function(path) {
  if (!file.exists(path)) {
    return(NULL)
  }
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

align_schema <- function(df) {
  if (is.null(df) || nrow(df) == 0L) {
    return(empty_frame())
  }
  for (cn in schema_cols) {
    if (!cn %in% names(df)) {
      df[[cn]] <- NA_character_
    }
  }
  df[, schema_cols, drop = FALSE]
}

# --- DMR PFAS exports: map ICIS column names (case-insensitive) ---

norm_names <- function(nm) {
  tolower(gsub("[^a-z0-9]", "", nm))
}

dmr_to_normalized <- function(df, src_label) {
  if (is.null(df) || nrow(df) == 0L) {
    return(empty_frame())
  }
  cn <- names(df)
  nn <- norm_names(cn)
  pick <- function(candidates) {
    for (cand in candidates) {
      k <- norm_names(cand)
      hit <- which(nn == k)
      if (length(hit)) {
        return(cn[[hit[1]]])
      }
    }
    ""
  }

  col_perm <- pick(c("EXTERNAL_PERMIT_NMBR", "external_permit_nmbr"))
  col_feat <- pick(c("PERM_FEATURE_NMBR", "perm_feature_nmbr"))
  col_pend <- pick(c("MONITORING_PERIOD_END_DATE", "monitoring_period_end_date"))
  col_paramc <- pick(c("PARAMETER_CODE", "parameter_code"))
  col_paramd <- pick(c("PARAMETER_DESC", "parameter_desc"))
  col_dmr_std <- pick(c("DMR_VALUE_STANDARD_UNITS", "dmr_value_standard_units"))
  col_dmr_num <- pick(c("DMR_VALUE_NMBR", "dmr_value_nmbr"))
  col_dmr_unit <- pick(c("DMR_UNIT_DESC", "dmr_unit_desc", "STANDARD_UNIT_DESC", "standard_unit_desc"))
  col_qual <- pick(c("DMR_VALUE_QUALIFIER_CODE", "dmr_value_qualifier_code"))

  permit <- if (nzchar(col_perm)) as.character(df[[col_perm]]) else rep(NA_character_, nrow(df))
  feat <- if (nzchar(col_feat)) as.character(df[[col_feat]]) else rep(NA_character_, nrow(df))
  pend <- if (nzchar(col_pend)) as.character(df[[col_pend]]) else rep(NA_character_, nrow(df))
  pc <- if (nzchar(col_paramc)) as.character(df[[col_paramc]]) else rep(NA_character_, nrow(df))
  pd <- if (nzchar(col_paramd)) as.character(df[[col_paramd]]) else rep(NA_character_, nrow(df))
  analyte <- ifelse(nzchar(pd), pd, ifelse(nzchar(pc), paste0("PARAM_", pc), "unknown"))

  rv <- rep(NA_real_, nrow(df))
  if (nzchar(col_dmr_std)) {
    rv <- suppressWarnings(as.numeric(df[[col_dmr_std]]))
  }
  if (anyNA(rv) && nzchar(col_dmr_num)) {
    rv2 <- suppressWarnings(as.numeric(df[[col_dmr_num]]))
    rv[is.na(rv)] <- rv2[is.na(rv)]
  }

  ru <- if (nzchar(col_dmr_unit)) as.character(df[[col_dmr_unit]]) else rep(NA_character_, nrow(df))
  qual <- if (nzchar(col_qual)) as.character(df[[col_qual]]) else rep(NA_character_, nrow(df))

  sid <- paste(
    permit %||% "",
    feat %||% "",
    pend %||% "",
    sep = "__"
  )

  out <- data.frame(
    source = "epa_icis_npdes_dmr",
    source_dataset = src_label,
    sample_id = sid,
    matrix = "npdes_effluent",
    sample_date = pend,
    analyte = analyte,
    cas = NA_character_,
    result_value = rv,
    result_unit = tolower(trimws(ru)),
    qualifier = qual,
    mdl = NA_real_,
    rl = NA_real_,
    detect_flag = NA_integer_,
    state = NA_character_,
    county = NA_character_,
    latitude = NA_real_,
    longitude = NA_real_,
    region = NA_character_,
    facility_water_type = NA_character_,
    sample_point_type = NA_character_,
    method_id = "ICIS_DMR",
    collection_year = NA_character_,
    collection_month = NA_character_,
    pws_size = NA_character_,
    facility_id = permit,
    sample_point_id = feat,
    health_endpoint = NA_character_,
    health_value = NA_real_,
    dataset_type = "environmental occurrence",
    upload_id = NA_character_,
    uploaded_at = NA_character_,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  align_schema(out)
}

parts <- list()

mp <- file.path(proc_dir, "pfas_training_master.csv")
if (file.exists(mp)) {
  parts <- c(parts, list(align_schema(read_csv_try(mp))))
}

norm_files <- Sys.glob(file.path(ext_upload_dir, "*_normalized.csv"))
for (nf in norm_files) {
  parts <- c(parts, list(align_schema(read_csv_try(nf))))
}

dmr_files <- Sys.glob(file.path(proc_dir, "npdes_dmr_pfas_fy*.csv"))
for (df_path in dmr_files) {
  raw <- read_csv_try(df_path)
  parts <- c(parts, list(dmr_to_normalized(raw, basename(df_path))))
}

if (length(parts) == 0L) {
  out <- empty_frame()
} else {
  out <- do.call(rbind, parts)
}

# de-dupe loose key
if (nrow(out) > 0L) {
  out <- out[!duplicated(out[c("source", "sample_id", "analyte", "result_value", "sample_date)]), , drop = FALSE]
}

out_fp <- file.path(train_dir, "pfas_multisource_training.csv")
utils::write.csv(out, out_fp, row.names = FALSE)

nr <- nrow(out)
tg <- 100000000L
pct <- if (tg > 0) 100 * nr / tg else 0
prog <- list(
  current_rows = nr,
  target_rows = tg,
  pct_of_target_raw = pct,
  rows_remaining = max(0L, tg - nr),
  rows_above_target = max(0L, nr - tg),
  generated_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  sources_merged = length(parts),
  note = "Includes EPA ICIS-NPDES PFAS-filtered DMR rows when npdes_dmr_pfas_fy*.csv present."
)

json_path <- file.path(train_dir, "pfas_training_target_progress.json")
if (requireNamespace("jsonlite", quietly = TRUE)) {
  jsonlite::write_json(prog, json_path, pretty = TRUE, auto_unbox = TRUE)
} else {
  utils::writeLines(
    c(
      "{",
      paste0('  "current_rows": ', nr, ","),
      paste0('  "target_rows": ', tg),
      "}"
    ),
    json_path
  )
}

message(
  "Wrote ",
  nr,
  " rows to ",
  normalizePath(out_fp, winslash = "/", mustWork = FALSE)
)
