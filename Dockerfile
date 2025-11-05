# Dockerfile
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Tokyo

WORKDIR /opt

# Ubuntuミラー最適化（任意） + CUDAのaptエントリ無効化
RUN sed -i \
  -e 's|http://archive.ubuntu.com/ubuntu|https://jp.archive.ubuntu.com/ubuntu|g' \
  -e 's|http://security.ubuntu.com/ubuntu|https://jp.archive.ubuntu.com/ubuntu|g' \
  /etc/apt/sources.list \
 && sed -i 's|^deb |# deb |' /etc/apt/sources.list.d/cuda*.list || true

# 基本ツール & Python & 開発ヘッダ類
RUN apt-get update && apt-get install -y --no-install-recommends \
    git git-lfs build-essential cmake ca-certificates curl tzdata jq \
    python3 python3-pip python3-venv \
    libopenblas-dev pkg-config libcurl4-openssl-dev zlib1g-dev \
    ccache \
 && rm -rf /var/lib/apt/lists/* \
 && git lfs install \
 && python3 -m pip install --no-cache-dir --upgrade pip

# llama.cpp と Python パッケージ（JupyterLab含む）
RUN git clone --depth 1 https://github.com/ggml-org/llama.cpp /opt/llama.cpp \
 && python3 -m pip install --no-cache-dir -r /opt/llama.cpp/requirements.txt \
 && python3 -m pip install --no-cache-dir \
      jupyterlab ipywidgets jupyterlab-lsp "python-lsp-server[all]" huggingface_hub

# HF 変換用の最低限（互換性のある組み合わせ：transformers が tokenizers を引き込みます）
RUN python3 -m pip install --no-cache-dir \
      "transformers==4.46.3" \
      "sentencepiece==0.2.0" "safetensors==0.4.5" "numpy==2.1.3"

# 作業ディレクトリ & ccache
RUN mkdir -p /workspace/hf /workspace/out /workspace/notebooks /models /ccache
ENV HF_HOME=/workspace/hf/.cache
ENV CCACHE_DIR=/ccache CCACHE_MAXSIZE=10G

# ---- llama.cpp を CUDA でビルド（T4=sm_75）----
ARG CUDA_ARCHS=75

# リンク時のみ CUDA stub を見せ、終了時に片付け
RUN set -eux; \
    CUDA_STUBS=/usr/local/cuda/targets/x86_64-linux/lib/stubs; \
    ln -sf "${CUDA_STUBS}/libcuda.so" "${CUDA_STUBS}/libcuda.so.1"; \
    echo "${CUDA_STUBS}" > /etc/ld.so.conf.d/zz-cuda-stubs.conf; ldconfig; \
    cmake -S /opt/llama.cpp -B /opt/llama.cpp/build \
      -DGGML_CUDA=ON \
      -DGGML_CUDA_ARCHITECTURES=${CUDA_ARCHS} \
      -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS \
      -DLLAMA_CURL=ON \
      -DLLAMA_BUILD_EXAMPLES=OFF \
      -DLLAMA_BUILD_TESTS=OFF \
      -DLLAMA_BUILD_SERVER=ON \
      -DLLAMA_BUILD_TOOLS=ON \
      -DGGML_CCACHE=ON \
      -DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath-link,${CUDA_STUBS}" \
    && cmake --build /opt/llama.cpp/build -j \
    && rm -f /etc/ld.so.conf.d/zz-cuda-stubs.conf \
    && ldconfig \
    && rm -f "${CUDA_STUBS}/libcuda.so.1"

# llama.cpp のバイナリを PATH へ
ENV PATH="/opt/llama.cpp/build/bin:${PATH}"

# ★ 追加：ワンコマンド変換・量子化ヘルパ（heredoc は 2 つの RUN に分ける）
RUN cat >/usr/local/bin/ggufify <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 1 ]]; then
  echo "Usage: ggufify <hf_repo_or_path> [out_dir=/workspace/out] [outtype=f16] [qtype=Q5_K_M]" >&2
  exit 1
fi
MODEL="$1"
OUT_DIR="${2:-/workspace/out}"
OUTTYPE="${3:-f16}"
QTYPE="${4:-Q5_K_M}"

mkdir -p "$OUT_DIR" /workspace/hf

python3 /opt/llama.cpp/convert_hf_to_gguf.py \
  --model "$MODEL" \
  --outtype "$OUTTYPE" \
  --outfile "${OUT_DIR}/model-${OUTTYPE}.gguf"

llama-quantize \
  "${OUT_DIR}/model-${OUTTYPE}.gguf" \
  "${OUT_DIR}/model-${QTYPE}.gguf" \
  "$QTYPE"

ls -lh "${OUT_DIR}"/*.gguf
EOS
RUN chmod +x /usr/local/bin/ggufify

# ★ 追加：Jupyter をトークン必須で起動するスクリプト（同じく素直な heredoc）
RUN cat >/usr/local/bin/start-jupyter <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

: "${JUPYTER_PORT:=8888}"
: "${JUPYTER_ROOT_DIR:=/workspace/notebooks}"

if [[ -z "${JUPYTER_TOKEN:-}" ]]; then
  echo "ERROR: JUPYTER_TOKEN is not set (.env で設定してください)" >&2
  exit 1
fi

mkdir -p "$JUPYTER_ROOT_DIR"

exec jupyter lab \
  --no-browser \
  --ServerApp.ip=0.0.0.0 \
  --ServerApp.port="${JUPYTER_PORT}" \
  --ServerApp.root_dir="${JUPYTER_ROOT_DIR}" \
  --IdentityProvider.token="${JUPYTER_TOKEN}" \
  --ServerApp.disable_check_xsrf=True \
  --allow-root
EOS
RUN chmod +x /usr/local/bin/start-jupyter

# ポート
EXPOSE 8888 8000

# 既定動作：Jupyter 起動（compose 側で上書き可）
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/start-jupyter"]