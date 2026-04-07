"""YAML configuration loader for FaceCount2.

This keeps runtime defaults (detector thresholds, logging paths, DB settings, etc.)
outside of code.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, Optional

import yaml


def load_config(config_path: Optional[str] = None) -> Dict[str, Any]:
    """Load config from YAML, returning an empty dict if not found."""
    if config_path is None:
        # project_root/configs/config.yaml
        config_path = str(Path(__file__).resolve().parents[1] / "configs" / "config.yaml")

    path = Path(config_path)
    if not path.exists():
        return {}

    raw = path.read_text(encoding="utf-8")
    if not raw.strip():
        return {}

    data = yaml.safe_load(raw)
    if not isinstance(data, dict):
        return {}

    return data


def deep_get(config: Dict[str, Any], dotted_key: str, default: Any = None) -> Any:
    """Get a nested value using dot-separated keys."""
    cur: Any = config
    for part in dotted_key.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return default
        cur = cur[part]
    return cur

