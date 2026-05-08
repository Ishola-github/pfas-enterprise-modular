ulib <- file.path(
  Sys.getenv("USERPROFILE"),
  "Documents", "R", "win-library",
  paste(R.version$major, strsplit(R.version$minor, ".", fixed = TRUE)[[1L]][1L], sep = ".")
)
cat(ulib)
