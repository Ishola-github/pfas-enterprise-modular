# app_enterprise4_latestpfas.R — Full PFAS Enterprise 4.0 dashboard (LatestPFAS.R)
# Entry point for RStudio Run App when you need the legacy monolith UI.
# Default repo entry app.R targets the 5.0 API demo instead.

suppressPackageStartupMessages({
  library(shiny)
  library(shinymanager)
  library(shinydashboard)
  library(DT)
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(purrr)
  library(stringr)
  library(scales)
  library(jsonlite)
  library(digest)
  library(DBI)
  library(RSQLite)
})

latest <- "LatestPFAS.R"
if (!file.exists(latest)) {
  stop("Missing ", latest, ". Clone the full repository or restore LatestPFAS.R.", call. = FALSE)
}

res <- source(latest, local = TRUE, encoding = "UTF-8")
if (is.null(res$value) || !inherits(res$value, "shiny.appobj")) {
  stop(
    "Failed to load PFAS Enterprise 4.0 from LatestPFAS.R (expected shinyApp object as last expression).",
    call. = FALSE
  )
}

res$value
