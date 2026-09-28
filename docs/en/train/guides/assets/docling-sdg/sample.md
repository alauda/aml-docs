# AutoRAG on Alauda AI

AutoRAG searches chunking, embedding, retrieval, and generation settings for a
document corpus. It evaluates candidate RAG patterns with a benchmark and writes
a deployable pattern.json.

The production workflow uses the selected pattern's indexing settings to build a
vector collection. Docling extracts text from PDFs into DoclingDocument JSON
before the search-space and optimization stages run.

Alauda AI Workbench can run Docling and SDG Hub locally for small corpora. Use
KubeRay or Kubeflow Pipelines when the corpus is large.
