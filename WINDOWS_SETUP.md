# OnSIDES — Windows 10 + RTX GPU Setup & Run Guide (conda + Docker)

Target machine: **Windows 10 64-bit, NVIDIA RTX GPU, conda + Docker Desktop**.
Repo branch with dev fixes: `dev/intel-mac` on `https://github.com/nghiencuuthuoc/PharmAppOnsides`
(upstream: `tatonetti-lab/onsides`). Test fix + env files are on that branch.

> Quyet dinh quan trong: **chay pipeline trong WSL2 (Ubuntu)**, khong chay
> Snakemake native tren Windows (Snakemake + `shell:` rules pandoc/duckdb/java
> tren Windows hay loi path). CUDA van dung duoc trong WSL2 (NVIDIA driver
> moi ho tro CUDA on WSL). Docker Desktop chay containers DB.

---

## 0. Cai dat tren Windows 10

1. **NVIDIA driver** moi nhat cho card RTX (ho tro CUDA 12.x). Kiem tra:
   `nvidia-smi` phai hien driver + CUDA version.
2. **WSL2 + Ubuntu 22.04**: `wsl --install -d Ubuntu-22.04` (PowerShell Admin),
   reboot, tao user Ubuntu.
3. **Docker Desktop for Windows**: bat che do **WSL 2 backend**, enable integration
   voi Ubuntu distro. Kiem tra trong Ubuntu: `docker --version`,
   `docker compose version`.
4. **Miniforge/Miniconda**: cai ban Linux x86_64 **trong Ubuntu**
   (khong phai ban Windows), vi moi truong pipeline nam trong WSL2.
   Neu muon them env native Windows (chi de dev nhe/annotator), cai them
   Miniconda Windows + dung `environment-windows.yml` (xem muc 3b).

## 1. Clone repo (trong Ubuntu WSL2)

```bash
git clone https://github.com/nghiencuuthuoc/PharmAppOnsides.git onsides
cd onsides
git checkout dev/intel-mac
git log --oneline -3
```

## 2. Tao conda env (trong Ubuntu WSL2)

```bash
conda env create -f environment-windows.yml -n onsides
conda activate onsides
```

File `environment-windows.yml` cai Python 3.12 + openjdk 11, poppler
(pdftotext), pandoc, duckdb, sqlite, curl qua conda-forge. Phan `pip:` de
nguyen theo `pyproject.toml` (torch se cai rieng o buoc 3 de lay ban CUDA).

## 3. Cai PyTorch CUDA cho RTX (buoc bat buoc truoc `pip install -e .`)

```bash
conda activate onsides
pip install torch --index-url https://download.pytorch.org/whl/cu126
python -c "import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0))"
```

Phai in `True` + ten card RTX. Sau do:

```bash
pip install -e ".[annotator]"
pip install pytest
python -c "import onsides; print('onsides OK')"
pytest src/onsides/ -q   # ky vong: 71 passed
```

### 3b. Native Windows (tuy chon, khong chay Snakemake)

Neu muon env Windows native (chi test/dev nhe): cai Miniconda Windows, mo
**Anaconda Prompt**, lap lai buoc 2-3 voi `environment-windows.yml`.
Luu y Windows: `pdftotext` (poppler) + Java phai co trong PATH, duong dan dai
can bat **LongPathsEnabled**, va Snakemake co the loi — dung WSL2 cho pipeline.

## 4. Verify system tools (trong Ubuntu WSL2)

```bash
java -version      # OpenJDK 11 (cho tabula-py / EU PDF)
pandoc --version
pdftotext -v
duckdb --version || python -c "import duckdb; print(duckdb.__version__)"
```

Neu thieu: `conda install -c conda-forge <ten-goi>` trong env `onsides`.
Dat bien moi truong cho tabula:

```bash
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH
export TABULA_JAVA_PATH=$JAVA_HOME/bin/java
```

## 5. Du lieu dau vao (khong co trong git — tu copy/tai)

| File | Dat tai | Nguon |
|---|---|---|
| `data/MRCONSO.RRF` (full, ~17M dong, GBs, ten HOA) | `data/` | UMLS license (tai tu NLM, khong public) |
| `data/omop_vocab/CONCEPT.csv` | `data/omop_vocab/` | OMOP CDM vocabulary (Athena) |
| `data/omop_vocab/CONCEPT_RELATIONSHIP.csv` | `data/omop_vocab/` | OMOP CDM vocabulary |
| `models/onsides-bert/` (da pull san, 419MB) | `models/` | Copy tu may Mac, hoac `huggingface_hub.snapshot_download('tatonettilab/onsides-bert', local_dir='models/onsides-bert')` |

Kiem tra: `wc -l data/MRCONSO.RRF` phai ra hang trieu dong (vai tram dong =
file mau, pipeline se ra vocab rong). Dung luong can: **~60GB trong**
(`_onsides/` ~40GB + data ~4GB + models).

### Tai san tu may Mac (tuy chon, tiet kiem download lai)

- `models/onsides-bert/` (419MB): copy nguyen thu muc.
- `_onsides/us/map_download/*.txt` (83MB: `rxnorm_mappings.txt`,
  `dm_spl_zip_files_meta_data.txt`): export step can, copy de khoi tai lai.
