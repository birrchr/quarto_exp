"""
tabulate.py
===========
Reads the raw microdata Parquet file and produces a suite of pre-aggregated
JSON and Parquet files consumed by the Quarto portal.

Why pre-aggregate?
  • No respondent-level data ever reaches the web server.
  • Aggregates load instantly in the browser (tiny JSON payloads).
  • Quarto pages become pure static HTML — no server-side compute needed.

Recommended companion tool: **pingouin** — a fantastic Python statistics
library purpose-built for survey/clinical data.  It provides:
  - One-way & two-way ANOVA with effect sizes
  - Chi-squared tests with Cramér's V
  - Correlation matrices
  - Bootstrap CIs (via `pingouin.compute_bootci`)
  - Easy syntax that mirrors R's stats workflow

Run:
    uv run python scripts/tabulate.py
"""

import json
from pathlib import Path

import duckdb
import numpy as np
import pandas as pd
import pingouin as pg
from rich.console import Console
from rich.table import Table

console = Console()

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
RAW_PARQUET = Path("data/raw/microdata.parquet")
AGG_DIR = Path("data/aggregated")
AGG_DIR.mkdir(parents=True, exist_ok=True)

CHRONIC_CONDITIONS = [
    "hypertension",
    "diabetes",
    "asthma",
    "depression",
    "anxiety",
    "arthritis",
    "heart_disease",
    "cancer_history",
]

# ---------------------------------------------------------------------------
# DuckDB connection (in-memory; reads Parquet via file scan)
# ---------------------------------------------------------------------------
con = duckdb.connect()

# Register the parquet as a view — DuckDB pushes predicates into the scan
con.execute(
    f"CREATE OR REPLACE VIEW micro AS SELECT * FROM read_parquet('{RAW_PARQUET}')"
)


# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------


def dump_json(obj, path: Path):
    """Serialise to pretty JSON, coercing numpy types."""

    def _default(o):
        if isinstance(o, (np.integer,)):
            return int(o)
        if isinstance(o, (np.floating,)):
            return round(float(o), 4)
        if isinstance(o, np.ndarray):
            return o.tolist()
        raise TypeError(f"Not serialisable: {type(o)}")

    path.write_text(json.dumps(obj, indent=2, default=_default))
    console.print(f"  [green]✓[/green] {path}")


def sql(query: str) -> pd.DataFrame:
    return con.execute(query).df()


# ---------------------------------------------------------------------------
# 1. Summary statistics (top-level KPI cards)
# ---------------------------------------------------------------------------


def tabulate_kpis():
    console.rule("[bold]1. KPI summary cards")

    kpis = (
        sql("""
        SELECT
            COUNT(*)                                         AS n_respondents,
            ROUND(SUM(survey_weight), 0)                    AS weighted_n,
            ROUND(AVG(bmi), 1)                              AS mean_bmi,
            ROUND(AVG(mental_health_score), 2)              AS mean_mh_score,
            ROUND(100.0 * AVG(has_family_doctor), 1)        AS pct_family_doctor,
            ROUND(100.0 * AVG(unmet_care_need), 1)          AS pct_unmet_need,
            ROUND(100.0 * AVG(any_chronic), 1)              AS pct_any_chronic,
            ROUND(AVG(er_visits_12mo), 2)                   AS mean_er_visits,
        FROM micro
    """)
        .iloc[0]
        .to_dict()
    )

    dump_json(kpis, AGG_DIR / "kpis.json")


# ---------------------------------------------------------------------------
# 2. Self-rated health distribution by key demographics
# ---------------------------------------------------------------------------


