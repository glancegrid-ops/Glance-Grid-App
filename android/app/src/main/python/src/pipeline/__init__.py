"""Pipeline orchestration package.

Exports :class:`~src.pipeline.pipeline.Pipeline` for backward-compatible imports:
`from src.pipeline import Pipeline`.
"""

from .pipeline import FrameProcessor, Pipeline

__all__ = ["Pipeline", "FrameProcessor"]

