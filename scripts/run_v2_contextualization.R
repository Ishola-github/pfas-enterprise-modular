# PFAS Enterprise 5.0 V2 — cross-cycle temporal contextualization (R wrapper).
#
# Invokes: python -m src.v2.cli
# Used by LatestPFAS.R (Reports tab) and smoke tests.
#
# Run standalone:
#   Rscript scripts/run_v2_contextualization.R \
#     data/v1/fixtures/nhanes_j_governed_v1_input.csv \
#     data/v2/outputs

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
}

resolve_v2_python <- function(python_exec = NULL) {
  py <- trimws(as.character(python_exec %||% ""))
  if (!nzchar(py)) {
    py <- trimws(Sys.getenv("PFAS_PYTHON", unset = ""))
  }
  local_default <- file.path("C:", "pfasenv", "Scripts", "python.exe")
  if (!nzchar(py) && file.exists(local_default)) {
    py <- local_default
  }
  if (!nzchar(py)) {
    py <- "python"
  }
  if (file.exists(py)) {
    return(py)
  }
  on_path <- Sys.which(py)
  if (nzchar(on_path)) {
    return(on_path)
  }
  NA_character_
}

run_v2_serum_contextualization <- function(
    input_csv,
    output_dir,
    project_root = ".",
    python_exec = NULL) {
  project_root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)
  input_csv <- normalizePath(input_csv, winslash = "/", mustWork = TRUE)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }
  output_dir <- normalizePath(output_dir, winslash = "/", mustWork = FALSE)

  py <- resolve_v2_python(python_exec)
  if (is.na(py)) {
    return(list(
      ok = FALSE,
      message = "Python executable not found. Set PFAS_PYTHON or pass python_exec.",
      summary = NULL,
      log = character(0)
    ))
  }

  args <- c(
    "-m", "src.v2.cli",
    "--input", input_csv,
    "--output-dir", output_dir
  )

  old_wd <- getwd()
  old_py <- Sys.getenv("PYTHONPATH", unset = NA_character_)
  on.exit(
    {
      setwd(old_wd)
      if (is.na(old_py)) {
        try(Sys.unsetenv("PYTHONPATH"), silent = TRUE)
      } else {
        Sys.setenv(PYTHONPATH = old_py)
      }
    },
    add = TRUE
  )
  setwd(project_root)
  Sys.setenv(PYTHONPATH = project_root, PFAS_PROJECT_ROOT = project_root)

  out <- tryCatch(
    system2(py, args = args, stdout = TRUE, stderr = TRUE),
    error = function(e) paste0("system2 error: ", conditionMessage(e))
  )
  st <- attr(out, "status")
  log_txt <- paste(out, collapse = "\n")

  if (!is.null(st) && !identical(as.integer(st), 0L)) {
    return(list(
      ok = FALSE,
      message = paste0("V2 CLI exited with status ", st),
      summary = NULL,
      log = log_txt
    ))
  }

  summary <- NULL
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    parsed <- tryCatch(
      jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = TRUE),
      error = function(e) NULL
    )
    if (is.list(parsed) && !is.null(parsed$run_id)) {
      summary <- parsed
    }
  }

  if (is.null(summary)) {
    return(list(
      ok = FALSE,
      message = "V2 CLI completed but JSON summary could not be parsed.",
      summary = NULL,
      log = log_txt
    ))
  }

  list(
    ok = TRUE,
    message = "V2 cross-cycle contextualization completed.",
    summary = summary,
    log = log_txt
  )
}

if (identical(sys.nframe(), 0L)) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 2L) {
    cat("Usage: Rscript scripts/run_v2_contextualization.R <input.csv> <output_dir>\n")
    quit(status = 2)
  }
  root <- Sys.getenv("PFAS_SMOKE_PROJECT_ROOT", unset = "")
  if (!nzchar(root)) {
    root <- normalizePath(getwd(), winslash = "/")
  }
  res <- run_v2_serum_contextualization(
    input_csv = args[[1]],
    output_dir = args[[2]],
    project_root = root
  )
  cat(res$log, "\n", sep = "")
  if (!isTRUE(res$ok)) {
    cat("FAIL:", res$message, "\n")
    quit(status = 1)
  }
  cat("PASS run_id=", res$summary$run_id, "\n", sep = "")
}