def tabulate_self_rated_health():
    console.rule("[bold]2. Self-rated health distributions")

    srh_order = ["Excellent", "Very good", "Good", "Fair", "Poor"]

    # Overall
    overall = sql("""
        SELECT self_rated_health, 
               COUNT(*) AS n,
               ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
        FROM micro
        GROUP BY self_rated_health
        ORDER BY self_rated_health
    """).to_dict(orient="records")

    # By age group
    by_age = sql("""
        SELECT age_group, self_rated_health,
               ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY age_group), 1) AS pct
        FROM micro
        GROUP BY age_group, self_rated_health
        ORDER BY age_group, self_rated_health
    """).to_dict(orient="records")

    # By gender (exclude small cells < 5)
    by_gender = sql("""
        SELECT gender, self_rated_health,
               ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY gender), 1) AS pct
        FROM micro
        GROUP BY gender, self_rated_health
        HAVING COUNT(*) >= 5
        ORDER BY gender, self_rated_health
    """).to_dict(orient="records")

    # By income
    by_income = sql("""
        SELECT income_bracket, self_rated_health,
               ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY income_bracket), 1) AS pct
        FROM micro
        GROUP BY income_bracket, self_rated_health
        ORDER BY income_bracket, self_rated_health
    """).to_dict(orient="records")

    dump_json(
        {
            "order": srh_order,
            "overall": overall,
            "by_age": by_age,
            "by_gender": by_gender,
            "by_income": by_income,
        },
        AGG_DIR / "self_rated_health.json",
    )


# ---------------------------------------------------------------------------
# 3. Chronic condition prevalence
# ---------------------------------------------------------------------------


def tabulate_chronic():
    console.rule("[bold]3. Chronic condition prevalence")

    # Overall prevalence per condition
    select_cols = ", ".join(
        f"ROUND(100.0 * AVG({c}), 1) AS {c}" for c in CHRONIC_CONDITIONS
    )
    overall = sql(f"SELECT {select_cols} FROM micro").iloc[0].to_dict()
    overall_list = [
        {"condition": k.replace("_", " ").title(), "prevalence": v}
        for k, v in overall.items()
    ]

    # By age group
    by_age_rows = []
    for c in CHRONIC_CONDITIONS:
        rows = sql(f"""
            SELECT age_group, '{c}' AS condition,
                   ROUND(100.0 * AVG({c}), 1) AS prevalence
            FROM micro
            GROUP BY age_group
            ORDER BY age_group
        """).to_dict(orient="records")
        by_age_rows.extend(rows)

    # Multimorbidity distribution (count of conditions)
    multimorbidity = sql("""
        SELECT chronic_count,
               COUNT(*) AS n,
               ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
        FROM micro
        GROUP BY chronic_count
        ORDER BY chronic_count
    """).to_dict(orient="records")

    # Chi-sq: any_chronic × income (pingouin)
    df = sql("SELECT any_chronic, income_bracket FROM micro")
    ct = pd.crosstab(df["any_chronic"], df["income_bracket"])
    chi2_result = pg.chi2_independence(df, x="income_bracket", y="any_chronic")

    # Debug

    #

    chi2_stats = {
        "chi2": round(float(chi2_result[2]["chi2"].iloc[0]), 3),
        "p_value": round(float(chi2_result[2]["pval"].iloc[0]), 4),
        "cramers_v": round(float(chi2_result[2]["cramer"].iloc[0]), 3),
    }

    dump_json(
        {
            "overall": overall_list,
            "by_age": by_age_rows,
            "multimorbidity": multimorbidity,
            "chi2_income": chi2_stats,
        },
        AGG_DIR / "chronic.json",
    )


# ---------------------------------------------------------------------------
# 4. BMI and physical activity
# ---------------------------------------------------------------------------


