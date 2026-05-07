#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args) >= 1L) normalizePath(args[[1]], winslash = "/", mustWork = FALSE) else normalizePath(getwd(), winslash = "/", mustWork = FALSE)

py <- Sys.getenv("PFAS_PYTHON", unset = "")
if (!nzchar(trimws(py))) {
  onp <- Sys.which("python")
  py <- if (nzchar(onp)) onp else "python"
}

script <- file.path(root, "scripts", "build_ucmr_exceedance_dataset.py")
if (!file.exists(script)) {
  stop("Missing scripts/build_ucmr_exceedance_dataset.py under: ", root)
}

argv <- c(script, "--project-root", root)
# Prefer comptox/ then compontox/ bridge when passing --bridge (Python also searches both if --bridge omitted).
bridge_rel <- NA_character_
b1 <- file.path(root, "data", "external", "comptox", "pfasmaster_bridge.csv")
b2 <- file.path(root, "data", "external", "compontox", "pfasmaster_bridge.csv")
if (file.exists(b1)) {
  bridge_rel <- "data/external/comptox/pfasmaster_bridge.csv"
} else if (file.exists(b2)) {
  bridge_rel <- "data/external/compontox/pfasmaster_bridge.csv"
}
if (!is.na(bridge_rel) && !nzchar(Sys.getenv("PFAS_BRIDGE_CSV", unset = ""))) {
  argv <- c(argv, "--bridge", bridge_rel)
} else if (!nzchar(Sys.getenv("PFAS_BRIDGE_CSV", unset = ""))) {
  warning(
    "No data/external/comptox/pfasmaster_bridge.csv or data/external/compontox/pfasmaster_bridge.csv found.\n",
    "  Copy pfasmaster_bridge.csv from your main machine or fill the template; Python will look for comptox first, then compontox."
  )
}

# Windows: system2(py, args=...) breaks when paths contain spaces (e.g. OneDrive folders).
# Build one cmd.exe-safe line with shQuote(, type = "cmd") instead.
qwin <- function(x) {
  shQuote(trimws(as.character(x)), type = "cmd")
}
if (identical(.Platform$OS.type, "windows")) {
  pyq <- if (nzchar(py) && file.exists(py)) {
    # winslash="/" avoids a lone "\" in source (harder to break with copy/paste); cmd accepts forward slashes.
    qwin(normalizePath(py, winslash = "/", mustWork = TRUE))
  } else {
    qwin(py)
  }
  line <- paste(c(pyq, vapply(argv, qwin, character(1L))), collapse = " ")
  cat("Running:\n", line, "\n", sep = "")
  out <- tryCatch(
    system(line, intern = TRUE, ignore.stderr = FALSE, wait = TRUE),
    error = function(e) {
      stop("system() failed: ", conditionMessage(e))
    }
  )
} else {
  cat("Running: ", py, " ", paste(argv, collapse = " "), "\n", sep = "")
  out <- tryCatch(
    system2(py, args = argv, stdout = TRUE, stderr = TRUE),
    error = function(e) {
      stop("system2 failed: ", conditionMessage(e))
    }
  )
}
if (length(out) > 0) cat(paste(out, collapse = "\n"), "\n")
st <- attr(out, "status")
if (!is.null(st) && !identical(as.integer(st), 0L)) {
  stop("Python dataset build failed with exit code: ", st)
}
invisible(TRUE)
