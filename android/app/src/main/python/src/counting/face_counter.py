"""Face counting utilities.

Keeps a simple running tally of detected faces.
"""

from __future__ import annotations

from typing import List


class FaceCounter:
    """Track face counts across frames."""

    def __init__(self) -> None:
        self._frame_counts: List[int] = []

    @property
    def total_faces(self) -> int:
        return sum(self._frame_counts)

    @property
    def last_frame_count(self) -> int:
        return self._frame_counts[-1] if self._frame_counts else 0

    @property
    def frame_counts(self) -> List[int]:
        return list(self._frame_counts)

    def update(self, face_count: int) -> None:
        self._frame_counts.append(face_count)

    def reset(self) -> None:
        self._frame_counts.clear()

