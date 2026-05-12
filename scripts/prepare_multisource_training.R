# Merge normalized external uploads, training master, and EPA ICIS-NPDES PFAS-filtered DMR exports
# into data/training/pfas_multisource_training.csv + progress JSON for the Shiny target tracker.
#
# Inputs (optional):
#   data/processed/pfas_training_master.csv
#   data/external_uploads/*_normalized.csv
#   data/processed/npdes_dmr_pfas_fy*.csv   (from scripts/filter_npdes_dmr_pfas.py)
#
# SOP (matrix separation): data/config/matrix_pipeline_sop.csv — do NOT merge distinct
# pipeline lanes into one generalized PFAS prediction pool. Each input part is classified
# into a pipeline_id; if more than one non-unknown lane would be combined, this script
# stops unless PFAS_ALLOW_MULTISOURCE_MERGE=1 (escape hatch for exploratory work only).
#
# NHANES serum training remains separate (train_nhanes_serum_pfas.py); this file still
# must not mix serum biomonitoring rows with UCMR / OTM-50 / NIST lanes in one CSV.

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
  "health_endpoint", "health_value", "dataset_type", "upload_id", "uploaded_at",
  "pipeline_lane"
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
  nr <- nrow(df)
  num_cols <- c("result_value", "mdl", "rl", "health_value", "latitude", "longitude")
  for (cn in schema_cols) {
    if (!cn %in% names(df)) {
      if (cn %in% num_cols) {
        df[[cn]] <- rep(NA_real_, nr)
      } else if (identical(cn, "detect_flag")) {
        df[[cn]] <- rep(NA_integer_, nr)
      } else {
        df[[cn]] <- rep(NA_character_, nr)
      }
    }
  }
  df[, schema_cols, drop = FALSE]
}

# Stable types across master vs new uploads so do.call(rbind, parts) does not fail (exit 1).

# Classify one merged part into a single SOP pipeline_id (see matrix_pipeline_sop.csv).
# Uses up to 500 rows for speed. Returns one of: drinking_water, serum, biosolids_sludge,
# afff, methanol_standards, air_emissions, wastewater_npdes, unknown, empty.
infer_matrix_pipeline_lane <- function(df, part_tag = "") {
  if (is.null(df) || nrow(df) == 0L) {
    return("empty")
  }
  n <- min(500L, nrow(df))
  mat <- tolower(trimws(as.character(df$matrix[seq_len(n)])))
  src <- tolower(trimws(as.character(df$source[seq_len(n)])))
  sds <- tolower(trimws(as.character(df$source_dataset[seq_len(n)])))
  dtype <- tolower(trimws(as.character(df$dataset_type[seq_len(n)])))
  tag <- tolower(as.character(part_tag)[1])

  any_src <- function(pat) {
    any(grepl(pat, c(src, sds, tag), perl = TRUE), na.rm = TRUE)
  }
  any_mat <- function(pat) {
    any(grepl(pat, mat, perl = TRUE), na.rm = TRUE)
  }

  if (any_src("nhanes") || any(dtype == "human biomonitoring", na.rm = TRUE) ||
    sum(grepl("^(serum|plasma|blood)(/|$)|serum|plasma|whole blood", mat), na.rm = TRUE) > n * 0.25) {
    return("serum")
  }
  if (any_src("^epa_icis_npdes_dmr|epa_icis_npdes_dmr") ||
    (any_mat("^npdes_effluent|npdes effluent") && any_src("icis|npdes"))) {
    return("wastewater_npdes")
  }
  if (any_src("ucmr|ucmr5") || any_mat("finished|distribution|tap|potable|drinking|raw water|groundwater|gw|surface water")) {
    return("drinking_water")
  }
  if (any_mat("sludge|biosolid|residual")) {
    return("biosolids_sludge")
  }
  if (any_mat("afff|\\bfoam\\b") || any_src("rm.?8690|8690|afff")) {
    return("afff")
  }
  if (any_mat("methanol|calibration") || any_src("8446|rm.?8446")) {
    return("methanol_standards")
  }
  if (any_src("otm.?50|otm50") || any_mat("stack|air emission|air_emissions|stack gas")) {
    return("air_emissions")
  }
  if (any_mat("npdes_effluent|wastewater effluent|effluent")) {
    return("wastewater_npdes")
  }
  "unknown"
}

tag_part_with_pipeline_lane <- function(df, lane) {
  if (is.null(df) || nrow(df) == 0L) {
    return(df)
  }
  df$pipeline_lane <- rep(as.character(lane), nrow(df))
  df
}

enforce_sop_single_pipeline <- function(lanes, allow_merge_env) {
  lanes <- unique(trimws(as.character(lanes)))
  lanes <- lanes[!is.na(lanes) & nzchar(lanes)]
  sig <- setdiff(lanes, c("empty", "unknown"))
  if (length(sig) <= 1L) {
    return(invisible(TRUE))
  }
  if (nzchar(allow_merge_env) && tolower(allow_merge_env) %in% c("1", "true", "yes")) {
    message(
      "WARNING: multiple pipeline lanes merged (PFAS_ALLOW_MULTISOURCE_MERGE). ",
      "SOP matrix separation is bypassed — not for evidence-governed training."
    )
    return(invisible(TRUE))
  }
  stop(
    "prepare_multisource_training: SOP matrix separation (data/config/matrix_pipeline_sop.csv) ",
    "forbids combining these pipeline lanes in one pfas_multisource_training.csv: ",
    paste(sort(sig), collapse = ", "),
    ". Use one lane per build (e.g. only UCMR *or* only ICIS DMR), or set PFAS_ALLOW_MULTISOURCE_MERGE=1 ",
    "for exploratory screening only."
  )
}

