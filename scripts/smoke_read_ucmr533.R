# Smoke-test EPA UCMR5 Method 533 occurrence table (same read settings as console recipe).
# Units like µg/L are often byte 0xB5 in EPA/Windows exports; fileEncoding = "latin1" avoids
# "invalid multibyte string" if R would otherwise treat the file as UTF-8.
#
# Usage:
#   Rscript scripts/smoke_read_ucmr533.R
#   Rscript scripts/smoke_read_ucmr533.R "path/to/UCMR5_533.txt"
#   Rscript scripts/smoke_read_ucmr533.R "path/to/UCMR5_533.txt" --sample 5000
#   Rscript scripts/smoke_read_ucmr533.R "path/to/UCMR5_533.txt" --write-full   # slow (~1.6M rows)
# Default path (first match wins): CLI arg, env UCMR5_533_TXT, R option pfas.ucmr5_533_path,
# or data/external/epa_ucmr5/UCMR5_533.txt under the project.
#
# R Console (source() has no CLI args; PowerShell $env:... is not visible here unless you
# started R from that shell). Use a real path, not the literal "C:/path/to/..." example:
#   options(pfas.ucmr5_533_path = "C:/Users/you/Downloads/.../UCMR5_533.txt")
#   source("scripts/smoke_read_ucmr533.R", encoding = "UTF-8")
# or: Sys.setenv(UCMR5_533_TXT = "C:/Users/you/Downloads/.../UCMR5_533.txt") then source().
#
# Run the whole file with Rscript (Terminal). Do not paste only the bottom if/else block into
# the R Console: variables like wf, d, sample_n, and out_dir are defined above.
is_placeholder_ucmr_path <- function(x) {
  if (length(x) != 1L || !nzchar(x)) {
    return(FALSE)
  }
  grepl("path[/\\\\]to[/\\\\]", x, ignore.case = TRUE)
}

args <- commandArgs(trailingOnly = TRUE)
argv <- commandArgs(trailingOnly = FALSE)
file_arg_src <- grep("^--file=", argv, value = TRUE)
script_dir <- if (length(file_arg_src)) {
  dirname(normalizePath(sub("^--file=", "", file_arg_src[1]), winslash = "/"))
} else {
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}
project_root <- if (basename(script_dir) == "scripts") {
  dirname(script_dir)
} else {
  script_dir
}

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
  envp <- Sys.getenv("UCMR5_533_TXT", "")
  optp <- getOption("pfas.ucmr5_533_path", default = "")
  if (!is.character(optp) || !nzchar(optp)) {
    optp <- ""
  }
  cand <- c(
    if (nzchar(envp)) envp else NA_character_,
    if (nzchar(optp)) optp else NA_character_,
    file.path(project_root, "data/external/epa_ucmr5/UCMR5_533.txt"),
    file.path(project_root, "data/raw/UCMR5_533.txt")
  )
  cand <- cand[!is.na(cand) & nzchar(cand)]
  hit <- cand[file.exists(cand)]
  if (length(hit) < 1) {
    stop(
      "Could not find UCMR5_533.txt. Do one of:\n",
      "  Terminal: Rscript scripts/smoke_read_ucmr533.R \"C:/real/path/UCMR5_533.txt\"\n",
      "  R Console before source(): options(pfas.ucmr5_533_path = \"C:/real/path/UCMR5_533.txt\")\n",
      "  Or copy the file to: ", file.path(project_root, "data/external/epa_ucmr5/UCMR5_533.txt"),
      "\n(Do not use the literal path C:/path/to/... from docs; replace with your real file.)",
      call. = FALSE
    )
  }
  hit[[1]]
}
if (is_placeholder_ucmr_path(p)) {
  stop(
    "Placeholder path not allowed: ", p, "\n",
    "Use your real UCMR5_533.txt location (e.g. under Downloads after EPA zip extract).",
    call. = FALSE
  )
}
if (!file.exists(p)) {
  hint <- if (nzchar(Sys.getenv("UCMR5_533_TXT", ""))) {
    "\nIf you set UCMR5_533_TXT in PowerShell, RStudio may not see it; use options(pfas.ucmr5_533_path=...) or Sys.setenv() in the R Console, or pass the path on the Rscript command line."
  } else {
    ""
  }
  stop("File not found: ", p, hint, call. = FALSE)
}
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
