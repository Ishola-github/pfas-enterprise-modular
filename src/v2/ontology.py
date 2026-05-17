"""V2 ontology loader (JSON schema aligned with V1)."""
from __future__ import annotations

from pathlib import Path

from src.v1.ontology import Ontology, OntologyLoadError, load_ontology

DEFAULT_ONTOLOGY_PATH = Path(__file__).resolve().parent / "data" / "ontology" / "pfos_pfoa_v2.json"

__all__ = ["Ontology", "OntologyLoadError", "load_ontology", "DEFAULT_ONTOLOGY_PATH"]
