#!/bin/bash
# Smoke test for OnSIDES Mac staging (CPU-only, no bulk downloads, no GPU).
# Usage: ./scripts/smoke_test.sh   (conda env 'onsides-dev' must exist)
set -u
PASS=0; FAIL=0
ok()   { echo "PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

export JAVA_HOME="${CONDA_PREFIX:-/Users/datbui/anaconda3/envs/onsides-dev}/lib/jvm"
export PATH="$JAVA_HOME/bin:$PATH"

# 1. unit tests
if conda run -n onsides-dev pytest src/onsides/ -q >/tmp/smoke_pytest.log 2>&1; then
  ok "pytest ($(grep -oE '[0-9]+ passed' /tmp/smoke_pytest.log | tail -1))"
else
  bad "pytest (see /tmp/smoke_pytest.log)"
fi

# 2. snakemake DAG dry-runs (evaluate/export expect MissingInput without data/)
for s in us/download us/parse uk/download uk/parse eu/download eu/parse \
         jp/download jp/parse onsides/evaluate onsides/export; do
  if conda run -n onsides-dev snakemake -s "snakemake/$s/Snakefile" -n \
      >/tmp/smoke_snake.log 2>&1; then
    ok "dry-run $s"
  elif echo "$s" | grep -q "^onsides/" && grep -q "MissingInputException" /tmp/smoke_snake.log; then
    ok "dry-run $s (expected MissingInput without data/)"
  else
    bad "dry-run $s (see /tmp/smoke_snake.log)"
  fi
done

# 3. OMOP TSVs readable with the pipeline's exact reader (skip if absent)
if [ -f data/omop_vocab/CONCEPT.csv ]; then
  if conda run -n onsides-dev python -c "
import duckdb
con = duckdb.connect()
n = con.execute(\"SELECT count(*) FROM read_csv('data/omop_vocab/CONCEPT.csv', sep='\t', quote='')\").fetchone()[0]
assert n > 1000000, n
print('CONCEPT rows:', n)
" >/tmp/smoke_omop.log 2>&1; then
    ok "OMOP CONCEPT.csv ($(grep -oE 'CONCEPT rows: [0-9]+' /tmp/smoke_omop.log | tail -1))"
  else
    bad "OMOP CONCEPT.csv (see /tmp/smoke_omop.log)"
  fi
else
  echo "SKIP: OMOP CONCEPT.csv absent"
fi

# 4. CLI entrypoint
if conda run -n onsides-dev build-zip --help >/dev/null 2>&1; then
  ok "build-zip --help"
else
  bad "build-zip --help"
fi

# 5. system tools
for t in "java -version" "pandoc --version" "pdftotext -v"; do
  if conda run -n onsides-dev $t >/dev/null 2>&1; then ok "$t"; else bad "$t"; fi
done

echo "---- smoke: $PASS passed, $FAIL failed ----"
[ "$FAIL" -eq 0 ]
