# ─────────────────────────────────────────────────────────────────────────────
# test_disclosure.R
# Checks the aggregation and disclosure control in fetch_and_aggregate.R on a
# small in-memory dataset. No data source or credentials needed.
#
# Run from the project root:
#   Rscript tests/test_disclosure.R
# ─────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages(library(testthat))

Sys.setenv(MIN_CELL_SIZE = "10", ROUND_BASE = "5")
source("scripts/fetch_and_aggregate.R")

# n identical respondents in one province/gender; the first `chronic` of them
# have a chronic condition.
records <- function(province, gender, n, chronic = 0) {
  data.frame(
    province = province, age_group = "35–44", income_bracket = "$50K–$74K",
    education = "College", gender = gender,
    any_chronic = rep(c(1, 0), c(chronic, n - chronic)),
    has_family_doctor = 1, unmet_care_need = 0, bmi = 25, mental_health_score = 2,
    stringsAsFactors = FALSE
  )
}

cells_for <- function(out, province) {
  rows <- out[out$dimension == "province" & out$group == province, ]
  setNames(split(rows, seq_len(nrow(rows))), rows$gender)
}

src <- rbind(
  # A: one small cell -> the smallest visible cell (Man) is hidden with it.
  records("A", "Woman", 40, chronic = 10), records("A", "Man", 30),
  records("A", "Non-binary / Other", 3),
  # B: two small cells that together are still < 10 -> Man hidden as well.
  records("B", "Woman", 40), records("B", "Man", 30),
  records("B", "Non-binary / Other", 3), records("B", "Prefer not to say", 4),
  # C: nothing small -> nothing hidden.
  records("C", "Woman", 22), records("C", "Man", 23)
)
out <- build_summary(src)

test_that("small cells and their complements are suppressed", {
  a <- cells_for(out, "A")
  expect_true(a[["Non-binary / Other"]]$suppressed)
  expect_true(a[["Man"]]$suppressed)
  expect_false(a[["Woman"]]$suppressed)
  expect_false(a[["All"]]$suppressed)

  b <- cells_for(out, "B")
  expect_true(all(c(b[["Non-binary / Other"]]$suppressed, b[["Prefer not to say"]]$suppressed,
                    b[["Man"]]$suppressed)))
  expect_false(b[["Woman"]]$suppressed)

  expect_false(any(out$suppressed[out$dimension == "province" & out$group == "C"]))
})

test_that("suppressed cells carry no values", {
  hidden <- out[out$suppressed, c("n", METRICS)]
  expect_gt(nrow(hidden), 0)
  expect_true(all(is.na(as.matrix(hidden))))
})

test_that("counts are rounded to ROUND_BASE and metrics use the true n", {
  a <- cells_for(out, "A")
  expect_equal(a[["All"]]$n, 75)      # 73 -> 75
  expect_equal(a[["Woman"]]$n, 40)
  expect_equal(cells_for(out, "C")[["All"]]$n, 45)
  expect_equal(a[["Woman"]]$pct_any_chronic, 25)
  expect_equal(a[["All"]]$pct_any_chronic, round(100 * 10 / 73, 1))
})

test_that("output passes validation and has only the expected columns", {
  expect_silent(validate_output(out))
  expect_identical(colnames(out), c("dimension", "group", "gender", "n", METRICS, "suppressed"))
})

test_that("validation rejects a lone suppressed split cell", {
  bad <- out
  a_man <- which(bad$dimension == "province" & bad$group == "A" & bad$gender == "Man")
  bad$suppressed[a_man] <- FALSE
  bad$n[a_man] <- 30
  expect_error(validate_output(bad), "lone suppressed split cell")
})

test_that("only allowlisted columns are read from the source", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path))
  write.csv(cbind(src, name = "Jane Doe", postcode = "K1A 0B1"), path, row.names = FALSE)

  env <- c(DATA_API_URL = "", DB_CONN_STR = "", DATA_LOCAL_FILE = path)
  old <- Sys.getenv(names(env), unset = NA)
  do.call(Sys.setenv, as.list(env))
  on.exit(for (k in names(old)) {
    if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k))
  }, add = TRUE)

  read <- suppressMessages(open_source())
  expect_identical(colnames(read), ALLOWED_COLUMNS)
})
