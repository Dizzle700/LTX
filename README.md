# VHS Restorer — Setup Guide

## Server (RunPod)

### 1. Create a RunPod pod
- GPU: RTX 4090 (24GB) or A100 40G
- Template: `RunPod PyTorch 2.x`  (Ubuntu 22.04, CUDA 12.x)
- Expose HTTP port: **8000**

### 2. Configure Hugging Face access
1. Accept the license for [`google/gemma-3-12b-it`](https://huggingface.co/google/gemma-3-12b-it).
2. Create a Hugging Face access token with **Read** permission.
3. Add it to the RunPod pod environment as `HF_TOKEN`.

The bootstrap validates this token before downloading the gated Gemma model.

### 3. Set Container Start Command
Paste this into "Container Start Command":
```bash
bash <(curl -sL YOUR_GIST_RAW_URL/server_bootstrap.sh)
```
> [!NOTE]
> Replace `YOUR_GIST_RAW_URL` with your raw Gist URL (e.g., `https://gist.githubusercontent.com/username/gist_id/raw/`).

### 4. Watch the logs
The pod logs will show download progress (~20 GB models).
Server is ready when you see: `Server is UP!`

> [!TIP]
> If you encounter startup issues, you can inspect the full logs inside the pod:
> - Installation logs: `/workspace/bootstrap.log`
> - FastAPI server logs: `/workspace/server.log`

### 5. Get your URL
In RunPod pod settings → Connect → copy the proxy URL for port 8000:
```
https://xxxxxxxxxxxxxxxx-8000.proxy.runpod.net
```

---

## Client (Linux / Windows)

### 1. Install Dependencies
Make sure you have `ffmpeg` installed on your local machine (required for splitting/merging long videos).

**Check if ffmpeg is installed:**
```bash
ffmpeg -version
```

**If not installed (Linux/Ubuntu):**
```bash
sudo apt update && sudo apt install -y ffmpeg
```

**Install Python packages:**
```bash
pip install PyQt6 requests
```

### 2. Run
```bash
python vhs_restorer_client.py
```

### 3. Usage
1. Paste your RunPod URL → **Connect**
2. Drop your VHS video into the drop zone
   - Supported containers include MP4, MKV, MOV, AVI, WebM, M4V, WMV,
     MPEG, MTS/M2TS, TS, VOB, FLV, 3GP, and OGV.
   - Browser uploads default to a 50 GB limit. Override it on RunPod with
     `MAX_UPLOAD_SIZE` (for example, `MAX_UPLOAD_SIZE=100gb`).
3. Choose mode:
   - `restoration` — removes VHS artifacts, noise, tracking errors
   - `hd` — HD upscale only
   - `both` — best results: restore first, then upscale
4. Set resolution (352×512 = fast, 704×1024 = best)
5. Click **Start Processing**
6. When done → **Download Result**

---

## VRAM guide

| Resolution | Frames | VRAM  | Time (4090) |
|-----------|--------|-------|-------------|
| 352×512   | 25     | ~10 GB | ~3 min |
| 352×512   | 97     | ~14 GB | ~10 min |
| 704×1024  | 97     | ~17 GB | ~20 min |
| 704×1024  | 217    | ~20 GB | ~45 min |

For `both` mode: double the time.

---

## Long VHS videos

Split into ~4 second chunks with ffmpeg, process each, then merge:
```bash
# Split
ffmpeg -i long_vhs.mp4 -c copy -f segment -segment_time 4 \
  -reset_timestamps 1 chunk_%03d.mp4

# Merge results
ffmpeg -f concat -safe 0 -i <(for f in restored_*.mp4; do echo "file '$f'"; done) \
  -c copy final_restored.mp4
```
