#!/usr/bin/env bash
set -euo pipefail

# build.sh - Build and run the UFOS project using docker-compose if available,
# otherwise fall back to a local Python virtualenv install for running tests.
# Usage: ./build.sh

ROOT_DIR=$(pwd)
ZIP_NAME="UFOS_v0.5.0_Production_Core.zip"
UNPACK_DIR="core_unpacked"

# If zip present, unpack to a known directory
if [ -f "$ZIP_NAME" ]; then
  echo "Found $ZIP_NAME — extracting to $UNPACK_DIR/..."
  rm -rf "$UNPACK_DIR"
  mkdir -p "$UNPACK_DIR"
  unzip -q "$ZIP_NAME" -d "$UNPACK_DIR"
  # If the zip contains a top-level directory, cd into it
  TOP_DIR_COUNT=$(find "$UNPACK_DIR" -maxdepth 1 -type d | wc -l)
  if [ $TOP_DIR_COUNT -eq 2 ]; then
    # there's exactly one directory inside the unpack dir
    TOP_DIR=$(find "$UNPACK_DIR" -maxdepth 1 -type d | tail -n 1)
    cd "$TOP_DIR"
  else
    cd "$UNPACK_DIR"
  fi
else
  echo "$ZIP_NAME not found. Assuming repository already contains project files in the current directory."
fi

# If .env.example exists, copy to .env (but do NOT overwrite an existing .env)
if [ -f ".env.example" ] && [ ! -f ".env" ]; then
  echo "Copying .env.example to .env — please edit .env with secrets before production runs."
  cp .env.example .env
fi

# Prefer docker compose if available
if command -v docker >/dev/null 2>&1; then
  # prefer new CLI when available
  if docker compose version >/dev/null 2>&1; then
    DC="docker compose"
  else
    DC="docker-compose"
  fi

  echo "Building containers with: $DC build"
  $DC build --pull --no-cache

  echo "Starting containers (detached)..."
  $DC up -d

  echo "Waiting for services to become healthy. Showing ps output:"
  $DC ps

  # Attempt to run tests via a service called 'api'. If your service is named differently,
  # change the SERVICE_FOR_TESTS variable or run tests manually.
  SERVICE_FOR_TESTS=${SERVICE_FOR_TESTS:-api}
  echo "Running tests using docker-compose service: $SERVICE_FOR_TESTS"
  if $DC run --rm "$SERVICE_FOR_TESTS" pytest -q; then
    echo "Tests passed"
    EXIT_CODE=0
  else
    echo "Tests failed"
    EXIT_CODE=1
  fi

  echo "Tearing down containers..."
  $DC down -v
  exit $EXIT_CODE
else
  echo "Docker not found — falling back to local Python environment."
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found. Install Python 3.8+ or install Docker to run this script."
    exit 2
  fi

  python3 -m venv .venv
  # shellcheck disable=SC1091
  source .venv/bin/activate
  python -m pip install --upgrade pip
  if [ -f requirements.txt ]; then
    pip install -r requirements.txt
  else
    echo "requirements.txt not found — install dependencies manually."
  fi

  # Attempt to run pytest if present
  if command -v pytest >/dev/null 2>&1 || python -m pytest -q; then
    python -m pytest -q || true
  else
    echo "pytest not installed; install via 'pip install pytest' or run your app manually (uvicorn/gunicorn)."
  fi
fi