coerce_multisource_row_types <- function(df) {
  if (is.null(df) || nrow(df) == 0L) {
    return(df)
  }
  for (cn in c("result_value", "mdl", "rl", "health_value", "latitude", "longitude")) {
    if (cn %in% names(df)) {
      df[[cn]] <- suppressWarnings(as.numeric(df[[cn]]))
    }
  }
  if ("detect_flag" %in% names(df)) {
    df[["detect_flag"]] <- suppressWarnings(as.integer(df[["detect_flag"]]))
  }
  df
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
    pipeline_lane = "wastewater_npdes",
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  align_schema(out)
}

parts <- list()
part_lanes <- character(0)
allow_merge <- Sys.getenv("PFAS_ALLOW_MULTISOURCE_MERGE", "")

mp <- file.path(proc_dir, "pfas_training_master.csv")
if (file.exists(mp)) {
  x <- read_csv_try(mp)
  if (!is.null(x)) {
    ax <- coerce_multisource_row_types(align_schema(x))
    lane <- infer_matrix_pipeline_lane(ax, "pfas_training_master.csv")
    part_lanes <- c(part_lanes, lane)
    parts <- c(parts, list(tag_part_with_pipeline_lane(ax, lane)))
  }
}

norm_files <- Sys.glob(file.path(ext_upload_dir, "*_normalized.csv"))
for (nf in norm_files) {
  x <- read_csv_try(nf)
  if (!is.null(x)) {
    ax <- coerce_multisource_row_types(align_schema(x))
    lane <- infer_matrix_pipeline_lane(ax, basename(nf))
    part_lanes <- c(part_lanes, lane)
    parts <- c(parts, list(tag_part_with_pipeline_lane(ax, lane)))
  }
}

dmr_files <- Sys.glob(file.path(proc_dir, "npdes_dmr_pfas_fy*.csv"))
for (df_path in dmr_files) {
  raw <- read_csv_try(df_path)
  if (!is.null(raw)) {
    ax <- coerce_multisource_row_types(dmr_to_normalized(raw, basename(df_path)))
    lane <- infer_matrix_pipeline_lane(ax, basename(df_path))
    part_lanes <- c(part_lanes, lane)
    parts <- c(parts, list(tag_part_with_pipeline_lane(ax, lane)))
  }
}

enforce_sop_single_pipeline(part_lanes, allow_merge)

if (length(parts) == 0L) {
  out <- empty_frame()
} else {
  out <- tryCatch(
    do.call(rbind, parts),
    error = function(e) {
      message("prepare_multisource_training rbind failed: ", conditionMessage(e))
      message("Part column classes (first 3 parts): ")
      for (i in head(seq_along(parts), 3L)) {
        pi <- parts[[i]]
        cls <- vapply(pi, function(v) class(v)[[1L]], character(1L))
        message("  part ", i, ": ", paste(names(cls), "=", cls, collapse = "; "))
      }
      stop(conditionMessage(e))
    }
  )
}

# Post-guard: rows must not carry conflicting pipeline_lane tags (belt + suspenders).
# Skip when the operator explicitly bypassed SOP separation via PFAS_ALLOW_MULTISOURCE_MERGE=1.
sop_bypassed <- nzchar(allow_merge) && tolower(allow_merge) %in% c("1", "true", "yes")
if (!sop_bypassed && nrow(out) > 0L && "pipeline_lane" %in% names(out)) {
  ul <- unique(trimws(as.character(out$pipeline_lane)))
  ul <- ul[!is.na(ul) & nzchar(ul)]
  ul_sig <- setdiff(ul, c("unknown", "empty"))
  if (length(ul_sig) > 1L) {
    stop(
      "prepare_multisource_training: output rows carry multiple distinct pipeline_lane values: ",
      paste(sort(ul_sig), collapse = ", "),
      ". This should not happen after part-level enforcement — report as a bug."
    )
  }
}

# de-dupe loose key (keep columns in a vector to avoid fragile nested quoting)
if (nrow(out) > 0L) {
  dedup_key <- c("source", "sample_id", "analyte", "result_value", "sample_date")
  out <- out[!duplicated(out[, dedup_key, drop = FALSE]), , drop = FALSE]
}

out_fp <- file.path(train_dir, "pfas_multisource_training.csv")
utils::write.csv(out, out_fp, row.names = FALSE)

nr <- nrow(out)
tg <- 100000000L
pct <- if (tg > 0) 100 * nr / tg else 0
sig_lanes <- unique(setdiff(trimws(part_lanes), c("", "empty", "unknown")))
prog <- list(
  current_rows = nr,
  target_rows = tg,
  pct_of_target_raw = pct,
  rows_remaining = max(0L, tg - nr),
  rows_above_target = max(0L, nr - tg),
  generated_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  sources_merged = length(parts),
  pipeline_lanes_per_part = as.list(part_lanes),
  pipeline_lane_effective = if (length(sig_lanes) == 1L) {
    sig_lanes[[1]]
  } else if (length(sig_lanes) == 0L) {
    "none"
  } else {
    paste(sig_lanes, collapse = "|")
  },
  sop_merge_bypassed = isTRUE(sop_bypassed),
  note = paste0(
    "SOP matrix separation: one pipeline per pfas_multisource_training.csv (see data/config/matrix_pipeline_sop.csv). ",
    "Includes EPA ICIS-NPDES PFAS-filtered DMR rows when npdes_dmr_pfas_fy*.csv present."
  )
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
