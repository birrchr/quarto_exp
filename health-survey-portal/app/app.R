# ─────────────────────────────────────────────────────────────────────────────
# CanHealth 2024 — interactive summary (Shinylive / webR)
#
# Runs entirely in the browser. It only ever sees processed_summary.csv, the
# suppressed aggregate table produced by scripts/fetch_and_aggregate.R and
# bundled into the page by scripts/build_dashboard_app.R.
#
# Local test (desktop R, from the project root):
#   Rscript -e 'shiny::runApp("app")'   # needs app/processed_summary.csv
# ─────────────────────────────────────────────────────────────────────────────

library(shiny)
library(bslib)
library(plotly)

summary_df <- read.csv("processed_summary.csv", stringsAsFactors = FALSE)

DIMENSIONS <- c(
  "Province"        = "province",
  "Age group"       = "age_group",
  "Household income" = "income_bracket",
  "Education"       = "education"
)

METRICS <- c(
  "Any chronic condition (%)" = "pct_any_chronic",
  "Has a family doctor (%)"   = "pct_family_doctor",
  "Unmet care need (%)"       = "pct_unmet_need",
  "Mean BMI"                  = "mean_bmi",
  "Mean PHQ-4 score"          = "mean_mh_score"
)

ui <- page_sidebar(
  title = "CanHealth 2024 — interactive summary",
  theme = bs_theme(version = 5, preset = "flatly", primary = "#1a7f8e"),
  sidebar = sidebar(
    selectInput("dimension", "Break down by", DIMENSIONS),
    selectInput("metric", "Indicator", METRICS),
    checkboxInput("by_gender", "Split by gender", value = FALSE),
    helpText(
      "Aggregates only. Cells with too few respondents are suppressed",
      "and counts are rounded."
    )
  ),
  card(
    full_screen = TRUE,
    card_header(textOutput("chart_title", inline = TRUE)),
    plotlyOutput("chart"),
    card_footer(textOutput("suppression_note", inline = TRUE))
  ),
  card(
    card_header("Table"),
    tableOutput("table")
  )
)

server <- function(input, output, session) {
  cells <- reactive({
    rows <- summary_df[summary_df$dimension == input$dimension, ]
    rows <- if (input$by_gender) rows[rows$gender != "All", ] else rows[rows$gender == "All", ]
    rows$value <- rows[[input$metric]]
    rows
  })

  metric_label <- reactive(names(METRICS)[METRICS == input$metric])

  output$chart_title <- renderText({
    paste(metric_label(), "by", tolower(names(DIMENSIONS)[DIMENSIONS == input$dimension]))
  })

  output$chart <- renderPlotly({
    d <- cells()
    p <- if (input$by_gender) {
      plot_ly(d, x = ~group, y = ~value, color = ~gender, type = "bar")
    } else {
      plot_ly(d, x = ~group, y = ~value, type = "bar", marker = list(color = "#1a7f8e"))
    }
    p |>
      layout(
        barmode = "group",
        xaxis = list(title = "", categoryorder = "array", categoryarray = sort(unique(d$group))),
        yaxis = list(title = metric_label()),
        legend = list(orientation = "h"),
        paper_bgcolor = "rgba(0,0,0,0)",
        plot_bgcolor = "rgba(0,0,0,0)"
      ) |>
      config(displaylogo = FALSE)
  })

  output$suppression_note <- renderText({
    n_suppressed <- sum(cells()$suppressed)
    if (n_suppressed == 0) {
      "No cells suppressed in this view."
    } else {
      sprintf("%d cell(s) suppressed for confidentiality and not shown.", n_suppressed)
    }
  })

  output$table <- renderTable({
    d <- cells()
    data.frame(
      Group = d$group,
      Gender = d$gender,
      `Respondents (rounded)` = ifelse(d$suppressed, "suppressed", format(d$n, big.mark = ",")),
      Value = ifelse(d$suppressed, "suppressed", format(d$value, nsmall = 1)),
      check.names = FALSE
    )
  })
}

shinyApp(ui, server)
