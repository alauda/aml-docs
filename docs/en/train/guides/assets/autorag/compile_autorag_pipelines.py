#!/usr/bin/env python3
"""Compile AutoRAG pipelines from the pipelines-components mirror.

The managed `documents-rag-optimization-pipeline` is the shortest path on a
cluster that already preloads it. Use this script when you need a compiled
YAML to upload, when you want the documents indexing pipeline, or when you
must lower CPU and memory requests for a small cluster.

Install the compiler dependencies first:

    python -m pip install 'kfp==2.16.1' 'kfp-kubernetes==2.16.1'
    python -m pip install --no-deps -e /path/to/pipelines-components
"""

import argparse
import os
from pathlib import Path
from typing import List, Optional

from kfp import compiler, dsl
from kfp.kubernetes import use_secret_as_env
from kfp_components.components.data_processing.autorag.documents_indexing.component import (
    documents_indexing as _documents_indexing_src,
)
from kfp_components.components.training.autorag.component_stage_map_publisher import (
    publish_component_stage_map,
)
from kfp_components.components.training.autorag.rag_templates_optimization.component import (
    rag_templates_optimization,
)
from kfp_components.components.training.autorag.search_space_preparation.component import (
    search_space_preparation,
)
from kfp_components.pipelines.data_processing.autorag.documents_indexing_pipeline.pipeline import (
    documents_indexing_pipeline,
)
from kfp_components.pipelines.training.autorag.documents_rag_optimization_pipeline.pipeline import (
    documents_rag_optimization_pipeline,
)
from kfp_components.utils.consts import AUTORAG_IMAGE

AUTORAG_RUNTIME_IMAGE = os.environ.get(
    "RELATED_IMAGE_ODH_AUTORAG_IMAGE", AUTORAG_IMAGE
)

# Current odh-autorag images ship ai4rag 0.17, which moved data helpers from
# ai4rag.components.* to ai4rag.utils.*. The ingestion DAG below uses those
# imports. Managed optimization/indexing pipelines still compile against the
# 0.10 wrappers in pipelines-components; rebuild the runtime with ai4rag~=0.10.1
# before running those YAMLs.


@dsl.component(base_image=AUTORAG_RUNTIME_IMAGE, install_kfp_package=False)
def test_data_loader(
    test_data_bucket_name: str,
    test_data_path: str,
    benchmark_sample_size: int = 25,
    test_data: dsl.Output[dsl.Artifact] = None,
):
    import json
    import logging

    from ai4rag.utils.clients.s3 import create_s3_client
    from ai4rag.utils.data.test_data_loader import load_test_data

    logging.basicConfig(level=logging.INFO)
    result = load_test_data(
        bucket_name=test_data_bucket_name,
        key=test_data_path,
        benchmark_sample_size=benchmark_sample_size,
        s3_client=create_s3_client(),
    )
    with open(test_data.path, "w", encoding="utf-8") as f:
        json.dump(result.data, f, indent=2, ensure_ascii=False)


@dsl.component(base_image=AUTORAG_RUNTIME_IMAGE, install_kfp_package=False)
def documents_discovery(
    input_data_bucket_name: str,
    input_data_path: str = "",
    test_data: dsl.Input[dsl.Artifact] = None,
    sampling_enabled: bool = True,
    sampling_max_size: float = 1.0,
    discovered_documents: dsl.Output[dsl.Artifact] = None,
):
    import json
    import logging
    from pathlib import Path

    from ai4rag.utils.clients.s3 import create_s3_client
    from ai4rag.utils.data.documents_discovery import discover_documents

    logging.basicConfig(level=logging.INFO)
    test_data_doc_names = None
    if test_data:
        with open(test_data.path, encoding="utf-8") as f:
            records = json.load(f)
        test_data_doc_names = list(
            {
                doc_id
                for r in records
                for doc_id in r.get("correct_answer_document_keys", r.get("correct_answer_document_ids", []))
            }
        )
    result = discover_documents(
        bucket_name=input_data_bucket_name,
        prefix=input_data_path,
        test_data_doc_names=test_data_doc_names,
        sampling_enabled=sampling_enabled,
        sampling_max_size_gb=sampling_max_size,
        s3_client=create_s3_client(),
    )
    output_dir = Path(discovered_documents.path)
    output_dir.mkdir(parents=True, exist_ok=True)
    result.save(path=output_dir, filename="documents_descriptor.json")


