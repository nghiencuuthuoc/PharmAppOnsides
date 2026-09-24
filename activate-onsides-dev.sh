#!/bin/bash
# Dev activate helper for OnSIDES on Intel Mac (osx-64).
# Usage: source ./activate-onsides-dev.sh
conda activate onsides-dev || { echo "env onsides-dev not found"; return 1; }
export JAVA_HOME="$CONDA_PREFIX/lib/jvm"
export PATH="$JAVA_HOME/bin:$PATH"
export TABULA_JAVA_PATH="$JAVA_HOME/bin/java"
echo "onsides-dev active | python $(python --version 2>&1)"
echo "java: $(java -version 2>&1 | head -1)"
echo "pandoc: $(pandoc --version 2>&1 | head -1)"
echo "pdftotext: $(pdftotext -v 2>&1 | head -1)"
python -c "import onsides; print('onsides import OK')"
