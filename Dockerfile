# OnSIDES full pipeline image (CUDA + Java/poppler/pandoc + Python 3.12)
# Run everything via Docker: pipeline (snakemake) + DB + annotator.
# Base CUDA 12.8 + Ubuntu 24.04 (noble has python3.12; jammy lacks it).
FROM nvidia/cuda:12.8.0-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64 \
    TABULA_JAVA_PATH=/usr/lib/jvm/java-11-openjdk-amd64/bin/java

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 python3.12-venv python3-pip \
    openjdk-11-jre-headless \
    poppler-utils pandoc curl unzip git sqlite3 build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

# Torch CUDA first (RTX 5090 needs cu128+), then project deps.
# Keep in one layer order to maximise cache reuse.
RUN python3.12 -m pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cu128

COPY pyproject.toml README.md ./
COPY src/ src/
RUN python3.12 -m pip install --no-cache-dir -e ".[annotator]" \
    && python3.12 -m pip install --no-cache-dir \
    beautifulsoup4 connectorx duckdb fastexcel httpx lxml openpyxl \
    pandas polars pyahocorasick pyarrow pydantic pypdf2 ratelimit rich \
    scikit-learn snakemake sqlalchemy sqlmodel tabula-py tqdm transformers \
    fastapi "uvicorn[standard]" pyyaml pytest

# duckdb CLI (same version as pip lib; export/evaluate shell rules need the binary)
RUN curl -L --retry 5 -o /tmp/duckdb_cli.zip \
    https://github.com/duckdb/duckdb/releases/download/v1.5.5/duckdb_cli-linux-amd64.zip \
    && unzip -o -j /tmp/duckdb_cli.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/duckdb && rm /tmp/duckdb_cli.zip \
    && duckdb --version

# Snakemake workflows + schemas + scripts (data/models mounted at runtime, not baked)
COPY snakemake/ snakemake/
COPY database/schema/ database/schema/
COPY scripts/ scripts/

CMD ["bash"]
