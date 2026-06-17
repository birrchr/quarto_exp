"""
portal_helpers.py
=================
Shared utilities imported by every Quarto QMD page.

Provides:
  - load()        : load a pre-aggregated JSON file
  - COLORS        : consistent Plotly colour palette
  - fig_defaults(): apply standard layout to any Plotly figure
  - make_bar()    : quick horizontal bar chart
  - make_grouped_bar(): grouped bar with consistent style
  - display_stat_box(): render a coloured callout box in a notebook

Usage in QMD:
    ```{python}
    import sys; sys.path.insert(0, "docs/assets")
    from portal_helpers import load, COLORS, fig_defaults
    data = load("self_rated_health")
    ```
"""

import json
from pathlib import Path
import plotly.graph_objects as go
import plotly.express as px
from IPython.display import display, HTML

# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

AGG_DIR = Path("data/aggregated")


def load(name: str) -> dict:
    """Load a pre-aggregated JSON file by stem name."""
    path = AGG_DIR / f"{name}.json"
    if not path.exists():
        raise FileNotFoundError(
            f"Aggregated file not found: {path}\n"
            "Did you run `uv run python scripts/tabulate.py` first?"
        )
    return json.loads(path.read_text())


# ---------------------------------------------------------------------------
# Visual design system
# ---------------------------------------------------------------------------

# Plotly colour sequences aligned with the SCSS palette
COLORS = {
    "primary":   "#1a7f8e",
    "secondary": "#5a8fa3",
    "success":   "#2e8b57",
    "warning":   "#e6a817",
    "danger":    "#c0392b",
    "neutral":   "#7a8c9a",
    # Categorical palette for multi-series charts
    "cat": [
        "#1a7f8e", "#e6a817", "#2e8b57", "#c0392b",
        "#5a8fa3", "#8e6a1a", "#3b2e8b", "#8b2e2e",
    ],
    # Sequential palette for health outcomes
    "health_scale": ["#c0392b", "#e6a817", "#f0d060", "#7ec88a", "#2e8b57"],
}

_BASE_LAYOUT = dict(
    font=dict(family="Inter, Segoe UI, system-ui", size=13, color="#2d3e50"),
    plot_bgcolor="white",
    paper_bgcolor="rgba(0,0,0,0)",
    margin=dict(t=50, b=50, l=60, r=30),
    hoverlabel=dict(
        bgcolor="white",
        bordercolor="#dde8f0",
        font_size=13,
    ),
    legend=dict(
        orientation="h",
        yanchor="bottom",
        y=1.02,
        xanchor="right",
        x=1,
        bgcolor="rgba(0,0,0,0)",
    ),
    xaxis=dict(
        showgrid=True,
        gridcolor="#eef2f7",
        linecolor="#dde8f0",
        zerolinecolor="#dde8f0",
    ),
    yaxis=dict(
        showgrid=True,
        gridcolor="#eef2f7",
        linecolor="#dde8f0",
    ),
)


def fig_defaults(fig: go.Figure, title: str = "", height: int = 420) -> go.Figure:
    """Apply standard portal layout to a Plotly figure."""
    fig.update_layout(
        **_BASE_LAYOUT,
        title=dict(
            text=title,
            font=dict(size=15, color="#1e2d3d", weight="bold" if title else "normal"),
            x=0,
        ),
        height=height,
    )
    return fig


# ---------------------------------------------------------------------------
# Pre-built chart helpers
# ---------------------------------------------------------------------------

def make_bar(
    x_vals, y_vals,
    title="", xlabel="", ylabel="",
    color=None,
    orientation="v",
    height=380,
) -> go.Figure:
    """Simple single-series bar chart."""
    color = color or COLORS["primary"]
    if orientation == "h":
        fig = go.Figure(go.Bar(x=x_vals, y=y_vals, orientation="h",
                               marker_color=color))
    else:
        fig = go.Figure(go.Bar(x=x_vals, y=y_vals,
                               marker_color=color))
    fig.update_layout(xaxis_title=xlabel, yaxis_title=ylabel)
    return fig_defaults(fig, title=title, height=height)


def make_grouped_bar(
    categories, series: dict,
    title="", xlabel="", ylabel="%",
    barmode="group",
    height=420,
) -> go.Figure:
    """
    Grouped or stacked bar chart.

    Parameters
    ----------
    categories : list
        X-axis labels.
    series : dict
        {series_name: [values...], ...}  One key per group.
    """
    fig = go.Figure()
    palette = COLORS["cat"]
    for i, (name, vals) in enumerate(series.items()):
        fig.add_trace(go.Bar(
            name=name,
            x=categories,
            y=vals,
            marker_color=palette[i % len(palette)],
        ))
    fig.update_layout(
        barmode=barmode,
        xaxis_title=xlabel,
        yaxis_title=ylabel,
    )
    return fig_defaults(fig, title=title, height=height)


def make_heatmap(
    z_matrix, x_labels, y_labels,
    title="", colorscale="teal",
    height=400,
) -> go.Figure:
    """Annotated heatmap."""
    fig = go.Figure(go.Heatmap(
        z=z_matrix,
        x=x_labels,
        y=y_labels,
        colorscale="Teal",
        text=[[f"{v:.1f}" for v in row] for row in z_matrix],
        texttemplate="%{text}",
        showscale=True,
    ))
    return fig_defaults(fig, title=title, height=height)


# ---------------------------------------------------------------------------
# HTML display helpers
# ---------------------------------------------------------------------------

def stat_box(value: str, label: str, icon: str = "📊", color: str = None) -> str:
    """Return HTML for a single KPI card."""
    color = color or COLORS["primary"]
    return f"""
    <div style="
        background:white; border:1px solid #dde8f0; border-radius:0.75rem;
        padding:1.4rem 1.2rem; box-shadow:0 1px 6px rgba(0,0,0,0.06);
        text-align:center; display:inline-block; min-width:160px; margin:0.5rem;
    ">
      <div style="font-size:1.8rem">{icon}</div>
      <div style="font-size:2rem; font-weight:700; color:{color}; line-height:1.1">{value}</div>
      <div style="font-size:0.8rem; color:#6c8090; margin-top:0.3rem;
                  text-transform:uppercase; letter-spacing:0.04em">{label}</div>
    </div>"""


def kpi_row(cards: list[tuple]) -> None:
    """
    Render a row of KPI cards.

    cards: list of (value, label, icon, color?) tuples
    """
    html = '<div style="display:flex; flex-wrap:wrap; gap:0; margin:1.5rem 0">'
    for card in cards:
        html += stat_box(*card)
    html += "</div>"
    display(HTML(html))


def data_note(text: str) -> None:
    """Display a yellow callout box for data caveats."""
    display(HTML(f"""
    <div style="
        background:#fff8e6; border-left:4px solid #e6a817;
        padding:0.9rem 1.1rem; border-radius:0 0.5rem 0.5rem 0;
        font-size:0.88rem; color:#5a4a1a; margin:1rem 0;
    ">⚠️  {text}</div>"""))
