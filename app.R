# app.R — PFAS Enterprise 4.0 (entry point for local run, RStudio Run App, rsconnect)
# Full application logic lives in LatestPFAS.R (kept separate for easier maintenance).
# shinyapps.io: Rscript scripts/deploy_shinyapps.R  (do not deploy .Rprofile — see rsconnect *.dcf ignoredFiles)

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
