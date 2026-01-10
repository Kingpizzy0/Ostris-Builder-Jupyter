#!/bin/bash

# Exit on error
set -e

echo "=== Starting Jupyter Toolkit Lab Services ==="

# Configuration
JUPYTER_PORT=${JUPYTER_PORT:-8888}
AI_TOOLKIT_PORT=${AI_TOOLKIT_PORT:-8675}
COMFYUI_PORT=${COMFYUI_PORT:-8188}
LOG_DIR="/var/log"

# Create log directory
mkdir -p "$LOG_DIR"

# 1. Set up Jupyter Lab
echo "[INFO] Configuring Jupyter Lab on port $JUPYTER_PORT..."

# Create .jupyter directory if it doesn't exist
mkdir -p ~/.jupyter

# Generate config if not exists
if [ ! -f ~/.jupyter/jupyter_lab_config.py ]; then
    jupyter lab --generate-config
fi

# Set the password (hashed) and configuration
cat >> ~/.jupyter/jupyter_lab_config.py << EOF
c.ServerApp.token = ''
c.ServerApp.password = ''
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.allow_origin = '*'
c.ServerApp.open_browser = False
c.ServerApp.port = $JUPYTER_PORT
c.ServerApp.allow_root = True
EOF

# Start Jupyter Lab in the background
echo "[INFO] Starting Jupyter Lab..."
nohup jupyter lab --config ~/.jupyter/jupyter_lab_config.py > "$LOG_DIR/jupyter.log" 2>&1 &
JUPYTER_PID=$!

# Verify Jupyter started
sleep 3
if ps -p $JUPYTER_PID > /dev/null; then
    echo "[OK] Jupyter Lab started successfully on port $JUPYTER_PORT"
    echo "      Logs: $LOG_DIR/jupyter.log"
    echo "      Access: No password required"
else
    echo "[ERROR] Jupyter Lab failed to start. Check logs at $LOG_DIR/jupyter.log"
    cat "$LOG_DIR/jupyter.log"
    exit 1
fi

# 2. Download Z-Image Turbo models if not present
echo "[INFO] Checking for Z-Image Turbo models..."
cd /app/ComfyUI

DIFFUSION_MODEL="models/diffusion_models/z_image_turbo_bf16.safetensors"
TEXT_ENCODER="models/text_encoders/qwen_3_4b.safetensors"
VAE_MODEL="models/vae/ae.safetensors"

download_model() {
    local url=$1
    local output=$2
    local name=$3
    
    if [ ! -f "$output" ]; then
        echo "[INFO] Downloading $name..."
        wget -c "$url" -O "$output"
        if [ $? -eq 0 ]; then
            echo "[OK] $name downloaded successfully"
        else
            echo "[ERROR] Failed to download $name"
            return 1
        fi
    else
        echo "[OK] $name already exists, skipping download"
    fi
}

# Download models if missing
download_model \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors" \
    "$DIFFUSION_MODEL" \
    "Z-Image Turbo Diffusion Model"

download_model \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors" \
    "$TEXT_ENCODER" \
    "Z-Image Turbo Text Encoder"

download_model \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors" \
    "$VAE_MODEL" \
    "Z-Image Turbo VAE"

echo "[OK] All Z-Image Turbo models ready"

# 3. Start ComfyUI
echo "[INFO] Starting ComfyUI on port $COMFYUI_PORT..."
cd /app/ComfyUI

nohup python main.py --listen 0.0.0.0 --port "$COMFYUI_PORT" > "$LOG_DIR/comfyui.log" 2>&1 &
COMFYUI_PID=$!

# Verify ComfyUI started
sleep 5
if ps -p $COMFYUI_PID > /dev/null; then
    echo "[OK] ComfyUI started successfully on port $COMFYUI_PORT"
    echo "      Logs: $LOG_DIR/comfyui.log"
else
    echo "[ERROR] ComfyUI failed to start. Check logs at $LOG_DIR/comfyui.log"
    cat "$LOG_DIR/comfyui.log"
    exit 1
fi

# 4. Start Ostris AI Toolkit UI
echo "[INFO] Starting AI Toolkit UI on port $AI_TOOLKIT_PORT..."
cd /app/ai-toolkit/ui

# Start the UI server in foreground (keeps container running)
echo "[OK] Launching AI Toolkit UI..."

# Error handling for npm start
if ! exec npm run start -- --host 0.0.0.0 --port "$AI_TOOLKIT_PORT"; then
    echo "[ERROR] AI Toolkit UI failed to start"
    exit 1
fi
