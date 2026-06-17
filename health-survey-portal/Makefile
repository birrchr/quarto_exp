# ─────────────────────────────────────────────────────────────────────────────
# CanHealth 2024 Portal — Makefile
# Provides short aliases for the common workflows.
# Usage: make <target>
# ─────────────────────────────────────────────────────────────────────────────

.PHONY: help install generate tabulate build preview publish clean all

# Default target: show help
help:
	@echo ""
	@echo "CanHealth 2024 Portal — available commands:"
	@echo ""
	@echo "  make install    Install all Python dependencies with uv"
	@echo "  make generate   Generate synthetic microdata  (data/raw/microdata.parquet)"
	@echo "  make tabulate   Run aggregation pipeline      (data/aggregated/*.json)"
	@echo "  make build      Render the Quarto website     (_site/)"
	@echo "  make preview    Live-preview the site in your browser"
	@echo "  make publish    Publish to GitHub Pages (requires quarto CLI)"
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

# Render the full Quarto site to _site/
build:
	quarto render

# Start a live-preview server (auto-refreshes on file save)
preview:
	quarto preview

# Publish directly to GitHub Pages (shortcut for quarto publish)
publish:
	quarto publish gh-pages

# Run the full pipeline from scratch
all: install generate tabulate build
	@echo ""
	@echo "🎉 Full pipeline complete! Open _site/index.html to preview."

# Remove all generated outputs
clean:
	rm -rf _site/ .quarto/ _freeze/
	rm -f data/aggregated/*.json
	@echo "🧹 Cleaned build outputs. Raw microdata in data/raw/ was NOT removed."

# Remove everything including raw data (use with caution)
clean-all: clean
	rm -rf data/raw/
	@echo "🧹 Removed all generated data including raw microdata."