- Index pages US/UK/EU/JP: nho (KBs), tai lai vai giay, khong can copy.

## 6. Chay pipeline (thu tu bat buoc, trong Ubuntu WSL2, chay trong `tmux`)

```bash
# Download (hours-days; EU/JP flaky -> --keep-going + rerun toi khi het viec)
snakemake -s snakemake/us/download/Snakefile --resources jobs=1
snakemake -s snakemake/uk/download/Snakefile --resources jobs=1
snakemake -s snakemake/eu/download/Snakefile --resources jobs=1 --keep-going
snakemake -s snakemake/jp/download/Snakefile --resources jobs=1 --keep-going
# US map zips ve dang .zip -> unzip tai cho (export can .txt):
# (cd _onsides/us/map_download && unzip -o '*.zip')

# Parse (hours; US ~50k labels nang nhat)
snakemake -s snakemake/us/parse/Snakefile
snakemake -s snakemake/uk/parse/Snakefile
snakemake -s snakemake/eu/parse/Snakefile
snakemake -s snakemake/jp/parse/Snakefile

# Checkpoint: 4 parquet phai co rows != 0 (US ~50k, UK ~7k, EU ~1.5k, JP ~9k)
python -c "
import polars as pl
for s,p in [('US','_onsides/us/label_text.parquet'),('UK','_onsides/uk/label_text.parquet'),
            ('EU','_onsides/eu/label_text.parquet'),('JP','_onsides/jp/med_label_text.parquet')]:
    print(s, f'{len(pl.read_parquet(p)):,} rows')"

# Evaluate (GPU RTX, days; BERT scoring hang trieu matches)
snakemake -s snakemake/onsides/evaluate/Snakefile

# Export (phut, CPU; nho xoa duck.db cu neu rerun: rm -f duck.db database/onsides.db)
snakemake -s snakemake/onsides/export/Snakefile

# Release zip
build-zip --version vX.Y.Z
```

Chu y: truoc moi Snakefile nen dry-run (`-n`) de xem viec se lam.
Loi quen thuoc (xem `AGENT_UPDATE_GUIDE.md`): `ENAMETOOLONG` (JP),
`MissingInputException` (US map chua unzip), `CREATE TABLE already exists`
(xoa `duck.db`), `Matching 0 terms` (xoa parquet vocab/combined stale).

## 7. Nap DB bang Docker (thay cho `database/database_scripts/*.sh` podman)

```bash
docker compose up -d
docker compose ps
```

- **Postgres** (`localhost:5432`, user/pass/db `onsides`): schema tu dong nap tu
  `database/schema/postgres.sql` luc khoi tao container. Nap CSVs theo thu tu
  (xem `database/postgres.sh` goc):
  `vocab_meddra_adverse_effect, product_label, vocab_rxnorm_ingredient,
  vocab_rxnorm_product, product_to_rxnorm, vocab_rxnorm_ingredient_to_product,
  product_adverse_effect` — dung `psql`/replica lenh `\copy` trong container.
- **MySQL** (`localhost:3306`, user/pass/db `onsides`): tuong tu voi
  `database/schema/mysql.sql` + `mysqlimport`/replica `LOAD DATA` (xem
  `database/mysql.sh`).
- **SQLite**: khong can container — dung truc tiep `database/onsides.db`
  do step export tao ra (hoac `database/sqlite.sh` voi sqlite3 CLI).

## 8. Annotator + truy van mau

```bash
uv run onsides-annotate   # hoac: python -m onsides.annotator.app
# -> http://localhost:8000 (can parsed labels o _onsides/us/labels/)
```

Vi du truy van: xem `docs/README.md` va `database/test.sql`,
`database/summarize.sql`.

## 9. Troubleshooting Windows/WSL2

- `nvidia-smi` trong WSL2 khong thay GPU: update driver Windows + kernel WSL
  (`wsl --update`), Docker Desktop dung WSL2 backend.
- `torch.cuda.is_available() == False`: kiem tra driver/CUDA, cai lai torch
  cu126; dung `pip list | grep torch`.
- Snakemake bao loi shell (`pandoc/duckdb/java not found`): dang o ngoai WSL
  hoac chua `conda activate onsides` — pipeline phai chay trong Ubuntu WSL2.
- Loi duplicate `.venv`/nix: du an nay dung conda tren Windows, **bo qua
  `nix develop`** (nix khong dung cho Windows).
- Disk: de trong toi thieu 60GB (NTFS qua WSL2 cham hon ext4 — neu cham,
  dat `_onsides/` tren o ext4/WSL filesystem thay vi `/mnt/c`).

## Phu luc: tien do da lam tren may Mac (de tai su dung)

- Env `onsides-dev` (Python 3.12, torch CPU 2.2.2, transformers 4.50.3) + fix
  `test_stringsearch.py` (string IDs, pytest 71 passed) — da push nhanh
  `dev/intel-mac`.
- Da tai that: US index + map txts (export-ready), UK browse+prefixes, EU
  manifest (2,302 thuoc) + 3 HTML + 3 PDF links + 1 PDF parse thanh cong
  (tabula/pdftotext/section 4.8 OK), JP index counts, model `onsides-bert`.
- Chua lam (can may moi): bulk downloads labels, parse full, evaluate (GPU),
  export, build-zip, nap Docker DB.
