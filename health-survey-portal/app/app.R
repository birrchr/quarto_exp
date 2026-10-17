# ─────────────────────────────────────────────────────────────────────────────
# CanHealth 2024 — interactive summary (Shinylive / webR)
#
# Runs entirely in the browser. It only ever sees processed_summary.csv, the
# suppressed aggregate table produced by scripts/fetch_and_aggregate.R and
# bundled into the page by scripts/build_dashboard_app.R.
#
# Layout: national headline tiles, one small-multiple dot plot per indicator
# (all on screen at once, same group order), and a heatmap of every group ×
# indicator against the national figure. Clicking a dot highlights that group
# in every chart.
#
# Local test (desktop R, from the project root):
#   Rscript -e 'shiny::runApp("app")'   # needs app/processed_summary.csv
# ─────────────────────────────────────────────────────────────────────────────

library(shiny)
library(bslib)
library(plotly)

summary_df <- read.csv("processed_summary.csv", stringsAsFactors = FALSE)

DIMENSIONS <- c(
  "Province"         = "province",
  "Age group"        = "age_group",
  "Household income" = "income_bracket",
  "Education"        = "education"
)

INDICATORS <- data.frame(
  id    = c("pct_any_chronic", "pct_family_doctor", "pct_unmet_need", "mean_bmi", "mean_mh_score"),
  label = c("Any chronic condition", "Has a family doctor", "Unmet care need",
            "Mean BMI", "Mean PHQ-4 score"),
  short = c("Chronic condition", "Family doctor", "Unmet need", "BMI", "PHQ-4"),
  pct   = c(TRUE, TRUE, TRUE, FALSE, FALSE),
  stringsAsFactors = FALSE
)

# Ordered categories read top to bottom in their natural order; anything not
# listed (e.g. provinces) is alphabetical.
GROUP_ORDER <- list(
  age_group      = c("18–24", "25–34", "35–44", "45–54", "55–64", "65–74", "75+"),
  income_bracket = c("Under $30K", "$30K–$59K", "$60K–$99K", "$100K–$149K", "$150K+"),
  education      = c("Less than high school", "High school diploma", "College / trades",
                     "Undergraduate degree", "Graduate degree")
)

# Monochrome blue throughout, so colour never implies good or bad. The three
# gender series are validated ramp steps and also differ in marker shape.
# "Prefer not to say" is mostly suppressed, so it is shown in the table only.
GENDER_COLORS  <- c("Woman" = "#104281", "Man" = "#2a78d6", "Non-binary / Other" = "#86b6ef")
GENDER_SYMBOLS <- c("Woman" = "circle", "Man" = "diamond", "Non-binary / Other" = "square")
GENDER_GLYPHS  <- c("Woman" = "●", "Man" = "◆", "Non-binary / Other" = "■")

INK       <- "#0b0b0b"
INK_2     <- "#52514e"
MUTED     <- "#898781"
GRID      <- "#e1e0d9"
BASELINE  <- "#c3c2b7"
SURFACE   <- "#fcfcfb"
ACCENT    <- "#1c5cab"
SEQUENTIAL <- list(c(0, "#cde2fb"), c(1, "#3987e5"))
FONT      <- list(family = "system-ui, -apple-system, 'Segoe UI', sans-serif", size = 12, color = INK_2)

# Shinylive loads a widget's JavaScript when its first output arrives, so
# several plotly outputs rendering at once race it ("Plotly is not defined").
# Shipping the scripts with the page avoids that.
PLOTLY_DEPS <- htmltools::findDependencies(
  htmltools::as.tags(plot_ly(type = "scatter", mode = "markers"))
)

national <- summary_df[summary_df$dimension == "overall" & summary_df$gender == "All", ]

order_groups <- function(dim, groups) {
  preset <- GROUP_ORDER[[dim]]
  if (is.null(preset)) sort(groups) else c(intersect(preset, groups), sort(setdiff(groups, preset)))
}

fmt_value <- function(x, pct) {
  ifelse(is.na(x), "suppressed", if (pct) sprintf("%.1f%%", x) else sprintf("%.1f", x))
}

fmt_n <- function(n) ifelse(is.na(n), "suppressed", format(n, big.mark = ","))


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

