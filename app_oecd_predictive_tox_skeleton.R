# app_oecd_predictive_tox_skeleton.R
# Standards-compliant predictive toxicology Shiny skeleton
# Designed to align with OECD/QSAR validation expectations and the
# five-pillar framework discussed in the attached publications.
# This file is a functional scaffold with placeholder data generators.
# Replace placeholder endpoint datasets and model outputs with validated production assets.
#
# Run locally: shiny::runApp("app_oecd_predictive_tox_skeleton.R")
# Or in RStudio: open this file and click Run App.

suppressPackageStartupMessages({
  library(shiny)
  library(shinydashboard)
  library(DT)
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(purrr)
  library(stringr)
  library(scales)
})

options(shiny.sanitize.errors = FALSE)

APP_TITLE <- "PFAS: Standards-Compliant Predictive Toxicology & Regulatory Screening System"
APP_VERSION <- "1.0.0-skeleton"

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
}

# -------------------------------------------------------------------
# Placeholder data builders
# Replace these with real endpoint datasets, descriptors, fingerprints,
# external/prospective validation assets, and audited model metadata.
# -------------------------------------------------------------------

build_compound_registry <- function() {
  tibble::tribble(
    ~compound_id, ~compound_name, ~CAS, ~SMILES, ~pfas_subclass,
    "CMP-001", "PFOA", "335-67-1", "C(C(C(C(C(C(C(F)(F)F)(F)F)(F)F)(F)F)(F)F)(F)F)(=O)O", "PFCA",
    "CMP-002", "PFOS", "1763-23-1", "OS(=O)(=O)C(C(C(C(C(C(C(C(F)(F)F)(F)F)(F)F)(F)F)(F)F)(F)F)(F)F", "PFSA",
    "CMP-003", "PFNA", "375-95-1", "C(C(C(C(C(C(C(C(F)(F)F)(F)F)(F)F)(F)F)(F)F)(F)F)(F)F)(=O)O", "PFCA",
    "CMP-004", "PFHxS", "355-46-4", "OS(=O)(=O)C(C(C(C(C(C(F)(F)F)(F)F)(F)F)(F)F)(F)F", "PFSA",
    "CMP-005", "HFPO-DA", "13252-13-6", "OC(=O)C(OCC(F)(F)C(F)(F)F)(F)F", "Ether-acid",
    "CMP-006", "GenX", "13252-13-6", "OC(=O)C(OCC(F)(F)C(F)(F)F)(F)F", "Ether-acid"
  ) |>
    dplyr::mutate(
      molecular_weight = c(414.07, 500.13, 464.08, 400.12, 330.05, 330.05),
      log_Kow = c(4.5, 5.3, 5.4, 4.0, 3.0, 3.0),
      tpsa = c(37.3, 42.5, 37.3, 42.5, 44.8, 44.8),
      hba = c(2L, 3L, 2L, 3L, 4L, 4L),
      hbd = c(1L, 0L, 1L, 0L, 1L, 1L),
      rotatable_bonds = c(7L, 8L, 8L, 6L, 4L, 4L),
      aromatic_ring_count = 0L,
      formal_charge = 0L,
      fluorine_count = c(15L, 17L, 17L, 13L, 9L, 9L),
      carbon_chain = c(8L, 8L, 9L, 6L, 6L, 6L),
      acid_class = c("PFCA-family", "PFSA-family", "PFCA-family", "PFSA-family", "Ether-acid", "Ether-acid"),
      acid_class_code = c(1, 2, 1, 2, 3, 3),
      ether_flag = c(0L, 0L, 0L, 0L, 1L, 1L),
      sulfonate_flag = c(0L, 1L, 0L, 1L, 0L, 0L),
      carboxylate_flag = c(1L, 0L, 1L, 0L, 1L, 1L),
      precursor_flag = 0L,
      structural_alerts = c("Perfluoroalkyl acid", "Perfluoroalkyl sulfonate", "Long-chain PFCA", "PFSA alert", "Ether PFAS", "Ether PFAS")
    )
}

build_dataset_registry <- function() {
  tibble::tribble(
    ~dataset_id, ~dataset_name, ~source, ~endpoint, ~endpoint_type, ~human_relevance, ~assay_domain, ~n_total, ~n_positive, ~n_negative, ~missing_rate_pct, ~duplicate_rate_pct, ~version, ~provenance,
    "DS-HEP-001", "HepG2 Viability Benchmark", "Public curated benchmark", "hepatotoxicity_proxy", "Binary", "Proxy for human hepatotoxicity", "in vitro", 5000, 1800, 3200, 1.8, 0.6, "2025.1", "Placeholder metadata: replace with actual dataset card",
    "DS-CARD-001", "hERG Cardiotoxicity Benchmark", "Public curated benchmark", "cardiotoxicity_proxy", "Binary", "Proxy for QT/cardiac risk", "in vitro", 7200, 2100, 5100, 2.1, 0.9, "2025.1", "Placeholder metadata: replace with actual dataset card",
    "DS-GENO-001", "Ames / Genotox Benchmark", "Public curated benchmark", "genotoxicity_proxy", "Binary", "Proxy for mutagenicity/genotoxicity", "in vitro", 8400, 2900, 5500, 1.2, 0.4, "2025.1", "Placeholder metadata: replace with actual dataset card",
    "DS-ENDO-001", "Endocrine Screening Benchmark", "Public curated benchmark", "endocrine_disruption_proxy", "Binary", "Proxy for endocrine activity", "in vitro", 4300, 1100, 3200, 3.5, 1.0, "2025.1", "Placeholder metadata: replace with actual dataset card"
  )
}