@dsl.component(base_image=AUTORAG_RUNTIME_IMAGE, install_kfp_package=False)
def text_extraction(
    documents_descriptor: dsl.Input[dsl.Artifact],
    extracted_text: dsl.Output[dsl.Artifact],
    max_extraction_workers: Optional[int] = 1,
    preset: str = "speed",
):
    import json
    import logging
    import os
    from pathlib import Path

    from ai4rag.utils.data.text_extraction import DoclingExtractionConfig, extract_text

    logging.basicConfig(level=logging.INFO)
    if preset not in {"speed", "balanced"}:
        raise ValueError(f"preset must be speed or balanced; got {preset!r}")
    descriptor_path = Path(documents_descriptor.path) / "documents_descriptor.json"
    with open(descriptor_path, encoding="utf-8") as f:
        descriptor = json.load(f)
    output_dir = Path(extracted_text.path)
    output_dir.mkdir(parents=True, exist_ok=True)
    extract_text(
        documents=descriptor["documents"],
        bucket=descriptor["bucket"],
        output_dir=output_dir,
        s3_endpoint=os.environ.get("AWS_S3_ENDPOINT"),
        s3_access_key=os.environ.get("AWS_ACCESS_KEY_ID"),
        s3_secret_key=os.environ.get("AWS_SECRET_ACCESS_KEY"),
        s3_region=os.environ.get("AWS_DEFAULT_REGION"),
        max_extraction_workers=max_extraction_workers,
        docling_artifacts_path=os.environ.get("DOCLING_ARTIFACTS_PATH"),
        docling_config=DoclingExtractionConfig(do_table_structure=preset == "balanced"),
    )


documents_indexing = dsl.component(
    base_image=AUTORAG_RUNTIME_IMAGE,
    install_kfp_package=False,
)(_documents_indexing_src.python_func)


def _apply_image(task) -> None:
    if AUTORAG_RUNTIME_IMAGE:
        task.set_container_image(AUTORAG_RUNTIME_IMAGE)


def _s3_secret(task, secret_name: str) -> None:
    use_secret_as_env(
        task,
        secret_name=secret_name,
        secret_key_to_env={
            "AWS_ACCESS_KEY_ID": "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY": "AWS_SECRET_ACCESS_KEY",
            "AWS_S3_ENDPOINT": "AWS_S3_ENDPOINT",
            "AWS_DEFAULT_REGION": "AWS_DEFAULT_REGION",
        },
        optional=True,
    )


def _ogx_secret(task, secret_name: str) -> None:
    use_secret_as_env(
        task,
        secret_name=secret_name,
        secret_key_to_env={
            "OGX_CLIENT_BASE_URL": "OGX_CLIENT_BASE_URL",
            "OGX_CLIENT_API_KEY": "OGX_CLIENT_API_KEY",
        },
    )


def _tier(task, cpu_request: str, memory_request: str, cpu_limit: str, memory_limit: str) -> None:
    task.set_caching_options(False)
    task.set_cpu_request(cpu_request).set_memory_request(memory_request)
    task.set_cpu_limit(cpu_limit).set_memory_limit(memory_limit)
    _apply_image(task)


@dsl.pipeline(
    name="autorag-document-ingestion",
    description=(
        "Load a RAG benchmark, discover the source documents in object storage, "
        "and extract text with Docling. Use this DAG to validate the corpus "
        "before running AutoRAG optimization."
    ),
)
def autorag_document_ingestion(
    test_data_secret_name: str,
    test_data_bucket_name: str,
    test_data_key: str,
    input_data_secret_name: str,
    input_data_bucket_name: str,
    input_data_key: str = "",
    preset: str = "speed",
):
    loader = test_data_loader(
        test_data_bucket_name=test_data_bucket_name,
        test_data_path=test_data_key,
        benchmark_sample_size=0,
    )
    _tier(loader, "500m", "1Gi", "1", "2Gi")
    _s3_secret(loader, test_data_secret_name)

    discovery = documents_discovery(
        input_data_bucket_name=input_data_bucket_name,
        input_data_path=input_data_key,
        test_data=loader.outputs["test_data"],
        sampling_enabled=True,
        sampling_max_size=1.0,
    )
    _tier(discovery, "500m", "1Gi", "1", "2Gi")
    _s3_secret(discovery, input_data_secret_name)

    extraction = text_extraction(
        documents_descriptor=discovery.outputs["discovered_documents"],
        preset=preset,
        max_extraction_workers=1,
    )
    _tier(extraction, "1", "2Gi", "2", "4Gi")
    _s3_secret(extraction, input_data_secret_name)


