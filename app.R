# app.R — PFAS Enterprise 5.0 entry (LatestPFAS.R includes Cloud API tab)
# For API-only UI without the full dashboard: shiny::runApp("app_enterprise5_api_only.R")

latest <- "LatestPFAS.R"
if (!file.exists(latest)) {
  stop("Missing ", latest, ". Clone the full repository or restore LatestPFAS.R.", call. = FALSE)
}

res <- source(latest, local = TRUE, encoding = "UTF-8")
if (is.null(res$value) || !inherits(res$value, "shiny.appobj")) {
  stop(
    "Failed to load PFAS Enterprise 5.0 from LatestPFAS.R (expected shinyApp object as last expression).",
    call. = FALSE
  )
}

res$value
