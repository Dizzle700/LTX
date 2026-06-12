#!/bin/bash
# =============================================================================
# LTX2.3-ICEdit-Insight  —  RunPod Bootstrap Script
# Paste this into "Container Start Command" on RunPod
# Or run manually: bash <(curl -sL https://gist.githubusercontent.com/.../bootstrap.sh)
# =============================================================================

set -e
WORKSPACE="/workspace"
REPO_DIR="$WORKSPACE/LTX2-ICEdit-Insight"
LOG="$WORKSPACE/bootstrap.log"
PORT=8000

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

log()  { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOG"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG"; }
fail() { echo -e "${RED}[FAIL]${NC} $1" | tee -a "$LOG"; exit 1; }

echo "==========================================" | tee "$LOG"
echo " VHS Restorer — RunPod Bootstrap v1.0"    | tee -a "$LOG"
echo " $(date)"                                  | tee -a "$LOG"
echo "==========================================" | tee -a "$LOG"

# ─── 1. System packages ───────────────────────────────────────────────────────
log "Installing system packages..."
apt-get update -qq 2>>"$LOG"
apt-get install -y -qq ffmpeg git wget curl htop nvtop 2>>"$LOG" && ok "System packages ready"

# ─── 2. Python environment ────────────────────────────────────────────────────
log "Setting up Python environment..."
if ! command -v conda &>/dev/null; then
    warn "conda not found, using system Python"
    PYTHON="python3"
    PIP="pip3"
else
    conda create -n ltx2 python=3.12 -y 2>>"$LOG" || true
    source activate ltx2 2>/dev/null || conda activate ltx2 2>/dev/null || true
    PYTHON="python"
    PIP="pip"
fi

# ─── 3. Clone / update repo ───────────────────────────────────────────────────
log "Cloning repository..."
if [ -d "$REPO_DIR/.git" ]; then
    cd "$REPO_DIR" && git pull 2>>"$LOG" && ok "Repo updated"
else
    git clone https://github.com/Valiant-Cat/LTX2-ICEdit-Insight.git "$REPO_DIR" 2>>"$LOG" \
        && ok "Repo cloned"
fi
cd "$REPO_DIR"

# ─── 4. PyTorch + dependencies ────────────────────────────────────────────────
log "Installing PyTorch..."
CUDA_VER=$(nvcc --version 2>/dev/null | grep -oP 'release \K[\d.]+' | head -1 || echo "12.4")
CUDA_MAJOR=$(echo $CUDA_VER | cut -d. -f1)
CUDA_MINOR=$(echo $CUDA_VER | cut -d. -f2)

if [ "$CUDA_MAJOR" -ge 12 ] && [ "$CUDA_MINOR" -ge 8 ]; then
    TORCH_IDX="https://download.pytorch.org/whl/cu128"
    log "Using CUDA 12.8 wheels"
else
    TORCH_IDX="https://download.pytorch.org/whl/cu124"
    log "Using CUDA 12.4 wheels"
fi

$PIP install torch torchaudio --index-url $TORCH_IDX -q 2>>"$LOG" && ok "PyTorch installed"
$PIP install -r requirements.txt -q 2>>"$LOG" && ok "Dependencies installed"
$PIP install fastapi uvicorn[standard] python-multipart aiofiles huggingface_hub -q 2>>"$LOG"

# ─── 5. Download models ───────────────────────────────────────────────────────
log "Downloading models from HuggingFace..."
mkdir -p models/checkpoints models/loras/ltx2.3-train \
         models/latent_upscale_models models/gemma_configs \
         inputs outputs

HF_REPO="joyfox/LTX2.3-ICEdit-Insight"

