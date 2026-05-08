# app.R — PFAS Enterprise 5.0 API demo (sales / customer demo frontend)
# Full 4.0 dashboard: use app_enterprise4_latestpfas.R + LatestPFAS.R

suppressPackageStartupMessages({
  library(shiny)
  library(httr)
  library(jsonlite)
})

api_base <- Sys.getenv("PFAS_API_URL", "https://pfas-enterprise-5.onrender.com")

ui <- fluidPage(
  titlePanel("PFAS Enterprise 5.0"),
  h4("Human-centered PFAS screening intelligence"),
  tags$p("Screening use only. Not a certified laboratory result."),

  sidebarLayout(
    sidebarPanel(
      textInput("sample_id", "Sample ID", "DEMO_001"),
      textInput("dtxsid", "DTXSID", "DTXSID8030271"),
      selectInput("method_id", "Method", c("EPA_533", "EPA_1633")),
      selectInput("matrix", "Matrix", c("water", "sludge", "serum")),
      actionButton("run", "Run Screening")
    ),
    mainPanel(
      h3("Prediction"),
      verbatimTextOutput("result"),
      h3("5.0 Sustainability Metrics"),
      verbatimTextOutput("sustainability")
    )
  )
)

server <- function(input, output, session) {
  result <- eventReactive(input$run, {
    payload <- list(
      sample_id = input$sample_id,
      dtxsid = input$dtxsid,
      method_id = input$method_id,
      matrix = input$matrix
    )

    res <- POST(
      paste0(trimws(api_base), "/predict"),
      body = payload,
      encode = "json",
      content_type_json()
    )

    txt <- content(res, "text", encoding = "UTF-8")
    parsed <- tryCatch(fromJSON(txt), error = function(e) list(raw = txt, error = conditionMessage(e)))
    if (status_code(res) >= 400) {
      stop(paste0("API error ", status_code(res), ": ", txt), call. = FALSE)
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
    if (!is.null(r$sustainability)) print(r$sustainability) else cat("(no sustainability block in response)\n")
  })
}

shinyApp(ui, server)
