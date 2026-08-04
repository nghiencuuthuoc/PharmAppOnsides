"""Upload the OnSIDES production BERT model to HuggingFace."""

import json
import shutil
import tempfile
from pathlib import Path

import torch
from huggingface_hub import HfApi
from safetensors.torch import save_file

ROOT = Path(__file__).resolve().parent.parent
REPO_ID = "tatonettilab/onsides-bert"
BASE_MODEL_DIR = ROOT / "models/microsoft/BiomedNLP-PubMedBERT-base-uncased-abstract"
WEIGHTS_PATH = ROOT / "models/bestepoch-bydrug-PMB_14-ALL-125-all_222_24_25_1e-06_256_32.pth"


def build_config(base_config_path: Path) -> dict:
    with open(base_config_path) as f:
        config = json.load(f)
    config["architectures"] = ["OnsidesForClassification"]
    config["model_type"] = "onsides"
    config["classifier_dropout"] = 0.5
    config["num_labels"] = 2
    config["id2label"] = {"0": "not_event", "1": "is_event"}
    config["label2id"] = {"not_event": 0, "is_event": 1}
    config["auto_map"] = {
        "AutoConfig": "configuration_onsides--OnsidesConfig",
        "AutoModel": "modeling_onsides--OnsidesForClassification",
    }
    return config


CONFIGURATION_PY = '''\
from transformers import PretrainedConfig


class OnsidesConfig(PretrainedConfig):
    model_type = "onsides"

    def __init__(self, classifier_dropout=0.5, num_labels=2, **kwargs):
        self.classifier_dropout = classifier_dropout
        self.num_labels = num_labels
        super().__init__(**kwargs)
'''


MODELING_PY = '''\
import torch
from torch import nn
from transformers import BertModel, PreTrainedModel

from .configuration_onsides import OnsidesConfig


class OnsidesForClassification(PreTrainedModel):
    """PubMedBERT fine-tuned to classify adverse drug events in product labels.

    Two-class classifier: 0 = not_event, 1 = is_event.
    Output logits are passed through ReLU (matching the training setup).
    """

    config_class = OnsidesConfig

    def __init__(self, config):
        super().__init__(config)
        self.bert = BertModel(config)
        self.dropout = nn.Dropout(config.classifier_dropout)
        self.linear = nn.Linear(config.hidden_size, config.num_labels)
        self.relu = nn.ReLU()
        self.post_init()

    def forward(self, input_ids, attention_mask=None, **kwargs):
        outputs = self.bert(
            input_ids=input_ids, attention_mask=attention_mask, return_dict=False
        )
        pooled_output = outputs[1]
        return self.relu(self.linear(self.dropout(pooled_output)))
'''