download_model() {
    local filename="$1"
    local dest="$2"
    if [ -f "$dest/$filename" ]; then
        warn "Already exists: $filename"
        return 0
    fi
    log "Downloading $filename (~$(du -sh $dest/$filename 2>/dev/null | cut -f1 || echo '?'))..."
    $PYTHON -c "
from huggingface_hub import hf_hub_download
import shutil, os
path = hf_hub_download('$HF_REPO', '$filename', cache_dir='/tmp/hf_cache')
os.makedirs('$dest', exist_ok=True)
shutil.copy2(path, '$dest/$filename')
print('  -> $dest/$filename')
" 2>>"$LOG" && ok "$filename downloaded" || warn "Failed: $filename"
}

download_model "ltx-2.3-edit-insight-dev-fp8.safetensors" "models/checkpoints"
download_model "ltx2.3-video-restoration-general.safetensors" "models/loras/ltx2.3-train"
download_model "ltx2.3-ic-video-upscale-general.safetensors" "models/loras/ltx2.3-train"

# Spatial upscaler from Lightricks
if [ ! -f "models/latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.1.safetensors" ]; then
    log "Downloading spatial upscaler..."
    $PYTHON -c "
from huggingface_hub import hf_hub_download
import shutil, os
path = hf_hub_download('Lightricks/LTX-2.3',
    'ltx-2.3-spatial-upscaler-x2-1.1.safetensors', cache_dir='/tmp/hf_cache')
shutil.copy2(path, 'models/latent_upscale_models/')
" 2>>"$LOG" && ok "Upscaler downloaded" || warn "Upscaler download failed (optional)"
fi

# ─── 6. Write FastAPI server ───────────────────────────────────────────────────
log "Writing server.py..."
cat > "$REPO_DIR/server.py" << 'PYEOF'
"""
VHS Restorer — FastAPI server for RunPod
Endpoints:
  POST /process          — upload video, returns job_id
  GET  /status/{job_id}  — returns progress 0-100, status, log tail
  GET  /download/{job_id}— streams the output MP4
  GET  /health           — GPU info
"""

import os, uuid, subprocess, threading, time, json, shutil
from pathlib import Path
from typing import Optional
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import StreamingResponse, JSONResponse
import torch

app = FastAPI(title="VHS Restorer", version="1.0.0")

REPO = Path(__file__).parent
INPUTS  = REPO / "inputs"
OUTPUTS = REPO / "outputs"
INPUTS.mkdir(exist_ok=True)
OUTPUTS.mkdir(exist_ok=True)

jobs: dict[str, dict] = {}   # job_id -> {status, progress, log, pid}

LORA_MAP = {
    "restoration": "models/loras/ltx2.3-train/ltx2.3-video-restoration-general.safetensors",
    "hd":          "models/loras/ltx2.3-train/ltx2.3-ic-video-upscale-general.safetensors",
    "both":        None,   # pipeline: restoration → hd
}

PROMPT_MAP = {
    "restoration": (
        "Restore this VHS tape footage: remove tape noise, static artifacts, color bleeding, "
        "tracking distortions, magnetic dropout, and grain. Recover details with stable colors."
    ),
    "hd": (
        "Convert this video to ultra-high-definition quality. Significantly improve clarity, "
        "fine detail richness, texture fidelity, and perceptual sharpness."
    ),
}


