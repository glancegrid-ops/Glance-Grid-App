"""Optional face analysis using DeepFace.

This module wraps a small subset of DeepFace functionality to keep the rest of the
pipeline decoupled, while allowing embedding extraction or face attribute analysis.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from src.gpu_utils import GPUConfig


class FaceAnalyzer:
    """Face analysis utilities."""

    def __init__(
        self,
        enforce_deepface: bool = False,
        use_gpu: bool = True,
        gpu_device: int = 0,
    ) -> None:
        # Apply TF device policy before DeepFace/TF initialize.
        GPUConfig(use_gpu=use_gpu, gpu_device=gpu_device).apply_tf_device_policy()

        self._deepface = None
        self._ensure_deepface_available(enforce=enforce_deepface)

    def _ensure_deepface_available(self, enforce: bool = False) -> None:
        if self._deepface is not None:
            return

        try:
            from deepface import DeepFace as ImportedDeepFace  # type: ignore

            self._deepface = ImportedDeepFace
        except Exception:
            if enforce:
                raise ImportError(
                    "DeepFace is required for face analysis. Install it via `pip install deepface`."
                )
            self._deepface = None

    def extract_embedding(self, img: Any, model_name: str = "Facenet") -> List[float]:
        """Extract an embedding for a face image."""
        self._ensure_deepface_available(enforce=True)
        assert self._deepface is not None
        embedding = self._deepface.represent(img_path=img, model_name=model_name)

        # DeepFace returns a list of dicts when given a batch-like input.
        if isinstance(embedding, list) and len(embedding) > 0 and "embedding" in embedding[0]:
            return embedding[0]["embedding"]  # type: ignore
        if isinstance(embedding, dict) and "embedding" in embedding:
            return embedding["embedding"]  # type: ignore
        raise RuntimeError("Unexpected output from DeepFace.represent")

    def analyze_attributes(self, img: Any, actions: Optional[List[str]] = None) -> Dict[str, Any]:
        """Run attribute analysis (age, gender, emotion, race)."""
        self._ensure_deepface_available(enforce=True)
        if actions is None:
            actions = ["age", "gender", "emotion", "race"]
        assert self._deepface is not None
        return self._deepface.analyze(img_path=img, actions=actions)

