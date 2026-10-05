"""Scoped wakefulness and suspension detection for serial benchmarks."""
from __future__ import annotations

import ctypes
import hashlib
import os
import threading
import time
from pathlib import Path


def file_set_identity(root: Path, filenames: tuple[str, ...]) -> str:
    """Fingerprint the actual measurement harness as well as product sources."""
    digest = hashlib.sha256()
    for name in sorted(filenames):
        digest.update(name.encode('utf-8') + b'\0')
        digest.update((root / name).read_bytes())
        digest.update(b'\0')
    return digest.hexdigest()


def native_identity(path: Path, revision: str) -> dict:
    if not revision or len(revision) != 40 or any(c not in '0123456789abcdef' for c in revision):
        raise ValueError('A full native source revision is required')
    return {'revision': revision, 'path': str(path.resolve()),
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def validate_dependency_change(base: dict, candidate: dict, *, allow_odbc: bool) -> None:
    differences = {key for key in base.keys() | candidate.keys() if base.get(key) != candidate.get(key)}
    if differences and (not allow_odbc or differences != {'odbc_fast'}):
        raise ValueError('Unexpected dependency differences: ' + ', '.join(sorted(differences)))


class MeasurementGuard:
    """A heartbeat gap invalidates a run; the OS power policy is never edited."""
    def __init__(self, max_gap_seconds: float = 60):
        self.max_gap_seconds = max_gap_seconds
        self.largest_gap_seconds = 0.0
        self._stop = threading.Event()
        self._thread = None
        self._previous_state = 0

    def __enter__(self):
        if os.name == 'nt':
            self._previous_state = ctypes.windll.kernel32.SetThreadExecutionState(0x80000003)
            if not self._previous_state:
                raise OSError('Cannot request temporary benchmark wakefulness')
        self._thread = threading.Thread(target=self._watch, daemon=True)
        self._thread.start()
        return self

    def _watch(self):
        previous = time.monotonic()
        while not self._stop.wait(1):
            now = time.monotonic()
            self.largest_gap_seconds = max(self.largest_gap_seconds, now - previous)
            previous = now

    @property
    def interrupted(self):
        return self.largest_gap_seconds > self.max_gap_seconds

    def __exit__(self, *args):
        self._stop.set()
        if self._thread is not None:
            self._thread.join()
        if self._previous_state:
            if not ctypes.windll.kernel32.SetThreadExecutionState(self._previous_state):
                raise OSError('Cannot restore benchmark execution state')
