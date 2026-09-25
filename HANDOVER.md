# OnSIDES — Hồ sơ chuyển giao máy chạy (Docker full-stack)

Ngày chốt: 2026-09-25. Nhánh: `dev/intel-mac` repo
`https://github.com/nghiencuuthuoc/PharmAppOnsides`.
Docs chi tiết: `WINDOWS_SETUP.md` (nền tảng), `DOCKER_ALL.md` (chạy Docker),
`HUMAN_UPDATE_GUIDE.md` / `AGENT_UPDATE_GUIDE.md` (upstream).

## 1. Kiến trúc

Một image duy nhất `onsides-pipeline:cu128` (CUDA 12.8 + Ubuntu 24.04 +
Python 3.12 + torch cu128 + Java 11/poppler/pandoc/duckdb CLI/sqlite3 +
snakemake + `src/onsides`) chạy pipeline; `postgres:16` + `mysql:8.4`
chạy DB; `annotator` (profile riêng) chạy API `:8000`. Code + data
bind-mount từ host (`.:/work`), không bake data vào image.

## 2. Hiện trạng máy nguồn (đã verify)

- Win 10 Pro 2009 64-bit, RTX 5090 driver 616.92 32GB, ổ C trống ~918GB.
- Git 2.55, Docker Desktop 4.91 (Engine 29.8), Ubuntu 26.04 trên WSL2,
  Python host 3.12 (per-user) + 3.14, VSCode, 7-Zip, CUDA Toolkit 13.4.
- Image `onsides-pipeline:cu128` 19.5GB; torch `2.11.0+cu128 True RTX 5090`.
- `pytest src/onsides/ -q`: **71 passed**.
- Services: pipeline Up, mysql/postgres healthy.
- Download US→UK→EU→JP đang chạy nền (`log/download_full.log`),
  `_onsides` ~21GB và tăng (đích ~40GB).

## 3. Data (đều gitignored, phải chuyển tay)

| File | Trạng thái | Nguồn |
|---|---|---|
| `data/MRCONSO.RRF` 2.2GB, 18,064,970 rows, đủ `MDR` 120k + `MDRJPN` 231k | FULL OK | UTS, key trong `.env` |
| `data/omop_vocab/CONCEPT.csv` + `CONCEPT_RELATIONSHIP.csv` (5 + 3 rows) | TEST, phải thay | Athena bundle RxNorm/RxNorm Extension/MedDRA/NDC cùng version |
| `models/onsides-bert/` 418MB | OK | HF `tatonettilab/onsides-bert` |
| `models/microsoft/BiomedNLP-PubMedBERT-base-uncased-abstract/` 420MB | OK | HF `microsoft/...` (public) |
| `models/bestepoch-bydrug-PMB_14-ALL-125-all_222_24_25_1e-06_256_32.pth` | THIẾU | Copy máy Mac hoặc train lại (GPU nhiều ngày) |
| `_onsides/` ~21GB (labels đang tải) | Đang tải | Pipeline tự tải; resume được |
| `.env` (`UMLS_API=...`) | Có, gitignored | Chuyển riêng, KHÔNG commit |

## 4. Dựng máy mới từ zero

```bat
winget-install-all.bat   :: Git/Docker/VSCode/Terminal/Python/7-Zip/Notepad++/CUDA + wsl --install -d Ubuntu (Admin, reboot)
onsides.bat build        :: docker compose build pipeline (10-20 phut)
onsides.bat gpu          :: nvidia-smi + torch cuda True
onsides.bat up           :: pipeline + postgres + mysql
onsides.bat test         :: pytest 71 passed
```

```bash
git clone -b dev/intel-mac https://github.com/nghiencuuthuoc/PharmAppOnsides.git .
# copy .env + data/ + models/ (muc 3) vao repo
docker compose exec pipeline bash
snakemake -s snakemake/us/download/Snakefile --cores 4 --resources jobs=1
# ... uk / eu+--keep-going / jp+--keep-going -> parse x4 -> checkpoint rows
# US ~50k, UK ~7k, EU ~1.5k, JP ~9k (polars dem rows, xem DOCKER_ALL.md)
snakemake -s snakemake/onsides/evaluate/Snakefile   # GPU, tinh bang ngay
snakemake -s snakemake/onsides/export/Snakefile
build-zip --version vX.Y.Z
```

DB + annotator: `docker compose up -d postgres mysql` (schema + CSV nạp
SAU export, xem `WINDOWS_SETUP.md` muc 7),
`docker compose --profile annotator up -d annotator` → `:8000`.

## 5. Secrets

- `.env` đã gitignored (`.gitignore:18`), không bao giờ commit.
- Mọi token/key từng dán vào chat đều coi như lộ: revoke tại nguồn
  (GitHub Settings → Tokens, UTS), không dán secret vào chat/terminal log.
- Pass DB `onsides/onsides` chỉ cho dev local, đổi khi dùng thật.

## 6. Sự cố đã gặp và cách fix (đừng làm lại)

1. WSL inbox cũ chỉ có distro `Ubuntu` (không có `Ubuntu-22.04`).
2. Snakemake 9 bắt buộc `--cores` (guide cũ cho v8 không có).
3. Base jammy không có python3.12 → đổi base `nvidia/cuda:12.8.0-runtime-ubuntu24.04`.
4. Ubuntu 24.04 cấm pip system (PEP 668) → `PIP_BREAK_SYSTEM_PACKAGES=1`,
   bỏ bước `pip install --upgrade pip` (lỗi RECORD Debian).
5. Image thiếu CLI `duckdb` (apt noble không có) → cài binary v1.5.5
   từ GitHub releases (đã có trong Dockerfile).
6. `postgres.sql` commit sẵn hỏng (enum thiếu `CREATE TYPE`) → bỏ mount
   init, nạp schema sau export.
7. `()` trong text `echo` của BAT đóng sớm khối `if` → `goto end` luôn
   chạy, bat chết im. Không dùng `()` trần trong `echo` của khối `if`.
8. 7-Zip không update được archive zip lớn → luôn xóa target trước khi nén.
9. Athena Download hay `Internal server error` → retry, đủ 4 vocabs
   (MedDRA bắt buộc), cùng version; có thể chia bundle rồi concat.
10. `wsl -l -v` treo khi `LxssManager` stopped / chưa có distro.
11. `where`/`docker` không thấy sau cài → reboot để PATH ăn; Docker daemon
    chỉ lên sau khi mở Docker Desktop.

## 7. Backup / restore

`backup.bat [full|slim|nodaily]` → zip timestamp ra `..\`, tự copy sang
`G:\My Drive` nếu vừa (verify size sau copy). `slim` bỏ `_onsides`,
`nodaily` bỏ zip DailyMed (`us/download`, `labelzips`, `*.zip`).
Lưu ý: G: chỉ ~7.8GB trống — full ~21GB+ không vừa.

## 8. Việc còn dở (máy mới tiếp tục)

- `git push origin dev/intel-mac`: commit local hơn remote, kẹt auth —
  chạy tay + xác thực browser (device-code), không dùng PAT dán sẵn.
- OMOP thật thay 2 file test; `.pth` weights (máy Mac hoặc train).
- Download labels chưa xong (theo dõi `log/download_full.log`).
- Docker Desktop phải mở trước mọi lệnh docker; tắt máy giữa chừng thì
  `compose up -d` lại + snakemake resume.
