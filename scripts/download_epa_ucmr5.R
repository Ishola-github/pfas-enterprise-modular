# Download EPA UCMR 5 occurrence bulk text files into data/external/epa_ucmr5/.
# Official package (standardized March 2024): tab-delimited .txt analytical results.
#
# Source page: https://www.epa.gov/dwucmr/occurrence-data-unregulated-contaminant-monitoring-rule
# Default ZIP: UCMR 5 Occurrence Data Text Files
#
# Optional env:
#   UCMR5_ZIP_URL  Alternate download URL (mirror)
#   UCMR5_SKIP_UNZIP  Set to "1" to only download the archive
#
# After this runs, point tools at files such as UCMR5_533.txt, UCMR5_537_1.txt,
# UCMR5_200_7.txt, or UCMR5_All.txt (very large) per EPA method bundle.

options(timeout = max(3600, getOption("timeout")))

root <- getwd()
dest_dir <- file.path(root, "data", "external", "epa_ucmr5")
dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)

zip_url <- trimws(Sys.getenv(
  "UCMR5_ZIP_URL",
  "https://www.epa.gov/system/files/other-files/2023-08/ucmr5-occurrence-data.zip"
))
if (!nzchar(zip_url)) {
  stop("UCMR5_ZIP_URL is empty.", call. = FALSE)
}

zip_path <- file.path(dest_dir, "ucmr5-occurrence-data.zip")

`%||%` <- function(x, y) if (is.null(x)) y else x

occurrence_present <- function(dir) {
  f <- list.files(dir, pattern = "\\.(txt|csv)$", ignore.case = TRUE, recursive = TRUE)
  length(f) > 0L
}

zip_usable <- file.exists(zip_path) && (file.info(zip_path)$size %||% 0) > 1000L

if (occurrence_present(dest_dir)) {
  message("Occurrence .txt/.csv already present under ", dest_dir, " — skip download/unzip.")
} else if (!zip_usable) {
  message("Downloading UCMR5 occurrence ZIP (EPA bulk) ...")
  st <- try(
    download.file(zip_url, zip_path, mode = "wb", quiet = FALSE),
    silent = TRUE
  )
  if (inherits(st, "try-error") || (!is.numeric(st)) || st != 0L) {
    stop(
      "UCMR5 ZIP download failed. Check network and URL:\n  ",
      zip_url,
      call. = FALSE
    )
  }
} else {
  message("Using existing ZIP (extracting): ", zip_path)
}

skip_unzip <- tolower(trimws(Sys.getenv("UCMR5_SKIP_UNZIP", "0"))) %in% c("1", "true", "yes")
if (!skip_unzip && file.exists(zip_path) && !occurrence_present(dest_dir)) {
  message("Extracting ZIP into ", dest_dir, " ...")
  unzip(zip_path, exdir = dest_dir)
}

if (!occurrence_present(dest_dir)) {
  stop(
    "No .txt/.csv occurrence files found after download/extract. ",
    "Inspect ZIP manually: ",
    normalizePath(zip_path, winslash = "/", mustWork = FALSE),
    call. = FALSE
  )
}

nf <- length(list.files(dest_dir, pattern = "\\.(txt|csv)$", ignore.case = TRUE, recursive = TRUE))
message("UCMR5 occurrence files available: ", nf, " under ", normalizePath(dest_dir, winslash = "/", mustWork = FALSE))
