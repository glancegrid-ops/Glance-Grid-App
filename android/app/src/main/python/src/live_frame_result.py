"""JSON-serializable face detection + optional DeepFace age/emotion for HTTP clients."""

from __future__ import annotations

from typing import Any, Dict, List, Optional

import cv2


def _normalize_box(box: Any) -> Optional[List[float]]:
    if box is None or len(box) != 4:
        return None
    try:
        return [float(box[0]), float(box[1]), float(box[2]), float(box[3])]
    except (TypeError, ValueError):
        return None


def _emotion_scores_dict(emotion_dict: Any) -> Optional[Dict[str, float]]:
    if not isinstance(emotion_dict, dict) or not emotion_dict:
        return None
    out: Dict[str, float] = {}
    for k, v in emotion_dict.items():
        try:
            out[str(k)] = float(v)
        except (TypeError, ValueError):
            continue
    return out or None


def analyze_bgr_frame_for_json(
    frame: Any,
    detector: Any,
    gaze_estimator: Any,
    *,
    analyzer: Any = None,
    deepface_actions: Optional[List[str]] = None,
) -> Dict[str, Any]:
    """Run MTCNN (+ optional DeepFace) on one BGR frame; return a plain JSON-friendly dict."""
    actions = deepface_actions if deepface_actions else ["age", "emotion"]
    detections = detector.detect_faces(frame)
    faces: List[Dict[str, Any]] = []

    for idx, det in enumerate(detections):
        keypoints = det.get("keypoints", {})
        looking = bool(gaze_estimator.is_looking_at_camera(keypoints))
        box = _normalize_box(det.get("box"))
        conf = det.get("confidence")
        try:
            conf_f = float(conf) if conf is not None else None
        except (TypeError, ValueError):
            conf_f = None

        face_entry: Dict[str, Any] = {
            "index": idx,
            "box": box,
            "confidence": conf_f,
            "looking_at_camera": looking,
            "age": None,
            "dominant_emotion": None,
            "emotion_confidence_percent": None,
            "emotion_scores": None,
        }

        if analyzer is not None:
            box_raw = det.get("box")
            if box_raw and len(box_raw) == 4:
                x, y, w, h = box_raw
                x1 = max(0, int(x))
                y1 = max(0, int(y))
                x2 = min(int(frame.shape[1]), x1 + int(w))
                y2 = min(int(frame.shape[0]), y1 + int(h))
                if x2 > x1 and y2 > y1:
                    face_crop = frame[y1:y2, x1:x2]
                    face_crop_rgb = cv2.cvtColor(face_crop, cv2.COLOR_BGR2RGB)
                    try:
                        analysis = analyzer.analyze_attributes(face_crop_rgb, actions=actions)
                        if isinstance(analysis, list):
                            analysis0 = analysis[0] if analysis else {}
                        else:
                            analysis0 = analysis

                        age_val = analysis0.get("age")
                        if age_val is not None:
                            try:
                                face_entry["age"] = int(round(float(age_val)))
                            except (TypeError, ValueError):
                                face_entry["age"] = age_val

                        emotion_dict = analysis0.get("emotion") or {}
                        dominant = analysis0.get("dominant_emotion")
                        if not dominant and isinstance(emotion_dict, dict) and emotion_dict:
                            dominant = max(
                                emotion_dict.keys(),
                                key=lambda k: float(emotion_dict.get(k, 0.0)),
                            )

                        if dominant:
                            face_entry["dominant_emotion"] = str(dominant)
                            if isinstance(emotion_dict, dict) and dominant in emotion_dict:
                                try:
                                    prob = float(emotion_dict.get(dominant, 0.0))
                                    face_entry["emotion_confidence_percent"] = round(prob, 2)
                                except (TypeError, ValueError):
                                    pass

                        scores = _emotion_scores_dict(emotion_dict)
                        if scores is not None:
                            face_entry["emotion_scores"] = scores
                    except Exception:
                        pass

        faces.append(face_entry)

    return {"face_count": len(faces), "faces": faces}