build_endpoint_definitions <- function() {
  tibble::tribble(
    ~endpoint_id, ~endpoint_name, ~clinical_meaning, ~label_definition, ~proxy_assay, ~intended_decision_context, ~limitations,
    "EP-HEP", "hepatotoxicity_proxy", "Potential liver toxicity risk", "Positive if assay-defined toxic class", "HepG2 viability / CYP-related proxy", "Early deprioritization / follow-up assay selection", "Proxy endpoint; not equivalent to confirmed human DILI",
    "EP-CARD", "cardiotoxicity_proxy", "Potential cardiac liability", "Positive if cardiotoxicity proxy class", "hERG / cardiac electrophysiology proxy", "Early cardiac liability triage", "Proxy endpoint; not full human cardiotoxicity severity",
    "EP-GENO", "genotoxicity_proxy", "Potential genotoxicity / mutagenicity", "Positive if benchmark label positive", "Ames / micronucleus proxy", "Mutagenicity screening / escalation", "Requires confirmatory evidence for regulatory use",
    "EP-ENDO", "endocrine_disruption_proxy", "Potential endocrine activity", "Positive if endocrine-active class", "Reporter / endocrine assay proxy", "Prioritization / assay follow-up", "Proxy endpoint with uncertain translation across contexts"
  )
}

build_proxy_assay_table <- function() {
  tibble::tribble(
    ~toxicity_domain, ~proxy_assay, ~mechanistic_relevance, ~human_translation_note, ~recommended_next_step,
    "Hepatotoxicity", "HepG2 viability / CYP inhibition", "Moderate", "Useful early proxy but incomplete for human liver injury", "Confirm with higher-content hepatic assay / human-relevant system",
    "Cardiotoxicity", "hERG / cardiomyocyte proxy", "High for selected mechanisms", "Captures some cardiac liabilities but not whole-clinical severity", "Confirm with broader cardiac panel / exposure context",
    "Genotoxicity", "Ames / micronucleus", "High", "Well-established screening proxies for mutagenicity/genotoxicity", "Escalate to confirmatory genotox review",
    "Endocrine disruption", "Reporter gene / endocrine assay", "Moderate", "Assay positive does not guarantee in vivo endocrine outcome", "Review receptor specificity and orthogonal evidence"
  )
}

build_descriptor_schema <- function() {
  tibble::tribble(
    ~feature_name, ~type, ~category, ~source, ~used_in_models,
    "molecular_weight", "numeric", "Descriptor", "RDKit placeholder", TRUE,
    "log_Kow", "numeric", "Descriptor", "RDKit placeholder", TRUE,
    "tpsa", "numeric", "Descriptor", "RDKit placeholder", TRUE,
    "hba", "integer", "Descriptor", "RDKit placeholder", TRUE,
    "hbd", "integer", "Descriptor", "RDKit placeholder", TRUE,
    "rotatable_bonds", "integer", "Descriptor", "RDKit placeholder", TRUE,
    "aromatic_ring_count", "integer", "Descriptor", "RDKit placeholder", TRUE,
    "formal_charge", "integer", "Descriptor", "RDKit placeholder", TRUE,
    "fluorine_count", "integer", "PFAS descriptor", "Rule-based placeholder", TRUE,
    "carbon_chain", "integer", "PFAS descriptor", "Rule-based placeholder", TRUE,
    "pfas_subclass", "categorical", "PFAS descriptor", "Rule-based placeholder", TRUE,
    "structural_alerts", "text", "Structural alerts", "Rule-based placeholder", FALSE
  )
}

build_fingerprint_schema <- function() {
  tibble::tribble(
    ~fingerprint_type, ~radius_or_length, ~mode, ~tool, ~included_for_endpoints,
    "MACCS", "166 bits", "binary", "RDKit placeholder", "All",
    "Morgan/ECFP", "radius 2 / 2048 bits", "binary", "RDKit placeholder", "All"
  )
}

build_structural_alert_table <- function() {
  tibble::tribble(
    ~alert_id, ~alert_name, ~mechanistic_relevance, ~endpoint_relevance, ~rule_source,
    "AL-001", "Perfluoroalkyl acid motif", "General persistence / PFAS identity", "All PFAS endpoints", "Placeholder SMARTS",
    "AL-002", "Long-chain PFCA alert", "Bioaccumulation concern", "Bioaccumulation / chronic concern", "Placeholder SMARTS",
    "AL-003", "PFSA alert", "PFSA subclass mechanistic grouping", "Cardio / bioaccumulation context", "Placeholder SMARTS",
    "AL-004", "Ether PFAS alert", "Emerging PFAS subclass", "New chemistry monitoring", "Placeholder SMARTS"
  )
}

