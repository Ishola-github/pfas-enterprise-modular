# Smoke test: lane_kind partition (physiological vs environmental vs reference)
# and serum_biomonitoring as a first-class training lane.
#
# Governance anchors:
#   - data/config/matrix_pipeline_sop.csv         (lane_kind column)
#   - data/training/<lane>/manifest.json          (lane_kind field per lane)
#   - data/training/serum/manifest.json           (semantic_type=serum_biomonitoring)
#   - validation/serum_v1/                        (serum lane governance boundary)
#   - SCOPE_AND_INTENDED_USE.md \u00a714           (physiological vs occurrence distinction)
#   - LatestPFAS.R                                (UI: three labeled lane-kind rows + grouped selectInputs)
#
# Run from project root:
#   Rscript scripts/smoke_serum_lane_kind.R
# Or in RStudio (Console), after setwd() to the repo pfas-toxicology folder:
#   source("scripts/smoke_serum_lane_kind.R", echo = FALSE)

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
}

repo_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
sop_path  <- file.path(repo_root, "data", "config", "matrix_pipeline_sop.csv")
app_path  <- file.path(repo_root, "LatestPFAS.R")
serum_v1  <- file.path(repo_root, "validation", "serum_v1")

if (!file.exists(sop_path)) stop("Missing ", sop_path)
if (!file.exists(app_path)) stop("Missing ", app_path)
if (!dir.exists(serum_v1)) {
  warning("validation/serum_v1/ not found at ", serum_v1,
          " -- serum lane governance boundary expected to be present")
}

sop <- utils::read.csv(sop_path, stringsAsFactors = FALSE, check.names = FALSE)

expected_lane_kind <- c(
  drinking_water     = "environmental_occurrence",
  serum              = "physiological_biomonitoring",
  biosolids_sludge   = "environmental_occurrence",
  afff               = "reference_material",
  methanol_standards = "reference_material",
  air_emissions      = "environmental_occurrence"
)

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  install.packages("jsonlite",
                   repos = c(CRAN = "https://cloud.r-project.org"))
}

read_manifest <- function(pid) {
  p <- file.path(repo_root, "data", "training", pid, "manifest.json")
  if (!file.exists(p)) return(NULL)
  tryCatch(jsonlite::fromJSON(p, simplifyVector = TRUE),
           error = function(e) NULL)
}

src <- paste(readLines(app_path, warn = FALSE), collapse = "\n")

expr <- tryCatch(parse(file = app_path), error = function(e) {
  stop("LatestPFAS.R failed to parse: ", conditionMessage(e))
})

checks <- list(
  # -------------------- SOP CSV structure --------------------
  list(
    name = "sop_has_lane_kind_column",
    ok = "lane_kind" %in% names(sop)
  ),
  list(
    name = "sop_has_6_lanes",
    ok = identical(nrow(sop), 6L)
  ),
  list(
    name = "sop_pipeline_ids_match_expected_set",
    ok = identical(sort(trimws(as.character(sop$pipeline_id))),
                   sort(names(expected_lane_kind)))
  ),
  # -------------------- SOP CSV: lane_kind values per lane --------------------
  list(
    name = "sop_serum_kind_is_physiological_biomonitoring",
    ok = identical(
      trimws(as.character(sop$lane_kind[sop$pipeline_id == "serum"])),
      "physiological_biomonitoring"
    )
  ),
  list(
    name = "sop_drinking_water_kind_is_environmental_occurrence",
    ok = identical(
      trimws(as.character(sop$lane_kind[sop$pipeline_id == "drinking_water"])),
      "environmental_occurrence"
    )
  ),
  list(
    name = "sop_biosolids_sludge_kind_is_environmental_occurrence",
    ok = identical(
      trimws(as.character(sop$lane_kind[sop$pipeline_id == "biosolids_sludge"])),
      "environmental_occurrence"
    )
  ),
  list(
    name = "sop_air_emissions_kind_is_environmental_occurrence",
    ok = identical(
      trimws(as.character(sop$lane_kind[sop$pipeline_id == "air_emissions"])),
      "environmental_occurrence"
    )
  ),
  list(
    name = "sop_afff_kind_is_reference_material",
    ok = identical(
      trimws(as.character(sop$lane_kind[sop$pipeline_id == "afff"])),
      "reference_material"
    )
  ),
  list(
    name = "sop_methanol_standards_kind_is_reference_material",
    ok = identical(
      trimws(as.character(sop$lane_kind[sop$pipeline_id == "methanol_standards"])),
      "reference_material"
    )
  ),
  # -------------------- SOP CSV: matrix-isolation invariants --------------------
  list(
    name = "sop_serum_is_only_physiological_lane",
    ok = sum(trimws(as.character(sop$lane_kind)) ==
               "physiological_biomonitoring") == 1L
  ),
  list(
    name = "sop_exactly_3_environmental_lanes",
    ok = sum(trimws(as.character(sop$lane_kind)) ==
               "environmental_occurrence") == 3L
  ),
  list(
    name = "sop_exactly_2_reference_lanes",
    ok = sum(trimws(as.character(sop$lane_kind)) ==
               "reference_material") == 2L
  )
)

# -------------------- per-lane manifests carry lane_kind --------------------
for (pid in names(expected_lane_kind)) {
  man <- read_manifest(pid)
  checks[[length(checks) + 1L]] <- list(
    name = paste0("manifest_present_for_", pid),
    ok = !is.null(man)
  )
  checks[[length(checks) + 1L]] <- list(
    name = paste0("manifest_lane_kind_matches_sop_for_", pid),
    ok = !is.null(man) &&
      identical(as.character(man$lane_kind), expected_lane_kind[[pid]])
  )
}