def tabulate_bmi_activity():
    console.rule("[bold]4. BMI and physical activity")

    # BMI histogram (bins of 2.5)
    bmi_hist = sql("""
        SELECT
            FLOOR(bmi / 2.5) * 2.5 AS bin_start,
            COUNT(*) AS n
        FROM micro
        WHERE bmi BETWEEN 15 AND 55
        GROUP BY bin_start
        ORDER BY bin_start
    """).to_dict(orient="records")

    # Mean BMI by age group and gender
    bmi_by_demo = sql("""
        SELECT age_group, gender,
               ROUND(AVG(bmi), 1) AS mean_bmi,
               COUNT(*)           AS n
        FROM micro
        WHERE gender IN ('Man', 'Woman')
        GROUP BY age_group, gender
        ORDER BY age_group, gender
    """).to_dict(orient="records")

    # Physical activity distribution by income
    pa_dist = sql("""
        SELECT income_bracket, physical_activity,
               COUNT(*) AS n,
               ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY income_bracket), 1) AS pct
        FROM micro
        GROUP BY income_bracket, physical_activity
        ORDER BY income_bracket, physical_activity
    """).to_dict(orient="records")

    # One-way ANOVA: BMI ~ physical_activity (pingouin)
    df = sql("SELECT bmi, physical_activity FROM micro")
    anova = pg.anova(data=df, dv="bmi", between="physical_activity", detailed=False)

    # Debug
    print(anova)
    print(anova.columns.tolist())
    ##

    anova_stats = {
        "F": round(float(anova["F"].iloc[0]), 3),
        "p_value": round(float(anova["p_unc"].iloc[0]), 4),
        "eta_sq": round(float(anova["np2"].iloc[0]), 4),
    }

    dump_json(
        {
            "bmi_histogram": bmi_hist,
            "bmi_by_demo": bmi_by_demo,
            "pa_distribution": pa_dist,
            "bmi_activity_anova": anova_stats,
        },
        AGG_DIR / "bmi_activity.json",
    )


# ---------------------------------------------------------------------------
# 5. Healthcare access
# ---------------------------------------------------------------------------


def tabulate_healthcare_access():
    console.rule("[bold]5. Healthcare access")

    # Family doctor access by province
    by_province = sql("""
        SELECT province,
               COUNT(*) AS n,
               ROUND(100.0 * AVG(has_family_doctor), 1)  AS pct_family_doctor,
               ROUND(100.0 * AVG(unmet_care_need), 1)    AS pct_unmet_need,
               ROUND(AVG(er_visits_12mo), 2)             AS mean_er_visits
        FROM micro
        GROUP BY province
        ORDER BY pct_family_doctor DESC
    """).to_dict(orient="records")

    # ER visits distribution
    er_dist = sql("""
        SELECT er_visits_12mo AS visits,
               COUNT(*) AS n,
               ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
        FROM micro
        GROUP BY er_visits_12mo
        ORDER BY er_visits_12mo
        LIMIT 10
    """).to_dict(orient="records")

    # Unmet need by income
    unmet_by_income = sql("""
        SELECT income_bracket,
               ROUND(100.0 * AVG(unmet_care_need), 1) AS pct_unmet_need
        FROM micro
        GROUP BY income_bracket
        ORDER BY income_bracket
    """).to_dict(orient="records")

    dump_json(
        {
            "by_province": by_province,
            "er_distribution": er_dist,
            "unmet_by_income": unmet_by_income,
        },
        AGG_DIR / "healthcare_access.json",
    )


# ---------------------------------------------------------------------------
# 6. Mental health
# ---------------------------------------------------------------------------