build_model_registry <- function() {
  tibble::tribble(
    ~model_id, ~endpoint, ~algorithm, ~representation, ~training_n, ~class_handling, ~calibration, ~version, ~deployment_status,
    "MDL-HEP-RF", "hepatotoxicity_proxy", "Random Forest", "Descriptors + MACCS + Morgan", 5000, "Class weights", "Platt/Isotonic placeholder", "1.0", "Prototype",
    "MDL-CARD-SVM", "cardiotoxicity_proxy", "SVM", "Descriptors + MACCS + Morgan", 7200, "Class weights", "Platt/Isotonic placeholder", "1.0", "Prototype",
    "MDL-GENO-XGB", "genotoxicity_proxy", "XGBoost", "Descriptors + MACCS + Morgan", 8400, "Class weights", "Platt/Isotonic placeholder", "1.0", "Prototype",
    "MDL-ENDO-RF", "endocrine_disruption_proxy", "Random Forest", "Descriptors + MACCS + Morgan", 4300, "Class weights", "Platt/Isotonic placeholder", "1.0", "Prototype"
  )
}

build_hyperparameter_summary <- function() {
  tibble::tribble(
    ~model_id, ~parameter, ~value, ~tuning_method,
    "MDL-HEP-RF", "mtry", "auto placeholder", "Nested CV placeholder",
    "MDL-HEP-RF", "ntree", "500", "Nested CV placeholder",
    "MDL-CARD-SVM", "cost", "auto placeholder", "Nested CV placeholder",
    "MDL-CARD-SVM", "gamma", "auto placeholder", "Nested CV placeholder",
    "MDL-GENO-XGB", "max_depth", "6", "Nested CV placeholder",
    "MDL-GENO-XGB", "eta", "0.05", "Nested CV placeholder",
    "MDL-ENDO-RF", "mtry", "auto placeholder", "Nested CV placeholder"
  )
}

build_baseline_comparison <- function() {
  tibble::tribble(
    ~endpoint, ~baseline_model, ~production_candidate, ~delta_auc, ~delta_balanced_accuracy, ~delta_sensitivity, ~delta_specificity,
    "hepatotoxicity_proxy", "Logistic Regression", "Random Forest", 0.07, 0.06, 0.04, 0.05,
    "cardiotoxicity_proxy", "Logistic Regression", "SVM", 0.05, 0.05, 0.03, 0.04,
    "genotoxicity_proxy", "Logistic Regression", "XGBoost", 0.08, 0.07, 0.05, 0.06,
    "endocrine_disruption_proxy", "Logistic Regression", "Random Forest", 0.04, 0.03, 0.02, 0.03
  )
}

build_validation_summary <- function() {
  tibble::tribble(
    ~model_id, ~endpoint, ~split_strategy, ~train_n, ~validation_n, ~test_n, ~external_set_n, ~prospective_set_n, ~leakage_check, ~status,
    "MDL-HEP-RF", "hepatotoxicity_proxy", "5-fold CV + hold-out", 4000, 500, 500, 700, 0, "Pass", "Needs prospective validation",
    "MDL-CARD-SVM", "cardiotoxicity_proxy", "5-fold CV + hold-out", 5760, 720, 720, 500, 0, "Pass", "Needs prospective validation",
    "MDL-GENO-XGB", "genotoxicity_proxy", "5-fold CV + hold-out", 6720, 840, 840, 600, 0, "Pass", "Needs prospective validation",
    "MDL-ENDO-RF", "endocrine_disruption_proxy", "5-fold CV + hold-out", 3440, 430, 430, 350, 0, "Pass", "Needs prospective validation"
  )
}

build_performance_metrics <- function() {
  tibble::tribble(
    ~model_id, ~AUC, ~Accuracy, ~Balanced_Accuracy, ~Sensitivity, ~Specificity, ~Precision, ~Recall, ~F1, ~MCC, ~Brier,
    "MDL-HEP-RF", 0.84, 0.79, 0.78, 0.75, 0.81, 0.72, 0.75, 0.74, 0.55, 0.16,
    "MDL-CARD-SVM", 0.82, 0.77, 0.76, 0.73, 0.79, 0.70, 0.73, 0.71, 0.51, 0.18,
    "MDL-GENO-XGB", 0.86, 0.80, 0.79, 0.77, 0.81, 0.75, 0.77, 0.76, 0.58, 0.15,
    "MDL-ENDO-RF", 0.78, 0.74, 0.72, 0.68, 0.77, 0.63, 0.68, 0.65, 0.44, 0.20
  )
}

build_error_buckets <- function() {
  tibble::tribble(
    ~endpoint, ~false_positives, ~false_negatives, ~likely_causes, ~high_risk_failure_mode,
    "hepatotoxicity_proxy", 55, 70, "Sparse chemotypes, proxy mismatch", "False negative hepatic liability",
    "cardiotoxicity_proxy", 63, 78, "Exposure context not modeled", "False negative cardiac risk",
    "genotoxicity_proxy", 49, 61, "Assay label inconsistency", "False negative mutagenicity",
    "endocrine_disruption_proxy", 52, 67, "Weak receptor transferability", "False negative endocrine activity"
  )
}

