"""Visualization utilities using OpenCV."""

from __future__ import annotations

from typing import Any, Dict, List, Optional

import cv2


class Visualizer:
    """Utility class for drawing detection results on frames."""

    def __init__(self, font_scale: float = 0.5, thickness: int = 2) -> None:
        self.font = cv2.FONT_HERSHEY_SIMPLEX
        self.font_scale = font_scale
        self.thickness = thickness

    def draw_overlays(
        self,
        frame: Any,
        detections: List[Dict[str, Any]],
        gaze_results: List[bool],
        face_count: int,
        fps: Optional[float] = None,
        age_results_text: Optional[List[str]] = None,
        emotion_dominant_results: Optional[List[str]] = None,
        emotion_dominant_prob_results: Optional[List[str]] = None,
    ) -> Any:
        """Draw bounding boxes, gaze labels, and counters on a frame."""
        for idx, (det, is_looking) in enumerate(zip(detections, gaze_results)):
            box = det.get("box")
            if not box:
                continue
            x, y, w, h = box
            x2, y2 = x + w, y + h

            color = (0, 255, 0) if is_looking else (0, 165, 255)
            label = "Looking" if is_looking else "Not Looking"

            cv2.rectangle(frame, (x, y), (x2, y2), color, self.thickness)

            (text_w, text_h), _ = cv2.getTextSize(
                label, self.font, self.font_scale, self.thickness
            )
            cv2.rectangle(
                frame,
                (x, y - text_h - 8),
                (x + text_w + 8, y),
                color,
                -1,
            )
            cv2.putText(
                frame,
                label,
                (x + 4, y - 4),
                self.font,
                self.font_scale,
                (0, 0, 0),
                self.thickness,
                cv2.LINE_AA,
            )

            # Age + emotion (if available).
            age_text = age_results_text[idx] if age_results_text and idx < len(age_results_text) else ""
            dom_text = emotion_dominant_results[idx] if emotion_dominant_results and idx < len(emotion_dominant_results) else ""
            prob_text = (
                emotion_dominant_prob_results[idx]
                if emotion_dominant_prob_results and idx < len(emotion_dominant_prob_results)
                else ""
            )

            if age_text or dom_text:
                parts = []
                if age_text:
                    parts.append(f"Age {age_text}")
                if dom_text:
                    if prob_text:
                        parts.append(f"{dom_text} {prob_text}")
                    else:
                        parts.append(dom_text)
                line2 = " ".join(parts)

                (text_w, text_h), _ = cv2.getTextSize(
                    line2, self.font, self.font_scale, self.thickness
                )
                # Draw near bottom of the face box.
                cv2.rectangle(
                    frame,
                    (x, max(y2 - text_h - 6, 0)),
                    (x + text_w + 6, y2),
                    (0, 0, 0),
                    -1,
                )
                cv2.putText(
                    frame,
                    line2,
                    (x + 3, max(y2 - 3, text_h)),
                    self.font,
                    self.font_scale,
                    (255, 255, 255),
                    self.thickness,
                    cv2.LINE_AA,
                )

        overlay_lines = [f"Faces: {face_count}"]
        if fps is not None:
            overlay_lines.append(f"FPS: {fps:.1f}")

        for idx, line in enumerate(overlay_lines):
            y = 25 + idx * 20
            cv2.putText(
                frame,
                line,
                (10, y),
                self.font,
                self.font_scale,
                (255, 255, 255),
                self.thickness,
                cv2.LINE_AA,
            )

        return frame