@dsl.pipeline(
    name="documents-rag-optimization-pipeline-smoke",
    description=(
        "AutoRAG optimization DAG with reduced CPU and memory requests for a "
        "small cluster. Production clusters should use the managed pipeline "
        "or the default compiler output."
    ),
)
def documents_rag_optimization_pipeline_smoke(
    test_data_secret_name: str,
    test_data_bucket_name: str,
    test_data_key: str,
    input_data_secret_name: str,
    input_data_bucket_name: str,
    ogx_secret_name: str,
    vector_io_provider_id: str,
    input_data_key: str = "",
    embedding_models: Optional[List] = None,
    generation_models: Optional[List] = None,
    optimization_metric: str = "overall_score",
    optimization_max_rag_patterns: int = 2,
    preset: str = "speed",
):
    stage_map = publish_component_stage_map(
        pipeline_id="documents-rag-optimization-pipeline",
        run_id=dsl.PIPELINE_JOB_ID_PLACEHOLDER,
    )
    _tier(stage_map, "100m", "256Mi", "500m", "512Mi")

    loader = test_data_loader(
        test_data_bucket_name=test_data_bucket_name,
        test_data_path=test_data_key,
        benchmark_sample_size=0,
    )
    loader.after(stage_map)
    _tier(loader, "500m", "1Gi", "1", "2Gi")
    _s3_secret(loader, test_data_secret_name)

    discovery = documents_discovery(
        input_data_bucket_name=input_data_bucket_name,
        input_data_path=input_data_key,
        test_data=loader.outputs["test_data"],
    )
    _tier(discovery, "500m", "1Gi", "1", "2Gi")
    _s3_secret(discovery, input_data_secret_name)

    extraction = text_extraction(
        documents_descriptor=discovery.outputs["discovered_documents"],
        preset=preset,
        max_extraction_workers=1,
    )
    _tier(extraction, "1", "2Gi", "2", "4Gi")
    _s3_secret(extraction, input_data_secret_name)

    search_space = search_space_preparation(
        test_data=loader.outputs["test_data"],
        extracted_text=extraction.outputs["extracted_text"],
        embedding_models=embedding_models,
        generation_models=generation_models,
        preset=preset,
    )
    _tier(search_space, "500m", "1Gi", "1", "2Gi")
    _ogx_secret(search_space, ogx_secret_name)

    optimization = rag_templates_optimization(
        extracted_text=extraction.outputs["extracted_text"],
        test_data=loader.outputs["test_data"],
        search_space_prep_report=search_space.outputs["search_space_prep_report"],
        vector_io_provider_id=vector_io_provider_id,
        optimization_settings={
            "metric": optimization_metric,
            "max_number_of_rag_patterns": optimization_max_rag_patterns,
        },
        test_data_key=test_data_key,
        input_data_key=input_data_key,
        preset=preset,
    )
    _tier(optimization, "1", "2Gi", "2", "4Gi")
    _ogx_secret(optimization, ogx_secret_name)


@dsl.pipeline(
    name="documents-indexing-pipeline-smoke",
    description="Documents indexing DAG with reduced CPU and memory requests.",
)
def documents_indexing_pipeline_smoke(
    ogx_secret_name: str,
    embedding_model_id: str,
    vector_io_provider_id: str,
    input_data_secret_name: str,
    input_data_bucket_name: str,
    input_data_key: Optional[str] = None,
    vector_store_id: str = None,
    embedding_params: Optional[dict] = None,
    distance_metric: str = "cosine",
    chunking_method: str = "recursive",
    chunk_size: int = 1024,
    chunk_overlap: int = 0,
    batch_size: int = 20,
):
    discovery = documents_discovery(
        input_data_bucket_name=input_data_bucket_name,
        input_data_path=input_data_key,
        sampling_enabled=False,
    )
    _tier(discovery, "500m", "1Gi", "1", "2Gi")
    _s3_secret(discovery, input_data_secret_name)

    extraction = text_extraction(
        documents_descriptor=discovery.outputs["discovered_documents"],
        max_extraction_workers=1,
    )
    _tier(extraction, "1", "2Gi", "2", "4Gi")
    _s3_secret(extraction, input_data_secret_name)

    indexing = documents_indexing(
        embedding_params=embedding_params,
        embedding_model_id=embedding_model_id,
        extracted_text=extraction.outputs["extracted_text"],
        vector_io_provider_id=vector_io_provider_id,
        distance_metric=distance_metric,
        chunking_method=chunking_method,
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
        batch_size=batch_size,
        vector_store_id=vector_store_id,
    )
    _tier(indexing, "500m", "1Gi", "1", "2Gi")
    _ogx_secret(indexing, ogx_secret_name)


PIPELINES = {
    "optimization": documents_rag_optimization_pipeline,
    "indexing": documents_indexing_pipeline,
    "ingestion": autorag_document_ingestion,
    "optimization-smoke": documents_rag_optimization_pipeline_smoke,
    "indexing-smoke": documents_indexing_pipeline_smoke,
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "pipeline",
        nargs="+",
        choices=sorted(PIPELINES),
        help="Pipeline function to compile. Repeat to compile more than one.",
    )
    parser.add_argument(
        "--output-dir",
        default=".",
        help="Directory for compiled YAML files.",
    )
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    for name in args.pipeline:
        package_path = output_dir / f"{name}.yaml"
        compiler.Compiler().compile(PIPELINES[name], package_path=str(package_path))
        print(f"compiled {name} -> {package_path}")


if __name__ == "__main__":
    main()
