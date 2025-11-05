# gguf-lab-gpu — 配布用コンテナ & ノートブック

CUDA 対応 GPU 環境で **Hugging Face の Transformers モデル → GGUF 変換 & 量子化（llama.cpp）** を手早く行うための配布一式です。
JupyterLab が同梱されており、GUI で操作できます。

> 既定は **NVIDIA T4 (Compute 7.5)** を想定しています。他 GPU の場合はビルド時に `CUDA_ARCHS` を変更してください。

---

## 同梱物

```
Dockerfile                  # CUDA12.4/Ubuntu22.04, llama.cpp を CUDA ビルド、Jupyter 付き
compose.yaml                # GPU パススルー & /workspace マウント、Jupyter の起動設定
.env.example                # 環境変数サンプル（JUPYTER_TOKEN 等）
workspace/                  # ホスト側の作業ディレクトリ（/workspace にマウント）
README.md                   # このファイル
```

作業ディレクトリのマウント：`./workspace`（ホスト） ←→ `/workspace`（コンテナ）  
出力ファイルは `/workspace/out/*.gguf` に生成されます。（ホスト側では `work/out/` に出力）

---

## 前提条件

- NVIDIA GPU + ドライバ
- **NVIDIA Container Toolkit**（`--gpus all` が使えること）
- Docker / Podman（Docker 互換 CLI）
- ネットワーク接続（Hugging Face モデルを取得する場合）

---

## 使い方（クイックスタート）

1. `.env.example` を `.env` にコピーして編集します。最低限 **`JUPYTER_TOKEN`** を任意の値に設定してください。

2. ビルド & 起動
>Buildには長時間かかります...30分くらい...?
```bash
docker compose build          # 他 GPU は: docker compose build --build-arg CUDA_ARCHS=86
docker compose up -d
```

3. ブラウザで `https://<ホストIP>:8888` を開き、`.env` の `JUPYTER_TOKEN` でログインします。

4. JupyterLab の **`notebooks/GGUF_Convert_Quantize.ipynb`** を開き、上から順に実行します。  
   - **ダウンロード中はスピナー表示**、**書き出しは進捗バー表示**で視認性を確保しています。
   - 実行コマンド（`convert_hf_to_gguf.py` / `llama-quantize`）はセル内に **RUN:** として表示します。
---

## よくある質問 / トラブルシュート

### 1) もう一度ダウンロードからやり直したい
Hugging Face のキャッシュと出力 GGUF を削除します。  
- キャッシュ: `/workspace/hf/.cache/hub/models--<org>--<repo>/`  
- 出力: `/workspace/out/*.gguf`

```bash
# 例: 生成物だけ削除して再出力
rm -f workspace/out/*.gguf
# 例: そのリポジトリのキャッシュも削除（必要なときだけ）
rm -rf workspace/hf/.cache/hub/models--sbintuitions--sarashina2.2-3b-instruct-v0.1
```

### 2) VRAM 不足や生成が途中で止まる
- 生成時のコンテキスト長（`-c`）、バッチ（`-b`）を小さくする
- **Flash-Attn が自動で無効**になる GPU があります（ログ出力に表示）。その場合は性能が下がるため生成トークン数を控えめに。

### 3) 長い回答が途中で切れる
- 生成コマンドに `-n`（最大生成トークン数）を指定してください。ノートブックでは `-n 512` などの例を付けています。
- Jupyter のレンダリング都合で途中省略される場合は、セル末尾の表示制御（HTML の `<div>`）で全文表示するよう調整済みです。

---


## 注意

- **Jupyter は必ずトークン必須**（`.env` の `JUPYTER_TOKEN`）で起動します。
- `work/` 以下はホストと共有されるため、機密データを置く場合は権限に注意してください。

---
