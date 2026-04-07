"""Face detection using MTCNN.

This module wraps the `mtcnn` face detector and provides a simple API to return
face bounding boxes and keypoints in an easy-to-consume form.
"""

from __future__ import annotations

from typing import Dict, List, Tuple

import cv2
import numpy as np

from src.gpu_utils import GPUConfig

FaceDetection = Dict[str, object]
"""Type alias for a single face detection result.

Expected keys:
- "box": Tuple[int, int, int, int]  (x, y, width, height)
- "confidence": float
- "keypoints": dict (left_eye, right_eye, nose, mouth_left, mouth_right)
"""


class FaceDetector:
    """Face detector wrapper around MTCNN or OpenCV cascade fallback."""

    def __init__(
        self,
        min_face_size: int = 20,
        steps_threshold: Tuple[float, float, float] = (0.6, 0.7, 0.7),
        use_gpu: bool = True,
        gpu_device: int = 0,
    ) -> None:
        # Apply TF GPU/CPU policy before mtcnn/TF initialize.
        GPUConfig(use_gpu=use_gpu, gpu_device=gpu_device).apply_tf_device_policy()

        self._detector_type = "mtcnn"
        try:
            from mtcnn import MTCNN  # local import so policy runs before TF init

            # MTCNN accepts `steps_threshold` (p-net, r-net, o-net stage thresholds).
            self._detector = MTCNN(
                min_face_size=min_face_size,
                steps_threshold=steps_threshold,
            )
        except ImportError:
            self._detector_type = "opencv"
            cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
            self._cascade = cv2.CascadeClassifier(cascade_path)
            if self._cascade.empty():
                raise RuntimeError(
                    "MTCNN not found and OpenCV cascade failed to load; cannot detect faces."
                )

    def detect_faces(self, frame: np.ndarray) -> List[FaceDetection]:
        """Detect faces in a BGR (OpenCV) frame."""
        results: List[FaceDetection] = []

        if self._detector_type == "mtcnn":
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            detections = self._detector.detect_faces(rgb)

            for det in detections:
                box = det.get("box")
                confidence = float(det.get("confidence", 0.0))
                keypoints = det.get("keypoints", {})

                # Ensure integer box values.
                if box is not None and len(box) == 4:
                    box = (int(box[0]), int(box[1]), int(box[2]), int(box[3]))

                results.append(
                    {
                        "box": box,
                        "confidence": confidence,
                        "keypoints": keypoints,
                    }
                )

        else:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            faces = self._cascade.detectMultiScale(
                gray,
                scaleFactor=1.1,
                minNeighbors=5,
                minSize=(20, 20),
                flags=cv2.CASCADE_SCALE_IMAGE,
            )
            for (x, y, w, h) in faces:
                results.append(
                    {
                        "box": (int(x), int(y), int(w), int(h)),
                        "confidence": 1.0,
                        "keypoints": {},
                    }
                )

        return results

