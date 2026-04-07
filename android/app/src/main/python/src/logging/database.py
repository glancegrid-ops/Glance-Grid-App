"""Database persistence for face detection results (SQLite)."""

from __future__ import annotations

import sqlite3
from datetime import datetime
from typing import Any, Dict, List, Optional


class FaceDatabase:
    """SQLite database for storing face detection results."""

    def __init__(self, db_path: str = "facecount.db") -> None:
        self.db_path = db_path
        self._connection: Optional[sqlite3.Connection] = None
        self._create_tables()

    def _get_connection(self) -> sqlite3.Connection:
        if self._connection is None:
            self._connection = sqlite3.connect(self.db_path)
            self._connection.row_factory = sqlite3.Row
        return self._connection

    def _create_tables(self) -> None:
        conn = self._get_connection()
        cursor = conn.cursor()

        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS face_results (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                frame_number INTEGER NOT NULL,
                frame_time_s REAL NOT NULL,
                face_count INTEGER NOT NULL,
                gaze_results TEXT NOT NULL,
                processing_time_ms REAL,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        """
        )

        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_name TEXT,
                start_time TEXT NOT NULL,
                end_time TEXT,
                total_frames INTEGER DEFAULT 0,
                total_faces INTEGER DEFAULT 0,
                avg_fps REAL,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        """
        )

        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS face_detections (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                result_id INTEGER NOT NULL,
                face_index INTEGER NOT NULL,
                box_x INTEGER,
                box_y INTEGER,
                box_width INTEGER,
                box_height INTEGER,
                confidence REAL,
                is_looking INTEGER,
                FOREIGN KEY (result_id) REFERENCES face_results (id)
            )
        """
        )

        conn.commit()

    def start_session(self, session_name: Optional[str] = None) -> int:
        conn = self._get_connection()
        cursor = conn.cursor()

        start_time = datetime.utcnow().isoformat()
        cursor.execute(
            "INSERT INTO sessions (session_name, start_time) VALUES (?, ?)",
            (session_name, start_time),
        )
        session_id = cursor.lastrowid
        conn.commit()
        return int(session_id)

    def end_session(
        self, session_id: int, total_frames: int, total_faces: int, avg_fps: float
    ) -> None:
        conn = self._get_connection()
        cursor = conn.cursor()

        end_time = datetime.utcnow().isoformat()
        cursor.execute(
            """
            UPDATE sessions
            SET end_time = ?, total_frames = ?, total_faces = ?, avg_fps = ?
            WHERE id = ?
        """,
            (end_time, total_frames, total_faces, avg_fps, session_id),
        )
        conn.commit()

    def save_frame_result(
        self,
        frame_number: int,
        frame_time_s: float,
        face_count: int,
        gaze_results: List[bool],
        detections: List[Dict[str, Any]],
        processing_time_ms: Optional[float] = None,
        session_id: Optional[int] = None,
    ) -> int:
        """Save a single frame's results."""
        conn = self._get_connection()
        cursor = conn.cursor()

        timestamp = datetime.utcnow().isoformat()
        gaze_str = ",".join(["1" if g else "0" for g in gaze_results])

        cursor.execute(
            """
            INSERT INTO face_results
            (timestamp, frame_number, frame_time_s, face_count, gaze_results, processing_time_ms)
            VALUES (?, ?, ?, ?, ?, ?)
        """,
            (
                timestamp,
                frame_number,
                frame_time_s,
                face_count,
                gaze_str,
                processing_time_ms,
            ),
        )

        result_id = int(cursor.lastrowid)

        for idx, det in enumerate(detections):
            box = det.get("box")
            if box and len(box) == 4 and idx < len(gaze_results):
                x, y, w, h = box
                cursor.execute(
                    """
                    INSERT INTO face_detections
                    (result_id, face_index, box_x, box_y, box_width, box_height, confidence, is_looking)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                    (
                        result_id,
                        idx,
                        int(x),
                        int(y),
                        int(w),
                        int(h),
                        det.get("confidence", 0.0),
                        1 if gaze_results[idx] else 0,
                    ),
                )

        conn.commit()
        return result_id

    def get_recent_results(self, limit: int = 100) -> List[Dict[str, Any]]:
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT * FROM face_results
            ORDER BY timestamp DESC
            LIMIT ?
        """,
            (limit,),
        )
        return [dict(row) for row in cursor.fetchall()]

    def get_session_stats(self, session_id: Optional[int] = None) -> Dict[str, Any]:
        conn = self._get_connection()
        cursor = conn.cursor()

        if session_id:
            cursor.execute("SELECT * FROM sessions WHERE id = ?", (session_id,))
            session = cursor.fetchone()
            return dict(session) if session else {}

        cursor.execute(
            """
            SELECT
                COUNT(*) as total_sessions,
                SUM(total_frames) as total_frames,
                SUM(total_faces) as total_faces,
                AVG(avg_fps) as avg_fps,
                MIN(start_time) as first_session,
                MAX(end_time) as last_session
            FROM sessions
            WHERE end_time IS NOT NULL
        """
        )
        row = cursor.fetchone()
        return dict(row) if row else {}

    def get_face_count_over_time(self, hours: int = 24) -> List[Dict[str, Any]]:
        conn = self._get_connection()
        cursor = conn.cursor()

        cursor.execute(
            """
            SELECT
                strftime('%Y-%m-%d %H:00:00', timestamp) as hour,
                SUM(face_count) as total_faces,
                COUNT(*) as frames_processed,
                AVG(face_count) as avg_faces_per_frame
            FROM face_results
            WHERE timestamp >= datetime('now', '-{} hours')
            GROUP BY strftime('%Y-%m-%d %H', timestamp)
            ORDER BY hour
        """.format(hours)
        )
        return [dict(row) for row in cursor.fetchall()]

    def close(self) -> None:
        if self._connection:
            self._connection.close()
            self._connection = None