def tabulate_mental_health():
    console.rule("[bold]6. Mental health")

    # Mean PHQ-4 score by age group and gender
    mh_by_age_gender = sql("""
        SELECT age_group, gender,
               ROUND(AVG(mental_health_score), 2) AS mean_score,
               COUNT(*)                           AS n
        FROM micro
        WHERE gender IN ('Man', 'Woman')
        GROUP BY age_group, gender
        ORDER BY age_group, gender
    """).to_dict(orient="records")

    # Correlation: mental_health_score vs chronic_count and er_visits
    df = sql(
        "SELECT mental_health_score, chronic_count, er_visits_12mo, bmi FROM micro"
    )
    ## DEBUG
    corr_df = pg.pairwise_corr(df, method="pearson")

    print(corr_df)
    print(corr_df.columns.tolist())

    corr = pg.pairwise_corr(df, method="pearson")[
        ["X", "Y", "r", "CI95", "p_unc"]
    ].rename(columns={"p_unc": "p_value"})
    corr["r"] = corr["r"].round(3)
    corr["p_value"] = corr["p_value"].round(4)
    corr["CI95"] = corr["CI95"].apply(lambda x: [round(v, 3) for v in x])
    corr_records = corr.to_dict(orient="records")

    # Depression & anxiety prevalence by age group
    dep_anx = sql("""
        SELECT age_group,
               ROUND(100.0 * AVG(depression), 1) AS pct_depression,
               ROUND(100.0 * AVG(anxiety), 1)    AS pct_anxiety
        FROM micro
        GROUP BY age_group
        ORDER BY age_group
    """).to_dict(orient="records")

    dump_json(
        {
            "mh_by_age_gender": mh_by_age_gender,
            "correlations": corr_records,
            "dep_anx_by_age": dep_anx,
        },
        AGG_DIR / "mental_health.json",
    )


# ---------------------------------------------------------------------------
# 7. Smoking & alcohol
# ---------------------------------------------------------------------------


def tabulate_behaviours():
    console.rule("[bold]7. Health behaviours (smoking & alcohol)")

    smoking = sql("""
        SELECT smoking_status,
               COUNT(*) AS n,
               ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
        FROM micro
        GROUP BY smoking_status
        ORDER BY pct DESC
    """).to_dict(orient="records")

    smoking_by_age = sql("""
        SELECT age_group, smoking_status,
               ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY age_group), 1) AS pct
        FROM micro
        GROUP BY age_group, smoking_status
        ORDER BY age_group, pct DESC
    """).to_dict(orient="records")

    alcohol = sql("""
        SELECT alcohol_frequency,
               COUNT(*) AS n,
               ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
        FROM micro
        GROUP BY alcohol_frequency
        ORDER BY pct DESC
    """).to_dict(orient="records")

    dump_json(
        {
            "smoking_overall": smoking,
            "smoking_by_age": smoking_by_age,
            "alcohol_overall": alcohol,
        },
        AGG_DIR / "behaviours.json",
    )


# ---------------------------------------------------------------------------
# 8. Write a manifest so the portal knows what's available
# ---------------------------------------------------------------------------


def write_manifest():
    console.rule("[bold]8. Writing manifest")
    manifest = {
        "generated_at": pd.Timestamp.now().isoformat(),
        "source": "data/raw/microdata.parquet",
        "n_respondents": int(sql("SELECT COUNT(*) AS n FROM micro").iloc[0]["n"]),
        "files": [str(p.name) for p in sorted(AGG_DIR.glob("*.json"))],
    }
    dump_json(manifest, AGG_DIR / "manifest.json")


# ---------------------------------------------------------------------------
# 9. Print a quick console summary table
# ---------------------------------------------------------------------------


def print_summary():
    df = sql("""
        SELECT
            COUNT(*) AS n,
            ROUND(100.0 * AVG(any_chronic), 1) AS pct_chronic,
            ROUND(AVG(bmi), 1) AS mean_bmi,
            ROUND(100.0 * AVG(has_family_doctor), 1) AS pct_gp
        FROM micro
    """)
    t = Table(title="CanHealth 2024 – Quick Summary", show_header=True)
    for col in df.columns:
        t.add_column(col)
    t.add_row(*[str(v) for v in df.iloc[0]])
    console.print(t)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main():
    console.print("\n[bold cyan]▶ CanHealth 2024 Tabulation Pipeline[/bold cyan]\n")

    tabulate_kpis()
    tabulate_self_rated_health()
    tabulate_chronic()
    tabulate_bmi_activity()
    tabulate_healthcare_access()
    tabulate_mental_health()
    tabulate_behaviours()
    write_manifest()
    print_summary()

    console.print("\n[bold green]✅ All aggregations complete.[/bold green]")
    console.print(f"   Output files in: [cyan]{AGG_DIR}[/cyan]")


if __name__ == "__main__":
    main()
