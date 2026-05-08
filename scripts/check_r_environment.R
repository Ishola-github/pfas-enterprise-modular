# Quick diagnostic: which R, which libraries, which env vars.
# Run: Rscript scripts/check_r_environment.R
# Or from PowerShell: & "C:\Program Files\R\R-x.y.z\bin\Rscript.exe" scripts/check_r_environment.R

cat("=== R.version.string ===\n")
cat(R.version.string, "\n\n")

cat("=== .libPaths() ===\n")
print(.libPaths())

cat("\n=== Sys.getenv(\"R_LIBS_USER\") ===\n")
u <- Sys.getenv("R_LIBS_USER")
if (nzchar(u)) cat(u, "\n") else cat("(empty)\n")

cat("\n=== Sys.getenv(\"R_LIBS\") ===\n")
l <- Sys.getenv("R_LIBS")
if (nzchar(l)) cat(l, "\n") else cat("(empty)\n")

cat("\n=== sessionInfo() (truncated header) ===\n")
print(sessionInfo())
