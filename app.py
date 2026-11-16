"""Interactive Placement360 placement analytics dashboard."""
from pathlib import Path
import pandas as pd
import streamlit as st

ROOT = Path(__file__).resolve().parent
DEFAULT_DATA = ROOT / "data" / "raw" / "campus_placement.csv"
st.set_page_config(page_title="Placement360 | Student Analytics", page_icon="🎓", layout="wide")
st.title("Placement360 — Student & Recruitment Analytics")
st.caption("Placement outcome analysis using public campus recruitment data or an institution's own CSV.")

uploaded = st.sidebar.file_uploader("Upload institutional student CSV (optional)", type=["csv"])
if uploaded is not None:
    df = pd.read_csv(uploaded)
    data_label = f"Uploaded file: {uploaded.name}"
elif DEFAULT_DATA.exists():
    df = pd.read_csv(DEFAULT_DATA)
    data_label = "Public Campus Recruitment CSV"
else:
    st.info("No data file found. Run python data/download_data.py or upload a student CSV from the sidebar.")
    st.stop()

if "PlacementStatus" not in df:
    st.error("The selected file must include a PlacementStatus column.")
    st.stop()


def placed_flag(series):
    values = series.astype(str).str.strip().str.lower().str.replace("_", "", regex=False)
    mapping = {
        "placed": 1, "yes": 1, "1": 1, "true": 1,
        "notplaced": 0, "not placed": 0, "no": 0, "0": 0, "false": 0,
    }
    return values.map(mapping)


df = df.copy()
df["_placed"] = placed_flag(df["PlacementStatus"])
df = df.dropna(subset=["_placed"])
df["_placed"] = df["_placed"].astype(int)

st.caption(f"Data source: {data_label} · {len(df):,} student records")
st.sidebar.header("Filters")
filtered = df.copy()
for dimension in ["Department", "Batch"]:
    if dimension in filtered.columns:
        choices = ["All"] + sorted(filtered[dimension].dropna().astype(str).unique().tolist())
        chosen = st.sidebar.selectbox(dimension, choices)
        if chosen != "All":
            filtered = filtered[filtered[dimension].astype(str) == chosen]

total = len(filtered)
placed = int(filtered["_placed"].sum())
not_placed = total - placed
rate = placed / total if total else 0.0
c1, c2, c3, c4 = st.columns(4)
c1.metric("Students", f"{total:,}")
c2.metric("Placed", f"{placed:,}")
c3.metric("Not placed", f"{not_placed:,}")
c4.metric("Placement rate", f"{rate:.1%}")

optional_metrics = []
company_col = next((c for c in ["Company", "CompanyName", "Employer", "CompanyID"] if c in filtered.columns), None)
engagement_col = next((c for c in ["EngagementEvents", "EngagementScore", "EngagementCount"] if c in filtered.columns), None)
if company_col:
    optional_metrics.append(("Participating employers", int(filtered[company_col].nunique())))
if engagement_col:
    engaged = pd.to_numeric(filtered[engagement_col], errors="coerce").fillna(0)
    optional_metrics.append(("Students with engagement", int((engaged > 0).sum())))
if optional_metrics:
    metric_cols = st.columns(len(optional_metrics))
    for metric_col, (label, value) in zip(metric_cols, optional_metrics):
        metric_col.metric(label, f"{value:,}")

left, right = st.columns(2)
with left:
    st.subheader("Placement status")
    st.bar_chart(pd.Series({"Placed": placed, "Not placed": not_placed}, name="Students"))
with right:
    st.subheader("Placement by cohort")
    group_options = [c for c in ["Department", "Batch"] if c in filtered.columns]
    if group_options:
        dimension = st.selectbox("Break down by", group_options)
        cohort = filtered.groupby(dimension, dropna=False)["_placed"].agg(
            Students="size", Placed="sum", PlacementRate="mean"
        )
        cohort["PlacementRate"] = cohort["PlacementRate"] * 100
        st.dataframe(cohort.sort_values("PlacementRate", ascending=False), use_container_width=True)
        st.bar_chart(cohort["PlacementRate"])
    else:
        st.info("Department and Batch breakdowns will appear when those columns are provided in an institutional CSV. They are not included in the public training dataset.")

st.subheader("Student profile and employability indicators")
numeric_candidates = [
    "CGPA", "Internships", "Projects", "Workshops/Certifications",
    "AptitudeTestScore", "SoftSkillsRating", "SSC_Marks", "HSC_Marks"
]
numeric = [c for c in numeric_candidates if c in filtered.columns]
if numeric:
    chosen_feature = st.selectbox("Explore a student attribute", numeric)
    distribution = filtered.groupby("_placed")[chosen_feature].mean().rename(
        index={0: "Not placed", 1: "Placed"}
    )
    st.bar_chart(distribution)
else:
    st.info("No known numeric student attributes were found in the selected file.")

st.subheader("Recruitment funnel")
funnel_columns = ["Applications", "Interviews", "Offers"]
if all(c in filtered.columns for c in funnel_columns):
    counts = [pd.to_numeric(filtered[c], errors="coerce").fillna(0).sum() for c in funnel_columns]
    f1, f2, f3 = st.columns(3)
    f1.metric("Applications", f"{counts[0]:,.0f}")
    f2.metric("Interviews", f"{counts[1]:,.0f}")
    f3.metric("Offers", f"{counts[2]:,.0f}")
    st.metric("Interview-to-offer rate", f"{counts[2] / counts[1]:.1%}" if counts[1] else "N/A")
else:
    st.info("Application, Interview and Offer totals require those columns in the uploaded institutional data. The public dataset contains only a final placement label, so this funnel is intentionally not estimated.")

importance_file = ROOT / "reports" / "feature_importance.csv"
if importance_file.exists():
    st.subheader("Model feature importance")
    importance = pd.read_csv(importance_file).head(15).set_index("feature")
    st.bar_chart(importance["importance"])

with st.expander("Preview filtered data"):
    st.dataframe(filtered.drop(columns=["_placed"]), use_container_width=True)

st.divider()
st.caption("Placement outcome is an observed label in the supplied data. Model feature importance indicates predictive association, not causation. Remove personal identifiers before uploading institutional records.")
