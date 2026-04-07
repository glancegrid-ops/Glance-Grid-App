"""Batch video processor for embedded/mobile integrations.

This module is designed to be called from an Android bridge (e.g. Chaquopy)
or from a local Python CLI wrapper.
"""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from src.config_loader import deep_get, load_config
from src.input.video_source import FileVideoSource
from main import build_pipeline_from_config


def _normalize_video_list(input_dir: Optional[str], files: Optional[List[str]]) -> List[str]:
    candidates: List[str] = []
    if files:
        candidates.extend(files)

    if input_dir:
        p = Path(input_dir)
        if p.exists() and p.is_dir():
            for ext in ("*.mp4", "*.mov", "*.mkv", "*.avi", "*.m4v"):
                candidates.extend([str(x) for x in sorted(p.glob(ext))])

    deduped: List[str] = []
    seen = set()
    for f in candidates:
        if f not in seen:
            seen.add(f)
            deduped.append(f)
    return deduped


def batch_process_videos(request: Dict[str, Any]) -> Dict[str, Any]:
    """Process a batch of videos and write per-video CSV + summary JSON.

    Expected request keys:
    - input_dir: Optional[str]
    - files: Optional[List[str]]
    - output_dir: str
    - config_path: Optional[str]
    - cancel_flag_path: Optional[str]
    """
    input_dir = request.get("input_dir")
    files = request.get("files")
    output_dir = request.get("output_dir", "logs/batch")
    config_path = request.get("config_path", "configs/config.yaml")
    cancel_flag_path = request.get("cancel_flag_path")

    videos = _normalize_video_list(input_dir=input_dir, files=files)
    out_dir = Path(output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    config = load_config(config_path)

    # Reuse existing YAML controls, plus optional batch profile defaults.
    batch_skip = deep_get(config, "batch.mobile.skip_frames", deep_get(config, "pipeline.skip_frames", 1))
    batch_every_n = deep_get(
        config,
        "batch.mobile.deepface_every_n_frames",
        deep_get(config, "deepface.age_emotion.every_n_frames", 1),
    )
    batch_deepface_enabled = bool(
        deep_get(config, "batch.mobile.deepface_enabled", deep_get(config, "deepface.age_emotion.enabled", False))
    )

    started = time.time()
    results: List[Dict[str, Any]] = []
    cancelled = False

    def should_stop() -> bool:
        if not cancel_flag_path:
            return False
        return Path(cancel_flag_path).exists()

    for video_path in videos:
        if should_stop():
            cancelled = True
            break

        video_file = Path(video_path)
        per_video_csv = out_dir / f"{video_file.stem}.csv"

        entry: Dict[str, Any] = {
            "input_video": str(video_file),
            "csv_output": str(per_video_csv),
            "status": "success",
        }

        try:
            source = FileVideoSource(str(video_file))
            # Apply mobile batch profile via overrides while reusing main runtime factory.
            config_for_video = dict(config)
            config_for_video.setdefault("deepface", {})
            config_for_video["deepface"].setdefault("age_emotion", {})
            config_for_video["deepface"]["age_emotion"]["enabled"] = batch_deepface_enabled
            config_for_video["deepface"]["age_emotion"]["every_n_frames"] = int(batch_every_n)

            pipeline, _show = build_pipeline_from_config(
                config=config_for_video,
                source=source,
                log_path_override=str(per_video_csv),
                skip_frames_override=max(1, int(batch_skip)),
                no_display_override=True,
            )
            run_stats = pipeline.run(show=False)
            entry.update(run_stats)
        except Exception as exc:
            entry["status"] = "failed"
            entry["error"] = str(exc)

        results.append(entry)

    summary = {
        "started_at_epoch_s": started,
        "ended_at_epoch_s": time.time(),
        "cancelled": cancelled,
        "total_inputs": len(videos),
        "processed_jobs": len(results),
        "successful_jobs": sum(1 for r in results if r.get("status") == "success"),
        "failed_jobs": sum(1 for r in results if r.get("status") == "failed"),
        "results": results,
    }

    summary_path = out_dir / "batch_summary.json"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    summary["summary_path"] = str(summary_path)
    return summary