def _run_stage(job_id: str, mode: str, in_path: Path, out_path: Path,
               height: int, width: int, num_frames: int, fps: float, seed: int):
    """Run a single pipeline stage in subprocess."""
    lora = LORA_MAP[mode]
    prompt = PROMPT_MAP[mode]
    env = {**os.environ, "PYTORCH_CUDA_ALLOC_CONF": "expandable_segments:True"}

    cmd = [
        "python", "run_pipeline.py",
        "--mode", mode,
        "--video", str(in_path),
        "--prompt", prompt,
        "--output", str(out_path),
        "--height", str(height),
        "--width",  str(width),
        "--num-frames", str(num_frames),
        "--fps", str(fps),
        "--seed", str(seed),
        "--sigma-profile", "workflow",
        "--streaming-prefetch-count", "2",
        "--model-checkpoint",
        "models/checkpoints/ltx-2.3-edit-insight-dev-fp8.safetensors",
        "--lora", lora,
    ]

    proc = subprocess.Popen(
        cmd, cwd=str(REPO), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1
    )
    jobs[job_id]["pid"] = proc.pid
    log_lines = []
    for line in proc.stdout:
        line = line.rstrip()
        log_lines.append(line)
        if len(log_lines) > 200:
            log_lines.pop(0)
        jobs[job_id]["log"] = log_lines[-50:]
        # crude progress: look for step indicators
        if "step" in line.lower() and "/" in line:
            try:
                parts = [p for p in line.split() if "/" in p]
                for p in parts:
                    a, b = p.split("/")
                    jobs[job_id]["progress"] = min(99, int(int(a)/int(b)*100))
                    break
            except Exception:
                pass
    proc.wait()
    return proc.returncode


def _job_worker(job_id: str, in_path: Path, mode: str,
                height: int, width: int, num_frames: int, fps: float, seed: int):
    """Background thread: run pipeline, update job state."""
    try:
        jobs[job_id]["status"] = "preprocessing"
        jobs[job_id]["progress"] = 2

        # Preprocess: scale to 480p, 24fps
        pre_path = INPUTS / f"{job_id}_480p.mp4"
        subprocess.run([
            "ffmpeg", "-y", "-i", str(in_path),
            "-vf", f"scale={width}:{height}",
            "-r", str(fps), "-c:v", "libx264", "-crf", "18",
            str(pre_path)
        ], capture_output=True)

        if mode == "both":
            # Stage 1: restoration
            jobs[job_id]["status"] = "restoring"
            jobs[job_id]["progress"] = 5
            restored = OUTPUTS / f"{job_id}_stage1.mp4"
            rc = _run_stage(job_id, "restoration", pre_path, restored,
                            height, width, num_frames, fps, seed)
            if rc != 0:
                raise RuntimeError("Restoration stage failed")

            # Stage 2: HD upscale
            jobs[job_id]["status"] = "upscaling"
            jobs[job_id]["progress"] = 55
            final = OUTPUTS / f"{job_id}_final.mp4"
            rc = _run_stage(job_id, "hd", restored, final,
                            height * 2, width * 2, num_frames, fps, seed)
            if rc != 0:
                raise RuntimeError("HD upscale stage failed")
            shutil.move(str(final), str(OUTPUTS / f"{job_id}.mp4"))
        else:
            jobs[job_id]["status"] = "processing"
            jobs[job_id]["progress"] = 5
            out = OUTPUTS / f"{job_id}.mp4"
            rc = _run_stage(job_id, mode, pre_path, out,
                            height, width, num_frames, fps, seed)
            if rc != 0:
                raise RuntimeError(f"Stage {mode} failed")

        jobs[job_id]["status"] = "done"
        jobs[job_id]["progress"] = 100

    except Exception as e:
        jobs[job_id]["status"] = "error"
        jobs[job_id]["error"] = str(e)
    finally:
        # Cleanup input
        try:
            in_path.unlink()
            pre_path.unlink(missing_ok=True)
        except Exception:
            pass


# ─── Endpoints ────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    gpu_info = {}
    try:
        if torch.cuda.is_available():
            i = torch.cuda.current_device()
            gpu_info = {
                "name": torch.cuda.get_device_name(i),
                "vram_total_gb": round(torch.cuda.get_device_properties(i).total_memory / 1e9, 1),
                "vram_free_gb":  round((torch.cuda.get_device_properties(i).total_memory
                                        - torch.cuda.memory_allocated(i)) / 1e9, 1),
            }
    except Exception:
        pass
    return {
        "status": "ok",
        "gpu": gpu_info,
        "active_jobs": sum(1 for j in jobs.values() if j["status"] not in ("done", "error")),
        "models_ready": Path("models/checkpoints/ltx-2.3-edit-insight-dev-fp8.safetensors").exists(),
    }


