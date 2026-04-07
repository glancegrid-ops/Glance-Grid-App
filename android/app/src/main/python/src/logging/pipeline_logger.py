"""Logging utilities for the desktop pipeline.

This module provides a lightweight logger that writes structured records to both
console and a file (CSV).
"""

from __future__ import annotations

import csv
import logging
from datetime import datetime
from typing import Any, Dict, List, Optional


class PipelineLogger:
    """Simple logger that writes CSV records and prints to console."""

    def __init__(self, log_path: Optional[str] = None) -> None:
        self._logger = logging.getLogger("FaceCount2")
        self._logger.setLevel(logging.INFO)

        if not self._logger.handlers:
            handler = logging.StreamHandler()
            handler.setFormatter(
                logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
            )
            self._logger.addHandler(handler)

        self._csv_file = None
        self._csv_writer = None

        if log_path:
            self._csv_file = open(log_path, "w", newline="", encoding="utf-8")
            self._csv_writer = csv.DictWriter(
                self._csv_file,
                fieldnames=[
                    "timestamp",
                    "frame_number",
                    "frame_time_s",
                    "face_count",
                    "gaze_results",
                    "age_results_text",
                    "emotion_dominant_results",
                    "emotion_dominant_prob_results",
                    "emotion_probs_results_json",
                ],
            )
            self._csv_writer.writeheader()

    def log_frame(
        self,
        frame_number: int,
        frame_time_s: float,
        face_count: int,
        gaze_results: List[bool],
        age_results_text: Optional[List[str]] = None,
        emotion_dominant_results: Optional[List[str]] = None,
        emotion_dominant_prob_results: Optional[List[str]] = None,
        emotion_probs_results_json: Optional[List[str]] = None,
        extra: Optional[Dict[str, Any]] = None,
    ) -> None:
        """Log a single frame's results."""
        timestamp = datetime.utcnow().isoformat()
        gaze_summary = ",".join(["1" if g else "0" for g in gaze_results])

        age_summary = ",".join(age_results_text) if age_results_text is not None else ""
        emotion_dom_summary = (
            ",".join(emotion_dominant_results) if emotion_dominant_results is not None else ""
        )
        emotion_prob_summary = (
            ",".join(emotion_dominant_prob_results) if emotion_dominant_prob_results is not None else ""
        )
        emotion_probs_json_summary = (
            ",".join(emotion_probs_results_json) if emotion_probs_results_json is not None else ""
        )

        message = (
            f"frame={frame_number} time={frame_time_s:.3f}s faces={face_count} "
            f"gaze=[{gaze_summary}] "
            f"age=[{age_summary}] emotion=[{emotion_dom_summary}] prob=[{emotion_prob_summary}]"
        )
        if extra:
            message += " " + " ".join(f"{k}={v}" for k, v in extra.items())

        self._logger.info(message)

        if self._csv_writer:
            self._csv_writer.writerow(
                {
                    "timestamp": timestamp,
                    "frame_number": frame_number,
                    "frame_time_s": f"{frame_time_s:.3f}",
                    "face_count": face_count,
                    "gaze_results": gaze_summary,
                    "age_results_text": age_summary,
                    "emotion_dominant_results": emotion_dom_summary,
                    "emotion_dominant_prob_results": emotion_prob_summary,
                    "emotion_probs_results_json": emotion_probs_json_summary,
                }
            )
            self._csv_file.flush()

    def close(self) -> None:
        """Close any open resources."""
        if self._csv_file:
            self._csv_file.close()
            self._csv_file = None
            self._csv_writer = None

