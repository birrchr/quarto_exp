# 🩺 CanHealth 2024 — Survey Data Portal

> A beginner-friendly, end-to-end example of publishing **interactive survey results**
> as a **free, static website** on GitHub Pages — with no server, no database,
> and no sensitive data ever leaving your computer.

**Live demo:** `https://YOUR_USERNAME.github.io/health-survey-portal`  
*(replace with your URL after following the deployment steps below)*

---

## Table of contents

1. [What does this project do?](#1-what-does-this-project-do)
2. [How does it work? (the big picture)](#2-how-does-it-work-the-big-picture)
3. [What you need to install](#3-what-you-need-to-install)
4. [Project layout explained](#4-project-layout-explained)
5. [Step-by-step: running locally](#5-step-by-step-running-locally)
6. [Step-by-step: publishing to GitHub](#6-step-by-step-publishing-to-github)
7. [Understanding the Python scripts](#7-understanding-the-python-scripts)
8. [Understanding the Quarto pages](#8-understanding-the-quarto-pages)
9. [Customising for your own survey](#9-customising-for-your-own-survey)
10. [Troubleshooting](#10-troubleshooting)
11. [Glossary](#11-glossary)

---

## 1. What does this project do?

Imagine you have a survey. You collected responses from thousands of people about
their health — their age, income, whether they smoke, how often they see a doctor.

You want to share the **findings** publicly on a website, but you **cannot share the
raw responses** because that would breach respondent privacy.

This project solves that in three steps:

```
Your raw survey data          Pre-summarised results        Public website
(stays on your computer)  →   (committed to GitHub)    →   (anyone can visit)

data/raw/microdata.parquet    data/aggregated/*.json        https://…github.io/…
  5,000 rows × 28 columns      8 tiny files, ~50 KB each     Interactive charts
  NEVER pushed to GitHub       Safe to share publicly         Runs in any browser
```

The website is made of plain HTML files. There is no server running, no database to
maintain, and it is hosted for free on GitHub Pages.

---

## 2. How does it work? (the big picture)

### The three-stage pipeline

```
┌──────────────────────────────┐
│  STAGE 1 — Generate data     │   Run once to create fake (or real) survey data
│  scripts/generate_data.py    │   Output: data/raw/microdata.parquet
└──────────────┬───────────────┘
               │  (raw data stays local — never committed to git)
               ▼
┌──────────────────────────────┐
│  STAGE 2 — Tabulate          │   Summarise the data into safe aggregates
│  scripts/tabulate.py         │   Output: data/aggregated/*.json
└──────────────┬───────────────┘
               │  (only the JSON summaries are committed to git)
               ▼
┌──────────────────────────────┐
│  STAGE 3 — Build the website │   Quarto reads the JSON and makes HTML pages
│  quarto render               │   Output: _site/ folder (static HTML)
└──────────────┬───────────────┘
               │
               ▼
        GitHub Pages hosts _site/ for free
```

**Why this design?**

- **Privacy:** raw respondent data never leaves your machine.
- **Speed:** the website is pre-built static HTML — it loads instantly.
- **Cost:** GitHub Pages hosting is completely free.
- **Reproducibility:** anyone with the JSON files can rebuild the entire site.

---

## 3. What you need to install

You need three tools on your computer. Everything else is handled automatically.

### 3.1 Python (version 3.11 or newer)

Python is the programming language the scripts are written in.

**Check if you already have it:**
```bash
python --version
# or
python3 --version
```
You want to see `Python 3.11.x` or higher.

**If not installed:**
- **Windows:** Download from https://python.org/downloads — tick "Add Python to PATH"
- **Mac:** `brew install python@3.11` (if you have Homebrew) or download from python.org
- **Linux:** `sudo apt install python3.11` (Ubuntu/Debian)

---

### 3.2 uv — the Python package manager

`uv` installs all the Python libraries this project needs. It is much faster than
the default `pip` tool.

**Install uv:**
```bash
# Mac / Linux:
curl -LsSf https://astral.sh/uv/install.sh | sh

# Windows (PowerShell):
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

**Verify installation:**
```bash
uv --version
# Should print something like: uv 0.5.x
```

---

### 3.3 Quarto — the website builder

Quarto converts Python notebooks into polished HTML pages.

**Download and install:** https://quarto.org/docs/get-started/

**Verify installation:**
```bash
quarto --version
# Should print something like: 1.5.57
```

> **Note for VS Code users:** Install the "Quarto" extension for syntax highlighting
> and a live preview button.

---

## 4. Project layout explained

```
health-survey-portal/
│
├── pyproject.toml              ← Tells uv which Python libraries to install
├── Makefile                    ← Shortcut commands (make generate, make build, etc.)
├── _quarto.yml                 ← Quarto site configuration (title, theme, navbar)
├── .gitignore                  ← Tells git what NOT to commit (raw data, etc.)
│
├── scripts/
│   ├── generate_data.py        ← Stage 1: creates fake survey microdata
│   └── tabulate.py             ← Stage 2: summarises microdata into JSON
│
├── data/
│   ├── raw/                    ← ⚠️  GITIGNORED — raw microdata lives here
│   │   ├── microdata.parquet   ←    5,000 rows × 28 columns
│   │   └── codebook.json       ←    variable descriptions
│   └── aggregated/             ← ✅  COMMITTED — safe summaries
│       ├── manifest.json       ←    when the pipeline last ran
│       ├── kpis.json           ←    headline numbers for the home page
│       ├── self_rated_health.json
│       ├── chronic.json
│       ├── bmi_activity.json
│       ├── mental_health.json
│       ├── behaviours.json
│       └── healthcare_access.json
│
├── docs/
│   ├── assets/
│   │   ├── custom.scss         ← Visual styling (colours, fonts, card layouts)
│   │   └── portal_helpers.py   ← Shared Python functions for all pages
│   ├── overview.qmd            ← Survey overview page
│   ├── self_rated_health.qmd   ← Results page
│   ├── chronic.qmd             ← Results page
│   ├── bmi_activity.qmd        ← Results page
│   ├── mental_health.qmd       ← Results page
│   ├── behaviours.qmd          ← Results page
│   ├── healthcare_access.qmd   ← Results page
│   └── methods.qmd             ← Technical documentation page
│
├── index.qmd                   ← Home page
│
└── .github/
    └── workflows/
        └── publish.yml         ← GitHub Actions: auto-publishes on every push
```

---

## 5. Step-by-step: running locally

Open a terminal and follow these steps exactly. Every command starts with `$` —
type the part after the `$`, not the `$` itself.

### Step 1 — Get the project onto your computer

If you are cloning from GitHub:
```bash
$ git clone https://github.com/YOUR_USERNAME/health-survey-portal.git
$ cd health-survey-portal
```

If you downloaded a ZIP file, unzip it and open a terminal in that folder.

---

### Step 2 — Install Python dependencies

```bash
$ uv sync
```

**What this does:**  
Reads `pyproject.toml`, creates a hidden `.venv/` folder, and installs every
library listed there (DuckDB, Plotly, Faker, pingouin, etc.).

**What you should see:**
```
Resolved 47 packages in 0.3s
Installed 47 packages in 2.1s
 + duckdb==1.1.3
 + faker==24.2.0
 + plotly==5.22.0
 ... (many more lines)
```

**If you see an error like "uv: command not found":**  
Close and reopen your terminal after installing uv (Step 3.2 above).

---

### Step 3 — Generate the synthetic microdata

```bash
$ uv run python scripts/generate_data.py
```

**What this does:**  
Creates 5,000 fake survey respondents with realistic health data and saves them
to `data/raw/microdata.parquet`.

**What you should see:**
```
🔧 Generating demographics …
🔧 Generating health variables …
✅ Wrote 5,000 rows → data/raw/microdata.parquet
✅ Wrote codebook → data/raw/codebook.json
```

> **Using your own data?** Skip this step entirely and place your own Parquet file
> at `data/raw/microdata.parquet`. See [Section 9](#9-customising-for-your-own-survey).

---

### Step 4 — Run the tabulation pipeline

```bash
$ uv run python scripts/tabulate.py
```

**What this does:**  
Reads the microdata, runs SQL queries with DuckDB, runs statistical tests with
pingouin, and saves 8 small JSON files to `data/aggregated/`.

**What you should see:**
```
▶ CanHealth 2024 Tabulation Pipeline

── 1. KPI summary cards ───────────────────────
  ✓ data/aggregated/kpis.json
── 2. Self-rated health distributions ─────────
  ✓ data/aggregated/self_rated_health.json
... (continues for each section)
✅ All aggregations complete.
```

---

### Step 5 — Preview the website

```bash
$ quarto preview
```

**What this does:**  
Renders the `.qmd` pages into HTML and opens a live preview in your browser at
`http://localhost:4040`. The page auto-refreshes every time you save a file.

> The first render takes about 30–60 seconds as Quarto executes all the Python
> code. Subsequent renders are much faster because of caching (`freeze: auto`).

**To stop the preview:** press `Ctrl+C` in the terminal.

---

### Step 6 (optional) — Build the final site

```bash
$ quarto render
```

This writes the finished website to the `_site/` folder. You can open
`_site/index.html` directly in a browser to see it without a server.

---

### Quick shortcut: run everything at once

If you have `make` installed (it comes pre-installed on Mac and Linux):

```bash
$ make all
```

This runs `uv sync` → `generate_data.py` → `tabulate.py` → `quarto render` in sequence.

---

## 6. Step-by-step: publishing to GitHub

### One-time setup

#### 6.1 Create a GitHub account

Sign up at https://github.com if you do not have an account.

#### 6.2 Create a new repository

1. Go to https://github.com/new
2. Name it `health-survey-portal` (or anything you like)
3. Set it to **Public** (required for free GitHub Pages)
4. Do **not** tick "Add a README file" — we already have one
5. Click **Create repository**

#### 6.3 Push the project to GitHub

Back in your terminal (in the project folder):

```bash
$ git init
$ git add .
$ git commit -m "Initial commit: CanHealth portal"
$ git branch -M main
$ git remote add origin https://github.com/YOUR_USERNAME/health-survey-portal.git
$ git push -u origin main
```

Replace `YOUR_USERNAME` with your actual GitHub username.

---

### What happens next (automatically)

GitHub Actions reads `.github/workflows/publish.yml` and runs a workflow:

1. ✅ Installs uv and Python
2. ✅ Runs `uv sync`
3. ✅ Checks that `data/aggregated/*.json` files exist (they were committed in step 6.3)
4. ✅ Runs `quarto render`
5. ✅ Publishes the `_site/` folder to the `gh-pages` branch

You can watch this happen at:  
`https://github.com/YOUR_USERNAME/health-survey-portal/actions`

---

### Enable GitHub Pages

1. Go to your repository on GitHub
2. Click **Settings** → **Pages** (left sidebar)
3. Under **Source**, select **Deploy from a branch**
4. Set **Branch** to `gh-pages` and folder to `/ (root)`
5. Click **Save**

After about 60 seconds, your site will be live at:  
`https://YOUR_USERNAME.github.io/health-survey-portal`

---

### Updating the site later

Whenever you want to update the published results:

```bash
# 1. If your raw data changed, re-tabulate:
$ uv run python scripts/tabulate.py

# 2. Commit the updated JSON files:
$ git add data/aggregated/
$ git commit -m "Update aggregated results"
$ git push
```

GitHub Actions will automatically rebuild and republish the site within ~2 minutes.

---

## 7. Understanding the Python scripts

### `scripts/generate_data.py`

This script is the "data factory." It uses two libraries:

- **`numpy`** — fast numerical computing; used here to generate random numbers
  with realistic statistical distributions (e.g. age-dependent disease probabilities)
- **`Faker`** — a library that generates fake-but-realistic data

Key concept — **seeded randomness:**
```python
RNG = np.random.default_rng(seed=42)
```
Setting a seed means the script produces the *exact same* fake data every time
it runs. This makes the project reproducible — if you send someone your code,
they can regenerate the same dataset.

Key concept — **Parquet format:**
```python
microdata.to_parquet("data/raw/microdata.parquet", engine="pyarrow")
```
Parquet is a compressed, column-oriented file format. Unlike CSV, it stores data
types (int, float, string) precisely, compresses data automatically, and allows
DuckDB to read only the columns it needs without loading the whole file.

---

### `scripts/tabulate.py`

This is the privacy-protecting aggregation step. It uses **DuckDB** — a very
fast in-process SQL database — to query the Parquet file.

Key concept — **DuckDB views:**
```python
con = duckdb.connect()
con.execute(
    "CREATE VIEW micro AS SELECT * FROM read_parquet('data/raw/microdata.parquet')"
)
```
This creates a virtual "table" called `micro`. DuckDB doesn't load all 5,000 rows
into memory — it reads only the columns and rows needed for each query.

Key concept — **SQL aggregations:**
```python
result = con.execute("""
    SELECT age_group,
           ROUND(100.0 * AVG(hypertension), 1) AS prevalence
    FROM micro
    GROUP BY age_group
""").df()
```
`GROUP BY` splits respondents into groups. `AVG(hypertension)` computes the mean
of a 0/1 column, giving us a proportion. Multiply by 100 → a percentage.

Key concept — **pingouin for statistics:**
```python
import pingouin as pg

# Chi-squared test: is chronic disease associated with income?
pg.chi2_independence(df, x="income_bracket", y="any_chronic")

# ANOVA: does BMI differ by activity level?
pg.anova(data=df, dv="bmi", between="physical_activity")
```
pingouin provides clean, readable statistical tests that return proper effect
sizes (Cramér's V, η²) alongside p-values — much better than just knowing
something is "statistically significant."

---

### `docs/assets/portal_helpers.py`

A shared library that every `.qmd` page imports. The most important function:

```python
def load(name: str) -> dict:
    """Load a pre-aggregated JSON file by stem name."""
    return json.loads(Path(f"data/aggregated/{name}.json").read_text())
```

Every page calls this to get its data:
```python
data = load("chronic")  # reads data/aggregated/chronic.json
prevalences = data["overall"]  # list of {condition, prevalence} dicts
```

---

## 8. Understanding the Quarto pages

Quarto `.qmd` files are a mix of **Markdown** (text) and **Python code blocks**.

```
---
title: "My Page Title"          ← YAML front matter: page metadata
---

Some regular text here.         ← Markdown: formatted normally

```{python}                      ← Python code block starts
data = load("chronic")          
fig = go.Figure(...)            
fig.show()                      ← fig.show() embeds the chart in the HTML
```                              ← code block ends

More text here.
```

When Quarto renders a `.qmd` file, it:
1. Executes the Python code blocks
2. Captures any output (printed text, charts, tables)
3. Weaves the output into the Markdown
4. Converts the whole thing to a styled HTML page

**Key settings in `_quarto.yml`:**

```yaml
execute:
  echo: false     # Hide the Python code from readers (they see only charts)
  freeze: auto    # Don't re-run Python unless the .qmd file changed
  cache: true     # Cache outputs so repeated renders are instant
```

`code-fold: true` in the format options means readers CAN click "Show code"
if they want to see the Python — but it is hidden by default.

---

## 9. Customising for your own survey

### Using your own data (instead of the synthetic data)

If you have real survey data in a CSV or Excel file:

```python
import pandas as pd

# From CSV:
df = pd.read_csv("my_survey.csv")

# From Excel:
df = pd.read_excel("my_survey.xlsx")

# From a SAS file (requires pyreadstat):
import pyreadstat

df, meta = pyreadstat.read_sas7bdat("my_survey.sas7bdat")

# Save as Parquet (required format for this project):
df.to_parquet("data/raw/microdata.parquet", index=False)
```

### Adding a new results page

**Step 1:** Add a new aggregation function to `tabulate.py`:

```python
def tabulate_my_topic():
    result = sql("""
        SELECT my_group_var,
               ROUND(AVG(my_outcome), 2) AS mean_outcome
        FROM micro
        GROUP BY my_group_var
    """).to_dict(orient="records")
    
    dump_json({"by_group": result}, AGG_DIR / "my_topic.json")
```

Don't forget to call it from `main()`:
```python
def main():
    ...
    tabulate_my_topic()  # add this line
```

**Step 2:** Create `docs/my_topic.qmd`:

```
---
title: "My Topic"
---

```{python}
import sys
sys.path.insert(0, ".")
from portal_helpers import load, fig_defaults, COLORS
import plotly.graph_objects as go
import pandas as pd

data = load("my_topic")
df   = pd.DataFrame(data["by_group"])
```

```{python}
fig = go.Figure(
    go.Bar(
        x=df["my_group_var"],
        y=df["mean_outcome"],
        marker_color=COLORS["primary"],
    )
)
fig_defaults(fig, "My Topic Chart").show()
```
```

**Step 3:** Add it to the navbar in `_quarto.yml`:

```yaml
navbar:
  left:
    - text: "Results"
      menu:
        - href: docs/my_topic.qmd
          text: "My Topic"    # ← add this
```

**Step 4:** Re-run and rebuild:
```bash
$ uv run python scripts/tabulate.py
$ quarto render
```

### Changing the visual theme

Open `_quarto.yml` and change the `theme` line:

```yaml
format:
  html:
    theme:
      light: cosmo    # try: flatly, cosmo, lux, journal, litera, minty, pulse
      dark: darkly    # try: darkly, slate, vapor, cyborg
```

Available Bootswatch themes: https://bootswatch.com

To change brand colours, edit `docs/assets/custom.scss`:
```scss
$primary:   #1a7f8e;   // change to your brand colour
$secondary: #5a8fa3;
```

---

### Interactive R dashboard (Shinylive)

`docs/dashboard.qmd` embeds an R Shiny app compiled to WebAssembly, so it runs in the
visitor's browser with no server. Its data is fetched and aggregated **at build time**:

```
secure source ──► scripts/fetch_and_aggregate.R ──► data/processed_summary.csv (gitignored)
                                                          │
app/app.R ──────► scripts/build_dashboard_app.R ◄─────────┘
                          │
                          ▼
              docs/_dashboard_app.qmd (gitignored) ──► included by docs/dashboard.qmd
```

- **Credentials** come only from environment variables: `DATA_API_URL` + `DATA_API_TOKEN`
  (HTTPS API) or `DB_CONN_STR` (+ `DATA_TABLE`) for an ODBC database, where the
  aggregation runs in-database. Set them as masked, protected CI/CD variables in GitLab.
- **Disclosure control:** only allowlisted columns are read. Output is one-way tables (by
  province, age group, income, education), each also split by gender. Estimates are
  unweighted, matching the Results pages. Cells with `n < MIN_CELL_SIZE` (default 10) are
  suppressed. Within each gender split, more cells are hidden until at least two are
  suppressed and together they cover `MIN_CELL_SIZE`, so no hidden value can be recovered
  as "All" minus the others. Counts are rounded to `ROUND_BASE` (default 5).
  `tests/test_disclosure.R` covers these rules (`make test-r`).
- **CI:** `.gitlab-ci.yml` at the repo root installs the R deps, runs the tests and both
  scripts, and renders. On the default branch (`build-site`) it uses the real source and
  publishes `public/` to GitLab Pages. Other branches (`build-preview`) build from a random
  sample made by `scripts/make_dev_sample.R` and are never published, because protected
  credentials are not available there.

One-time setup (requires R ≥ 4.1 and Quarto ≥ 1.4):

```bash
$ make dashboard-deps      # R packages from DESCRIPTION + quarto add quarto-ext/shinylive
$ git add _extensions/     # commit the extension so CI doesn't download it each run
```

Local build with synthetic data (no credentials needed):

```bash
$ make test-r
$ DATA_LOCAL_FILE=data/raw/microdata.parquet make dashboard-data   # needs the arrow R package
$ quarto render
```

`docs/_dashboard_app.qmd` is generated by `make dashboard-data` and is not committed, so
`quarto render` fails on the dashboard page until you have run it once.

---

## 10. Troubleshooting

### "uv: command not found" after installing uv

Close and reopen your terminal. If still not found, restart your computer.

---

### "quarto: command not found"

Quarto installs to a system location. On Mac, try:
```bash
export PATH="$PATH:/Applications/quarto/bin"
```
Or reinstall from https://quarto.org/docs/get-started/

---

### "FileNotFoundError: data/aggregated/kpis.json"

You haven't run the tabulation pipeline yet:
```bash
$ uv run python scripts/generate_data.py   # Step 3
$ uv run python scripts/tabulate.py        # Step 4
```

---

### "ModuleNotFoundError: No module named 'duckdb'"

The virtual environment is not active, or `uv sync` was not run:
```bash
$ uv sync
$ uv run python scripts/tabulate.py   # always use `uv run` to use the venv
```

---

### Quarto renders but charts are blank

Make sure you are using `fig.show()` at the end of each code block, not
`fig.write_html()` or `plt.show()`. Quarto captures `fig.show()` output.

---

### GitHub Actions fails with "aggregated data files not found"

The `data/aggregated/*.json` files need to be committed to the repository.
Run the pipeline locally, then commit:
```bash
$ uv run python scripts/generate_data.py
$ uv run python scripts/tabulate.py
$ git add data/aggregated/
$ git commit -m "Add aggregated results"
$ git push
```

---

### The GitHub Pages site shows a 404 error

1. Wait 2–3 minutes after the Actions workflow finishes
2. Check **Settings → Pages** and confirm the source is `gh-pages` branch
3. Make sure the repository is **Public**

---

### Charts look different in dark mode

Plotly figures pick up the page background. If a chart looks wrong in dark mode,
add this to the figure:
```python
fig.update_layout(paper_bgcolor="rgba(0,0,0,0)")
```

---

## 11. Glossary

| Term | Plain-English meaning |
|---|---|
| **Parquet** | A compressed file format for tabular data, like a very efficient CSV. DuckDB reads it natively. |
| **DuckDB** | A database that runs inside your Python script — no server needed. Very fast at SQL queries on files. |
| **SQL** | A language for asking questions about data: "give me the average BMI grouped by age group." |
| **Aggregation** | Summarising many rows into fewer rows — e.g. 5,000 individual responses → 7 age-group averages. |
| **JSON** | A text format for storing structured data. Small, human-readable, and loads instantly in a browser. |
| **Quarto** | A tool that turns Python notebooks (`.qmd` files) into polished websites, PDFs, or slides. |
| **GitHub Pages** | A free GitHub feature that serves a folder of HTML files as a public website. |
| **GitHub Actions** | Automated scripts that run on GitHub's servers when you push code (used here to rebuild the site). |
| **virtual environment (`.venv/`)** | An isolated folder where Python packages are installed, so they don't conflict with other projects. |
| **uv** | A fast package manager that creates virtual environments and installs Python libraries. |
| **pingouin** | A Python statistics library that makes tests like ANOVA and chi-squared easy, with effect sizes. |
| **Plotly** | A Python charting library that creates interactive charts (zoom, hover, toggle) that work in HTML. |
| **ANOVA** | "Analysis of Variance" — a statistical test asking "do these groups have significantly different means?" |
| **Cramér's V** | A 0–1 number measuring how strongly two categorical variables are associated. 0 = no association. |
| **p-value** | The probability of seeing results this extreme if there were no real effect. Below 0.05 = significant. |
| **effect size** | How *large* an effect is, not just whether it's statistically detectable. |
| **SCSS** | An extension of CSS (the language that styles websites) with variables and nesting. |
| **freeze: auto** | A Quarto setting that skips re-running Python code if the source file hasn't changed. |
| **gitignore** | A file listing what git should ignore — in this project, the raw microdata. |
| **seed** | A starting number for a random number generator. Same seed = same "random" numbers every time. |

---

## Contributing

This project is intended as a teaching example. If you find a bug or want to add
a new chart type or statistical method, open a GitHub Issue or Pull Request.

---

## Licence

MIT — use freely, adapt for your own surveys, give credit if you share it.