@app.post("/process")
async def process_video(
    file: UploadFile = File(...),
    mode: str = Form("restoration"),   # restoration | hd | both
    height: int = Form(512),
    width:  int = Form(352),
    num_frames: int = Form(97),
    fps: float = Form(24.0),
    seed: int = Form(42),
):
    if mode not in LORA_MAP:
        raise HTTPException(400, f"mode must be one of: {list(LORA_MAP)}")
    if num_frames % 8 != 1:
        raise HTTPException(400, "num_frames must satisfy 8k+1 (e.g. 25, 97, 217)")

    job_id = str(uuid.uuid4())[:12]
    in_path = INPUTS / f"{job_id}_raw.mp4"

    with open(in_path, "wb") as f:
        content = await file.read()
        f.write(content)

    jobs[job_id] = {
        "status": "queued", "progress": 0,
        "log": [], "error": None, "pid": None,
        "mode": mode, "created": time.time(),
    }

    t = threading.Thread(
        target=_job_worker,
        args=(job_id, in_path, mode, height, width, num_frames, fps, seed),
        daemon=True
    )
    t.start()
    return {"job_id": job_id, "status": "queued"}


@app.get("/status/{job_id}")
def get_status(job_id: str):
    if job_id not in jobs:
        raise HTTPException(404, "Job not found")
    j = jobs[job_id]
    return {
        "job_id": job_id,
        "status": j["status"],
        "progress": j["progress"],
        "log": j["log"],
        "error": j.get("error"),
        "mode": j.get("mode"),
        "elapsed": round(time.time() - j["created"], 1),
    }


@app.get("/download/{job_id}")
def download_result(job_id: str):
    if job_id not in jobs:
        raise HTTPException(404, "Job not found")
    if jobs[job_id]["status"] != "done":
        raise HTTPException(400, f"Job not done yet: {jobs[job_id]['status']}")

    out_path = OUTPUTS / f"{job_id}.mp4"
    if not out_path.exists():
        raise HTTPException(404, "Output file not found")

    def iter_file():
        with open(out_path, "rb") as f:
            while chunk := f.read(1024 * 1024):
                yield chunk

    return StreamingResponse(
        iter_file(),
        media_type="video/mp4",
        headers={"Content-Disposition": f"attachment; filename=restored_{job_id}.mp4"}
    )


@app.delete("/job/{job_id}")
def delete_job(job_id: str):
    if job_id in jobs:
        out = OUTPUTS / f"{job_id}.mp4"
        out.unlink(missing_ok=True)
        del jobs[job_id]
    return {"deleted": job_id}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", 8000)), log_level="info")
PYEOF

ok "server.py written"

# ─── 7. Start server ──────────────────────────────────────────────────────────
log "Starting FastAPI server on port $PORT..."
cd "$REPO_DIR"

# Kill existing server if running
pkill -f "uvicorn server:app" 2>/dev/null || true
sleep 1

nohup $PYTHON server.py > "$WORKSPACE/server.log" 2>&1 &
SERVER_PID=$!
echo $SERVER_PID > "$WORKSPACE/server.pid"

# Wait for server to come up
for i in $(seq 1 30); do
    sleep 2
    if curl -sf "http://localhost:$PORT/health" > /dev/null 2>&1; then
        ok "Server is UP! PID=$SERVER_PID  Port=$PORT"
        log "Health: $(curl -s http://localhost:$PORT/health)"
        echo ""
        echo "=========================================="
        echo " Server ready at: http://localhost:$PORT"
        echo " Logs: tail -f $WORKSPACE/server.log"
        echo "=========================================="
        exit 0
    fi
    log "Waiting for server... ($i/30)"
done

fail "Server did not start in 60s — check $WORKSPACE/server.log"