MODEL_CARD = """\
---
license: mit
language: en
tags:
  - adverse-drug-events
  - drug-safety
  - pharmacovigilance
  - text-classification
  - biomedical
  - PubMedBERT
datasets:
  - custom
base_model: microsoft/BiomedNLP-PubMedBERT-base-uncased-abstract
pipeline_tag: text-classification
library_name: transformers
---

# OnSIDES-BERT: Adverse Drug Event Classifier

A fine-tuned [PubMedBERT](https://huggingface.co/microsoft/BiomedNLP-PubMedBERT-base-uncased-abstract) model for classifying whether a medical term mentioned in a drug product label represents a true adverse drug event or an incidental mention.

This is the production model used by [OnSIDES](https://github.com/tatonetti-lab/onsides), an international database of adverse drug events extracted from product labels across four countries (USA, EU, UK, Japan).

## Model Details

- **Base model**: [microsoft/BiomedNLP-PubMedBERT-base-uncased-abstract](https://huggingface.co/microsoft/BiomedNLP-PubMedBERT-base-uncased-abstract)
- **Task**: Binary text classification (is_event vs. not_event)
- **Architecture**: PubMedBERT + Dropout(0.5) + Linear(768, 2) + ReLU
- **Training data**: 200 manually curated FDA drug labels from [Denmer-Fushman et al.](https://pubmed.ncbi.nlm.nih.gov/29381145/), with MedDRA term matches labeled as adverse events or incidental mentions
- **Sections**: Trained jointly on Adverse Reactions (AR), Boxed Warnings (BW), and Warnings & Precautions (WP)
- **Training details**: Learning rate 1e-6, batch size 32, max sequence length 256, 125-word context window, early stopping with patience 4

## Performance

**Held-out test set** (80/10/10 drug-level split of 200 manually annotated FDA labels):

| Section | F1 | Precision | Recall | AUROC |
|---|---|---|---|---|
| Adverse Reactions | 0.942 | 0.962 | 0.922 | 0.996 |
| Boxed Warning | 0.901 | 0.977 | 0.835 | 0.996 |
| Warnings & Precautions | 0.880 | 0.851 | 0.911 | 0.995 |

**Independent hold-out** (30 manually annotated FDA labels, not used in training or threshold tuning):

| Section | F1 | Precision | Recall | AUROC |
|---|---|---|---|---|
| Adverse Reactions | 0.847 | 0.871 | 0.825 | 0.965 |
| Boxed Warning | 0.736 | 1.000 | 0.582 | 0.988 |
| Warnings & Precautions | 0.756 | 0.789 | 0.725 | 0.973 |

**TAC 2017 benchmark**: F1 = 89.87 (state of the art).

## Usage

```python
import torch
from transformers import AutoTokenizer, AutoModel

tokenizer = AutoTokenizer.from_pretrained("tatonettilab/onsides-bert")
model = AutoModel.from_pretrained("tatonettilab/onsides-bert", trust_remote_code=True)
model.eval()

text = "Patients receiving EXAMPLE DRUG reported nausea, headache, and dizziness."
inputs = tokenizer(text, return_tensors="pt", max_length=256, truncation=True, padding="max_length")

with torch.no_grad():
    logits = model(input_ids=inputs["input_ids"], attention_mask=inputs["attention_mask"])

# logits shape: (batch_size, 2)
# Column 0 = not_event score, Column 1 = is_event score
predicted_class = logits.argmax(dim=1).item()
print("is_event" if predicted_class == 1 else "not_event")
```

### Input Format

The model expects text constructed from drug label sections with MedDRA term context. In the OnSIDES pipeline, each input is a window of up to 125 words surrounding a candidate MedDRA term match, with the event term and source section prepended. See the [OnSIDES repository](https://github.com/tatonetti-lab/onsides) for the full text construction pipeline.

### Recommended Thresholds

For the OnSIDES v3.2.0 database, section-specific thresholds were applied to the raw logit scores:

| Section | Threshold |
|---|---|
| Adverse Reactions | 0.6926 |
| Boxed Warning | 0.8713 |
| Warnings & Precautions | 0.5878 |

## Citation

```bibtex
@article{tanaka2025onsides,
  title={OnSIDES database: Extracting adverse drug events from drug labels using natural language processing models},
  author={Tanaka, Yutaro and Chen, Hsin Yi and Belloni, Payal and Gisladottir, Undina and Kefeli, Jaden and Patterson, Joshua and Srinivasan, Ashwin and Zietz, Michael and Sirdeshmukh, Gaurav and Berkowitz, Jacob and LaRow Brown, Kathleen and Tatonetti, Nicholas P},
  journal={Med},
  year={2025},
  publisher={Elsevier},
  doi={10.1016/j.medj.2025.100642}
}
```

## License

MIT License. See the [OnSIDES repository](https://github.com/tatonetti-lab/onsides) for full details.
"""


def main():
    upload_dir = Path(tempfile.mkdtemp(prefix="onsides-bert-"))
    print(f"Building upload in {upload_dir}")

    # 1. Config
    config = build_config(BASE_MODEL_DIR / "config.json")
    with open(upload_dir / "config.json", "w") as f:
        json.dump(config, f, indent=2)
    print("Wrote config.json")

    # 2. Model weights as safetensors
    state_dict = torch.load(WEIGHTS_PATH, weights_only=True, map_location="cpu")
    state_dict.pop("bert.embeddings.position_ids", None)
    state_dict = {k: v.contiguous() for k, v in state_dict.items()}
    save_file(state_dict, upload_dir / "model.safetensors")
    print(f"Converted weights to safetensors ({len(state_dict)} tensors)")

    # 3. Tokenizer files
    for fname in ["tokenizer_config.json", "vocab.txt"]:
        shutil.copy(BASE_MODEL_DIR / fname, upload_dir / fname)
    print("Copied tokenizer files")

    # 4. Custom model code
    (upload_dir / "configuration_onsides.py").write_text(CONFIGURATION_PY)
    (upload_dir / "modeling_onsides.py").write_text(MODELING_PY)
    print("Wrote model code files")

    # 5. Model card
    (upload_dir / "README.md").write_text(MODEL_CARD)
    print("Wrote model card")

    # 6. Upload
    api = HfApi()
    api.create_repo(REPO_ID, exist_ok=True, repo_type="model")
    print(f"Created/verified repo: {REPO_ID}")

    api.upload_folder(
        folder_path=str(upload_dir),
        repo_id=REPO_ID,
        commit_message="Upload OnSIDES production model (PubMedBERT fine-tuned for adverse drug event classification)",
    )
    print(f"Upload complete! https://huggingface.co/{REPO_ID}")

    shutil.rmtree(upload_dir)


if __name__ == "__main__":
    main()
