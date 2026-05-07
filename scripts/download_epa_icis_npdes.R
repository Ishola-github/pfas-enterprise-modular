# Download EPA ECHO ICIS-NPDES bulk files (biosolids, outfalls, DMR FY ZIPs, reference tables).
# Mirrors logic in download_epa_icis_npdes_ml.ps1. Canonical index:
#   https://echo.epa.gov/tools/data-downloads
#
# Environment (optional):
#   PFAS_ICIS_DMR_YEARS   Comma-separated fiscal years, default "2024,2025"
#   PFAS_ICIS_INCLUDE_LIMITS  "1"/"true" to also fetch npdes_limits.zip (~459 MB)
#
# Output: data/raw/epa_icis_npdes/ (+ ref_tables/)

options(
  timeout = max(600, getOption("timeout"))
)

root <- getwd()
out_dir <- file.path(root, "data", "raw", "epa_icis_npdes")
ref_dir <- file.path(out_dir, "ref_tables")
dir.create(ref_dir, recursive = TRUE, showWarnings = FALSE)

save_if_missing <- function(url, dest) {
  if (file.exists(dest)) {
    message("Skip (exists): ", basename(dest))
    return(invisible(TRUE))
  }
  message("Downloading ", basename(dest))
  status <- download.file(url, dest, mode = "wb", quiet = TRUE)
  if (status != 0L) {
    stop("Download failed: ", url, " -> ", dest, call. = FALSE)
  }
  invisible(TRUE)
}

# Biosolids + outfalls (weekly refresh on EPA side)
save_if_missing(
  "https://echo.epa.gov/files/echodownloads/npdes_biosolids_downloads.zip",
  file.path(out_dir, "npdes_biosolids_downloads.zip")
)
save_if_missing(
  "https://echo.epa.gov/files/echodownloads/npdes_outfalls_layer.zip",
  file.path(out_dir, "npdes_outfalls_layer.zip")
)

years_raw <- Sys.getenv("PFAS_ICIS_DMR_YEARS", "2024,2025")
years <- trimws(strsplit(years_raw, ",", fixed = TRUE)[[1]])
years <- years[nzchar(years)]
if (length(years) == 0) years <- "2024"

for (y in years) {
  yy <- gsub("[^0-9]", "", y)
  if (nchar(yy) != 4L) next
  save_if_missing(
    sprintf("https://echo.epa.gov/files/echodownloads/npdes_dmrs_fy%s.zip", yy),
    file.path(out_dir, sprintf("npdes_dmrs_fy%s.zip", yy))
  )
}

lim <- tolower(trimws(Sys.getenv("PFAS_ICIS_INCLUDE_LIMITS", "0")))
if (lim %in% c("1", "true", "yes")) {
  save_if_missing(
    "https://echo.epa.gov/files/echodownloads/npdes_limits.zip",
    file.path(out_dir, "npdes_limits.zip")
  )
}

save_if_missing(
  "https://echo.epa.gov/system/files/REF_Parameter.csv",
  file.path(ref_dir, "REF_Parameter.csv")
)
save_if_missing(
  "https://echo.epa.gov/files/echodownloads/ref_tables/REF_STATISTICAL_BASE.csv",
  file.path(ref_dir, "REF_STATISTICAL_BASE.csv")
)
save_if_missing(
  "https://echo.epa.gov/system/files/REF_FREQUENCY_OF_ANALYSIS.csv",
  file.path(ref_dir, "REF_FREQUENCY_OF_ANALYSIS.csv")
)
save_if_missing(
  "https://echo.epa.gov/system/files/REF_SAMPLE_TYPE_0.csv",
  file.path(ref_dir, "REF_SAMPLE_TYPE_0.csv")
)

message("Done. Files under ", normalizePath(out_dir, winslash = "/", mustWork = FALSE))
