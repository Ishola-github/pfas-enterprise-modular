# Anchor + lane-registry invariants smoke.
#
# This smoke enforces the "kept honest" claims about the
# physiological-classification stamp:
#
#   (1) The v1.0 governance anchor at
#       data/training/serum/nhanes_serum_pfas_2017_2018.csv is byte-for-byte
#       unchanged. Its SHA-256 still equals the value committed to
#       validation/serum_v1/provenance.md.
#   (2) schema_contract.md \u00a78 still defers to provenance.md for the
#       promotion-gate hash (i.e. nobody edited the promotion gate to
#       point at a different file).
#   (3) The stamp lives ONLY in the built training table
#       (data/training/serum/training.csv), NOT in the anchor CSV. The
#       anchor's header is unchanged.
#   (4) PHYSIOLOGICAL_LANE_STAMPS is intentionally narrow: it has exactly
#       one key, "serum", in BOTH the Python pipeline
#       (scripts/run_matrix_pipeline.py) and the R Shiny app
#       (LatestPFAS.R). No environmental-occurrence or reference-material
#       lane has been added to the registry.
#   (5) No env / ref-material manifest carries a `physiological_classification`
#       block. No env / ref-material training.csv carries the five stamp
#       columns. Their `lane_kind` is still environmental_occurrence or
#       reference_material.
#   (6) The Python pipeline's CANONICAL_OUTPUT_COLUMNS is unchanged in
#       width (28). The stamp columns are surfaced only via the per-lane
#       `extra_columns` mechanism.
#
# Run from project root:
#   Rscript scripts/smoke_serum_anchor_invariants.R
#
# Governance anchors:
#   - validation/serum_v1/schema_contract.md \u00a78 (promotion gate)
#   - validation/serum_v1/provenance.md \u00a73 (anchor hash table)
#   - data/config/matrix_pipeline_sop.csv (lane_kind partition)

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  install.packages("jsonlite",
                   repos = c(CRAN = "https://cloud.r-project.org"))
}
if (!requireNamespace("digest", quietly = TRUE)) {
  install.packages("digest",
                   repos = c(CRAN = "https://cloud.r-project.org"))
}

repo_root <- normalizePath(getwd(), winslash = "/")

ANCHOR_CSV_REL <- "data/training/serum/nhanes_serum_pfas_2017_2018.csv"
ANCHOR_CSV_DOCUMENTED_SHA256 <-
  "dfd4dbb59128043e91870265acc15f91f673ec81ee3d00d91223022755e4490f"
PHYSIOLOGICAL_CLASSIFICATION_FIELDS <- c(
  "sample_domain", "sample_matrix", "measurement_context",
  "source_program", "governance_lane"
)
ENVIRONMENTAL_LANES <- c("drinking_water", "biosolids_sludge", "air_emissions")
REFERENCE_LANES     <- c("afff", "methanol_standards")
NONPHYSIOLOGICAL_LANES <- c(ENVIRONMENTAL_LANES, REFERENCE_LANES)

read_text <- function(path) {
  paste(readLines(path, warn = FALSE, encoding = "UTF-8"),
        collapse = "\n")
}

csv_header_cols <- function(path) {
  if (!file.exists(path)) return(character(0))
  hdr <- readLines(path, n = 1, warn = FALSE)
  if (length(hdr) < 1) return(character(0))
  strsplit(hdr, ",", fixed = TRUE)[[1]]
}

# ---- collected resources ---------------------------------------------
anchor_csv_path <- file.path(repo_root, ANCHOR_CSV_REL)
provenance_md   <- file.path(repo_root, "validation/serum_v1/provenance.md")
schema_md       <- file.path(repo_root, "validation/serum_v1/schema_contract.md")
schema_json     <- file.path(repo_root, "validation/serum_v1/schema_contract.json")
run_pipeline_py <- file.path(repo_root, "scripts/run_matrix_pipeline.py")
latest_app_r    <- file.path(repo_root, "LatestPFAS.R")
serum_manifest  <- file.path(repo_root, "data/training/serum/manifest.json")

