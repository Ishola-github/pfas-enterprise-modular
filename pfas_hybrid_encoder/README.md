# PFAS hybrid encoder — vector backbone

Executable slice of **graphs + descriptors + context + measurement_flags**:

| Block | Role |
|-------|------|
| RDKit descriptors (+ PFAS-aware counts) | **what the molecule is** |
| Morgan fingerprint (radius 2, default 256 bits) | Structure-driven chemistry (chains, branching, ethers, sulfonates, acids) |
| Measurement vector | **how it was measured**: ND/censoring, LOD substitution policy, QA, matrix flags |

Later: concatenate a **graph latent** or train a **tabular encoder** (e.g. FT-Transformer / TabNet) on this canonical table — **before** committing to full GNN at small-sample scale.

---

## Canonical feature table (`shared_encoder_input.parquet`)

Orchestration boundary: **[`preprocess_matrix.py`](preprocess_matrix.py)** — ``result_value`` / MRL / LOD aliases, NHANES survey/demo copies (**``WTSAF2YR``, ``RIDAGEYR``, …** → additive ``etl_*`` targets), then **routed recipes**:

| Recipe | Canonical unit | QA / methods (minimum expectations) |
|--------|----------------|---------------------------------------|
| `water_v1` | **ng/L** | EPA **533 / 537.1 / 1633** in ``method_id`` → ``etl_method_*`` |
| `serum_v1` | **ng/mL** | NHANES LOD handling + weights/demographics via aliases; **no** drinking-water exceedance labeling |
| `air_v1` | **ng/m³** | **OTM-50 / OTM-45** patterns in ``method_id``; optional ``control_device``, ``source_type`` (``etl_air_*``); flagged ``etl_not_drinking_water_mcl_lane`` |
| `solids_v1` | **ng/g_dw** | **1633A**-style solids methods; optional ``dry_solids_frac`` / ``percent_solids`` → ``etl_*`` |

**Suite id:** ``etl_matrix_v2``. Unknown matrix labels route to ``canonical_conc_unit=unspecified`` unless **`--recipe-strict-other`**.

Generate from any ingest CSV/parquet:

```bash
# from repo root `pfas-toxicology/`
pip install -r pfas_hybrid_encoder/requirements.txt
python pfas_hybrid_encoder/build_shared_encoder_table.py \
  --input data/examples/encoder_ingest_smoke.csv \
  --derive-matrix-onehot matrix \
  --recipe-etl-v1 \
  --output results/shared_encoder_input.parquet \
  --provenance results/shared_encoder_input_provenance.json
```

- **`--recipe-etl-v1`**: calls `preprocess_matrix.preprocess_for_shared_encoder` (aliases → recipes above → validators). Default hybrid width is **`len(all_feature_names())`** with Morgan on (**15 descriptors + 256 bits + measurement tail from `MEASUREMENT_BLOCK_NAMES`**, currently **288** scalars — bump **`ENCODER_SEMANTIC_VERSION`** when that tail changes). Air and solids get dedicated **`matrix_air` / `matrix_solids`** lanes (and **`meas_flag_matrix_*`** in the vector) when you use **`--derive-matrix-onehot`**; **`matrix_food` / `matrix_fish`** are reserved for a later layout bump.
- **`--derive-matrix-onehot matrix`**: maps `matrix` strings onto `matrix_*` flags before encoding.
- **`--analyte-registry`**: optional `(analyte, SMILES)` join when SMILES missing in rows.
- **Without recipes**: you must harmonize units yourself; the encoder still does not auto-convert across media.

ETL columns auto-appended to the parquet when present: `canonical_conc_unit`, `recipe_id`, `etl_suite_id`, `etl_outlier_flag`, `etl_month_*`, `etl_method_*`, etc.

**Tests**: `pip install -r pfas_hybrid_encoder/requirements-dev.txt` then `pytest pfas_hybrid_encoder/tests/`.

Companion **`shared_encoder_input_provenance.json`**: semantic encoder version, RDKit version, Morgan block id, full ordered feature names (for reproducibility / QMS).

Example ingest (with **`conc_unit`**): [`data/examples/encoder_ingest_smoke.csv`](../data/examples/encoder_ingest_smoke.csv).

---

## Interpretability stance (commercial / regulator-facing)

Environmental clients need **QC, uncertainty, matrix context, and chemistry** — not a generic oversized classifier. Morgan + explicit censoring flags + matrix heads is deliberately **physics-informed tabular ML**, not placeholder “big AI.”

---

## Known gaps / roadmap

| Gap | Mitigation direction |
|-----|----------------------|
| **No GNN yet** | Morgan is the correct default until sample size and graph supervision justify Torch Geometric/DGL. |
| **Identifier provenance** | Add ingest columns **`pubchem_cid`**, **`comptox_dtxsid`** (and versioned joins); carry through parquet; pin CompTox dump date in provenance JSON. |
| **Matrix normalization** | Use **`--recipe-etl-v1`** (water ng/L, serum ng/mL) or custom ETL — never pool raw mixed units. |
| **Temporal covariates** | Add **`collection_year`**, **`month`**, **`season`** (passed through today); encode later (splines / embeddings). |
| **Shared 64-D latent** | Train TabNet / FT-Transformer on this table → **`pfas_embedding_64`** column set; keep measurement flags partly **outside** the bottleneck if you need auditors to read QC. |

Descriptor / encoder lineage is keyed by **`ENCODER_SEMANTIC_VERSION`** + **`descriptor_block_id`** + **`morgan_block_id`** in [`pfas_encoder_vector.py`](pfas_encoder_vector.py).

---

## API

- **`HybridVectorEncoder.encode(smiles, MeasurementRow(...))`** → vector + names + meta.
- **`encode_batch_with_meta(df, smiles_col)`** → `features` DataFrame + per-row meta.
- **`encoder_provenance()`** → versions for JSON sidecars.
- **`apply_matrix_group_flags_inplace(df, "matrix_column")`** → boolean matrix flags.

Concentration aliases on ingest: **`quant_value`**, **`conc`**, **`result_value`**, **`concentration`**, **`meas_conc`**.

CLI smoke test:

```bash
python pfas_encoder_vector.py --smiles "C(C(C(C(C(C(C(F)(F)F)(F)F)(F)F)(F)F)(F)F)(F)F)(=O)O" --non-detect --lod 0.002 --json
```

---

## Files

| File | Role |
|------|------|
| `pfas_encoder_vector.py` | Descriptors + Morgan + ND / measurement logic |
| [`preprocess_matrix.py`](preprocess_matrix.py) | **Raw rows → matrix-safe normalized rows** (aliases + recipes + validation) |
| `recipes/*.py` | Per-matrix unit + ND policy + QA flags |
| `build_shared_encoder_table.py` | **`shared_encoder_input.parquet`** + provenance JSON |
| `requirements.txt` | deps (`numpy`, `pandas`, `rdkit`, `pyarrow`) |
| `README.md` | This note |
