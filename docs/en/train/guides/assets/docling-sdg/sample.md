# Preparing Fine-Tuning Data on Alauda AI Platform

Docling converts source documents to Markdown for use in synthetic data
generation. It can also write DoclingDocument JSON to preserve document
structure, including tables and bounding boxes.

SDG Hub uses an OpenAI-compatible teacher model to generate question-and-answer
pairs from the document text. The resulting pairs can be exported as JSONL for
supervised fine-tuning.

Alauda AI Workbench can run Docling and SDG Hub locally for small corpora. Use
KubeRay or Kubeflow Pipelines when the corpus is large.
