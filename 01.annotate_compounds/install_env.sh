#!/bin/bash
set -euo pipefail

ENV_NAME="mod-01-env"

mkdir -p .cache/uv tmp

export UV_CACHE_DIR="$PWD/.cache/uv"
export TMPDIR="$PWD/tmp"

uv venv "$ENV_NAME" --python 3.11
source "$ENV_NAME/bin/activate"

uv pip install -r requirements.txt
uv pip install ipykernel

echo "To activate later: source $ENV_NAME/bin/activate"
echo "To install a package: uv pip install pkg-name"
echo "To update requirements.txt: uv pip freeze > requirements.txt"
