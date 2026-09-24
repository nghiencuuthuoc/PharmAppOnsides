# OnSIDES — chạy tất cả qua Docker (Windows 10 + RTX 5090)

Image duy nhất `onsides-pipeline:cu128` chứa: CUDA 12.8 runtime, Python 3.12,
torch cu128, Java 11, poppler, pandoc, duckdb, sqlite3, snakemake + `src/onsides`.
DB vẫn là `postgres:16` + `mysql:8.4` trong cùng compose.

## 0. Prereqs (Windows)

1. Driver NVIDIA mới nhất (đã OK: RTX 5090, 616.92).
2. WSL2 + Ubuntu 22.04: PowerShell Admin `wsl --install -d Ubuntu-22.04`, reboot.
3. Docker Desktop: bật WSL2 backend + integration Ubuntu. Test trong Ubuntu:
   `docker --version`, `docker compose version`.
4. RAM/disk: trống ~60GB cho `_onsides/` + `data/` + `models/`. Ổ C hiện trống ~1000GB.

## 1. Build

```bash
docker compose build pipeline
docker run --rm --gpus all onsides-pipeline:cu128 python3.12 -c "import torch; print(torch.__version__, torch.cuda.is_available())"
docker run --rm --gpus all onsides-pipeline:cu128 nvidia-smi
```

Phải thấy `True` + `RTX 5090`. Nếu `False`: update driver + `wsl --update`,
Docker Desktop dùng WSL2 backend.

## 2. Chuẩn bị data (bind-mount, gitignored)

Đặt trên host (mount vào `/work`):
- `data/MRCONSO.RRF`, `data/omop_vocab/CONCEPT.csv` + `CONCEPT_RELATIONSHIP.csv`
- `models/onsides-bert/` (copy tay 419MB hoặc `huggingface_hub.snapshot_download`)
- `_onsides/us/map_download/*.txt` (copy tay 83MB để khỏi tải lại)

## 3. Chạy pipeline trong container

```bash
docker compose up -d pipeline
docker compose exec pipeline bash
# trong container (snakemake 9 cần --cores):
python -c "import onsides; print('onsides OK')"
pytest src/onsides/ -q   # kỳ vọng 71 passed
snakemake -s snakemake/us/download/Snakefile --cores 4 --resources jobs=1 -n  # dry-run
snakemake -s snakemake/us/download/Snakefile --cores 4 --resources jobs=1
# ... uk/eu/jp download -> parse -> evaluate -> export (xem WINDOWS_SETUP.md mục 6,
# thêm --cores 4 vào mọi lệnh snakemake)
# checkpoint rows:
python -c "import polars as pl; [print(s, f'{len(pl.read_parquet(p)):,} rows') for s,p in [('US','_onsides/us/label_text.parquet'),('UK','_onsides/uk/label_text.parquet'),('EU','_onsides/eu/label_text.parquet'),('JP','_onsides/jp/med_label_text.parquet')]]"
snakemake -s snakemake/onsides/evaluate/Snakefile
snakemake -s snakemake/onsides/export/Snakefile
build-zip --version vX.Y.Z
exit
```

Lưu ý lỗi quen thuộc: `MissingInputException` US map chưa unzip,
`CREATE TABLE already exists` (xóa `duck.db`), `Matching 0 terms` (xóa parquet stale).

## 4. DB + annotator

```bash
docker compose up -d postgres mysql
docker compose ps
# schema + CSVs nạp SAU bước export (schema trong image export mới chuẩn,
# file commit sẵn thiếu CREATE TYPE cho enum): xem WINDOWS_SETUP.md mục 7
# (psql \copy / mysqlimport)
docker compose --profile annotator up -d annotator
# -> http://localhost:8000
```

Pass DB mặc định `onsides/onsides` chỉ cho dev local — đổi khi dùng thật.

## Troubleshooting

- `docker: unknown flag --gpus`: update Docker Desktop, dùng `docker compose exec` sau `up -d pipeline` thay vì `run --gpus`.
- CUDA trong container không thấy GPU nhưng WSL2 thấy: kiểm tra NVIDIA Container Toolkit trong Docker Desktop, thử `docker run --rm --gpus all nvidia/cuda:12.8.0-runtime-ubuntu22.04 nvidia-smi`.
- Build chậm: đã có `.dockerignore` loại `_onsides/data/models/log`; không copy data vào image.
