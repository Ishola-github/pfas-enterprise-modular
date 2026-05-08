# app.R — Combined entry: Enterprise 4.0 dashboard (LatestPFAS.R) + Cloud API 5.0 tab
# Run App in RStudio from the project root (same working directory as LatestPFAS.R expects).

suppressPackageStartupMessages({
  library(shiny)
  library(httr)
  library(jsonlite)
})

api5_ui <- function(id) {
  ns <- NS(id)
  fluidPage(
    titlePanel("PFAS Enterprise 5.0 (cloud API)"),
    h4("Human-centered PFAS screening intelligence"),
    tags$p(
      "Screening use only. Not a certified laboratory result. ",
      tags$strong(
        "PFAS Enterprise 5.0 is a screening decision-support platform, not a certified laboratory replacement."
      )
    ),
    helpText(
      "API base URL: ",
      tags$code(Sys.getenv("PFAS_API_URL", "https://pfas-enterprise-5.onrender.com")),
      " — override with ",
      tags$code('Sys.setenv(PFAS_API_URL = "https://your-host.onrender.com")'),
      " before ",
      tags$code("Run App"),
      "."
    ),
    sidebarLayout(
      sidebarPanel(
        textInput(ns("sample_id"), "Sample ID", "DEMO_001"),
        textInput(ns("dtxsid"), "DTXSID", "DTXSID8030271"),
        selectInput(ns("method_id"), "Method", c("EPA_533", "EPA_1633")),
        selectInput(ns("matrix"), "Matrix", c("water", "sludge", "serum")),
        actionButton(ns("run"), "Run Screening")
      ),
      mainPanel(
        h3("Prediction"),
        verbatimTextOutput(ns("result")),
        h3("5.0 Sustainability metrics"),
        verbatimTextOutput(ns("sustainability"))
      )
    )
  )
}

api5_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    result <- eventReactive(input$run, {
      api_base <- trimws(Sys.getenv("PFAS_API_URL", "https://pfas-enterprise-5.onrender.com"))
      payload <- list(
        sample_id = input$sample_id,
        dtxsid = input$dtxsid,
        method_id = input$method_id,
        matrix = input$matrix
      )

      res <- httr::POST(
        paste0(api_base, "/predict"),
        body = payload,
        encode = "json",
        httr::content_type_json()
      )

      txt <- httr::content(res, "text", encoding = "UTF-8")
      parsed <- tryCatch(jsonlite::fromJSON(txt), error = function(e) {
        list(raw = txt, error = conditionMessage(e))
      })
      if (httr::status_code(res) >= 400) {
        stop(paste0("API error ", httr::status_code(res), ": ", txt), call. = FALSE)
      }
      parsed
    })

    output$result <- renderPrint({
      req(result())
      r <- result()
      if (!is.null(r$error)) {
        cat("Could not parse JSON:\n")
        print(r)
        return(invisible(NULL))
      }
      keep <- c("run_id", "prediction", "confidence", "ad_warning", "intended_use")
      present <- keep[keep %in% names(r)]
      print(r[present])
    })

    output$sustainability <- renderPrint({
      req(result())
      r <- result()
      if (!is.null(r$sustainability)) {
        print(r$sustainability)
      } else {
        cat("(no sustainability block in response)\n")
      }
    })
  })
}

latest_path <- "LatestPFAS.R"
if (!file.exists(latest_path)) {
  stop(
    "Missing LatestPFAS.R in working directory. Use app_enterprise5_api_only.R for API-only, or open the project root.",
    call. = FALSE
  )
}

latest_env <- new.env(parent = globalenv())
sys.source(latest_path, envir = latest_env, encoding = "UTF-8")

if (!exists("ui", envir = latest_env, inherits = FALSE) || !exists("server", envir = latest_env, inherits = FALSE)) {
  stop("LatestPFAS.R did not define ui and server in the sourced environment.", call. = FALSE)
}

legacy_ui <- get("ui", envir = latest_env)
legacy_server <- get("server", envir = latest_env)

combined_ui <- navbarPage(
  title = "PFAS Enterprise",
  header = tags$head(
    tags$style(HTML(".navbar-default { margin-bottom: 12px; }"))
  ),
  tabPanel("Enterprise 4.0", legacy_ui),
  tabPanel("Cloud API 5.0", api5_ui("api5"))
)

combined_server <- function(input, output, session) {
  legacy_server(input, output, session)
  api5_server("api5")
}

shinyApp(combined_ui, combined_server)
