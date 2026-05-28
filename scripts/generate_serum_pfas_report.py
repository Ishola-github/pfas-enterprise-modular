from pathlib import Path
import pandas as pd
from datetime import datetime, timezone

CSV = Path("data/contextualization_outputs/serum_pfas_batch_contextualized_v1.csv")
OUT = Path("data/contextualization_outputs/serum_pfas_governed_report_v1.md")

df = pd.read_csv(CSV)

lines = []

lines.append("# PFAS Enterprise 5.0 — Governed Serum PFAS Contextualization Report")
lines.append("")
lines.append(f"Generated UTC: {datetime.now(timezone.utc).isoformat()}")
lines.append("")
lines.append("## Scope")
lines.append("")
lines.append("- Matrix: serum only")
lines.append("- Supported analytes: PFOS_TOTAL, PFOA_TOTAL")
lines.append("- Units: ng/mL")
lines.append("- Reference: NHANES 2017–2018 weighted stratified serum PFAS reference")
lines.append("- Mode: Research Use Only")
lines.append("")
lines.append("## Governance Notice")
lines.append("")
lines.append(
    "This report provides population-reference contextualization only. "
    "It is not diagnosis, treatment guidance, toxicity interpretation, medical advice, "
    "or regulatory compliance determination."
)
lines.append("")
lines.append("## Results")
lines.append("")

for _, row in df.iterrows():
    lines.append(f"### Sample {row['sample_id']}")
    lines.append("")
    lines.append(f"- Status: {row['status']}")

    if row["status"] == "REJECTED":
        lines.append(f"- Rejection reason: {row.get('reason')}")
        lines.append("")
        continue

    lines.append(f"- Analyte: {row['analyte']}")
    lines.append(f"- Input value: {row['input_value']} {row['units']}")
    lines.append(f"- Sex: {row['sex']}")
    lines.append(f"- Age: {int(row['age'])}")
    lines.append(f"- Age group: {row['age_group']}")
    lines.append(f"- Reference n: {int(row['n_reference'])}")
    lines.append(f"- Contextualization band: {row['contextualization_band']}")
    lines.append("")
    lines.append("Reference percentiles:")
    lines.append("")
    lines.append(f"- p50: {row['p50']}")
    lines.append(f"- p75: {row['p75']}")
    lines.append(f"- p90: {row['p90']}")
    lines.append(f"- p95: {row['p95']}")
    lines.append(f"- p99: {row['p99']}")
    lines.append("")

lines.append("## Governance Rules Applied")
lines.append("")
lines.append("- Serum-only contextualization")
lines.append("- PFOS/PFOA-only V1 scope")
lines.append("- ng/mL-only unit enforcement")
lines.append("- Cross-matrix contextualization blocked")
lines.append("- Clinical interpretation prohibited")
lines.append("- Rejected rows retained for audit transparency")
lines.append("")

OUT.write_text("\n".join(lines))

print("Saved:", OUT)
