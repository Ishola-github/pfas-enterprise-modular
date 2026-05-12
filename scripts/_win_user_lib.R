# Shared helper: Windows per-user library path (RStudio vs Rscript, LocalAppData vs Documents).
# Sourced by scripts/install_r_deps_win_user_lib.R and r_user_lib_path.R

win_user_lib_dir <- function() {
  e <- trimws(Sys.getenv("R_LIBS_USER", unset = ""))
  if (nzchar(e)) {
    return(normalizePath(path.expand(e), winslash = "/", mustWork = FALSE))
  }
  maj <- R.version$major
  min1 <- strsplit(R.version$minor, ".", fixed = TRUE)[[1L]][1L]
  ver <- paste(maj, min1, sep = ".")
  local <- normalizePath(
    path.expand(file.path(Sys.getenv("LOCALAPPDATA"), "R", "win-library", ver)),
    winslash = "/",
    mustWork = FALSE
  )
  docs <- normalizePath(
    path.expand(file.path(Sys.getenv("USERPROFILE"), "Documents", "R", "win-library", ver)),
    winslash = "/",
    mustWork = FALSE
  )
  if (dir.exists(local)) return(local)
  if (dir.exists(docs)) return(docs)
  # Default for new installs (recent R for Windows uses LocalAppData)
  local
}
