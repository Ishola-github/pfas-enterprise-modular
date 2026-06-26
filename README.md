# PFAS Enterprise 5.0

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20425189.svg)](https://doi.org/10.5281/zenodo.20425189)

> **Human-centered PFAS screening decision-support platform for environmental laboratories, consultants, and researchers.**

---

# Overview

PFAS Enterprise 5.0 is a Research Use Only (RUO) decision-support platform designed to harmonize PFAS datasets, perform screening, generate model-card reports, maintain provenance, and route uncertain samples for qualified human review.

The platform emphasizes transparency, reproducibility, and human oversight while supporting laboratory workflows and environmental decision-making.

---

# Scientific Background

Per- and polyfluoroalkyl substances (PFAS) are persistent environmental contaminants requiring robust analytical chemistry, reproducible computational workflows, and expert interpretation.

PFAS Enterprise 5.0 combines analytical chemistry principles, computational toxicology, explainable screening methods, and reproducibility practices into a unified research platform.

Potential applications include:

* PFAS environmental monitoring
* Human biomonitoring
* Drinking-water assessment
* Exposure science
* Laboratory workflow support
* Environmental consulting
* Research reproducibility

---

# Governance and Scope

**Research Use Only (RUO)**

This platform:

* is not EPA-approved
* is not ISO-accredited
* is not a certified laboratory method
* is not a replacement for EPA Method 1633 or EPA Method 533
* is not intended for clinical diagnosis

All screening outputs require qualified scientific review.

---

# Features

## Data Harmonization

* Sample import
* PFAS data harmonization
* Applicability-domain assessment

## Decision Support

* Human-review routing
* Model-card reports
* Screening summaries
* Audit logs

## Reproducibility

* Frozen releases
* Provenance tracking
* Validation workflows
* Manifest generation

## Sustainability

* Sustainability metrics
* Estimated avoided costs
* Environmental impact indicators

---

# Workflow

```text
Sample Import
      ↓
Applicability Domain
      ↓
PFAS Screening
      ↓
Human Review
      ↓
Model Card Report
      ↓
Audit Trail
```

---

# Installation

Clone the repository:

```bash
git clone https://github.com/Ishola-github/pfas-enterprise-modular.git
cd pfas-enterprise-modular
```

Checkout the reproducibility release:

```bash
git checkout serum-v2.0.0-temporal
```

Run the verification workflow:

```bash
bash scripts/repro_one_shot.sh
```

---

# Inputs

* PFAS analytical datasets
* Laboratory sample metadata
* Method identifiers
* Sample identifiers

---

# Outputs

The platform can generate:

* Model-card reports
* Screening summaries
* Provenance manifests
* Audit logs
* Validation reports
* Sustainability metrics

---

# Repository Structure

```text
pfas-enterprise-modular/
├── api/
├── data/
├── docs/
├── validation/
├── scripts/
├── app.R
├── LatestPFAS.R
├── Dockerfile
├── README.md
├── LICENSE
└── CITATION.cff
```

---

# Limitations

PFAS Enterprise 5.0 is:

* a research platform
* a screening decision-support tool
* not a laboratory replacement
* not a validated regulatory system
* not intended for clinical decision making

---

# Citation

Please cite the Zenodo DOI associated with the frozen release and follow the repository citation guidance.

---

# License

Released under the MIT License.

---

# Future Roadmap

Planned enhancements include:

* Expanded PFAS libraries
* Additional analytical workflows
* Explainable AI improvements
* LC-MS/MS workflow integration
* Enhanced laboratory dashboards
* LIMS integration
* Automated reporting
* Broader reproducibility support

---

# Author

**Sunday A. Ishola, M.S.**

Environmental Toxicologist • Analytical Chemist • Clinical Toxicologist

Research interests include PFAS, analytical chemistry, environmental toxicology, exposure science, computational toxicology, and reproducible scientific computing.
