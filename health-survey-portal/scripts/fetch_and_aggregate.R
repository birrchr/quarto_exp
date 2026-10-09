# ─────────────────────────────────────────────────────────────────────────────
# fetch_and_aggregate.R
# Build-time step: pull survey records from the secure source, reduce them to
# suppressed, aggregate-only cells, and write data/processed_summary.csv.
#
# Only the aggregate CSV leaves this script. Raw records are held in memory
# (or never leave the database, for the DBI source) and are not written out.
#
# Data source — set exactly one, via environment variables / CI variables:
#   DATA_API_URL + DATA_API_TOKEN   HTTPS endpoint returning CSV or JSON records
#   DB_CONN_STR  [+ DATA_TABLE]     ODBC connection string; aggregation runs
#                                   in-database, default table "survey_responses"
#   DATA_LOCAL_FILE                 Local CSV or Parquet of synthetic data
#                                   (development only; Parquet needs arrow)
#
# Governance knobs (optional):
#   MIN_CELL_SIZE   Cells with fewer respondents are suppressed   (default 10)
#   ROUND_BASE      Published counts are rounded to this base     (default 5)
#
# Run:
#   Rscript scripts/fetch_and_aggregate.R
# Sourcing the file (e.g. from tests/) defines the functions without running.
# ─────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(dplyr)
})

OUTPUT_PATH <- "data/processed_summary.csv"

MIN_CELL_SIZE <- as.integer(Sys.getenv("MIN_CELL_SIZE", "10"))
ROUND_BASE    <- as.integer(Sys.getenv("ROUND_BASE", "5"))

# Breakdown dimensions published in the dashboard; each is also split by gender.
DIMENSIONS <- c("province", "age_group", "income_bracket", "education")
SPLIT      <- "gender"

# Allowlist: only these columns are ever read from the source. Anything else
# (names, IDs, postcodes, free text, timestamps) is dropped before aggregation.
INDICATORS <- c(
  "any_chronic", "has_family_doctor", "unmet_care_need",
  "bmi", "mental_health_score"
)
ALLOWED_COLUMNS <- c(DIMENSIONS, SPLIT, INDICATORS)

METRICS <- c(
  "pct_any_chronic", "pct_family_doctor", "pct_unmet_need",
  "mean_bmi", "mean_mh_score"
)


# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------

env_or_null <- function(name) {
  value <- Sys.getenv(name, unset = "")
  if (nzchar(value)) value else NULL
}

