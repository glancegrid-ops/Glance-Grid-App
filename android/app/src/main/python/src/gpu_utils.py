"""GPU/CPU configuration helpers.

On Apple Silicon, TensorFlow can accelerate via Metal when `tensorflow-metal`
is installed. This helper lets you force a CPU-only mode by hiding TensorFlow
GPU devices before mtcnn/deepface initialize.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import List, Optional


@dataclass(frozen=True)
class GPUConfig:
    """TensorFlow GPU configuration.

    Attributes
    ----------
    use_gpu:
        When false, hide all TensorFlow GPU devices (hard CPU-only).
    gpu_device:
        Index of the GPU device to make visible when `use_gpu` is true.
    """

    use_gpu: bool = True
    gpu_device: int = 0

    @property
    def is_available(self) -> bool:
        """Backward-compatible alias used by `main.py`."""
        return self.use_gpu

    def _list_gpus(self) -> List[object]:
        import tensorflow as tf  # type: ignore

        return list(tf.config.list_physical_devices("GPU"))

    def apply_tf_device_policy(self) -> None:
        """Apply a best-effort TensorFlow GPU/CPU policy.

        This should be called before TensorFlow-backed components initialize.
        """
        try:
            import tensorflow as tf  # type: ignore
        except Exception:
            return

        try:
            gpus = list(tf.config.list_physical_devices("GPU"))
        except Exception:
            return

        if not gpus:
            return

        if not self.use_gpu:
            # Hard CPU-only mode: hide all TF GPU devices.
            try:
                tf.config.set_visible_devices([], "GPU")
            except Exception:
                # If TF already initialized, masking may fail; keep best-effort.
                pass
            return

        # GPU enabled: optionally restrict to one device.
        if 0 <= self.gpu_device < len(gpus):
            visible = [gpus[self.gpu_device]]
        else:
            visible = gpus

        try:
            tf.config.set_visible_devices(visible, "GPU")
        except Exception:
            pass

        # Memory growth avoids grabbing all VRAM-like memory up front.
        try:
            for gpu in tf.config.list_physical_devices("GPU"):
                try:
                    tf.config.experimental.set_memory_growth(gpu, True)
                except Exception:
                    pass
        except Exception:
            pass

    def print_gpu_info(self) -> None:
        """Print TensorFlow's GPU view (for debugging)."""
        try:
            import tensorflow as tf  # type: ignore
        except Exception as exc:
            print("TensorFlow not available:", exc)
            return

        try:
            physical = tf.config.list_physical_devices("GPU")
            visible = tf.config.get_visible_devices()
            print("TensorFlow version:", tf.__version__)
            print("Physical GPUs:", physical)
            print("Visible devices:", visible)
        except Exception as exc:
            print("Failed to query GPU info:", exc)

