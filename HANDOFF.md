# HANDOFF — OnSIDES GPU run (from Mac Intel staging → Windows 10 RTX machine)

Date: 2026-09-25. Branch: `dev/intel-mac` on `PharmAppOnsides`.
Mac staging stops bulk downloads here; it runs **smoke tests only**
(`scripts/smoke_test.sh`). Full pipeline runs on the GPU machine.

## 0. Physical copy on external drive (2026-09-25, verified)

- Location: **`/Volumes/SSD4T-QC/PharmAppOnsides/`** (exFAT 4TB, 367GB free).
- Content: full repo checkout (incl. `.git` @ `dev/intel-mac`) + `_onsides/`
  + `data/` + `models/` + `data/umls_chunks/` (UMLS chunks 0-1, 256MB).
- Verified byte-identical (logical bytes + file counts):
  `us/download` 17,924,348,331 B · `uk/labels` 10,250 files ·
  `eu/labels` 5,394 files · `jp` 20,778 files ·
  `omop_vocab` 2,566,369,545 B · `models/onsides-bert` 438,873,435 B.
- NOTE exFAT: `du` over-reports (~1MB clusters) — trust file counts/bytes,
  not `du`. Plug into Windows machine and copy to NTFS/ext4, or run
  directly from the drive (slower).

## 1. What to copy to the GPU machine (gitignored, NOT in git)

| Path | Size | Status 2026-09-25 | Note |
|---|---|---|---|
| `_onsides/us/download/*.zip` (6 parts) | ~17 GB | COMPLETE | DailyMed human Rx parts 1-6 |
| `_onsides/us/map_download/*.txt` | ~83 MB | COMPLETE | `rxnorm_mappings.txt`, `dm_spl_zip_files_meta_data.txt` (export-ready) |
| `_onsides/us/*.html`, `*.done` | KBs | COMPLETE | Index pages + parse markers |
| `_onsides/uk/labels/` | ~10,244 HTML | COMPLETE* | *Killed at end; rerun download Snakefile with `--rerun-incomplete` to refill partial files |
| `_onsides/uk/browse_page.html`, `prefix_page/` | KBs | COMPLETE | Index |
| `_onsides/eu/labels/` | 780 HTML + 152 PDF | PARTIAL (34%) | Rerun `eu/download` Snakefile with `--keep-going` until done |
| `_onsides/eu/manifest.xlsx` | 0.9 MB | COMPLETE | 2,302 human medicines enumerated |
| `_onsides/jp/*index_page/` | 521 HTML | ~COMPLETE (521/524) | Rerun `jp/download` Snakefile to finish + fetch labels |
| `data/omop_vocab/CONCEPT.csv` | 677 MB | COMPLETE | Mirror v4 → TSV, verified via pipeline SQL (2.45M RxNorm rows, 2.59M Maps-to) |
| `data/omop_vocab/CONCEPT_RELATIONSHIP.csv` | 1.9 GB | COMPLETE | 37.6M rows, verified |
| `data/OMOP_PROVENANCE.md` | — | — | Read this: gaps (no MedDRA→MRCONSO fallback covers; no NDC→JP empty) |
| `/tmp/umls_p0.bin` (128,310,359 B) | 128 MB | COMPLETE | Chunk 0/4 of `umls-2026AA-mrconso.zip` (see §3) |
| `/tmp/umls_p1.bin` (~4 MB) | PARTIAL | Chunk 1/4, unverified — redownload recommended |
| `models/onsides-bert/` | 419 MB | COMPLETE | HF safetensors (see §4 re `.pth`) |

Total to transfer: ~21 GB (`_onsides` 17 GB + `data` 2.5 GB + `models` 0.4 GB + UMLS chunks).

## 2. Resume downloads on the GPU machine (60 GB+ free, in WSL2 Ubuntu)

```bash
# Labels (rerun until "nothing to be done"; EU/JP need --keep-going)
snakemake -s snakemake/us/download/Snakefile --resources jobs=1 --rerun-incomplete
snakemake -s snakemake/uk/download/Snakefile --resources jobs=1 --rerun-incomplete
snakemake -s snakemake/eu/download/Snakefile --resources jobs=1 --keep-going --rerun-incomplete
snakemake -s snakemake/jp/download/Snakefile --resources jobs=1 --keep-going --rerun-incomplete
# Parse, then checkpoints from WINDOWS_SETUP.md §6
```

## 3. UMLS MRCONSO — RESOLVED via machine-to-machine copy (2026-09-25)

- Source: `/Volumes/SSD4T-QC/PharmAppOnsides_v2026.01/Onsides_nodaily_20260925_0914.zip`
  (Windows machine snapshot, 1.8GB/9,839 files — listed with `unzip -l` only).
- Taken (single-file `unzip -p` streams, archive itself untouched):
  - `data/MRCONSO.RRF` = **2,340,511,941 B, 18,064,970 lines**, 120,810 `|MDR|`
    rows, 360,528 `|RXNORM|` rows — full release, verified.
  - `models/microsoft/BiomedNLP-PubMedBERT-base-uncased-abstract/`
    (`pytorch_model.bin` 440,474,434 B + config/tokenizer/vocab) — exactly the
    `network_path` default in `snakemake/onsides/evaluate/Snakefile`.
- Skipped: their `data/omop_vocab/*.csv` (543/212 B stubs — ours verified good),
  their `_onsides/uk` (1,773 vs ours 10,250), their `models/onsides-bert`
  (identical to ours). No trained `.pth` in the zip (see §4).
- The slow NLM direct download (CAS ticket flow documented in git history) is
  no longer needed; UTS API key should still be regenerated (passed chat).

## 4. Open dev item for the GPU machine: evaluate weights format

`snakemake/onsides/evaluate/Snakefile` expects
`models/microsoft/BiomedNLP-PubMedBERT-base-uncased-abstract/` +
`models/bestepoch-bydrug-PMB_14-ALL-125-all_222_24_25_1e-06_256_32.pth`
(`src/onsides/predict.py` loads `.pth`). The HF `models/onsides-bert/`
(safetensors + custom `modeling_onsides.py`) does **not** plug in directly —
either train `.pth` via `snakemake/onsides/train/Snakefile`, or patch
`predict.py` to load safetensors (small task, GPU machine).

## 5. Mac staging role from now on: smoke tests only

```bash
./scripts/smoke_test.sh
```

Covers: pytest (71 tests), `snakemake -n` DAG checks for all 10 Snakefiles,
`read_csv(sep='\t')` OMOP readability, `build-zip --help`, tool presence
(java/pandoc/pdftotext). No bulk downloads, no GPU work.