# Returns a data frame (API / local) or a lazy dbplyr table (DB), restricted
# to the allowlisted columns. Credentials are never printed.
open_source <- function() {
  api_url  <- env_or_null("DATA_API_URL")
  conn_str <- env_or_null("DB_CONN_STR")
  local    <- env_or_null("DATA_LOCAL_FILE")

  configured <- c(api = !is.null(api_url), db = !is.null(conn_str), local = !is.null(local))
  if (sum(configured) != 1) {
    stop(
      "Set exactly one data source: DATA_API_URL (+ DATA_API_TOKEN), ",
      "DB_CONN_STR, or DATA_LOCAL_FILE. Currently set: ",
      if (any(configured)) paste(names(configured)[configured], collapse = ", ") else "none",
      call. = FALSE
    )
  }

  src <- if (!is.null(api_url)) {
    fetch_api(api_url)
  } else if (!is.null(conn_str)) {
    open_db(conn_str)
  } else {
    read_local(local)
  }

  missing <- setdiff(ALLOWED_COLUMNS, colnames(src))
  if (length(missing) > 0) {
    stop("Source is missing required columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  select(src, all_of(ALLOWED_COLUMNS))
}

fetch_api <- function(url) {
  token <- env_or_null("DATA_API_TOKEN")
  if (is.null(token)) stop("DATA_API_URL is set but DATA_API_TOKEN is not.", call. = FALSE)

  message("Fetching records from API (DATA_API_URL).")
  # httr2 redacts the Authorization header in printed requests and errors.
  resp <- httr2::request(url) |>
    httr2::req_auth_bearer_token(token) |>
    httr2::req_timeout(120) |>
    httr2::req_retry(max_tries = 3) |>
    httr2::req_perform()

  if (grepl("json", httr2::resp_content_type(resp), fixed = TRUE)) {
    as.data.frame(httr2::resp_body_json(resp, simplifyVector = TRUE))
  } else {
    utils::read.csv(text = httr2::resp_body_string(resp), stringsAsFactors = FALSE)
  }
}

read_local <- function(path) {
  message("Using local development file (DATA_LOCAL_FILE).")
  if (grepl("\\.parquet$", path, ignore.case = TRUE)) {
    as.data.frame(arrow::read_parquet(path))
  } else {
    utils::read.csv(path, stringsAsFactors = FALSE)
  }
}

open_db <- function(conn_str) {
  table <- Sys.getenv("DATA_TABLE", "survey_responses")
  message("Connecting to database (DB_CONN_STR), table: ", table)
  con <- DBI::dbConnect(odbc::odbc(), .connection_string = conn_str)
  # I() lets DATA_TABLE be schema-qualified, e.g. "analytics.survey_responses".
  tbl(con, I(table))
}


# ---------------------------------------------------------------------------
# Aggregation & disclosure control
# ---------------------------------------------------------------------------

# One row per (dimension level × gender). Runs in-database for DBI sources.
summarise_cells <- function(src, dim, split = NULL) {
  src |>
    group_by(!!!rlang::syms(c(dim, split))) |>
    summarise(
      n                 = n(),
      pct_any_chronic   = 100 * mean(as.numeric(any_chronic), na.rm = TRUE),
      pct_family_doctor = 100 * mean(as.numeric(has_family_doctor), na.rm = TRUE),
      pct_unmet_need    = 100 * mean(as.numeric(unmet_care_need), na.rm = TRUE),
      mean_bmi          = mean(as.numeric(bmi), na.rm = TRUE),
      mean_mh_score     = mean(as.numeric(mental_health_score), na.rm = TRUE),
      .groups = "drop"
    ) |>
    collect() |>
    mutate(
      dimension = dim,
      group     = coalesce(as.character(.data[[dim]]), "Not stated"),
      gender    = if (is.null(split)) "All" else coalesce(as.character(.data[[split]]), "Not stated"),
      n         = as.integer(n)
    ) |>
    select(dimension, group, gender, n, all_of(METRICS))
}

# Complementary suppression for the split (by-gender) cells of one group. The
# group's "All" row is published, so a single hidden split cell could be
# recovered as All minus the visible ones. Keep hiding the smallest visible
# cell until at least two are hidden and together they cover MIN_CELL_SIZE.
protect_split_cells <- function(n, suppressed, is_split) {
  hide   <- suppressed[is_split]
  cell_n <- n[is_split]
  if (!any(hide)) return(suppressed)
  while (!all(hide) && (sum(hide) < 2 || sum(cell_n[hide]) < MIN_CELL_SIZE)) {
    visible <- which(!hide)
    hide[visible[which.min(cell_n[visible])]] <- TRUE
  }
  suppressed[is_split] <- hide
  suppressed
}

apply_disclosure_control <- function(cells) {
  cells |>
    group_by(dimension, group) |>
    mutate(suppressed = protect_split_cells(n, n < MIN_CELL_SIZE, gender != "All")) |>
    ungroup() |>
    mutate(
      # Publish rounded counts only; metrics come from the true n.
      n = if_else(suppressed, NA_integer_, as.integer(ROUND_BASE * round(n / ROUND_BASE))),
      across(all_of(METRICS), \(x) if_else(suppressed, NA_real_, round(x, 1)))
    )
}

# All published cells: each dimension overall and split by gender.
build_summary <- function(src) {
  cells <- bind_rows(lapply(DIMENSIONS, function(dim) {
    bind_rows(summarise_cells(src, dim), summarise_cells(src, dim, SPLIT))
  }))

  cells |>
    apply_disclosure_control() |>
    arrange(dimension, group, gender) |>
    as.data.frame()
}

# Last line of defence before anything is written.
validate_output <- function(out) {
  expected <- c("dimension", "group", "gender", "n", METRICS, "suppressed")
  stopifnot(
    "unexpected columns in output" = identical(colnames(out), expected),
    "unsuppressed cell below threshold" = all(is.na(out$n) | out$n >= MIN_CELL_SIZE - ROUND_BASE / 2),
    "suppressed cell leaks values" = all(is.na(as.matrix(out[out$suppressed, c("n", METRICS)]))),
    "lone suppressed split cell" = all(
      tapply(out$suppressed[out$gender != "All"],
             paste(out$dimension, out$group)[out$gender != "All"],
             function(s) sum(s) != 1 || length(s) == 1)
    )
  )
  invisible(out)
}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main <- function() {
  src <- open_source()
  if (inherits(src, "tbl_sql")) {
    on.exit(DBI::dbDisconnect(dbplyr::remote_con(src)), add = TRUE)
  }

  out <- build_summary(src)
  validate_output(out)

  dir.create(dirname(OUTPUT_PATH), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(out, OUTPUT_PATH, row.names = FALSE, na = "")

  message(sprintf(
    "Wrote %s: %d cells (%d suppressed, threshold n < %d, counts rounded to base %d).",
    OUTPUT_PATH, nrow(out), sum(out$suppressed), MIN_CELL_SIZE, ROUND_BASE
  ))
}

if (sys.nframe() == 0) main()
