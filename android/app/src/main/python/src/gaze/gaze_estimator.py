"""Simple gaze estimation heuristics.

This module provides a lightweight gaze estimator that uses facial keypoints
(from MTCNN) to guess whether the person is roughly looking toward the camera.
"""

from __future__ import annotations

from typing import Dict, Tuple


Keypoints = Dict[str, Tuple[int, int]]
"""Keypoints from MTCNN: left_eye, right_eye, nose, mouth_left, mouth_right."""


class GazeEstimator:
    """Estimate gaze direction from facial landmarks."""

    def __init__(
        self,
        max_horizontal_offset: float = 0.25,
        max_vertical_offset: float = 0.25,
        use_eye_symmetry: bool = True,
        use_mouth_check: bool = True,
    ) -> None:
        self.max_horizontal_offset = max_horizontal_offset
        self.max_vertical_offset = max_vertical_offset
        self.use_eye_symmetry = use_eye_symmetry
        self.use_mouth_check = use_mouth_check

    def is_looking_at_camera(self, keypoints: Keypoints) -> bool:
        """Return True if the subject appears to be looking at the camera."""
        required = {"left_eye", "right_eye", "nose"}
        if not required.issubset(keypoints.keys()):
            return False

        lx, ly = keypoints["left_eye"]
        rx, ry = keypoints["right_eye"]
        nx, ny = keypoints["nose"]

        eye_center_x = (lx + rx) / 2.0
        eye_center_y = (ly + ry) / 2.0
        inter_eye_dist = max(abs(rx - lx), 1.0)

        dx = (nx - eye_center_x) / inter_eye_dist
        dy = (ny - eye_center_y) / inter_eye_dist

        nose_centered = (
            abs(dx) <= self.max_horizontal_offset
            and abs(dy) <= self.max_vertical_offset
        )

        eye_symmetry = True
        if self.use_eye_symmetry:
            # Eyes roughly level.
            eye_symmetry = abs(ly - ry) / inter_eye_dist <= 0.15

        mouth_check = True
        if self.use_mouth_check and "mouth_left" in keypoints and "mouth_right" in keypoints:
            mlx, mly = keypoints["mouth_left"]
            mrx, mry = keypoints["mouth_right"]
            mouth_center_y = (mly + mry) / 2.0
            # Mouth should be below nose.
            mouth_check = mouth_center_y > ny

        return nose_centered and eye_symmetry and mouth_check

