# syntax=docker/dockerfile:1
# Upstream publishes no image. Built from a pinned commit of main: the PyPI
# 0.1.0 release predates strands-decider-2B-qwen3.5-v1-2610.
FROM docker.io/library/python:3.14-slim

ARG STRANDS_DECIDER_VERSION=0ac22a97e584f3ccf87cc9b8cc5fdbad57cdf534

ENV PYTHONUNBUFFERED=1 HF_HOME=/cache

# Triton (flash-linear-attention's Gated DeltaNet kernels) compiles its launcher
# with gcc on the first request.
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

# cu126 wheels bundle the CUDA runtime; the driver comes from the DRA claim.
RUN pip install --no-cache-dir torch==2.7.1 --index-url https://download.pytorch.org/whl/cu126 \
    && pip install --no-cache-dir \
        "strands-decider[cuda] @ https://github.com/strands-labs/strands-decider/archive/${STRANDS_DECIDER_VERSION}.tar.gz"

RUN useradd --uid 1000 --create-home decider && mkdir /cache && chown decider /cache
USER 1000

EXPOSE 8000
ENTRYPOINT ["strands-decider"]
