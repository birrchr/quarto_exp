# TASK: Refactor Quarto Website to Render Interactive R Shinylive App with Secure Build-Time Data Fetching

## Objective
Update our Quarto-based website to fetch sensitive data from an external secure source at build time, aggregate/anonymize the data to eliminate raw records or PII, and present the final output as an interactive R Shiny visual using Shinylive (WebAssembly). The build must run smoothly within our GitLab CI/CD pipeline without pushing any raw data or credentials into the repository.

---

## 1. Prerequisites & Dependencies
- Update the R environment dependencies (e.g., in `DESCRIPTION`, `renv.lock`, or `requirements.txt`) to include:
  - `shinylive`
  - `quarto`
  - `httr2` or `DBI` (for secure remote fetching)
  - `dplyr` / `tidyverse`
  - `bslib`
  - `plotly` (or `ggplot2`)

- Ensure the Quarto extension for Shinylive is declared or installed:
  `quarto add quarto-ext/shinylive`

---

## 2. Secure Data Acquisition Script (`scripts/fetch_and_aggregate.R`)
Create an isolated R script that executes during the build phase:
1. **Credentials:** Read database/API connection details strictly from environment variables (e.g., `Sys.getenv("DATA_API_TOKEN")` or `Sys.getenv("DB_CONN_STR")`). Never hardcode secrets.
2. **Data Extraction:** Fetch the required dataset from our external repository.
3. **Data Protection & Aggregation:**
   - Drop all Personally Identifiable Information (PII) and raw transaction rows.
   - Perform summary aggregations (e.g., `group_by(...) %>% summarise(...)`).
   - Round small cell counts or suppress low-volume counts if required by governance.
4. **Output:** Save the clean, aggregated output to `data/processed_summary.rds` or `data/processed_summary.csv`.
5. **Git Hygiene:** Add `data/` and any cached raw files to `.gitignore` so local test data is never committed.

---

## 3. Create/Refactor the Quarto Document (`dashboard.qmd`)
Update or create the target `.qmd` file to embed the Shinylive application using WebAssembly:

1. **YAML Header:**
   ```yaml
   ---
   title: "Interactive Data Summary"
   format: html
   filters:
     - shinylive
   ---