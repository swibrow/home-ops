#!/bin/sh
# Stage Wan 2.2 TI2V-5B and Qwen-Image 2.1 into the models PVC. Idempotent: each
# file is skipped if already present, so this only pays the ~35GB download once
# per empty volume. Downloads to a .part file and renames, so an interrupted pull
# is not mistaken for a complete one on the next start.
set -eu

WAN="https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files"
QWEN_IMAGE="https://huggingface.co/abenzerps/Qwen-Image-2.1-Uncensored-GGUF/resolve/main"

fetch() {
    dir="$1"
    file="$2"
    url="$3"
    mkdir -p "/models/${dir}"
    if [ -f "/models/${dir}/${file}" ]; then
        echo "have ${dir}/${file}"
        return 0
    fi
    echo "fetching ${dir}/${file}"
    curl -fL --retry 5 --retry-delay 10 --retry-connrefused \
        -o "/models/${dir}/${file}.part" \
        "${url}"
    mv "/models/${dir}/${file}.part" "/models/${dir}/${file}"
}

# ComfyUI's WanVideoLoader reads from diffusion_models/, not checkpoints/.
fetch diffusion_models wan2.2_ti2v_5B_fp16.safetensors "${WAN}/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors"
fetch vae wan2.2_vae.safetensors "${WAN}/vae/wan2.2_vae.safetensors"
# fp8 encoder over the fp16: 6.7GB vs 11.4GB, and the 3090 Ti has no FP8 tensor
# cores either way, so the only thing the larger file buys is VRAM pressure.
fetch text_encoders umt5_xxl_fp8_e4m3fn_scaled.safetensors "${WAN}/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"

# Loaded with the ComfyUI-GGUF "Unet Loader (GGUF)" node. Q8_0 fits the 24GB
# card with room to spare; the int8 encoder runs in system RAM, under the pod's
# 24Gi limit where the 17.5GB bf16 one would not leave enough headroom.
fetch diffusion_models qwen-image-2.1-UC-Q8_0.gguf "${QWEN_IMAGE}/qwen-image-2.1-UC-Q8_0.gguf"
fetch text_encoders qwen3vl_8b_int8_convrot.safetensors "${QWEN_IMAGE}/text_encoders/qwen3vl_8b_int8_convrot.safetensors"
fetch vae qwen_image_2.1_vae_bf16.safetensors "${QWEN_IMAGE}/vae/qwen_image_2.1_vae_bf16.safetensors"

echo "models staged"