build_ad_registry <- function() {
  tibble::tribble(
    ~endpoint, ~ad_method, ~training_space_basis, ~distance_metric, ~threshold, ~status,
    "hepatotoxicity_proxy", "Distance to training chemical space", "Descriptors + fingerprints", "z-score / NN hybrid placeholder", "1.5 / 2.5", "Prototype",
    "cardiotoxicity_proxy", "Distance to training chemical space", "Descriptors + fingerprints", "z-score / NN hybrid placeholder", "1.5 / 2.5", "Prototype",
    "genotoxicity_proxy", "Distance to training chemical space", "Descriptors + fingerprints", "z-score / NN hybrid placeholder", "1.5 / 2.5", "Prototype",
    "endocrine_disruption_proxy", "Distance to training chemical space", "Descriptors + fingerprints", "z-score / NN hybrid placeholder", "1.5 / 2.5", "Prototype"
  )
}

build_prediction_table <- function(compounds) {
  endpoints <- c("hepatotoxicity_proxy", "cardiotoxicity_proxy", "genotoxicity_proxy", "endocrine_disruption_proxy")
  expand.grid(compound_id = compounds$compound_id, endpoint = endpoints, stringsAsFactors = FALSE) |>
    tibble::as_tibble() |>
    dplyr::left_join(compounds, by = "compound_id") |>
    dplyr::mutate(
      predicted_probability = c(0.61, 0.72, 0.44, 0.31, 0.28, 0.28, 0.67, 0.80, 0.36, 0.22, 0.24, 0.24,
                                0.58, 0.64, 0.51, 0.34, 0.26, 0.26, 0.62, 0.74, 0.40, 0.30, 0.27, 0.27),
      predicted_class = ifelse(predicted_probability >= 0.50, "Positive", "Negative"),
      ad_distance = c(1.1, 1.3, 1.7, 1.4, 2.8, 2.8, 1.2, 1.6, 1.5, 1.4, 2.6, 2.6,
                      1.3, 1.2, 1.8, 1.5, 2.4, 2.4, 1.0, 1.1, 1.9, 1.7, 2.3, 2.3),
      ad_status = dplyr::case_when(
        ad_distance <= 1.5 ~ "Inside",
        ad_distance <= 2.5 ~ "Borderline",
        TRUE ~ "Outside"
      ),
      confidence = dplyr::case_when(
        ad_status == "Outside" ~ "Low",
        predicted_probability >= 0.80 ~ "High",
        predicted_probability >= 0.60 ~ "Medium",
        TRUE ~ "Low"
      ),
      similar_compound_support = c("Moderate", "High", "Moderate", "Low", "Low", "Low", "Moderate", "High", "Moderate", "Low", "Low", "Low",
                                   "Moderate", "Moderate", "Moderate", "Low", "Low", "Low", "High", "High", "Moderate", "Low", "Low", "Low"),
      recommended_action = dplyr::case_when(
        ad_status == "Outside" ~ "Out-of-domain: do not rely",
        predicted_class == "Positive" & confidence %in% c("High", "Medium") ~ "Confirm with assay",
        predicted_class == "Positive" ~ "Needs human review",
        TRUE ~ "Advance with caution"
      )
    )
}

build_feature_importance <- function() {
  tibble::tribble(
    ~endpoint, ~feature, ~importance, ~interpretation,
    "hepatotoxicity_proxy", "log_Kow", 0.23, "Exposure/partitioning-related contribution",
    "hepatotoxicity_proxy", "fluorine_count", 0.19, "PFAS burden proxy",
    "hepatotoxicity_proxy", "molecular_weight", 0.14, "Global size signal",
    "cardiotoxicity_proxy", "sulfonate_flag", 0.21, "Subclass-associated alert contribution",
    "cardiotoxicity_proxy", "log_Kow", 0.17, "Lipophilicity-related signal",
    "genotoxicity_proxy", "structural_alerts", 0.18, "Structural-risk proxy placeholder",
    "genotoxicity_proxy", "molecular_weight", 0.11, "Weak size contribution",
    "endocrine_disruption_proxy", "ether_flag", 0.20, "Subclass-associated pattern",
    "endocrine_disruption_proxy", "carbon_chain", 0.14, "Chain-length contribution"
  )
}

build_analog_support <- function(compounds) {
  tibble::tribble(
    ~query_compound, ~nearest_analog, ~similarity, ~known_label, ~source_dataset, ~relevance,
    "PFOA", "PFNA", 0.89, "Positive in hepatotoxicity proxy", "DS-HEP-001", "High",
    "PFOS", "PFHxS", 0.87, "Positive in cardiotoxicity proxy", "DS-CARD-001", "High",
    "HFPO-DA", "GenX", 0.95, "Negative/Borderline mixed", "DS-ENDO-001", "Moderate"
  )
}

build_mechanistic_rationale <- function() {
  tibble::tribble(
    ~endpoint, ~evidence_type, ~description, ~strength, ~source,
    "hepatotoxicity_proxy", "Proxy assay rationale", "Hepatic proxy endpoint used for early screening", "Moderate", "Internal model card placeholder",
    "cardiotoxicity_proxy", "Mechanistic proxy", "Cardiac proxy informed by electrophysiology-related assay logic", "Moderate", "Internal model card placeholder",
    "genotoxicity_proxy", "Assay benchmark", "Mutagenicity proxy from benchmark screening context", "High", "Internal model card placeholder",
    "endocrine_disruption_proxy", "Assay benchmark", "Endocrine-active proxy from reporter-style endpoint logic", "Moderate", "Internal model card placeholder"
  )
}

