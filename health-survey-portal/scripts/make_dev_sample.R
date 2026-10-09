# ─────────────────────────────────────────────────────────────────────────────
# make_dev_sample.R
# Writes a small random dataset in the secure source's shape, so the dashboard
# can be built without credentials (CI preview builds on non-protected
# branches). The values are meaningless; it is a smoke test, not a preview of
# real results.
#
# Run:
#   Rscript scripts/make_dev_sample.R [output path, default data/dev_sample.csv]
#   DATA_LOCAL_FILE=data/dev_sample.csv Rscript scripts/fetch_and_aggregate.R
# ─────────────────────────────────────────────────────────────────────────────

args <- commandArgs(trailingOnly = TRUE)
OUTPUT_PATH <- if (length(args) > 0) args[[1]] else "data/dev_sample.csv"
N <- 2000

set.seed(2024)
pick <- function(levels, prob = NULL) sample(levels, N, replace = TRUE, prob = prob)

sample_df <- data.frame(
  province       = pick(c("Ontario", "Quebec", "British Columbia", "Alberta", "Manitoba", "PEI")),
  age_group      = pick(c("18–24", "25–34", "35–44", "45–54", "55–64", "65–74", "75+")),
  income_bracket = pick(c("Under $30K", "$30K–$49K", "$50K–$74K", "$75K–$99K", "$100K–$149K", "$150K+")),
  education      = pick(c("Less than high school", "High school", "College", "Bachelor's", "Graduate degree")),
  gender         = pick(c("Woman", "Man", "Non-binary / Other", "Prefer not to say"),
                        prob = c(0.49, 0.48, 0.02, 0.01)),
  any_chronic         = rbinom(N, 1, 0.45),
  has_family_doctor   = rbinom(N, 1, 0.85),
  unmet_care_need     = rbinom(N, 1, 0.12),
  bmi                 = round(rnorm(N, 27, 5), 1),
  mental_health_score = sample(0:12, N, replace = TRUE)
)

dir.create(dirname(OUTPUT_PATH), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(sample_df, OUTPUT_PATH, row.names = FALSE)
message(sprintf("Wrote %s (%d synthetic rows).", OUTPUT_PATH, N))
