# AutoRAG on Alauda AI

AutoRAG is a Kubeflow Pipelines workflow that searches retrieval-augmented
generation (RAG) configurations for a document corpus. It uses the ai4rag
optimization engine and talks to Llama Stack, now OGX, for embeddings,
generation, and vector I/O.

## What the optimizer changes

The search space covers:

- Chunking method, chunk size, and chunk overlap
- Embedding models registered in OGX
- Generation models registered in OGX
- Retrieval method, including simple retrieval and hybrid ranking

The pipeline ranks candidate RAG patterns with a quality metric such as
faithfulness, answer correctness, context correctness, answer relevance, or
the aggregated overall score.

## Inputs you must prepare

1. Source documents in an S3-compatible bucket. PDF, DOCX, PPTX, Markdown,
   HTML, and plain text are supported.
2. A benchmark JSON file. Each record has a `question`, `correct_answers`,
   and `correct_answer_document_ids` that name the source files.
3. An OGX endpoint with at least one embedding model and one generation
   model, plus a vector I/O provider such as `milvus-remote` or `pgvector`.

## Outputs you can deploy

Each optimized pattern includes a `pattern.json` with indexing and
`/v1/responses` settings, evaluation metrics, and notebooks that replay
indexing and inference. Use those indexing settings with the documents
indexing pipeline to build a production collection from the full corpus.
