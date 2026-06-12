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
    CONDA_BASE="$(conda info --base 2>/dev/null)" || fail "Could not locate conda base"
    source "$CONDA_BASE/etc/profile.d/conda.sh" 2>>"$LOG" || fail "Could not initialize conda"
    conda activate ltx2 2>>"$LOG" || fail "Could not activate conda env: ltx2"
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

if [ "$CUDA_MAJOR" -gt 12 ] || { [ "$CUDA_MAJOR" -eq 12 ] && [ "$CUDA_MINOR" -ge 8 ]; }; then
    TORCH_IDX="https://download.pytorch.org/whl/cu128"
    log "Using CUDA 12.8 wheels"
else
    TORCH_IDX="https://download.pytorch.org/whl/cu124"
    log "Using CUDA 12.4 wheels"
fi

"$PIP" install --force-reinstall torch torchvision torchaudio --index-url "$TORCH_IDX" -q 2>>"$LOG" && ok "PyTorch stack installed"
"$PIP" install -r requirements.txt -q 2>>"$LOG" && ok "Dependencies installed"
"$PIP" install --force-reinstall torch torchvision torchaudio --index-url "$TORCH_IDX" -q 2>>"$LOG" && ok "PyTorch stack aligned after requirements"
"$PIP" install gradio fastapi 'uvicorn[standard]' python-multipart aiofiles huggingface_hub -q 2>>"$LOG" && ok "Web dependencies installed"
"$PYTHON" -c "import torch, torchvision; print(f'torch={torch.__version__} torchvision={torchvision.__version__} cuda={torch.version.cuda}')" >>"$LOG" 2>&1 \
    && ok "PyTorch/torchvision import check passed" \
    || fail "PyTorch/torchvision import check failed; check $LOG"

# ─── 5. Download models ───────────────────────────────────────────────────────
log "Downloading models from HuggingFace..."
mkdir -p models/checkpoints models/loras/ltx2.3-train \
         models/latent_upscale_models models/gemma_configs \
         inputs outputs

HF_REPO="joyfox/LTX2.3-ICEdit-Insight"
GEMMA_REPO="${GEMMA_REPO:-google/gemma-3-12b-it}"

download_model() {
    local filename="$1"
    local dest="$2"
    local required="${3:-required}"
    if [ -f "$dest/$filename" ]; then
        warn "Already exists: $filename"
        return 0
    fi
    log "Downloading $filename (~$(du -sh $dest/$filename 2>/dev/null | cut -f1 || echo '?'))..."
    "$PYTHON" -c "
from huggingface_hub import hf_hub_download
import os
os.makedirs('$dest', exist_ok=True)
token = os.getenv('HF_TOKEN')
path = hf_hub_download('$HF_REPO', '$filename', local_dir='$dest', local_dir_use_symlinks=False, token=token)
print('  -> ' + path)
" 2>>"$LOG" && ok "$filename downloaded" || {
        if [ "$required" = "required" ]; then
            fail "Failed to download required model: $filename"
        else
            warn "Failed: $filename"
        fi
    }
}

download_model "ltx-2.3-edit-insight-dev-fp8.safetensors" "models/checkpoints" required
download_model "ltx2.3-video-restoration-general.safetensors" "models/loras/ltx2.3-train" required
download_model "ltx2.3-ic-video-upscale-general.safetensors" "models/loras/ltx2.3-train" required

# The Insight checkpoint does not contain the Gemma text encoder. run_pipeline.py
# needs both its tokenizer/config files and model shards under this directory.
if [ -f "models/gemma_configs/tokenizer.model" ] && \
   compgen -G "models/gemma_configs/model*.safetensors" > /dev/null; then
    warn "Gemma text encoder already exists"
else
    log "Downloading Gemma text encoder from $GEMMA_REPO (~25 GB)..."
    "$PYTHON" -c "
from huggingface_hub import snapshot_download
import os