# -------------------- serum-specific manifest fields --------------------
serum_man <- read_manifest("serum")
checks[[length(checks) + 1L]] <- list(
  name = "serum_manifest_has_semantic_type_serum_biomonitoring",
  ok = !is.null(serum_man) &&
    identical(as.character(serum_man$semantic_type), "serum_biomonitoring")
)
checks[[length(checks) + 1L]] <- list(
  name = "serum_manifest_has_lane_kind_note",
  ok = !is.null(serum_man) &&
    !is.null(serum_man$lane_kind_note) &&
    nzchar(as.character(serum_man$lane_kind_note))
)
checks[[length(checks) + 1L]] <- list(
  name = "serum_manifest_references_serum_v1_governance",
  ok = !is.null(serum_man) &&
    !is.null(serum_man$lane_kind_note) &&
    grepl("validation/serum_v1", as.character(serum_man$lane_kind_note),
          fixed = TRUE)
)

# -------------------- LatestPFAS.R UI: three labeled lane-kind rows --------
ui_checks <- list(
  list(
    name = "ui_has_environmental_occurrence_header",
    ok = grepl("Environmental-occurrence lanes", src, fixed = TRUE)
  ),
  list(
    name = "ui_has_physiological_body_burden_header",
    ok = grepl("Physiological body-burden lanes", src, fixed = TRUE)
  ),
  list(
    name = "ui_has_reference_material_header",
    ok = grepl("Reference-material lanes", src, fixed = TRUE)
  ),
  # The intro paragraph above the headers also mentions the lane-kind phrases.
  # Anchor on the source-code form of the header: `Lanes lanes ("` followed by
  # a closing quote-and-comma (only the headers have that construct -- the intro
  # text uses the phrases mid-sentence).
  list(
    name = "ui_serum_button_lives_under_physiological_header",
    ok = {
      i_env  <- regexpr('Environmental-occurrence lanes (",', src, fixed = TRUE)
      i_phys <- regexpr('Physiological body-burden lanes (",', src, fixed = TRUE)
      i_ref  <- regexpr('Reference-material lanes (",', src, fixed = TRUE)
      i_btn  <- regexpr('"btn_lane_serum"', src, fixed = TRUE)
      all(c(i_env, i_phys, i_ref, i_btn) > 0) &&
        as.integer(i_btn) > as.integer(i_phys) &&
        as.integer(i_btn) < as.integer(i_ref)
    }
  ),
  list(
    name = "ui_drinking_water_button_lives_under_environmental_header",
    ok = {
      i_env  <- regexpr('Environmental-occurrence lanes (",', src, fixed = TRUE)
      i_phys <- regexpr('Physiological body-burden lanes (",', src, fixed = TRUE)
      i_btn  <- regexpr('"btn_lane_drinking_water"', src, fixed = TRUE)
      all(c(i_env, i_phys, i_btn) > 0) &&
        as.integer(i_btn) > as.integer(i_env) &&
        as.integer(i_btn) < as.integer(i_phys)
    }
  ),
  list(
    name = "ui_afff_button_lives_under_reference_header",
    ok = {
      i_ref  <- regexpr('Reference-material lanes (",', src, fixed = TRUE)
      i_btn  <- regexpr('"btn_lane_afff"', src, fixed = TRUE)
      all(c(i_ref, i_btn) > 0) &&
        as.integer(i_btn) > as.integer(i_ref)
    }
  ),
  list(
    name = "ui_serum_button_shows_governance_pointer",
    ok = grepl("validation/serum_v1/", src, fixed = TRUE) &&
      grepl("convert_nhanes_xpt_to_csv.R", src, fixed = TRUE)
  ),
  list(
    name = "ui_serum_button_shows_anchor_hash_short_form",
    ok = grepl("dfd4dbb5", src, fixed = TRUE)
  ),
  # -------------------- selectInput grouping by lane_kind ---------------
  list(
    name = "selectinput_ad_lane_grouped_by_lane_kind",
    ok = grepl('selectInput\\("ad_lane_select",[\\s\\S]*?Physiological body-burden lanes \\(serum_biomonitoring\\)[\\s\\S]*?Reference-material lanes',
               src, perl = TRUE)
  ),
  list(
    name = "selectinput_bv_lane_grouped_by_lane_kind",
    ok = grepl('selectInput\\("bv_lane",[\\s\\S]*?Physiological body-burden lanes \\(serum_biomonitoring\\)[\\s\\S]*?Reference-material lanes',
               src, perl = TRUE)
  ),
  # -------------------- SOP table renderer still happy with 4 columns ----
  list(
    name = "sop_renderer_has_lane_kind_label",
    ok = grepl('lane_kind\\s*=\\s*"Lane kind"', src, perl = TRUE)
  ),
  list(
    name = "outputs_table_emits_lane_kind_column",
    ok = grepl("`Lane kind`", src, fixed = TRUE)
  )
)
checks <- c(checks, ui_checks)

failed <- character(0)
for (c in checks) {
  if (!isTRUE(c$ok)) {
    failed <- c(failed, c$name)
  }
}

cat("LatestPFAS.R parse: OK (", length(expr), " top-level expr)\n", sep = "")
cat("Lane-kind partition smoke:\n")
for (c in checks) {
  cat(sprintf("  %s: %s\n", c$name,
              if (isTRUE(c$ok)) "PASS" else "FAIL"))
}

if (length(failed) > 0L) {
  stop("FAILED: ", paste(failed, collapse = ", "))
}
cat("Overall: PASS (", length(checks), "/", length(checks), ")\n", sep = "")
