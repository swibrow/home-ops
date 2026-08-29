#!/bin/sh
# Stage Wan 2.2 TI2V-5B into the models PVC. Idempotent: each file is skipped if
# already present, so this only pays the ~18GB download once per empty volume.
# Downloads to a .part file and renames, so an interrupted pull is not mistaken
# for a complete one on the next start.
set -eu

REPO="https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files"

fetch() {
    dir="$1"
    file="$2"
    mkdir -p "/models/${dir}"
    if [ -f "/models/${dir}/${file}" ]; then
        echo "have ${dir}/${file}"
        return 0
    fi
    echo "fetching ${dir}/${file}"
    curl -fL --retry 5 --retry-delay 10 --retry-connrefused \
        -o "/models/${dir}/${file}.part" \
        "${REPO}/${dir}/${file}"
    mv "/models/${dir}/${file}.part" "/models/${dir}/${file}"
}

# ComfyUI's WanVideoLoader reads from diffusion_models/, not checkpoints/.
fetch diffusion_models wan2.2_ti2v_5B_fp16.safetensors
fetch vae wan2.2_vae.safetensors
# fp8 encoder over the fp16: 6.7GB vs 11.4GB, and the 3090 Ti has no FP8 tensor
# cores either way, so the only thing the larger file buys is VRAM pressure.
fetch text_encoders umt5_xxl_fp8_e4m3fn_scaled.safetensors

echo "wan 2.2 ti2v-5b staged"
