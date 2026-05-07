# Smoke-test EPA UCMR5 Method 533 occurrence table (same read settings as console recipe).
# Units like µg/L are often byte 0xB5 in EPA/Windows exports; fileEncoding = "latin1" avoids
# "invalid multibyte string" if R would otherwise treat the file as UTF-8.
#
# Usage:
#   Rscript scripts/smoke_read_ucmr533.R
#   Rscript scripts/smoke_read_ucmr533.R "C:/path/to/UCMR5_533.txt"
#   Rscript scripts/smoke_read_ucmr533.R "C:/path/to/UCMR5_533.txt" --sample 5000
#   Rscript scripts/smoke_read_ucmr533.R "C:/path/to/UCMR5_533.txt" --write-full   # slow (~1.6M rows)
args <- commandArgs(trailingOnly = TRUE)
path_arg <- args[args != "--write-full" & !grepl("^--sample=", args)]
sample_n <- NA_integer_
wf <- any(args == "--write-full")
for (a in args) {
  if (grepl("^--sample=", a)) {
    sample_n <- suppressWarnings(as.integer(sub("^--sample=", "", a)))
  }
}
if (is.na(sample_n) && any(args == "--sample")) {
  idx <- which(args == "--sample")
  if (length(idx) && idx[[1]] < length(args)) {
    sample_n <- suppressWarnings(as.integer(args[[idx[[1]] + 1L]]))
  }
}

p <- if (length(path_arg) >= 1) path_arg[[1]] else {
  cand <- c(
    "C:/Users/techj/Downloads/ucmr5-occurrence-data-by-method-classification/UCMR5_533.txt",
    "C:/Users/techj/Downloads/ucmr5-occurrence-data-by-method-classification (1)/UCMR5_533.txt"
  )
  hit <- cand[file.exists(cand)]
  if (length(hit) < 1) {
    stop(
      "Pass path to UCMR5_533.txt as first argument, or place the zip extract under Downloads with a known folder name.",
      call. = FALSE
    )
  }
  hit[[1]]
}
if (!file.exists(p)) stop("File not found: ", p, call. = FALSE)
message("Reading: ", normalizePath(p, winslash = "/", mustWork = TRUE))
d <- read.delim(
  p,
  sep = "\t",
  quote = "",
  fill = TRUE,
  stringsAsFactors = FALSE,
  fileEncoding = "latin1"
)
message("dim: ", nrow(d), " x ", ncol(d))
print(utils::head(d, 3))

out_dir <- dirname(normalizePath(p, winslash = "/", mustWork = TRUE))
if (isTRUE(wf)) {
  out <- file.path(out_dir, "UCMR5_533_clean.csv")
  message("Writing full CSV (slow): ", out)
  utils::write.csv(d, out, row.names = FALSE, fileEncoding = "UTF-8")
  message("Done: ", out)
} else if (is.finite(sample_n) && sample_n > 0L) {
  n <- min(sample_n, nrow(d))
  out <- file.path(out_dir, sprintf("UCMR5_533_clean_sample_%d.csv", n))
  message("Writing sample n=", n, " rows: ", out)
  utils::write.csv(d[seq_len(n), , drop = FALSE], out, row.names = FALSE, fileEncoding = "UTF-8")
  message("Done: ", out)
} else {
  message(
    "No CSV written. For Shiny smoke test: ",
    "Rscript scripts/smoke_read_ucmr533.R <path> --sample 5000\n",
    "Full export (slow): add flag --write-full"
  )
}