build_model_cards <- function() {
  tibble::tribble(
    ~model_id, ~endpoint, ~dataset_source, ~representation, ~algorithm, ~training_date, ~validation_strategy, ~external_validation, ~prospective_validation, ~ad_method, ~intended_use, ~limitations, ~owner_version,
    "MDL-HEP-RF", "hepatotoxicity_proxy", "DS-HEP-001", "Descriptors + MACCS + Morgan", "Random Forest", "2026-04-07", "5-fold CV + hold-out + external set", "Available", "Not yet", "Distance + nearest neighbors", "Screening / prioritization", "Proxy endpoint, no prospective validation yet", "Owner A / v1.0",
    "MDL-CARD-SVM", "cardiotoxicity_proxy", "DS-CARD-001", "Descriptors + MACCS + Morgan", "SVM", "2026-04-07", "5-fold CV + hold-out + external set", "Available", "Not yet", "Distance + nearest neighbors", "Screening / prioritization", "Proxy endpoint, exposure context incomplete", "Owner A / v1.0",
    "MDL-GENO-XGB", "genotoxicity_proxy", "DS-GENO-001", "Descriptors + MACCS + Morgan", "XGBoost", "2026-04-07", "5-fold CV + hold-out + external set", "Available", "Not yet", "Distance + nearest neighbors", "Screening / prioritization", "No prospective validation yet", "Owner A / v1.0",
    "MDL-ENDO-RF", "endocrine_disruption_proxy", "DS-ENDO-001", "Descriptors + MACCS + Morgan", "Random Forest", "2026-04-07", "5-fold CV + hold-out + external set", "Available", "Not yet", "Distance + nearest neighbors", "Screening / prioritization", "Proxy endpoint, mechanism depends on assay context", "Owner A / v1.0"
  )
}

build_oecd_checklist <- function() {
  tibble::tribble(
    ~principle, ~requirement, ~evidence_in_app, ~status, ~notes,
    "Defined endpoint", "Endpoint must be clearly defined", "Endpoint Definitions table", "Partial", "Needs real production endpoint cards",
    "Unambiguous algorithm", "Algorithm and configuration explicit", "Model registry + hyperparameters", "Partial", "Needs production-training provenance",
    "Applicability domain", "AD clearly defined", "AD registry + compound AD summary", "Partial", "Prototype AD only",
    "Goodness-of-fit / robustness / predictivity", "Performance and validation reported", "Validation summary + metrics", "Partial", "Needs real external/prospective runs",
    "Mechanistic interpretation", "Interpretability where possible", "Feature importance + alerts + analog support", "Partial", "Needs endpoint-specific mechanistic evidence"
  )
}

build_system_readiness <- function() {
  tibble::tribble(
    ~component, ~status, ~notes,
    "Endpoint definitions", "Present", "Placeholder endpoint cards loaded",
    "Descriptor generation", "Present", "Placeholder descriptor schema",
    "Fingerprints generation", "Present", "Schema only; connect real generator",
    "Validation metrics", "Present", "Placeholder tables",
    "External validation", "Present", "Placeholder metadata only",
    "Prospective validation", "Missing", "Add prospective test assets",
    "Applicability domain", "Present", "Prototype AD tables",
    "Mechanistic interpretation", "Present", "Placeholder evidence tables",
    "Weight-of-evidence engine", "Present", "Rule-based skeleton",
    "Model cards", "Present", "Placeholder cards"
  )
}

# -------------------------------------------------------------------
# Materialize app data
# -------------------------------------------------------------------

compounds <- build_compound_registry()
dataset_registry <- build_dataset_registry()
endpoint_definitions <- build_endpoint_definitions()
proxy_assay_table <- build_proxy_assay_table()
descriptor_schema <- build_descriptor_schema()
fingerprint_schema <- build_fingerprint_schema()
structural_alert_table <- build_structural_alert_table()
model_registry <- build_model_registry()
hyperparameter_summary <- build_hyperparameter_summary()
baseline_comparison <- build_baseline_comparison()
validation_summary <- build_validation_summary()
performance_metrics <- build_performance_metrics()
error_buckets <- build_error_buckets()
ad_registry <- build_ad_registry()
predictions <- build_prediction_table(compounds)
feature_importance <- build_feature_importance()
analog_support <- build_analog_support(compounds)
mechanistic_rationale <- build_mechanistic_rationale()
model_cards <- build_model_cards()
oecd_checklist <- build_oecd_checklist()
system_readiness <- build_system_readiness()

compound_ad_summary <- predictions |>
  dplyr::select(compound_id, compound_name, endpoint, ad_distance, ad_status, confidence) |>
  dplyr::arrange(endpoint, compound_name)

