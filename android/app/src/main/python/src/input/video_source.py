"""Video source abstractions.

This module defines a small abstraction layer over OpenCV video capture sources.
It is designed to keep the pipeline code independent of whether frames come from
an MP4 file or a live camera.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Optional, Tuple

import cv2


class VideoSource(ABC):
    """Abstract base class for video sources."""

    @abstractmethod
    def read(self) -> Tuple[bool, Optional["numpy.ndarray"]]:
        """Read the next frame from the source."""

    @abstractmethod
    def release(self) -> None:
        """Release any underlying resources (e.g., camera handles)."""

    @abstractmethod
    def is_opened(self) -> bool:
        """Return True if the underlying source is currently open."""


class FileVideoSource(VideoSource):
    """Video source backed by a video file (e.g., MP4)."""

    def __init__(self, path: str) -> None:
        self._path = path
        self._capture = cv2.VideoCapture(path)

    def read(self) -> Tuple[bool, Optional["numpy.ndarray"]]:
        if not self._capture.isOpened():
            return False, None
        return self._capture.read()

    def release(self) -> None:
        if self._capture.isOpened():
            self._capture.release()

    def is_opened(self) -> bool:
        return self._capture.isOpened()


class CameraVideoSource(VideoSource):
    """Video source backed by a system webcam."""

    def __init__(self, camera_index: int = 0, width: int = 640, height: int = 480) -> None:
        self._capture = cv2.VideoCapture(camera_index)
        self._capture.set(cv2.CAP_PROP_FRAME_WIDTH, width)
        self._capture.set(cv2.CAP_PROP_FRAME_HEIGHT, height)

    def read(self) -> Tuple[bool, Optional["numpy.ndarray"]]:
        if not self._capture.isOpened():
            return False, None
        return self._capture.read()

    def release(self) -> None:
        if self._capture.isOpened():
            self._capture.release()

    def is_opened(self) -> bool:
        return self._capture.isOpened()

