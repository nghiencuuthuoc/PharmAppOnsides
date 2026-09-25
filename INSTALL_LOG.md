# OnSIDES — Biên bản cài đặt apps (máy nguồn, 2026-09-25)

Cài bằng `winget-install-all.bat` + `setup.bat`. Win 10 Pro 2009 64-bit,
RTX 5090 driver 616.92 32GB.

| App | Version | Ghi chú |
|---|---|---|
| Git | 2.55.0.3 | `C:\Program Files\Git\cmd\git.exe` |
| Docker Desktop | 4.91.0 (Engine 29.8.0) | WSL2 backend; integration Ubuntu: tick tay trong Settings → Resources |
| VS Code (User) | 1.139.0 | Lần đầu upgrade fail do đang mở, tắt rồi chạy lại thì OK |
| Windows Terminal | 1.24.11911.0 | |
| Python 3.12 (host) | 3.12.10 per-user | Pipeline chạy trong container, host chỉ dùng check nhanh |
| 7-Zip | 26.03 | Nén backup; lưu ý không update được archive zip lớn |
| Notepad++ | 8.9.8.1 | |
| NVIDIA CUDA Toolkit | 13.4 | Optional; driver đủ cho container |
| Ubuntu (WSL2) | 26.04 (distro `Ubuntu`, inbox WSL cũ không có `Ubuntu-22.04`) | User `ezycloudx-admin` |
| `docker` trong Ubuntu | chưa có | Chưa tick WSL Integration; không bắt buộc vì chạy từ Windows CLI |

Verify: `nvidia-smi` host + `/usr/lib/wsl/lib/nvidia-smi` trong WSL đều thấy
RTX 5090; `docker version` thấy Server 4.91.0.