weight_of_evidence <- predictions |>
  dplyr::mutate(
    structural_alert_count = dplyr::if_else(
      is.na(structural_alerts) | structural_alerts == "",
      0L,
      1L
    ),
    evidence_grade = dplyr::case_when(
      ad_status == "Outside" ~ "Weak",
      predicted_class == "Positive" & confidence == "High" ~ "Strong",
      predicted_class == "Positive" ~ "Moderate",
      TRUE ~ "Moderate"
    ),
    woe_score = dplyr::case_when(
      evidence_grade == "Strong" ~ 3,
      evidence_grade == "Moderate" ~ 2,
      TRUE ~ 1
    ),
    suggested_action = recommended_action,
    escalation_priority = dplyr::case_when(
      predicted_class == "Positive" & ad_status != "Outside" ~ "High",
      ad_status == "Outside" ~ "High",
      TRUE ~ "Medium"
    )
  ) |>
  dplyr::select(
    compound_id, compound_name, endpoint, predicted_class, predicted_probability,
    confidence, ad_status, structural_alert_count, similar_compound_support,
    evidence_grade, woe_score, suggested_action, escalation_priority
  )

# -------------------------------------------------------------------
# Reusable plotting helpers
# -------------------------------------------------------------------

plot_class_balance <- function() {
  df <- dataset_registry |>
    dplyr::select(endpoint, n_positive, n_negative) |>
    tidyr::pivot_longer(cols = c(n_positive, n_negative), names_to = "class", values_to = "n")

  ggplot(df, aes(x = endpoint, y = n, fill = class)) +
    geom_col(position = "stack") +
    coord_flip() +
    labs(x = NULL, y = "Count", title = "Class balance by endpoint") +
    theme_minimal(base_size = 12)
}

plot_missingness <- function() {
  df <- dataset_registry |>
    dplyr::select(dataset_name, missing_rate_pct)

  ggplot(df, aes(x = reorder(dataset_name, missing_rate_pct), y = missing_rate_pct)) +
    geom_col() +
    coord_flip() +
    labs(x = NULL, y = "Missing rate (%)", title = "Dataset missingness") +
    theme_minimal(base_size = 12)
}

plot_validation_metrics <- function(metric_name) {
  df <- performance_metrics |>
    dplyr::select(model_id, dplyr::all_of(metric_name))

  ggplot(df, aes(x = reorder(model_id, .data[[metric_name]]), y = .data[[metric_name]])) +
    geom_col() +
    coord_flip() +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
    labs(x = NULL, y = metric_name, title = paste(metric_name, "by model")) +
    theme_minimal(base_size = 12)
}

plot_ad_distribution <- function() {
  ggplot(compound_ad_summary, aes(x = ad_status)) +
    geom_bar() +
    labs(x = NULL, y = "Count", title = "Applicability-domain status") +
    theme_minimal(base_size = 12)
}

plot_prediction_risk <- function() {
  df <- weight_of_evidence |>
    dplyr::count(endpoint, predicted_class)

  ggplot(df, aes(x = endpoint, y = n, fill = predicted_class)) +
    geom_col(position = "stack") +
    coord_flip() +
    labs(x = NULL, y = "Count", title = "Predicted class distribution by endpoint") +
    theme_minimal(base_size = 12)
}

plot_feature_importance <- function(endpoint_pick) {
  df <- feature_importance |>
    dplyr::filter(endpoint == endpoint_pick)

  ggplot(df, aes(x = reorder(feature, importance), y = importance)) +
    geom_col() +
    coord_flip() +
    labs(x = NULL, y = "Importance", title = paste("Top features:", endpoint_pick)) +
    theme_minimal(base_size = 12)
}

# -------------------------------------------------------------------
# UI
# -------------------------------------------------------------------

