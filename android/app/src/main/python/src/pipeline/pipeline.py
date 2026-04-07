"""Pipeline orchestration for face + gaze detection.

This module wires together video sources, detection, gaze estimation, counting,
visualization, and logging into a single processing loop.
"""

from __future__ import annotations

import time
import json
from typing import Any, Callable, Dict, List, Optional, TYPE_CHECKING

import cv2

from ..counting.face_counter import FaceCounter
from ..detection.face_detector import FaceDetector
from ..gaze.gaze_estimator import GazeEstimator
from ..input.video_source import VideoSource
from ..logging.database import FaceDatabase
from ..logging.pipeline_logger import PipelineLogger
from ..visualization.visualizer import Visualizer

if TYPE_CHECKING:
    from ..analysis.face_analyzer import FaceAnalyzer


class Pipeline:
    """Main pipeline that processes video frames."""

    def __init__(
        self,
        source: VideoSource,
        detector: Optional[FaceDetector] = None,
        gaze_estimator: Optional[GazeEstimator] = None,
        counter: Optional[FaceCounter] = None,
        visualizer: Optional[Visualizer] = None,
        logger: Optional[PipelineLogger] = None,
        analyzer: Optional[Any] = None,
        database: Optional[FaceDatabase] = None,
        session_name: Optional[str] = None,
        skip_frames: int = 1,
        use_threading: bool = False,
        deepface_every_n_frames: int = 1,
        deepface_actions: Optional[List[str]] = None,
    ) -> None:
        if use_threading:
            # The previous threaded implementation referenced missing worker code.
            raise NotImplementedError("Threaded processing is not implemented.")

        self.source = source
        self.detector = detector or FaceDetector()
        self.gaze_estimator = gaze_estimator or GazeEstimator()
        self.counter = counter or FaceCounter()
        self.visualizer = visualizer or Visualizer()
        self.logger = logger or PipelineLogger()
        self.analyzer = analyzer

        self.database = database
        self.session_name = session_name

        self.skip_frames = max(1, int(skip_frames))
        self._frame_number = 0
        self.deepface_every_n_frames = max(1, int(deepface_every_n_frames))
        self.deepface_actions = deepface_actions or ["age", "emotion"]

        # Expose a lightweight processor for single-frame usage.
        self.processor = FrameProcessor(
            detector=self.detector,
            gaze_estimator=self.gaze_estimator,
            counter=self.counter,
        )

    def process_frame(self, frame: Any) -> Dict[str, Any]:
        """Process a single BGR frame and return structured results."""
        self._frame_number += 1

        detections = self.detector.detect_faces(frame)
        gaze_results: List[bool] = []
        for det in detections:
            keypoints = det.get("keypoints", {})
            gaze_results.append(self.gaze_estimator.is_looking_at_camera(keypoints))

        face_count = len(detections)
        self.counter.update(face_count)

        age_results_text: List[str] = ["" for _ in detections]
        emotion_dominant_results: List[str] = ["" for _ in detections]
        emotion_dominant_prob_results: List[str] = ["" for _ in detections]
        emotion_probs_results_json: List[str] = ["" for _ in detections]

        # DeepFace: per-face age + emotion (heavy), throttled by `deepface_every_n_frames`.
        if self.analyzer is not None and (self._frame_number % self.deepface_every_n_frames == 0):
            for idx, det in enumerate(detections):
                box = det.get("box")
                if not box or len(box) != 4:
                    continue
                x, y, w, h = box
                x1 = max(0, int(x))
                y1 = max(0, int(y))
                x2 = min(int(frame.shape[1]), x1 + int(w))
                y2 = min(int(frame.shape[0]), y1 + int(h))
                if x2 <= x1 or y2 <= y1:
                    continue

                face_crop = frame[y1:y2, x1:x2]
                face_crop_rgb = cv2.cvtColor(face_crop, cv2.COLOR_BGR2RGB)

                try:
                    analysis = self.analyzer.analyze_attributes(
                        face_crop_rgb,
                        actions=self.deepface_actions,
                    )

                    if isinstance(analysis, list):
                        analysis0 = analysis[0] if analysis else {}
                    else:
                        analysis0 = analysis

                    # Age
                    age_val = analysis0.get("age")
                    if age_val is not None:
                        try:
                            age_results_text[idx] = f"{float(age_val):.0f}"
                        except (TypeError, ValueError):
                            age_results_text[idx] = str(age_val)

                    # Emotion
                    emotion_dict = analysis0.get("emotion") or {}
                    dominant = analysis0.get("dominant_emotion")

                    if not dominant and isinstance(emotion_dict, dict) and emotion_dict:
                        # Fallback: pick max-prob label
                        dominant = max(emotion_dict.keys(), key=lambda k: emotion_dict.get(k, 0.0))

                    if dominant:
                        emotion_dominant_results[idx] = str(dominant)
                        if isinstance(emotion_dict, dict) and dominant in emotion_dict:
                            try:
                                prob = float(emotion_dict.get(dominant, 0.0))
                                emotion_dominant_prob_results[idx] = f"{prob:.1f}%"
                            except (TypeError, ValueError):
                                pass

                    if isinstance(emotion_dict, dict) and emotion_dict:
                        emotion_probs_results_json[idx] = json.dumps(emotion_dict)
                except Exception:
                    # Best-effort only; don't crash the whole pipeline if a face fails.
                    continue

        return {
            "frame_number": self._frame_number,
            "face_count": face_count,
            "gaze_results": gaze_results,
            "detections": detections,
            "age_results_text": age_results_text,
            "emotion_dominant_results": emotion_dominant_results,
            "emotion_dominant_prob_results": emotion_dominant_prob_results,
            "emotion_probs_results_json": emotion_probs_results_json,
        }

    def run(
        self,
        show: bool = True,
        window_name: str = "FaceCount2",
        progress_callback: Optional[Callable[[Dict[str, Any]], None]] = None,
        should_stop: Optional[Callable[[], bool]] = None,
    ) -> Dict[str, Any]:
        """Run the pipeline in a loop until the source ends or user quits."""
        start_time = time.perf_counter()
        prev_time = start_time

        session_id: Optional[int] = None
        processed_frames = 0
        stopped_by_request = False
        if self.database:
            session_id = self.database.start_session(self.session_name)

        last_annotated: Any = None

        raw_frame_idx = 0
        try:
            while self.source.is_opened():
                if should_stop is not None and should_stop():
                    stopped_by_request = True
                    break

                success, frame = self.source.read()
                if not success or frame is None:
                    break

                raw_frame_idx += 1

                now = time.perf_counter()
                fps = 1.0 / (now - prev_time) if now > prev_time else 0.0
                prev_time = now

                # Skip processing to speed up inference.
                if raw_frame_idx % self.skip_frames != 0:
                    if show:
                        # Prefer the last annotated frame, but fall back to the
                        # current raw frame until the first processed result exists.
                        frame_to_show = last_annotated if last_annotated is not None else frame
                        cv2.imshow(window_name, frame_to_show)
                        key = cv2.waitKey(1) & 0xFF
                        if key in (27, ord("q")):
                            break
                    continue

                processed_frames += 1

                proc_start = time.perf_counter()
                result = self.process_frame(frame)
                proc_ms = (time.perf_counter() - proc_start) * 1000.0

                frame_time_s = now - start_time

                annotated = self.visualizer.draw_overlays(
                    frame,
                    detections=result["detections"],
                    gaze_results=result["gaze_results"],
                    face_count=result["face_count"],
                    fps=fps,
                    age_results_text=result.get("age_results_text"),
                    emotion_dominant_results=result.get("emotion_dominant_results"),
                    emotion_dominant_prob_results=result.get("emotion_dominant_prob_results"),
                )
                last_annotated = annotated

                # Logging (CSV + console)
                self.logger.log_frame(
                    frame_number=result["frame_number"],
                    frame_time_s=frame_time_s,
                    face_count=result["face_count"],
                    gaze_results=result["gaze_results"],
                    age_results_text=result.get("age_results_text"),
                    emotion_dominant_results=result.get("emotion_dominant_results"),
                    emotion_dominant_prob_results=result.get("emotion_dominant_prob_results"),
                    emotion_probs_results_json=result.get("emotion_probs_results_json"),
                )

                if progress_callback is not None:
                    progress_callback(
                        {
                            "frame_number": result["frame_number"],
                            "face_count": result["face_count"],
                            "processed_frames": processed_frames,
                            "elapsed_s": frame_time_s,
                        }
                    )

                # SQLite (optional)
                if self.database and session_id is not None:
                    self.database.save_frame_result(
                        frame_number=result["frame_number"],
                        frame_time_s=frame_time_s,
                        face_count=result["face_count"],
                        gaze_results=result["gaze_results"],
                        detections=result["detections"],
                        processing_time_ms=proc_ms,
                        session_id=session_id,
                    )

                if show:
                    cv2.imshow(window_name, annotated)
                    key = cv2.waitKey(1) & 0xFF
                    if key in (27, ord("q")):
                        break
        finally:
            self.source.release()
            if show:
                cv2.destroyAllWindows()
            self.logger.close()

            if self.database and session_id is not None:
                elapsed_s = max(time.perf_counter() - start_time, 1e-9)
                total_faces = self.counter.total_faces
                avg_fps = processed_frames / elapsed_s if elapsed_s > 0 else 0.0
                self.database.end_session(
                    session_id=session_id,
                    total_frames=processed_frames,
                    total_faces=total_faces,
                    avg_fps=avg_fps,
                )
                self.database.close()

        elapsed_s = max(time.perf_counter() - start_time, 1e-9)
        return {
            "processed_frames": processed_frames,
            "total_faces": self.counter.total_faces,
            "avg_fps": processed_frames / elapsed_s if elapsed_s > 0 else 0.0,
            "elapsed_s": elapsed_s,
            "stopped_by_request": stopped_by_request,
        }


class FrameProcessor:
    """Lightweight processor used for single-frame inference."""

    def __init__(
        self,
        detector: FaceDetector,
        gaze_estimator: GazeEstimator,
        counter: Optional[FaceCounter] = None,
    ) -> None:
        self.detector = detector
        self.gaze_estimator = gaze_estimator
        self.counter = counter or FaceCounter()
        self._frame_number = 0

    def process(self, frame: Any) -> Dict[str, Any]:
        """Process a single frame and return detection and gaze results."""
        self._frame_number += 1

        detections = self.detector.detect_faces(frame)
        gaze_results: List[bool] = []
        for det in detections:
            keypoints = det.get("keypoints", {})
            gaze_results.append(self.gaze_estimator.is_looking_at_camera(keypoints))

        face_count = len(detections)
        self.counter.update(face_count)

        return {
            "frame_number": self._frame_number,
            "face_count": face_count,
            "gaze_results": gaze_results,
            "detections": detections,
        }

    def run(self, *args: Any, **kwargs: Any) -> None:
        """Not implemented for FrameProcessor.

        Use `Pipeline.run()` for video loop processing.
        """
        raise NotImplementedError("FrameProcessor.run() is not implemented.")

