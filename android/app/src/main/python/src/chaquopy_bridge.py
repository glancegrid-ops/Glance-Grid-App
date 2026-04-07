"""Chaquopy / Android entry: JPEG bytes in, JSON string out.

Call from Kotlin (after Chaquopy starts Python) on module ``src.chaquopy_bridge``:
``init_runtime`` with an absolute config path, then ``analyze_jpeg_bytes`` with JPEG ``byte[]``.

Flutter: use a MethodChannel to Android; capture camera JPEG every 30s and forward bytes.
"""

from __future__ import annotations

import json
import os
import time
from typing import Any, Dict, Optional

import cv2
import numpy as np

from src.config_loader import load_config
from src.frame_analysis_runtime import FrameAnalysisRuntime
from src.live_frame_result import analyze_bgr_frame_for_json

_runtime: Optional[FrameAnalysisRuntime] = None


def init_runtime(config_path: Optional[str] = None) -> None:
    """Load YAML config and build detector (and optional DeepFace). Call once from Android."""
    global _runtime
    path = config_path
    if not path:
        path = os.environ.get("FACECOUNT_CONFIG")
    cfg = load_config(path)
    _runtime = FrameAnalysisRuntime.from_config(cfg)


def _ensure_runtime() -> FrameAnalysisRuntime:
    global _runtime
    if _runtime is None:
        init_runtime(None)
    assert _runtime is not None
    return _runtime


def analyze_jpeg_bytes(jpeg_bytes: bytes) -> str:
    """Decode JPEG, run face + age/emotion pipeline, return JSON (same shape as POST /analyze_frame)."""
    rt = _ensure_runtime()
    if not jpeg_bytes:
        return json.dumps(
            {
                "timestamp_ms": int(time.time() * 1000),
                "error": "empty_input",
                "deepface_enabled": rt.deepface_requested,
                "face_count": 0,
                "faces": [],
            }
        )

    np_arr = np.frombuffer(jpeg_bytes, dtype=np.uint8)
    img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
    if img is None:
        return json.dumps(
            {
                "timestamp_ms": int(time.time() * 1000),
                "error": "unable_to_decode_image",
                "deepface_enabled": rt.analyzer is not None,
                "face_count": 0,
                "faces": [],
            }
        )

    payload = analyze_bgr_frame_for_json(
        img,
        rt.detector,
        rt.gaze_estimator,
        analyzer=rt.analyzer,
        deepface_actions=rt.deepface_actions,
    )
    body: Dict[str, Any] = {
        "timestamp_ms": int(time.time() * 1000),
        "deepface_enabled": rt.deepface_requested,
        **payload,
    }
    return json.dumps(body)


def reset_runtime() -> None:
    """Drop cached models (tests / process death)."""
    global _runtime
    _runtime = None