ui <- dashboardPage(
  dashboardHeader(title = APP_TITLE),
  dashboardSidebar(
    sidebarMenu(
      menuItem("Home / Overview", tabName = "home", icon = icon("home")),
      menuItem("Data & Endpoints", tabName = "data", icon = icon("database")),
      menuItem("Representations", tabName = "representations", icon = icon("project-diagram")),
      menuItem("Modeling", tabName = "modeling", icon = icon("cogs")),
      menuItem("Validation", tabName = "validation", icon = icon("check-circle")),
      menuItem("Predictions", tabName = "predictions", icon = icon("table")),
      menuItem("Applicability Domain", tabName = "ad", icon = icon("bullseye")),
      menuItem("Mechanistic Interpretation", tabName = "mechanistic", icon = icon("microscope")),
      menuItem("Decision Support", tabName = "decision", icon = icon("balance-scale")),
      menuItem("Compliance / Model Cards", tabName = "compliance", icon = icon("clipboard-check")),
      menuItem("Reports / Export", tabName = "reports", icon = icon("file-export"))
    )
  ),
  dashboardBody(
    tags$head(tags$style(HTML(".small-box h3 {font-size: 26px;} .content {padding: 15px;} .box .dataTables_wrapper {overflow-x:auto;}"))),
    tabItems(
      tabItem(
        tabName = "home",
        fluidRow(
          valueBoxOutput("vb_compounds", width = 2),
          valueBoxOutput("vb_datasets", width = 2),
          valueBoxOutput("vb_models", width = 2),
          valueBoxOutput("vb_inside_ad", width = 2),
          valueBoxOutput("vb_outside_ad", width = 2),
          valueBoxOutput("vb_high_concern", width = 2)
        ),
        fluidRow(
          box(width = 6, title = "Intended Use", status = "primary", solidHeader = TRUE,
              p("Use this system for screening, prioritization, transparency review, and weight-of-evidence support. Do not treat this scaffold as a standalone regulatory submission engine until it is backed by validated production endpoint models and audited datasets.")),
          box(width = 6, title = "Current Limitations", status = "warning", solidHeader = TRUE,
              p("This version is a standards-oriented skeleton. Replace placeholder datasets, placeholder validation statistics, and placeholder model cards with real endpoint assets, external validation results, and prospective testing evidence."))
        ),
        fluidRow(
          box(width = 6, title = "System Readiness", status = "info", solidHeader = TRUE, DTOutput("tbl_system_readiness")),
          box(width = 6, title = "OECD / QSAR Principles Checklist", status = "info", solidHeader = TRUE, DTOutput("tbl_oecd_home"))
        )
      ),
      tabItem(
        tabName = "data",
        fluidRow(
          box(width = 12, title = "Datasets", status = "primary", solidHeader = TRUE, DTOutput("tbl_dataset_registry"))
        ),
        fluidRow(
          box(width = 6, title = "Endpoint Definitions", status = "warning", solidHeader = TRUE, DTOutput("tbl_endpoint_definitions")),
          box(width = 6, title = "Proxy Endpoints", status = "warning", solidHeader = TRUE, DTOutput("tbl_proxy_assays"))
        ),
        fluidRow(
          box(width = 6, title = "Dataset Missingness", status = "info", solidHeader = TRUE, plotOutput("plot_missingness", height = 300)),
          box(width = 6, title = "Class Balance", status = "info", solidHeader = TRUE, plotOutput("plot_class_balance", height = 300))
        )
      ),
      tabItem(
        tabName = "representations",
        fluidRow(
          box(width = 6, title = "Descriptor Schema", status = "primary", solidHeader = TRUE, DTOutput("tbl_descriptor_schema")),
          box(width = 6, title = "Fingerprint Schema", status = "primary", solidHeader = TRUE, DTOutput("tbl_fingerprint_schema"))
        ),
        fluidRow(
          box(width = 12, title = "Structural Alerts", status = "warning", solidHeader = TRUE, DTOutput("tbl_structural_alerts"))
        ),
        fluidRow(
          box(width = 12, title = "Compound Registry", status = "info", solidHeader = TRUE, DTOutput("tbl_compounds"))
        )
      ),
      tabItem(
        tabName = "modeling",
        fluidRow(
          box(width = 8, title = "Model Registry", status = "primary", solidHeader = TRUE, DTOutput("tbl_model_registry")),
          box(width = 4, title = "Baseline Comparison", status = "info", solidHeader = TRUE, DTOutput("tbl_baseline_comparison"))
        ),
        fluidRow(
          box(width = 12, title = "Hyperparameter Summary", status = "warning", solidHeader = TRUE, DTOutput("tbl_hyperparameters"))
        )
      ),
      tabItem(
        tabName = "validation",
        fluidRow(
          box(width = 8, title = "Validation Summary", status = "primary", solidHeader = TRUE, DTOutput("tbl_validation_summary")),
          box(width = 4, title = "Error Buckets", status = "warning", solidHeader = TRUE, DTOutput("tbl_error_buckets"))
        ),
        fluidRow(
          box(width = 6, title = "Performance Metrics", status = "info", solidHeader = TRUE, DTOutput("tbl_performance_metrics")),
          box(width = 6, title = "Balanced Accuracy by Model", status = "info", solidHeader = TRUE, plotOutput("plot_bal_acc", height = 300))
        )
      ),
      tabItem(
        tabName = "predictions",
        fluidRow(
          box(width = 12, title = "Compound-Level Predictions", status = "primary", solidHeader = TRUE, DTOutput("tbl_predictions"))
        ),
        fluidRow(
          box(width = 12, title = "Prediction Distribution", status = "info", solidHeader = TRUE, plotOutput("plot_prediction_risk", height = 300))
        )
      ),
      tabItem(
        tabName = "ad",
        fluidRow(
          box(width = 6, title = "Applicability Domain Registry", status = "primary", solidHeader = TRUE, DTOutput("tbl_ad_registry")),
          box(width = 6, title = "AD Status Distribution", status = "info", solidHeader = TRUE, plotOutput("plot_ad_distribution", height = 300))
        ),
        fluidRow(
          box(width = 12, title = "Compound AD Summary", status = "warning", solidHeader = TRUE, DTOutput("tbl_ad_summary"))
        )
      ),
      tabItem(
        tabName = "mechanistic",
        fluidRow(
          box(width = 4, title = "Endpoint", status = "primary", solidHeader = TRUE,
              selectInput("mechanistic_endpoint", "Choose endpoint", choices = unique(feature_importance$endpoint), selected = unique(feature_importance$endpoint)[1])),
          box(width = 8, title = "Top Feature Contributions", status = "info", solidHeader = TRUE, plotOutput("plot_feature_importance", height = 300))
        ),
        fluidRow(
          box(width = 6, title = "Feature Importance Table", status = "primary", solidHeader = TRUE, DTOutput("tbl_feature_importance")),
          box(width = 6, title = "Analog / Read-Across Support", status = "warning", solidHeader = TRUE, DTOutput("tbl_analog_support"))
        ),
        fluidRow(
          box(width = 12, title = "Mechanistic Rationale", status = "info", solidHeader = TRUE, DTOutput("tbl_mechanistic_rationale"))
        )
      ),
      tabItem(
        tabName = "decision",
        fluidRow(
          box(width = 12, title = "Weight-of-Evidence / Decision Summary", status = "primary", solidHeader = TRUE, DTOutput("tbl_woe"))
        )
      ),
      tabItem(
        tabName = "compliance",
        fluidRow(
          box(width = 5, title = "OECD / QSAR Checklist", status = "warning", solidHeader = TRUE, DTOutput("tbl_oecd_checklist")),
          box(width = 7, title = "Model Cards", status = "primary", solidHeader = TRUE, DTOutput("tbl_model_cards"))
        )
      ),
      tabItem(
        tabName = "reports",
        fluidRow(
          box(width = 12, title = "Export / Reporting Specification", status = "info", solidHeader = TRUE,
              tags$ul(
                tags$li("Prediction CSV"),
                tags$li("Validation report"),
                tags$li("Model card PDF/HTML"),
                tags$li("Compliance summary PDF/HTML"),
                tags$li("Compound-level weight-of-evidence report")
              ),
              p("Implementation note: wire these buttons to downloadHandler objects once real production datasets and model assets are attached.")
          )
        )
      )
    )
  )
)

