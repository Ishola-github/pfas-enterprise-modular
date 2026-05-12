# Print the user library path this R session should use (stdout only).
argv <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", argv, value = TRUE)
script_dir <- if (length(file_arg)) {
  dirname(normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/"))
} else {
  getwd()
}
source(file.path(script_dir, "_win_user_lib.R"))
cat(win_user_lib_dir())
