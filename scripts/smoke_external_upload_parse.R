# Mirrors External ML delimited path in LatestPFAS.R (staging + read_delimited_robust + sanitize).
# Run from project root: Rscript scripts/smoke_external_upload_parse.R [path/to/file.csv]
 `%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
}

read_delimited_robust <- function(path, sep, header = TRUE, nrows = NA_integer_) {
  if (!nzchar(path %||% "") || !file.exists(path)) return(NULL)
  enc_candidates <- c("UTF-8-BOM", "latin1", "CP1252", "UTF-8", "UTF-16LE", "UTF-16BE")
  nr_limit <- NA_integer_
  if (is.finite(nrows) && !is.na(nrows) && nrows > 0L) nr_limit <- as.integer(nrows)
  quote_modes <- list(default = "\"", none = "")
  for (enc in enc_candidates) {
    for (qm in quote_modes) {
      qch <- qm
      args <- list(
        file = path,
        sep = sep,
        header = header,
        stringsAsFactors = FALSE,
        colClasses = "character",
        check.names = FALSE,
        quote = qch,
        comment.char = "",
        fill = TRUE,
        blank.lines.skip = TRUE,
        allowEscapes = FALSE,
        skipNul = TRUE,
        fileEncoding = enc,
        dec = ".",
        strip.white = TRUE
      )
      if (!is.na(nr_limit)) args$nrows <- nr_limit
      df <- tryCatch(
        suppressWarnings(do.call(utils::read.table, args)),
        error = function(e) NULL
      )
      if (!is.null(df) && is.data.frame(df) && ncol(df) >= 1L) return(df)
    }
  }
  NULL
}

read_first_line_robust <- function(path) {
  if (!nzchar(path %||% "") || !file.exists(path)) return("")
  read_one <- function(enc_raw) {
    tryCatch(
      suppressWarnings(readLines(path, n = 1L, warn = FALSE, encoding = enc_raw)),
      error = function(e) character(0)
    )
  }
  for (enc in c("latin1", "CP1252", "UTF-8")) {
    ln <- read_one(enc)
    if (length(ln) > 0 && nzchar(ln[[1]])) return(ln[[1]])
  }
  for (enc in c("UTF-16LE", "UTF-16BE")) {
    ln <- read_one(enc)
    if (length(ln) > 0 && nzchar(ln[[1]])) return(ln[[1]])
  }
  ln <- tryCatch(suppressWarnings(readLines(path, n = 1L, warn = FALSE)), error = function(e) "")
  if (length(ln) > 0) ln[[1]] else ""
}

sanitize_utf8_df <- function(df, light = FALSE) {
  strip_embedded_nul_chars <- function(v) {
    if (!is.character(v) || !length(v)) return(v)
    z <- intToUtf8(0L)
    hit <- !is.na(v) & nzchar(v) & grepl(z, v, fixed = TRUE)
    if (!any(hit, na.rm = TRUE)) return(v)
    out <- v
    out[hit] <- vapply(
      out[hit],
      function(s) paste(strsplit(s, z, fixed = TRUE)[[1]], collapse = ""),
      FUN.VALUE = "",
      USE.NAMES = FALSE
    )
    out
  }
  df <- as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)
  names(df) <- iconv(names(df), from = "", to = "UTF-8", sub = "")
  names(df) <- trimws(names(df))
  nn <- names(df)
  empty_nm <- is.na(nn) | !nzchar(nn)
  if (any(empty_nm)) nn[empty_nm] <- paste0("__unnamed_col_", which(empty_nm))
  nn <- make.unique(nn, sep = "__dup__")
  names(df) <- nn
  do_iconv <- !isTRUE(light)
  for (nm in names(df)) {
    col <- df[[nm]]
    if (is.character(col)) {
      if (do_iconv) df[[nm]] <- iconv(col, from = "", to = "UTF-8", sub = "")
      df[[nm]] <- strip_embedded_nul_chars(df[[nm]])
      df[[nm]] <- trimws(df[[nm]])
    } else if (is.factor(col)) {
      ch <- as.character(col)
      if (do_iconv) ch <- iconv(ch, from = "", to = "UTF-8", sub = "")
      ch <- strip_embedded_nul_chars(ch)
      df[[nm]] <- trimws(ch)
    }
  }
  df
}

stage_delimited_upload_file <- function(path, ext, peek_max_raw = 4L * 1024^2) {
  ext <- tolower(ext %||% "")
  sz <- suppressWarnings(as.integer(file.info(path)$size %||% 0))
  peek_n <- max(0L, min(sz, as.integer(peek_max_raw)))
  peek_has_nul <- FALSE
  if (peek_n > 0L) {
    buf <- tryCatch(readBin(path, what = "raw", n = peek_n), error = function(e) raw())
    peek_has_nul <- length(buf) > 0L && any(buf == as.raw(0L))
  }
  need_strip <- ext == "txt" && isTRUE(peek_has_nul)
  tmp <- tempfile(fileext = paste0(".", ext))
  if (need_strip && sz > 0L) {
    rawf <- tryCatch(readBin(path, what = "raw", n = sz), error = function(e) NULL)
    if (!is.null(rawf) && length(rawf) > 0L) {
      rawf <- rawf[rawf != as.raw(0L)]
      writeBin(rawf, tmp)
      return(tmp)
    }
    return("")
  }
  if (isTRUE(file.copy(path, tmp, overwrite = TRUE))) return(tmp)
  ""
}

read_upload_delimited_base <- function(path_clean, ext) {
  read_try_best <- function(order) {
    best <- NULL
    best_ncol <- -1L
    for (sep in order) {
      if (!nzchar(sep %||% "")) next
      df <- read_delimited_robust(path_clean, sep = sep)
      if (is.null(df) || !is.data.frame(df) || ncol(df) < 1L) next
      nc <- ncol(df)
      if (nc > best_ncol) {
        best <- df
        best_ncol <- as.integer(nc)
      }
      if (nc >= 2L) return(df)
    }
    best
  }

  sniff_order <- function() {
    first <- read_first_line_robust(path_clean)
    if (!nzchar(first)) return(c(",", "\t", "|", ";"))
    counts <- c(
      comma = lengths(regmatches(first, gregexpr(",", first, fixed = TRUE))),
      tab = lengths(regmatches(first, gregexpr("\t", first, fixed = TRUE))),
      semi = lengths(regmatches(first, gregexpr(";", first, fixed = TRUE))),
      pipe = lengths(regmatches(first, gregexpr("|", first, fixed = TRUE)))
    )
    mx <- suppressWarnings(max(counts, na.rm = TRUE))
    if (!is.finite(mx) || mx < 1L) return(c(",", "\t", "|", ";"))
    hits <- names(counts)[counts == mx]
    sep_map <- c(comma = ",", tab = "\t", semi = ";", pipe = "|")
    sniffed <- unname(sep_map[hits])
    unique(c(sniffed, ",", "\t", "|", ";"))
  }

  ext <- tolower(ext %||% "")
  all_seps <- c(",", "\t", "|", ";")
  if (ext == "csv") return(read_try_best(unique(c(",", all_seps))))
  if (ext == "tsv") return(read_try_best(unique(c("\t", all_seps))))
  if (identical(ext, "txt")) return(read_try_best(sniff_order()))
  read_try_best(all_seps)
}

smoke_one <- function(label, path, ext) {
  message("--- ", label, " ---")
  message("Path: ", normalizePath(path, winslash = "/", mustWork = TRUE))
  tmp <- stage_delimited_upload_file(path, ext)
  on.exit(unlink(tmp), add = TRUE)
  if (is.null(tmp) || !nzchar(tmp) || !file.exists(tmp)) {
    stop("staging failed", call. = FALSE)
  }
  df <- read_upload_delimited_base(tmp, ext)
  if (is.null(df) || !is.data.frame(df) || ncol(df) < 1L) {
    stop("parse failed", call. = FALSE)
  }
  ncell <- nrow(df) * ncol(df)
  lite <- is.finite(ncell) && ncell > 1e6L
  out <- sanitize_utf8_df(df, light = lite)
  message("PASS dim=", nrow(out), "x", ncol(out), " light_sanitize=", lite)
  print(utils::head(out, 3))
  invisible(TRUE)
}

args <- commandArgs(trailingOnly = TRUE)
repo_test <- normalizePath("data/test_upload/test_upload.csv", mustWork = TRUE)
extras <- if (length(args) >= 1) args else character(0)

ok <- TRUE
tryCatch(
  smoke_one("repo smoke CSV", repo_test, "csv"),
  error = function(e) {
    ok <<- FALSE
    message("FAIL repo: ", conditionMessage(e))
  }
)

sample_od <- "C:/Users/techj/OneDrive/Desktop/python_work/PFAS on R Studio/UCMR5_533_sample.csv"
if (file.exists(sample_od)) {
  tryCatch(
    smoke_one("OneDrive UCMR sample (if present)", sample_od, "csv"),
    error = function(e) {
      ok <<- FALSE
      message("FAIL sample: ", conditionMessage(e))
    }
  )
} else {
  message("(optional) No OneDrive sample at: ", sample_od)
}

for (p in extras) {
  if (!file.exists(p)) {
    message("Skip missing: ", p)
    next
  }
  ext <- tolower(tools::file_ext(p))
  if (!ext %in% c("csv", "tsv", "txt")) {
    message("Skip non-delimited: ", p)
    next
  }
  tryCatch(
    smoke_one(basename(p), p, ext),
    error = function(e) {
      ok <<- FALSE
      message("FAIL ", p, ": ", conditionMessage(e))
    }
  )
}

if (!ok) quit(status = 1)
message("All smoke checks passed.")