# -------------------------------------------------------------------
# Server
# -------------------------------------------------------------------

server <- function(input, output, session) {
  output$vb_compounds <- renderValueBox({
    valueBox(nrow(compounds), "Compounds", icon = icon("flask"), color = "aqua")
  })

  output$vb_datasets <- renderValueBox({
    valueBox(nrow(dataset_registry), "Endpoint Datasets", icon = icon("database"), color = "yellow")
  })

  output$vb_models <- renderValueBox({
    valueBox(nrow(model_registry), "Models", icon = icon("cubes"), color = "purple")
  })

  output$vb_inside_ad <- renderValueBox({
    valueBox(sum(compound_ad_summary$ad_status == "Inside"), "Inside AD", icon = icon("check"), color = "green")
  })

  output$vb_outside_ad <- renderValueBox({
    valueBox(sum(compound_ad_summary$ad_status == "Outside"), "Outside AD", icon = icon("exclamation-triangle"), color = "red")
  })

  output$vb_high_concern <- renderValueBox({
    valueBox(sum(weight_of_evidence$predicted_class == "Positive"), "Positive Flags", icon = icon("radiation"), color = "maroon")
  })

  render_dt <- function(df, pageLength = 8) {
    DT::datatable(df, options = list(pageLength = pageLength, scrollX = TRUE), rownames = FALSE)
  }

  output$tbl_system_readiness <- renderDT(render_dt(system_readiness, 10))
  output$tbl_oecd_home <- renderDT(render_dt(oecd_checklist, 5))
  output$tbl_dataset_registry <- renderDT(render_dt(dataset_registry, 8))
  output$tbl_endpoint_definitions <- renderDT(render_dt(endpoint_definitions, 6))
  output$tbl_proxy_assays <- renderDT(render_dt(proxy_assay_table, 6))
  output$tbl_descriptor_schema <- renderDT(render_dt(descriptor_schema, 10))
  output$tbl_fingerprint_schema <- renderDT(render_dt(fingerprint_schema, 5))
  output$tbl_structural_alerts <- renderDT(render_dt(structural_alert_table, 8))
  output$tbl_compounds <- renderDT(render_dt(compounds, 8))
  output$tbl_model_registry <- renderDT(render_dt(model_registry, 8))
  output$tbl_baseline_comparison <- renderDT(render_dt(baseline_comparison, 8))
  output$tbl_hyperparameters <- renderDT(render_dt(hyperparameter_summary, 10))
  output$tbl_validation_summary <- renderDT(render_dt(validation_summary, 8))
  output$tbl_error_buckets <- renderDT(render_dt(error_buckets, 8))
  output$tbl_performance_metrics <- renderDT(render_dt(performance_metrics, 8))
  output$tbl_predictions <- renderDT(render_dt(predictions, 10))
  output$tbl_ad_registry <- renderDT(render_dt(ad_registry, 8))
  output$tbl_ad_summary <- renderDT(render_dt(compound_ad_summary, 10))
  output$tbl_analog_support <- renderDT(render_dt(analog_support, 8))
  output$tbl_mechanistic_rationale <- renderDT(render_dt(mechanistic_rationale, 8))
  output$tbl_woe <- renderDT(render_dt(weight_of_evidence, 10))
  output$tbl_oecd_checklist <- renderDT(render_dt(oecd_checklist, 8))
  output$tbl_model_cards <- renderDT(render_dt(model_cards, 8))

  output$tbl_feature_importance <- renderDT({
    df <- feature_importance |>
      dplyr::filter(endpoint == input$mechanistic_endpoint)
    render_dt(df, 8)
  })

  output$plot_missingness <- renderPlot(plot_missingness())
  output$plot_class_balance <- renderPlot(plot_class_balance())
  output$plot_bal_acc <- renderPlot(plot_validation_metrics("Balanced_Accuracy"))
  output$plot_prediction_risk <- renderPlot(plot_prediction_risk())
  output$plot_ad_distribution <- renderPlot(plot_ad_distribution())
  output$plot_feature_importance <- renderPlot(plot_feature_importance(input$mechanistic_endpoint))
}

shinyApp(ui, server)
