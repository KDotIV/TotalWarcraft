"""Run every offline suite on Windows or CI, failing at the first failed suite."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
for suite in sorted((root / 'tests').glob('test_*.py')):
    subprocess.run([sys.executable, str(suite)], cwd=root, check=True)