snapshot_download(
    repo_id='$GEMMA_REPO',
    local_dir='models/gemma_configs',
    token=os.getenv('HF_TOKEN'),
    allow_patterns=[
        'config.json',
        'tokenizer.model',
        'tokenizer_config.json',
        'special_tokens_map.json',
        'added_tokens.json',
        'model*.safetensors',
    ],
)
" 2>>"$LOG" && ok "Gemma text encoder downloaded" || \
        fail "Failed to download $GEMMA_REPO. Set HF_TOKEN and accept the Gemma license at https://huggingface.co/$GEMMA_REPO, then restart the pod."
fi

if [ ! -f "models/gemma_configs/tokenizer.model" ]; then
    fail "Gemma download is incomplete: models/gemma_configs/tokenizer.model is missing"
fi
if ! compgen -G "models/gemma_configs/model*.safetensors" > /dev/null; then
    fail "Gemma download is incomplete: no model*.safetensors files were found"
fi
ok "Gemma text encoder files verified"

# Spatial upscaler from Lightricks
if [ ! -f "models/latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.1.safetensors" ]; then
    log "Downloading spatial upscaler..."
    "$PYTHON" -c "
from huggingface_hub import hf_hub_download
import os
os.makedirs('models/latent_upscale_models', exist_ok=True)
token = os.getenv('HF_TOKEN')
path = hf_hub_download('Lightricks/LTX-2.3',
    'ltx-2.3-spatial-upscaler-x2-1.1.safetensors', local_dir='models/latent_upscale_models', local_dir_use_symlinks=False, token=token)
" 2>>"$LOG" && ok "Upscaler downloaded" || warn "Upscaler download failed (optional)"
fi

# ─── 6. Write FastAPI server ───────────────────────────────────────────────────
log "Writing server.py..."
cat > "$REPO_DIR/server.py" << 'PYEOF'
"""
VHS Restorer — Gradio Web UI for RunPod
Provides an interactive, modern web interface to upload, restore, and download VHS videos.
Supports auto-resolution detection and segment-based processing for long videos.
"""

import os
import sys
import inspect
import uuid
import time
import subprocess
import json
import shutil
from pathlib import Path
import gradio as gr

REPO = Path(__file__).parent
INPUTS  = REPO / "inputs"
OUTPUTS = REPO / "outputs"
PORT = int(os.getenv("PORT", "8000"))
MAX_UPLOAD_SIZE = os.getenv("MAX_UPLOAD_SIZE", "50gb")
VIDEO_EXTENSIONS = [
    ".mp4", ".mkv", ".mov", ".avi", ".webm", ".m4v", ".wmv",
    ".mpg", ".mpeg", ".mts", ".m2ts", ".ts", ".vob", ".flv",
    ".3gp", ".ogv",
]
INPUTS.mkdir(exist_ok=True)
OUTPUTS.mkdir(exist_ok=True)

