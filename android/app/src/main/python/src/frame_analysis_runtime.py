"""Shared detector + gaze + optional DeepFace wiring for FastAPI and Chaquopy."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Optional

from src.analysis.face_analyzer import FaceAnalyzer
from src.config_loader import deep_get
from src.detection.face_detector import FaceDetector
from src.gaze.gaze_estimator import GazeEstimator
from src.gpu_utils import GPUConfig


@dataclass(frozen=True)
class FrameAnalysisRuntime:
    detector: FaceDetector
    gaze_estimator: GazeEstimator
    analyzer: Optional[FaceAnalyzer]
    deepface_actions: List[str]
    deepface_requested: bool

    @classmethod
    def from_config(
        cls,
        config: Dict[str, Any],
        *,
        detector: Optional[FaceDetector] = None,
        gaze_estimator: Optional[GazeEstimator] = None,
    ) -> FrameAnalysisRuntime:
        """Build runtime; reuse ``detector`` / ``gaze_estimator`` when provided (e.g. FastAPI tests)."""
        gpu_enabled = bool(deep_get(config, "gpu.enabled", True))
        gpu_device = deep_get(config, "gpu.device_index", 0)
        try:
            gpu_device = int(gpu_device)
        except (TypeError, ValueError):
            gpu_device = 0
        gpu_config = GPUConfig(use_gpu=gpu_enabled, gpu_device=gpu_device)

        if detector is None:
            min_face_size = deep_get(config, "detection.min_face_size", 20)
            try:
                min_face_size = int(min_face_size)
            except (TypeError, ValueError):
                min_face_size = 20

            steps_threshold = deep_get(config, "detection.steps_threshold", [0.6, 0.7, 0.7])
            if not isinstance(steps_threshold, (list, tuple)) or len(steps_threshold) != 3:
                steps_threshold = [0.6, 0.7, 0.7]
            steps_threshold_tuple = tuple(float(x) for x in steps_threshold)

            detector = FaceDetector(
                min_face_size=min_face_size,
                steps_threshold=steps_threshold_tuple,  # type: ignore[arg-type]
                use_gpu=gpu_config.is_available,
                gpu_device=gpu_config.gpu_device,
            )

        if gaze_estimator is None:
            gaze_estimator = GazeEstimator(
                max_horizontal_offset=float(deep_get(config, "gaze.max_horizontal_offset", 0.25)),
                max_vertical_offset=float(deep_get(config, "gaze.max_vertical_offset", 0.25)),
                use_eye_symmetry=bool(deep_get(config, "gaze.use_eye_symmetry", True)),
                use_mouth_check=bool(deep_get(config, "gaze.use_mouth_check", True)),
            )

        deepface_enabled = bool(deep_get(config, "deepface.age_emotion.enabled", False))
        deepface_actions = deep_get(config, "deepface.age_emotion.actions", ["age", "emotion"])
        if not isinstance(deepface_actions, list) or not deepface_actions:
            deepface_actions = ["age", "emotion"]
        deepface_actions_list: List[str] = [str(a) for a in deepface_actions]

        deepface_enforce = bool(deep_get(config, "deepface.age_emotion.enforce_deepface", False))
        analyzer: Optional[FaceAnalyzer] = None
        if deepface_enabled:
            analyzer = FaceAnalyzer(
                enforce_deepface=deepface_enforce,
                use_gpu=gpu_config.use_gpu,
                gpu_device=gpu_config.gpu_device,
            )

        return cls(
            detector=detector,
            gaze_estimator=gaze_estimator,
            analyzer=analyzer,
            deepface_actions=deepface_actions_list,
            deepface_requested=deepface_enabled,
        )


def build_frame_analysis_runtime(config: Dict[str, Any]) -> FrameAnalysisRuntime:
    """Build components for single-frame face + optional age/emotion analysis."""
    return FrameAnalysisRuntime.from_config(config)
