set -eo pipefail
# Ascend setup scripts read unset shell variables; enable nounset afterwards.
for f in /usr/local/Ascend/ascend-toolkit/set_env.sh /usr/local/Ascend/nnal/atb/set_env.sh; do
  [ ! -f "$f" ] || source "$f"
done
set -u
echo "--- Base runtime ---"
python3 - <<'PY'
import platform, torch, torch_npu
print("python", platform.python_version(), "torch", torch.__version__, "torch_npu", torch_npu.__version__, flush=True)
PY

echo "--- Install LLaMA Factory runtime dependencies ---"
python3 -m pip install --disable-pip-version-check --prefix=/workspace/runtime-py \
  --index-url https://pypi.tuna.tsinghua.edu.cn/simple \
  'llamafactory[metrics,modelscope]==0.9.4' \
  'transformers<=4.51.1' 'tokenizers>=0.21.1'
export PYTHONPATH="/workspace/runtime-py/lib/python$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')/site-packages:${PYTHONPATH:-}"
export PATH="/workspace/runtime-py/bin:${PATH}"
python3 - <<'PY'
import torch, torch_npu, transformers
import llamafactory
print("installed LLaMA Factory", getattr(llamafactory, "__version__", "imported"), "transformers", transformers.__version__, flush=True)
torch.npu.set_device("npu:0")
probe = torch.ones((16, 16), device="npu:0")
print("NPU preflight matmul", tuple((probe @ probe).shape), flush=True)
PY

mkdir -p /workspace/tiny-qwen2 /workspace/data
python3 - <<'PY'
import json
from tokenizers import ByteLevelBPETokenizer
from transformers import GPT2TokenizerFast, Qwen2Config, Qwen2ForCausalLM

path = "/workspace/tiny-qwen2"
bpe = ByteLevelBPETokenizer()
bpe.train_from_iterator(
    ["hello world", "A5 NPU training smoke", "tiny synthetic instruction data"],
    vocab_size=512, min_frequency=1,
    special_tokens=["<pad>", "<s>", "</s>", "<unk>"],
)
bpe.save_model(path)
tok = GPT2TokenizerFast(
    vocab_file=f"{path}/vocab.json", merges_file=f"{path}/merges.txt",
    unk_token="<unk>", bos_token="<s>", eos_token="</s>", pad_token="<pad>",
)
tok.chat_template = "{% for m in messages %}{{ m.role }}: {{ m.content }}\\n{% endfor %}"
tok.save_pretrained(path)
cfg = Qwen2Config(
    vocab_size=len(tok), hidden_size=64, intermediate_size=128,
    num_hidden_layers=2, num_attention_heads=4, num_key_value_heads=4,
    max_position_embeddings=256, tie_word_embeddings=True,
)
Qwen2ForCausalLM(cfg).save_pretrained(path)
with open("/workspace/data/tiny.json", "w") as f:
    json.dump([
        {"instruction": "What is training?", "input": "", "output": "Training updates a model from data."},
        {"instruction": "What is an NPU?", "input": "", "output": "An NPU accelerates neural network computation."},
    ] * 8, f)
with open("/workspace/data/dataset_info.json", "w") as f:
    json.dump({"tiny_sft": {"file_name": "tiny.json"}}, f)
print("synthetic Qwen2 model and SFT data prepared", flush=True)
PY

cat > /workspace/train.yaml <<'YAML'
model_name_or_path: /workspace/tiny-qwen2
trust_remote_code: true
resize_vocab: true
stage: sft
do_train: true
finetuning_type: lora
lora_rank: 8
lora_alpha: 16
lora_dropout: 0.05
lora_target: q_proj,v_proj
dataset: tiny_sft
dataset_dir: /workspace/data
template: qwen
cutoff_len: 128
max_samples: 16
overwrite_cache: true
preprocessing_num_workers: 1
dataloader_num_workers: 0
output_dir: /workspace/output
logging_steps: 1
save_steps: 2
overwrite_output_dir: true
per_device_train_batch_size: 1
gradient_accumulation_steps: 1
learning_rate: 0.00005
num_train_epochs: 1.0
max_steps: 2
lr_scheduler_type: constant
warmup_steps: 0
bf16: true
fp16: false
flash_attn: disabled
report_to: none
YAML
llamafactory-cli train /workspace/train.yaml
find /workspace/output -name adapter_config.json -print -quit | grep -q adapter_config.json
echo "LLaMA Factory LoRA smoke completed and adapter checkpoint exists"
python3 - <<'PYTHON'
import json, math
from pathlib import Path
out = Path('/workspace/output')
state = json.loads((out / 'checkpoint-2/trainer_state.json').read_text())
assert state['global_step'] == 2, state
losses = [x['loss'] for x in state['log_history'] if 'loss' in x]
assert losses and all(math.isfinite(x) for x in losses), losses
assert (out / 'adapter_config.json').is_file()
assert any(p.stat().st_size > 0 for p in out.glob('adapter_model.*'))
print('PASS: C19 completed 2 LoRA steps with finite loss and adapter weights', flush=True)
PYTHON