LORA_MAP = {
    "restoration": "models/loras/ltx2.3-train/ltx2.3-video-restoration-general.safetensors",
    "hd":          "models/loras/ltx2.3-train/ltx2.3-ic-video-upscale-general.safetensors",
    "both":        None,
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

def uploaded_path(value):
    """Return a filesystem path from Gradio's filepath/FileData variants."""
    if not value:
        return None
    if isinstance(value, (str, os.PathLike)):
        return str(value)
    if isinstance(value, dict):
        return value.get("path") or value.get("name")
    return getattr(value, "path", None) or getattr(value, "name", None)


def probe_video(video_path):
    video_path = uploaded_path(video_path)
    if not video_path:
        return 512, 352, 24.0, "Ready. Upload a video to begin."
    try:
        import subprocess, json
        cmd = [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height,r_frame_rate",
            "-of", "json", video_path
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if res.returncode == 0:
            info = json.loads(res.stdout)
            if "streams" in info and len(info["streams"]) > 0:
                stream = info["streams"][0]
                w = stream.get("width")
                h = stream.get("height")
                fps_raw = stream.get("r_frame_rate", "24/1")
                
                # Round to nearest multiple of 16 (good for LTX models)
                w_rounded = max(256, min(1024, round(w / 16) * 16))
                h_rounded = max(256, min(1024, round(h / 16) * 16))
                
                fps = 24.0
                if "/" in fps_raw:
                    num, den = map(int, fps_raw.split("/"))
                    if den > 0:
                        fps = round(num / den, 2)
                
                status_text = f"Probed video: {w}x{h} ({fps} FPS). Set target resolution to {w_rounded}x{h_rounded}."
                return h_rounded, w_rounded, fps, status_text
    except Exception as e:
        return 512, 352, 24.0, f"Failed to probe video: {str(e)}"
    return 512, 352, 24.0, "Ready."

def process_video_web(video_path, mode, height, width, num_frames, fps, seed, auto_split):
    video_path = uploaded_path(video_path)
    if not video_path:
        yield "Error", "Please upload a video file first.", None
        return
        
    job_id = str(uuid.uuid4())[:12]
    job_dir = OUTPUTS / job_id
    job_dir.mkdir(exist_ok=True)
    
    in_path = Path(video_path)
    log_lines = []
    
    def log_and_yield(status_text, new_log=None):
        if new_log:
            log_lines.append(f"[{time.strftime('%H:%M:%S')}] {new_log}")
        trimmed_logs = "\n".join(log_lines[-100:])
        return status_text, trimmed_logs

    def emit(status_text, new_log=None, video=None):
        status, logs = log_and_yield(status_text, new_log)
        return status, logs, video
        
    yield emit("Initializing job...", f"Starting job {job_id}")
    yield emit("Initializing job...", f"Mode: {mode} | Resolution: {width}x{height} | Frames: {num_frames} | FPS: {fps} | Seed: {seed}")
    
    # 1. Get duration
    duration = 0.0
    try:
        cmd = [
            "ffprobe", "-v", "error", "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", str(in_path)
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        duration = float(res.stdout.strip())
        yield emit("Initializing job...", f"Input video duration: {duration:.2f} seconds")
    except Exception as e:
        yield emit("Initializing job...", f"Warning: failed to get duration: {e}")
        
    segment_duration = num_frames / fps
    should_split = auto_split and duration > (segment_duration * 1.1)
    chunks_to_process = []

    def preprocess_video(source_path, output_path, label, keyframe_interval=None):
        yield emit(label, f"Resizing and formatting {source_path.name}...")

        base_cmd = [
            "ffmpeg", "-y", "-i", str(source_path),
            "-vf", f"scale={width}:{height}",
            "-r", str(fps),
        ]
        keyframe_args = []
        if keyframe_interval:
            keyframe_args = [
                "-force_key_frames", f"expr:gte(t,n_forced*{keyframe_interval:.6f})",
                "-g", str(max(1, int(round(fps * keyframe_interval)))),
                "-keyint_min", str(max(1, int(round(fps * keyframe_interval)))),
            ]
        nvenc_cmd = base_cmd + keyframe_args + ["-c:v", "h264_nvenc", "-preset", "p4", "-an", str(output_path)]
        cpu_cmd = base_cmd + keyframe_args + ["-c:v", "libx264", "-crf", "18", "-preset", "veryfast", "-an", str(output_path)]

        res_pre = subprocess.run(nvenc_cmd, capture_output=True, text=True)
        if res_pre.returncode != 0:
            log_lines.append("NVENC preprocessing failed; retrying with libx264.")
            res_pre = subprocess.run(cpu_cmd, capture_output=True, text=True)

        if res_pre.returncode != 0 or not output_path.exists():
            yield emit("Error", f"Failed to preprocess {source_path.name}:\n{res_pre.stderr}")
            return False
        return True
    
    if should_split:
        normalized_path = job_dir / "normalized_full.mp4"
        ok_preprocess = yield from preprocess_video(
            in_path,
            normalized_path,
            "Preprocessing video before split...",
            segment_duration
        )
        if not ok_preprocess:
            return

        yield emit("Splitting video into chunks...", f"Video is longer than {segment_duration:.1f}s. Splitting normalized input into ~{segment_duration:.1f}s chunks...")
        
        split_cmd = [
            "ffmpeg", "-y", "-i", str(normalized_path),
            "-f", "segment", "-segment_time", str(segment_duration),
            "-c", "copy", "-reset_timestamps", "1",
            "-map", "0:v:0", str(job_dir / "chunk_%03d.mp4")
        ]
        res = subprocess.run(split_cmd, capture_output=True, text=True)
        if res.returncode != 0:
            yield emit("Error", f"Failed to split video:\n{res.stderr}")
            return
            
        chunks = sorted(job_dir.glob("chunk_*.mp4"))
        if not chunks:
            yield emit("Error", "Failed to split video: ffmpeg produced no chunks.")
            return
        yield emit("Splitting video into chunks...", f"Successfully split video into {len(chunks)} chunks.")
        
        for idx, chunk in enumerate(chunks):
            chunks_to_process.append((chunk, job_dir / f"restored_{chunk.name}", idx))
    else:
        # Preprocess full video directly
        pre_path = job_dir / "pre_full.mp4"
        ok_preprocess = yield from preprocess_video(in_path, pre_path, "Preprocessing video...")
        if not ok_preprocess:
            return
            
        chunks_to_process.append((pre_path, job_dir / "restored_full.mp4", 0))

    # Helper to run a pipeline stage
    def run_stage(mode_name, input_file, output_file, cur_height, cur_width, chunk_idx, total_chunks, stage_name):
        lora = LORA_MAP[mode_name]
        prompt = PROMPT_MAP[mode_name]
        env = {**os.environ, "PYTORCH_CUDA_ALLOC_CONF": "expandable_segments:True"}
        
        cmd = [
            sys.executable, "run_pipeline.py",
            "--mode", mode_name,
            "--video", str(input_file),
            "--prompt", prompt,
            "--output", str(output_file),
            "--height", str(cur_height),
            "--width",  str(cur_width),
            "--num-frames", str(num_frames),
            "--fps", str(fps),
            "--seed", str(seed),
            "--sigma-profile", "workflow",
            "--streaming-prefetch-count", "2",
            "--model-checkpoint", "models/checkpoints/ltx-2.3-edit-insight-dev-fp8.safetensors",
            "--lora", lora if lora else "",
        ]
        
        prefix = f"[{stage_name}] "
        if total_chunks > 1:
            prefix += f"[Chunk {chunk_idx+1}/{total_chunks}] "
            
        proc = subprocess.Popen(
            cmd, cwd=str(REPO), env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1
        )
        
        for line in proc.stdout:
            line = line.rstrip()
            if line:
                log_lines.append(f"{prefix}{line}")
            if "step" in line.lower() or "loading" in line.lower():
                yield emit(f"Processing... {prefix}{line.strip()[:60]}...")
        proc.wait()
        return proc.returncode

    total_chunks = len(chunks_to_process)
    for chunk_in, chunk_out, idx in chunks_to_process:
        if mode == "both":
            # Stage 1: restoration
            yield emit(f"Restoring chunk {idx+1}/{total_chunks}...", f"Starting Restoration for chunk {idx+1}...")
            temp_restored = job_dir / f"temp_restored_{idx}.mp4"
            rc = yield from run_stage("restoration", chunk_in, temp_restored, height, width, idx, total_chunks, "RESTORE")
            if rc != 0:
                yield emit("Error", "Restoration stage failed. Check logs below.")
                return
                
            # Stage 2: HD upscale
            yield emit(f"Upscaling chunk {idx+1}/{total_chunks}...", f"Starting HD Upscale for chunk {idx+1}...")
            rc = yield from run_stage("hd", temp_restored, chunk_out, height * 2, width * 2, idx, total_chunks, "UPSCALE")
            if rc != 0:
                yield emit("Error", "HD upscale stage failed. Check logs below.")
                return
            temp_restored.unlink(missing_ok=True)
        else:
            yield emit(f"Processing chunk {idx+1}/{total_chunks}...", f"Starting {mode} for chunk {idx+1}...")
            target_h = height * 2 if mode == "hd" else height
            target_w = width * 2 if mode == "hd" else width
            rc = yield from run_stage(mode, chunk_in, chunk_out, target_h, target_w, idx, total_chunks, mode.upper())
            if rc != 0:
                yield emit("Error", f"Processing stage {mode} failed. Check logs below.")
                return

    # 3. Merge chunks if split
    final_output = job_dir / f"restored_{job_id}.mp4"
    if should_split:
        yield emit("Merging restored chunks...", "Combining restored video segments...")
        list_file = job_dir / "merge_list.txt"
        with open(list_file, "w") as f:
            for _, chunk_out, _ in chunks_to_process:
                f.write(f"file '{chunk_out.name}'\n")
                
        merge_cmd = [
            "ffmpeg", "-y", "-f", "concat", "-safe", "0",
            "-i", str(list_file), "-c", "copy", str(final_output)
        ]
        res = subprocess.run(merge_cmd, capture_output=True, text=True)
        if res.returncode != 0:
            yield emit("Error", f"Failed to merge chunks:\n{res.stderr}")
            return
        yield emit("Merging complete!", "Successfully merged all video chunks.")
    else:
        shutil.move(str(chunks_to_process[0][1]), str(final_output))

    # Cleanup intermediate files
    for chunk_in, chunk_out, _ in chunks_to_process:
        chunk_in.unlink(missing_ok=True)
        if should_split:
            chunk_out.unlink(missing_ok=True)
            
    yield emit("Done!", "Video processing complete! Download the result below.", str(final_output))


# ─── Gradio UI Design ─────────────────────────────────────────────────────────

theme = gr.themes.Soft(
    primary_hue="violet",
    secondary_hue="indigo",
    neutral_hue="slate",
).set(
    body_background_fill="*neutral_950",
    block_background_fill="*neutral_900",
    block_border_width="1px",
    block_border_color="*neutral_800",
    button_primary_background_fill="*primary_600",
    button_primary_background_fill_hover="*primary_500",
)

css = """
.gradio-container {
    max-width: 1200px !important;
    margin: 0 auto !important;
}
.header-box {
    text-align: center;
    padding: 20px 0;
    margin-bottom: 20px;
    background: linear-gradient(135deg, rgba(124, 111, 247, 0.1) 0%, rgba(90, 84, 196, 0.05) 100%);
    border: 1px solid rgba(124, 111, 247, 0.2);
    border-radius: 12px;
}
.header-box h1 {
    font-size: 28px !important;
    font-weight: 800 !important;
    color: #ffffff !important;
    margin-bottom: 5px !important;
    background: linear-gradient(90deg, #7c6ff7, #3ecf8e);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
}
.header-box p {
    color: #9a9ba8 !important;
    font-size: 14px !important;
}
"""

with gr.Blocks(theme=theme, css=css) as demo:
    gr.HTML("""
    <div class="header-box">
        <h1>VHS Restorer</h1>
        <p>AI-powered video restoration and upscaling using LTX2.3-ICEdit-Insight</p>
    </div>
    """)
    
    with gr.Row():
        with gr.Column(scale=1):
            gr.Markdown("### 🛠 Input & Settings")
            input_video = gr.File(
                label=f"Upload Video (up to {MAX_UPLOAD_SIZE})",
                file_types=VIDEO_EXTENSIONS,
                type="filepath",
            )
            
            mode = gr.Dropdown(
                label="Restoration Mode",
                choices=[
                    ("VHS Restoration (Artifact removal)", "restoration"),
                    ("HD Upscale only (x2 Resolution)", "hd"),
                    ("Both (VHS Restore then HD Upscale)", "both")
                ],
                value="both"
            )
            
            with gr.Row():
                width_spin = gr.Number(label="Target Width", value=352, precision=0)
                height_spin = gr.Number(label="Target Height", value=512, precision=0)
                
            with gr.Row():
                frames_combo = gr.Dropdown(
                    label="Frames (8k+1 Chunk Size)",
                    choices=[("25 (~1s)", 25), ("49 (~2s)", 49), ("97 (~4s)", 97), ("145 (~6s)", 145), ("217 (~9s)", 217)],
                    value=97
                )
                fps_spin = gr.Number(label="FPS", value=24.0)
                
            with gr.Row():
                seed_spin = gr.Number(label="Seed", value=42, precision=0)
                random_seed = gr.Checkbox(label="Randomize Seed", value=False)
                
            auto_split = gr.Checkbox(label="Auto-split long videos (4s chunks)", value=True)
            
            btn_start = gr.Button("▶ Start Processing", variant="primary")
            btn_cancel = gr.Button("🛑 Cancel Job", variant="secondary")
            
        with gr.Column(scale=1):
            gr.Markdown("### 📊 Status & Output")
            status_text = gr.Textbox(label="Current Status", value="Ready. Upload a video to begin.", interactive=False)
            
            output_video = gr.Video(label="Restored Video Output", interactive=False)
            
            log_output = gr.Textbox(
                label="Server Live Logs",
                value="",
                lines=15,
                max_lines=20,
                interactive=False
            )

    # Event handlers
    # Probe video on change
    input_video.change(
        fn=probe_video,
        inputs=[input_video],
        outputs=[height_spin, width_spin, fps_spin, status_text]
    )
    
    # Run processing
    def adjust_seed_and_run(video, mode_val, h, w, frames, fps_val, seed_val, rand_seed, split_val):
        s = seed_val
        if rand_seed:
            import random
            s = random.randint(0, 99999)
        yield from process_video_web(video, mode_val, int(h), int(w), int(frames), float(fps_val), int(s), split_val)
        
    click_event = btn_start.click(
        fn=adjust_seed_and_run,
        inputs=[input_video, mode, height_spin, width_spin, frames_combo, fps_spin, seed_spin, random_seed, auto_split],
        outputs=[status_text, log_output, output_video]
    )
    
    btn_cancel.click(fn=None, inputs=None, outputs=None, cancels=[click_event])

if __name__ == "__main__":
    launch_kwargs = {
        "server_name": "0.0.0.0",
        "server_port": PORT,
        "share": False,
    }
    if "max_file_size" in inspect.signature(demo.launch).parameters:
        launch_kwargs["max_file_size"] = MAX_UPLOAD_SIZE
    demo.queue().launch(**launch_kwargs)
PYEOF

ok "server.py written"

# ─── 7. Start server ──────────────────────────────────────────────────────────
log "Starting FastAPI server on port $PORT..."
cd "$REPO_DIR"

# Kill existing server if running
if [ -f "$WORKSPACE/server.pid" ]; then
    OLD_PID="$(cat "$WORKSPACE/server.pid" 2>/dev/null || true)"
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        log "Stopping existing server PID=$OLD_PID..."
        kill "$OLD_PID" 2>/dev/null || true
    fi
fi
pkill -f "python[0-9.]* server.py" 2>/dev/null || true
pkill -f "uvicorn server:app" 2>/dev/null || true
sleep 1

MAX_UPLOAD_SIZE="${MAX_UPLOAD_SIZE:-50gb}" PORT="$PORT" nohup "$PYTHON" server.py > "$WORKSPACE/server.log" 2>&1 &
SERVER_PID=$!
echo $SERVER_PID > "$WORKSPACE/server.pid"

# Wait for server to come up
for i in $(seq 1 30); do
    sleep 2
    if curl -sf "http://localhost:$PORT/" > /dev/null 2>&1; then
        ok "Server is UP! PID=$SERVER_PID  Port=$PORT"
        log "Gradio Web UI is active and ready."
        echo ""
        echo "=========================================="
        echo " Server ready at: http://localhost:$PORT"
        # Keep container alive and stream server logs to RunPod stdout
        tail -f "$WORKSPACE/server.log"
    fi
    log "Waiting for server... ($i/30)"
done

fail "Server did not start in 60s — check $WORKSPACE/server.log"
