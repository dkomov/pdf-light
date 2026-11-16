"""Download a project-local CPython runtime with uv and install pinned dependencies."""

import argparse
import os
import shutil
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--uv", default="uv", help="Path to the uv executable")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    uv = shutil.which(args.uv)
    if not uv:
        parser.error("Install uv first: https://docs.astral.sh/uv/getting-started/installation/")
    env = dict(os.environ)
    env["UV_PYTHON_INSTALL_DIR"] = str(root / ".runtime" / "python")
    env["UV_PYTHON_BIN_DIR"] = str(root / ".runtime" / "bin")
    env["UV_CACHE_DIR"] = str(root / ".runtime" / "cache")
    version = (root / ".python-version").read_text().strip()
    subprocess.run([uv, "python", "install", version], env=env, check=True)
    executable = Path(
        subprocess.check_output(
            [uv, "python", "find", "--managed-python", version], env=env, text=True
        ).strip()
    ).resolve()
    prefix = Path(
        subprocess.check_output(
            [str(executable), "-I", "-B", "-c", "import sys; print(sys.prefix)"], text=True
        ).strip()
    )
    # The destination is the downloaded project-local runtime, not the system Python.
    target = prefix / "lib" / "python3.12" / "site-packages"
    subprocess.run(
        [
            uv,
            "pip",
            "install",
            "--python",
            str(executable),
            "--target",
            str(target),
            "-r",
            str(root / "requirements.txt"),
        ],
        env=env,
        check=True,
    )
    (root / ".runtime" / "prefix.txt").write_text(str(prefix) + "\n")
    print(f"Runtime ready: {prefix}")


if __name__ == "__main__":
    main()
