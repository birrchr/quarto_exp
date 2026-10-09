# ─────────────────────────────────────────────────────────────────────────────
# CanHealth 2024 Portal — Makefile
# Provides short aliases for the common workflows.
# Usage: make <target>
# ─────────────────────────────────────────────────────────────────────────────

.PHONY: help install generate tabulate dashboard-deps dashboard-data test-r build preview clean clean-all all

# Default target: show help
help:
	@echo ""
	@echo "CanHealth 2024 Portal — available commands:"
	@echo ""
	@echo "  make install    Install all Python dependencies with uv"
	@echo "  make generate   Generate synthetic microdata  (data/raw/microdata.parquet)"
	@echo "  make tabulate   Run aggregation pipeline      (data/aggregated/*.json)"
	@echo "  make dashboard-deps  Install R packages + Shinylive Quarto extension"
	@echo "  make dashboard-data  Fetch, aggregate and bundle the Shinylive app data"
	@echo "  make test-r     Test the dashboard's disclosure control (R)"
	@echo "  make build      Render the Quarto website     (_site/)"
	@echo "  make preview    Live-preview the site in your browser"
	@echo "  make all        install → generate → tabulate → build"
	@echo "  make clean      Remove generated files"
	@echo ""

# Install Python packages into a local .venv
install:
	uv sync
	@echo ""
	@echo "✅ Dependencies installed into .venv/"
	@echo "   Activate with:  source .venv/bin/activate"

# Generate synthetic microdata
generate:
	uv run python scripts/generate_data.py

# Aggregate the microdata into portal-ready JSON files
tabulate:
	uv run python scripts/tabulate.py

# Install R build dependencies (DESCRIPTION) and the Shinylive Quarto extension
dashboard-deps:
	Rscript -e 'if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes"); remotes::install_deps(dependencies = TRUE)'
	quarto add --no-prompt quarto-ext/shinylive

# Fetch from the secure source (credentials via env vars), aggregate, and
# bundle into docs/_dashboard_app.qmd. For local work with synthetic data:
#   DATA_LOCAL_FILE=data/raw/microdata.parquet make dashboard-data
dashboard-data:
	Rscript scripts/fetch_and_aggregate.R
	Rscript scripts/build_dashboard_app.R

# Unit tests for the suppression and rounding rules in fetch_and_aggregate.R
test-r:
	Rscript tests/test_disclosure.R

# Render the full Quarto site to _site/
build:
	quarto render

# Start a live-preview server (auto-refreshes on file save)
preview:
	quarto preview


# Run the full pipeline from scratch
all: install generate tabulate build
	@echo ""
	@echo "🎉 Full pipeline complete! Open _site/index.html to preview."

# Remove all generated outputs
clean:
	# _freeze/ is kept: it is committed and CI renders the Python pages from it.
	rm -rf _site/ .quarto/
	rm -f data/aggregated/*.json data/processed_summary.csv docs/_dashboard_app.qmd app/processed_summary.csv
	@echo "🧹 Cleaned build outputs. Raw microdata in data/raw/ was NOT removed."

# Remove everything including raw data (use with caution)
clean-all: clean
	rm -rf data/raw/
	@echo "🧹 Removed all generated data including raw microdata."