kpi_tiles <- c(
  list(value_box(
    title = "Respondents",
    value = fmt_n(national$n),
    p("Rounded to the nearest 5"),
    theme = value_box_theme(bg = SURFACE, fg = INK)
  )),
  lapply(seq_len(nrow(INDICATORS)), function(i) {
    ind <- INDICATORS[i, ]
    value_box(
      title = ind$label,
      value = fmt_value(national[[ind$id]], ind$pct),
      p("All respondents"),
      theme = value_box_theme(bg = SURFACE, fg = INK)
    )
  })
)

facet_cards <- lapply(seq_len(nrow(INDICATORS)), function(i) {
  ind <- INDICATORS[i, ]
  card(
    full_screen = TRUE,
    card_header(ind$label),
    plotlyOutput(paste0("facet_", ind$id), height = "360px"),
    card_footer(class = "small text-muted", textOutput(paste0("note_", ind$id), inline = TRUE))
  )
})

ui <- page_sidebar(
  title = "CanHealth 2024 — health indicators at a glance",
  fillable = FALSE,
  theme = bs_theme(
    version = 5, preset = "flatly", primary = ACCENT, bg = "#f9f9f7", fg = INK,
    base_font = font_collection("system-ui", "-apple-system", "Segoe UI", "sans-serif")
  ),
  htmltools::attachDependencies(tags$span(), PLOTLY_DEPS),
  tags$head(tags$style(HTML("
    .bslib-value-box .value-box-title { font-size: .85rem; color: #52514e; }
    .bslib-value-box .value-box-value { font-size: 1.9rem; font-weight: 600; }
    .bslib-value-box p { font-size: .75rem; color: #898781; margin: 0; }
    .legend-row { display: flex; flex-wrap: wrap; gap: 1.25rem; align-items: center;
                  font-size: .85rem; color: #52514e; margin: .25rem 0 .75rem; }
    .legend-row .swatch { display: inline-block; width: 10px; height: 10px;
                          border-radius: 50%; margin-right: .4rem; vertical-align: middle; }
    .legend-row .glyph { margin-right: .35rem; font-size: 1rem; line-height: 1; }
    .legend-row .rule { display: inline-block; width: 16px; border-top: 2px dashed #898781;
                        margin-right: .4rem; vertical-align: middle; }
  "))),
  sidebar = sidebar(
    width = 270,
    radioButtons("dimension", "Break down by", DIMENSIONS),
    radioButtons("view", "Show", c("All respondents" = "all", "Women vs men vs non-binary" = "gender")),
    selectInput("highlight", "Highlight a group", c("None" = "")),
    helpText("Tip: click any dot to highlight that group in every chart; click it again to clear."),
    hr(),
    helpText(
      "Aggregates only. Cells with fewer than 10 respondents are suppressed,",
      "along with enough neighbouring gender cells that they can't be worked out",
      "by subtraction. Counts are rounded to the nearest 5. Estimates are unweighted."
    )
  ),
  layout_columns(fill = FALSE, col_widths = breakpoints(sm = 6, md = 4, xl = 2), !!!kpi_tiles),
  uiOutput("legend"),
  layout_column_wrap(width = "260px", fill = FALSE, heights_equal = "row", !!!facet_cards),
  card(
    full_screen = TRUE,
    card_header("Every indicator at once: which groups are highest and lowest"),
    plotlyOutput("heatmap", height = "440px"),
    card_footer(
      class = "small text-muted",
      "Within each indicator, darker = higher value. Hover a cell for its difference ",
      "from the national figure. All respondents."
    )
  ),
  accordion(
    open = FALSE,
    accordion_panel("Data table", tableOutput("table"))
  )
)


# ---------------------------------------------------------------------------
# Charts
# ---------------------------------------------------------------------------

base_layout <- function(p, groups, ind) {
  p |>
    layout(
      font = FONT,
      showlegend = FALSE,
      margin = list(l = 8, r = 16, t = 8, b = 32),
      paper_bgcolor = "rgba(0,0,0,0)",
      plot_bgcolor = "rgba(0,0,0,0)",
      xaxis = list(title = "", zeroline = FALSE, gridcolor = GRID, linecolor = BASELINE,
                   ticksuffix = if (ind$pct) "%" else "", fixedrange = TRUE),
      yaxis = list(title = "", categoryorder = "array", categoryarray = rev(groups),
                   showgrid = TRUE, gridcolor = GRID, automargin = TRUE, fixedrange = TRUE,
                   tickfont = list(color = INK_2)),
      shapes = list(list(
        type = "line", xref = "x", yref = "paper", y0 = 0, y1 = 1,
        x0 = national[[ind$id]], x1 = national[[ind$id]],
        line = list(color = MUTED, width = 1.5, dash = "dash")
      )),
      hoverlabel = list(bgcolor = SURFACE, bordercolor = BASELINE, font = list(color = INK))
    ) |>
    config(displayModeBar = FALSE, responsive = TRUE)
}

# One small multiple: a dot per group (or a dumbbell across genders).
facet_plot <- function(rows, ind, dim, view, highlight, source) {
  groups <- order_groups(dim, unique(rows$group))
  rows$value <- rows[[ind$id]]
  dimmed <- function(group) if (nzchar(highlight)) ifelse(group == highlight, 1, 0.25) else 1

  if (view == "all") {
    d <- rows[rows$gender == "All" & !rows$suppressed, ]
    d$tip <- sprintf("<b>%s</b><br>%s<br>n ≈ %s", d$group, fmt_value(d$value, ind$pct), fmt_n(d$n))
    d$national <- national[[ind$id]]
    colors <- if (nzchar(highlight)) ifelse(d$group == highlight, ACCENT, BASELINE) else ACCENT
    p <- plot_ly(source = source) |>
      add_segments(
        data = d, x = ~national, xend = ~value, y = ~group, yend = ~group,
        line = list(color = BASELINE, width = 2), hoverinfo = "skip"
      ) |>
      add_markers(
        data = d, x = ~value, y = ~group, customdata = ~group,
        marker = list(size = 11, color = colors, line = list(color = SURFACE, width = 2)),
        hovertext = ~tip, hoverinfo = "text"
      )
  } else {
    d <- rows[rows$gender %in% names(GENDER_COLORS) & !rows$suppressed, ]
    spans <- do.call(rbind, lapply(split(d, d$group), function(g) {
      if (nrow(g) < 2) return(NULL)
      data.frame(group = g$group[1], lo = min(g$value), hi = max(g$value))
    }))
    p <- plot_ly(source = source)
    if (!is.null(spans)) {
      p <- add_segments(
        p, data = spans, x = ~lo, xend = ~hi, y = ~group, yend = ~group,
        line = list(color = BASELINE, width = 2), hoverinfo = "skip"
      )
    }
    for (g in names(GENDER_COLORS)) {
      dg <- d[d$gender == g, ]
      if (nrow(dg) == 0) next
      dg$tip <- sprintf("<b>%s</b> · %s<br>%s<br>n ≈ %s", dg$group, g,
                        fmt_value(dg$value, ind$pct), fmt_n(dg$n))
      p <- add_markers(
        p, data = dg, x = ~value, y = ~group, customdata = ~group, name = g,
        marker = list(size = 11, color = GENDER_COLORS[[g]], symbol = GENDER_SYMBOLS[[g]],
                      opacity = dimmed(dg$group),
                      line = list(color = SURFACE, width = 2)),
        hovertext = ~tip, hoverinfo = "text"
      )
    }
  }

  base_layout(p, groups, ind) |> event_register("plotly_click")
}

heatmap_plot <- function(rows, dim, highlight) {
  d <- rows[rows$gender == "All", ]
  groups <- order_groups(dim, unique(d$group))
  d <- d[match(groups, d$group), ]

  values <- sapply(INDICATORS$id, function(id) d[[id]])
  values <- matrix(values, nrow = length(groups))
  nat <- unlist(national[INDICATORS$id])
  rel <- sweep(values, 2, nat, function(v, n) 100 * (v - n) / n)
  # Shade each indicator on its own scale: lightest = lowest group, darkest =
  # highest. The indicators have different units, so a shared scale wouldn't work.
  shade <- apply(values, 2, function(v) {
    span <- diff(range(v, na.rm = TRUE))
    if (span == 0) rep(0.5, length(v)) else (v - min(v, na.rm = TRUE)) / span
  })
  shade <- matrix(shade, nrow = length(groups))

  labels <- sapply(seq_len(nrow(INDICATORS)), function(j) fmt_value(values[, j], INDICATORS$pct[j]))
  labels <- matrix(labels, nrow = length(groups))
  tips <- matrix(sprintf(
    "<b>%s</b> · %s<br>%s (national %s)<br>%+.1f%% vs national",
    rep(groups, nrow(INDICATORS)), rep(INDICATORS$label, each = length(groups)),
    labels, rep(mapply(fmt_value, nat, INDICATORS$pct), each = length(groups)), rel
  ), nrow = length(groups))

  # Outline the highlighted row (category positions are 0-based indices).
  row <- match(highlight, groups) - 1
  outline <- if (is.na(row)) list() else list(list(
    type = "rect", xref = "x", yref = "y", x0 = -0.5, x1 = nrow(INDICATORS) - 0.5,
    y0 = row - 0.5, y1 = row + 0.5, line = list(color = INK, width = 2)
  ))

  plot_ly(
    x = INDICATORS$label, y = groups, z = shade, type = "heatmap",
    zmin = 0, zmax = 1, colorscale = SEQUENTIAL, showscale = FALSE,
    text = labels, texttemplate = "%{text}", textfont = list(color = INK, size = 12),
    hovertext = tips, hoverinfo = "text", xgap = 2, ygap = 2
  ) |>
    layout(
      font = FONT,
      margin = list(l = 8, r = 8, t = 8, b = 8),
      paper_bgcolor = "rgba(0,0,0,0)",
      plot_bgcolor = "rgba(0,0,0,0)",
      xaxis = list(title = "", side = "top", fixedrange = TRUE, tickfont = list(color = INK_2)),
      yaxis = list(title = "", autorange = "reversed", fixedrange = TRUE, automargin = TRUE,
                   tickfont = list(color = INK_2)),
      shapes = outline,
      hoverlabel = list(bgcolor = SURFACE, bordercolor = BASELINE, font = list(color = INK))
    ) |>
    config(displayModeBar = FALSE, responsive = TRUE)
}


# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

server <- function(input, output, session) {
  rows <- reactive(summary_df[summary_df$dimension == input$dimension, ])

  observeEvent(input$dimension, {
    groups <- order_groups(input$dimension, unique(rows()$group))
    updateSelectInput(session, "highlight", choices = c("None" = "", groups), selected = "")
  })

  lapply(INDICATORS$id, function(id) {
    ind <- INDICATORS[INDICATORS$id == id, ]
    source <- paste0("src_", id)

    output[[paste0("facet_", id)]] <- renderPlotly(
      facet_plot(rows(), ind, input$dimension, input$view, input$highlight, source)
    )

    output[[paste0("note_", id)]] <- renderText({
      shown <- if (input$view == "all") "All" else names(GENDER_COLORS)
      hidden <- rows()$suppressed & rows()$gender %in% shown
      nat <- sprintf("National: %s", fmt_value(national[[id]], ind$pct))
      if (any(hidden)) sprintf("%s · %d value(s) suppressed", nat, sum(hidden)) else nat
    })

    observeEvent(event_data("plotly_click", source = source, priority = "event"), {
      # y is the group's row, whichever trace (dot or connecting line) was hit.
      clicked <- event_data("plotly_click", source = source)$y[[1]]
      selected <- if (identical(clicked, input$highlight)) "" else clicked
      updateSelectInput(session, "highlight", selected = selected)
    })
  })

  output$legend <- renderUI({
    items <- if (input$view == "all") {
      list(tags$span(tags$span(class = "swatch", style = sprintf("background:%s", ACCENT)), "Group value"))
    } else {
      lapply(names(GENDER_COLORS), function(g) {
        tags$span(tags$span(class = "glyph", style = sprintf("color:%s", GENDER_COLORS[[g]]),
                            GENDER_GLYPHS[[g]]), g)
      })
    }
    div(class = "legend-row", items,
        tags$span(tags$span(class = "rule"), "National, all respondents"),
        if (input$view == "gender") tags$span("“Prefer not to say” is in the data table only."))
  })

  output$heatmap <- renderPlotly(heatmap_plot(rows(), input$dimension, input$highlight))

  output$table <- renderTable({
    d <- rows()
    d <- d[order(match(d$group, order_groups(input$dimension, unique(d$group))), d$gender), ]
    out <- data.frame(Group = d$group, Gender = d$gender, `Respondents (rounded)` = fmt_n(d$n),
                      check.names = FALSE)
    for (i in seq_len(nrow(INDICATORS))) {
      out[[INDICATORS$label[i]]] <- fmt_value(d[[INDICATORS$id[i]]], INDICATORS$pct[i])
    }
    out
  }, striped = TRUE, hover = TRUE, spacing = "s", width = "100%")
}

shinyApp(ui, server)