checks <- list(

  # ---------- (1) Anchor CSV byte-for-byte unchanged --------------------
  list(
    name = "anchor_csv_exists",
    ok = file.exists(anchor_csv_path)
  ),
  list(
    name = "anchor_csv_sha256_matches_documented_value",
    ok = {
      if (!file.exists(anchor_csv_path)) FALSE else {
        h <- tolower(digest::digest(file = anchor_csv_path, algo = "sha256"))
        identical(h, tolower(ANCHOR_CSV_DOCUMENTED_SHA256))
      }
    }
  ),
  list(
    name = "provenance_md_cites_documented_hash",
    ok = {
      if (!file.exists(provenance_md)) FALSE else {
        grepl(ANCHOR_CSV_DOCUMENTED_SHA256, read_text(provenance_md),
              fixed = TRUE)
      }
    }
  ),

  # ---------- (2) Promotion gate untouched ------------------------------
  list(
    name = "schema_contract_md_section_8_still_defers_to_provenance",
    ok = {
      if (!file.exists(schema_md)) FALSE else {
        txt <- read_text(schema_md)
        grepl("## 8. Promotion gate", txt, fixed = TRUE) &&
          grepl("nhanes_serum_pfas_2017_2018.csv", txt, fixed = TRUE) &&
          grepl("provenance.md", txt, fixed = TRUE)
      }
    }
  ),
  list(
    # Make sure nobody silently swapped the promotion-gate file pointer.
    name = "schema_contract_md_section_8_does_not_point_at_training_csv",
    ok = {
      if (!file.exists(schema_md)) FALSE else {
        # Grab \u00a78 only (between "## 8" and the next "## ").
        lines <- readLines(schema_md, warn = FALSE, encoding = "UTF-8")
        start <- grep("^## 8\\.", lines)
        if (length(start) < 1L) FALSE else {
          rest <- lines[(start[1L] + 1L):length(lines)]
          end_rel <- grep("^## ", rest)
          end <- if (length(end_rel) > 0L) start[1L] + end_rel[1L] - 1L
                 else length(lines)
          section <- paste(lines[start[1L]:end], collapse = "\n")
          # Section 8 points at the anchor; must NOT point at the built
          # training table (which carries the stamp and a different hash).
          !grepl("training\\.csv", section, perl = TRUE)
        }
      }
    }
  ),

  # ---------- (3) Anchor header unchanged (no stamp columns) ------------
  list(
    name = "anchor_csv_header_does_NOT_contain_stamp_columns",
    ok = {
      hdr <- csv_header_cols(anchor_csv_path)
      length(hdr) > 0L &&
        !any(PHYSIOLOGICAL_CLASSIFICATION_FIELDS %in% hdr)
    }
  ),
  list(
    # provenance.md \u00a73 says the anchor has 20 columns. Verify the file on
    # disk still has 20 columns.
    name = "anchor_csv_column_count_is_20",
    ok = {
      hdr <- csv_header_cols(anchor_csv_path)
      length(hdr) == 20L
    }
  ),
  list(
    # provenance.md \u00a73 says the anchor has 2,133 data rows + 1 header.
    # Use a streaming line count so this works on Windows without
    # loading the whole file.
    name = "anchor_csv_data_row_count_is_2133",
    ok = {
      if (!file.exists(anchor_csv_path)) FALSE else {
        con <- file(anchor_csv_path, "r")
        on.exit(close(con), add = TRUE)
        n <- 0L
        repeat {
          chunk <- readLines(con, n = 65536L, warn = FALSE)
          if (length(chunk) == 0L) break
          n <- n + length(chunk)
        }
        # 1 header + 2133 data rows = 2134 lines
        identical(n, 2134L)
      }
    }
  ),

  # ---------- (4) Lane registry is narrow (Python + R) ------------------
  list(
    name = "python_pipeline_lane_stamps_registry_only_serum",
    ok = {
      if (!file.exists(run_pipeline_py)) FALSE else {
        txt <- read_text(run_pipeline_py)
        # Match the registry block; require it to declare exactly
        # one key, "serum".
        m <- regmatches(
          txt,
          regexpr(
            "PHYSIOLOGICAL_LANE_STAMPS: dict\\[str, dict\\[str, str\\]\\] = \\{[^}]*\\}",
            txt, perl = TRUE
          )
        )
        if (length(m) < 1L || !nzchar(m)) FALSE else {
          keys <- regmatches(m, gregexpr('"[^"]+":', m, perl = TRUE))[[1]]
          identical(keys, c('"serum":'))
        }
      }
    }
  ),
  list(
    name = "python_pipeline_serum_stamp_values_canonical",
    ok = {
      if (!file.exists(run_pipeline_py)) FALSE else {
        txt <- read_text(run_pipeline_py)
        grepl('"sample_domain":       "physiological"', txt, fixed = TRUE) &&
          grepl('"sample_matrix":       "human_serum"',
                txt, fixed = TRUE) &&
          grepl('"measurement_context": "biomonitoring"',
                txt, fixed = TRUE) &&
          grepl('"source_program":      "CDC NHANES"',
                txt, fixed = TRUE) &&
          grepl('"governance_lane":     "serum_v1"', txt, fixed = TRUE)
      }
    }
  ),
  list(
    name = "python_pipeline_stamp_does_not_carry_units_field",
    # The previous schema had `"units": "ng/mL"` in the stamp. Now
    # units are a row property (canonical `result_unit`). If anyone
    # re-introduces a stamp-level units field, this check fails.
    ok = {
      if (!file.exists(run_pipeline_py)) FALSE else {
        txt <- read_text(run_pipeline_py)
        # Locate the stamp literal and require it to NOT have a
        # "units": key. Use the SERUM_PHYSIOLOGICAL_STAMP dict literal
        # specifically (not the unrelated "units" -> "ng/mL" in
        # row-dicts elsewhere).
        m <- regmatches(
          txt,
          regexpr(
            "SERUM_PHYSIOLOGICAL_STAMP: dict\\[str, str\\] = \\{[^}]*\\}",
            txt, perl = TRUE
          )
        )
        length(m) >= 1L && nzchar(m) && !grepl('"units":', m, fixed = TRUE)
      }
    }
  ),
  list(
    name = "r_app_lane_stamps_registry_only_serum",
    ok = {
      if (!file.exists(latest_app_r)) FALSE else {
        # Source the file in a sandbox env and check the registry's keys
        # by symbolic inspection. Sourcing the whole app is heavy
        # because of Shiny dependencies, so parse instead and walk to
        # the registry assignment.
        env <- new.env()
        # Pull out the registry literal via regex and eval it.
        txt <- read_text(latest_app_r)
        m <- regmatches(
          txt,
          regexpr(
            "PHYSIOLOGICAL_LANE_STAMPS <- list\\([^\\)]*\\)",
            txt, perl = TRUE
          )
        )
        if (length(m) < 1L || !nzchar(m)) FALSE else {
          # Replace SERUM_PHYSIOLOGICAL_STAMP reference with a stub so
          # eval doesn't need the rest of the file.
          stub <- gsub("SERUM_PHYSIOLOGICAL_STAMP", "list(stub = TRUE)",
                       m, fixed = TRUE)
          parsed <- try(eval(parse(text = stub), envir = env),
                        silent = TRUE)
          if (inherits(parsed, "try-error")) FALSE
          else identical(names(parsed), "serum")
        }
      }
    }
  ),
  list(
    name = "r_app_lane_stamp_function_reads_from_registry",
    # Ensures nobody bypasses the registry by hand-coding lanes in the
    # function body again.
    ok = {
      if (!file.exists(latest_app_r)) FALSE else {
        txt <- read_text(latest_app_r)
        grepl("PHYSIOLOGICAL_LANE_STAMPS[[lane]]", txt, fixed = TRUE)
      }
    }
  ),

  # ---------- (5) Env / reference lanes were not modified --------------
  list(
    name = "all_env_ref_manifests_have_correct_lane_kind",
    ok = {
      ok <- TRUE
      for (lane in NONPHYSIOLOGICAL_LANES) {
        mf <- file.path(repo_root, "data", "training", lane, "manifest.json")
        if (!file.exists(mf)) { ok <- FALSE; break }
        m <- jsonlite::fromJSON(mf, simplifyVector = TRUE)
        expected <- if (lane %in% ENVIRONMENTAL_LANES)
                       "environmental_occurrence"
                    else "reference_material"
        if (!identical(m$lane_kind, expected)) { ok <- FALSE; break }
      }
      ok
    }
  ),
  list(
    name = "no_env_ref_manifest_carries_physiological_classification",
    ok = {
      bad <- character(0)
      for (lane in NONPHYSIOLOGICAL_LANES) {
        mf <- file.path(repo_root, "data", "training", lane, "manifest.json")
        if (!file.exists(mf)) { bad <- c(bad, lane); next }
        m <- jsonlite::fromJSON(mf, simplifyVector = TRUE)
        if (!is.null(m$physiological_classification)) {
          bad <- c(bad, lane)
        }
        if (!is.null(m$semantic_type) &&
            identical(m$semantic_type, "serum_biomonitoring")) {
          bad <- c(bad, lane)
        }
      }
      length(bad) == 0L
    }
  ),
  list(
    name = "no_env_ref_training_csv_carries_stamp_columns",
    ok = {
      bad <- character(0)
      for (lane in NONPHYSIOLOGICAL_LANES) {
        tr <- file.path(repo_root, "data", "training", lane, "training.csv")
        if (!file.exists(tr)) next  # not every env lane has a built CSV
        hdr <- csv_header_cols(tr)
        if (any(PHYSIOLOGICAL_CLASSIFICATION_FIELDS %in% hdr)) {
          bad <- c(bad, lane)
        }
      }
      length(bad) == 0L
    }
  ),
  list(
    # The serum lane should still carry the stamp; this is the
    # converse check so a regression that drops the stamp from serum
    # while leaving env lanes alone is caught here too.
    name = "serum_training_csv_carries_stamp_columns",
    ok = {
      tr <- file.path(repo_root, "data/training/serum/training.csv")
      hdr <- csv_header_cols(tr)
      length(hdr) > 0L &&
        all(PHYSIOLOGICAL_CLASSIFICATION_FIELDS %in% hdr)
    }
  ),

  # ---------- (6) Canonical core header unchanged ----------------------
  list(
    name = "python_canonical_output_columns_count_is_28",
    ok = {
      if (!file.exists(run_pipeline_py)) FALSE else {
        txt <- read_text(run_pipeline_py)
        m <- regmatches(
          txt,
          regexpr(
            "CANONICAL_OUTPUT_COLUMNS = \\[[^\\]]*\\]",
            txt, perl = TRUE
          )
        )
        if (length(m) < 1L || !nzchar(m)) FALSE else {
          n_entries <- length(regmatches(m, gregexpr('"[^"]+"', m,
                                                     perl = TRUE))[[1]])
          identical(n_entries, 28L)
        }
      }
    }
  ),
  list(
    # Stamp columns are added via extra_columns=, not by mutating the
    # canonical core. If anyone adds them to CANONICAL_OUTPUT_COLUMNS,
    # this fails.
    name = "python_canonical_output_columns_does_NOT_contain_stamp",
    ok = {
      if (!file.exists(run_pipeline_py)) FALSE else {
        txt <- read_text(run_pipeline_py)
        m <- regmatches(
          txt,
          regexpr(
            "CANONICAL_OUTPUT_COLUMNS = \\[[^\\]]*\\]",
            txt, perl = TRUE
          )
        )
        if (length(m) < 1L || !nzchar(m)) FALSE else {
          !any(vapply(PHYSIOLOGICAL_CLASSIFICATION_FIELDS, function(f)
                      grepl(paste0('"', f, '"'), m, fixed = TRUE),
                      logical(1)))
        }
      }
    }
  ),

  # ---------- (7) Anchor + built table do NOT share a hash --------------
  list(
    # Sanity: the anchor and the built training table should NEVER
    # have the same hash. The anchor is 20 cols / 2133 rows; the
    # built table is 33 cols / 27619 rows.
    name = "anchor_csv_hash_differs_from_built_training_csv_hash",
    ok = {
      built <- file.path(repo_root, "data/training/serum/training.csv")
      if (!(file.exists(anchor_csv_path) && file.exists(built))) FALSE
      else {
        h_anchor <- digest::digest(file = anchor_csv_path, algo = "sha256")
        h_built  <- digest::digest(file = built,           algo = "sha256")
        !identical(tolower(h_anchor), tolower(h_built))
      }
    }
  ),
  list(
    name = "serum_manifest_training_csv_is_built_not_anchor",
    # The manifest's `training_csv` pointer must point at the BUILT
    # training table, not the v1.0 anchor. The anchor is frozen and
    # carries a different hash (and a different row count).
    ok = {
      if (!file.exists(serum_manifest)) FALSE else {
        m <- jsonlite::fromJSON(serum_manifest, simplifyVector = TRUE)
        identical(m$training_csv, "data/training/serum/training.csv") &&
          !identical(tolower(m$training_csv_sha256),
                     tolower(ANCHOR_CSV_DOCUMENTED_SHA256))
      }
    }
  ),

  # ---------- (8) Out-of-scope cycles documented consistently ---------
  # The four non-J NHANES cycles known to the project (Pre-pandemic
  # P_PFAS, 2015-2016 PFAS_I, 2013-2014 PFAS_H, 2003-2004 L06AGE_C)
  # plus the 2013-2014 isomer companion SSPFAS_H must be documented
  # as out-of-scope in every doc that lists scope coverage. If a new
  # cycle gets quietly admitted by editing only the JSON, this smoke
  # fails because the other docs would lag.
  list(
    name = "schema_contract_json_lists_all_out_of_scope_cycles",
    ok = {
      txt <- read_text(schema_json)
      grepl('"P_PFAS_prepandemic_2017_2020"', txt, fixed = TRUE) &&
        grepl('"L06AGE_C_2003_2004_legacy"', txt, fixed = TRUE) &&
        grepl('"PFAS_H_2013_2014"',          txt, fixed = TRUE) &&
        grepl('"SSPFAS_H_2013_2014"',        txt, fixed = TRUE)
    }
  ),
  list(
    name = "schema_contract_md_section_7_lists_pfas_h",
    ok = {
      txt <- read_text(schema_md)
      grepl("PFAS_H.XPT", txt, fixed = TRUE) &&
        grepl("SSPFAS_H.XPT", txt, fixed = TRUE) &&
        grepl("## 7.1 Cycle H specifics", txt, fixed = TRUE)
    }
  ),
  list(
    name = "provenance_md_section_6_lists_pfas_h",
    ok = {
      txt <- read_text(provenance_md)
      grepl("PFAS_H.XPT", txt, fixed = TRUE) &&
        grepl("SSPFAS_H.XPT", txt, fixed = TRUE)
    }
  ),
  list(
    name = "applicability_domain_txt_mentions_pfas_h",
    ok = {
      ad_txt <- file.path(repo_root, "validation/serum_v1/applicability_domain.txt")
      txt <- read_text(ad_txt)
      grepl("PFAS_H", txt, fixed = TRUE) &&
        grepl("SSPFAS_H", txt, fixed = TRUE)
    }
  ),
  list(
    name = "readme_mentions_pfas_h_and_its_isomer_companion",
    ok = {
      rm <- file.path(repo_root, "validation/serum_v1/README.md")
      txt <- read_text(rm)
      grepl("PFAS_H.XPT", txt, fixed = TRUE) &&
        grepl("SSPFAS_H.XPT", txt, fixed = TRUE)
    }
  ),
  list(
    # Negative check: PFAS_H rows must NOT have crept into the built
    # training table. The training table is sourced from
    # data/processed/nhanes_pfas_with_demo.parquet (PFAS_J merged with
    # demographics) -- nothing should reference PFAS_H here.
    name = "built_training_csv_carries_no_pfas_h_rows",
    ok = {
      tr <- file.path(repo_root, "data/training/serum/training.csv")
      if (!file.exists(tr)) FALSE else {
        # Stream-scan rather than read whole CSV; the file is ~10 MB.
        con <- file(tr, "r")
        on.exit(close(con), add = TRUE)
        hit <- FALSE
        repeat {
          chunk <- readLines(con, n = 65536L, warn = FALSE)
          if (length(chunk) == 0L) break
          if (any(grepl("PFAS_H", chunk, fixed = TRUE)) ||
              any(grepl("LBXPFBS", chunk, fixed = TRUE)) ||
              any(grepl("LBXPFHP", chunk, fixed = TRUE)) ||
              any(grepl("LBXPFDO", chunk, fixed = TRUE))) {
            hit <- TRUE
            break
          }
        }
        !hit
      }
    }
  )
)

failed <- character(0)
for (c in checks) if (!isTRUE(c$ok)) failed <- c(failed, c$name)

cat("Anchor + lane-registry invariants smoke:\n")
for (c in checks) {
  cat(sprintf("  %s: %s\n", c$name,
              if (isTRUE(c$ok)) "PASS" else "FAIL"))
}
if (length(failed) > 0L) {
  stop("FAILED: ", paste(failed, collapse = ", "))
}
cat("Overall: PASS (", length(checks), "/", length(checks), ")\n", sep = "")
