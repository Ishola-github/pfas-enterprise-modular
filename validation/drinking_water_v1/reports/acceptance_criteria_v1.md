# Acceptance criteria — **before** further testing (v1)

Define targets **before** collecting new metrics. Replace “Current” with values from your frozen holdout run (e.g. ML results panel at declared τ).

| Metric | Current (example at freeze) | Target |
| ------ | --------------------------- | ------ |
| Recall | 0.933 | ≥ 0.90 |
| NPV | 0.9469 | ≥ 0.90 |
| Precision | 0.3467 | Improve in a later cycle (document baseline) |
| False-positive rate (among true negatives) | 0.5951 | Reduce over time; document baseline |
| Group overlap | 0 | **Must remain 0** |
| Audit artifact generation | yes | **Required** for each gated run |

## Notes

- **Current** column: fill from `nhanes_model_metrics*.json` (or screening twin under `results/screening/`) at freeze.
- If the UI shows both **evaluation split** counts and **task-level** counts (`model_matrix_task_counts.csv`), document which denominator applies to the reported confusion matrix (see `EVIDENCE_COPY_CHECKLIST.md`).
