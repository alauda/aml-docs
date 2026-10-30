"""Invoke a LangChain agent and assert that MLflow stored its nested trace."""

from __future__ import annotations

import os
import time
import uuid

import mlflow
from langchain.agents import create_agent
from langchain_openai import ChatOpenAI


def configure_proxy_cookie() -> None:
    if not os.environ.get("MLFLOW_PROXY_COOKIE"):
        return

    from mlflow.tracking.request_header.abstract_request_header_provider import (
        RequestHeaderProvider,
    )
    from mlflow.tracking.request_header.registry import _request_header_provider_registry

    class ProxyCookieHeader(RequestHeaderProvider):
        def in_context(self) -> bool:
            return True

        def request_headers(self) -> dict[str, str]:
            return {"Cookie": os.environ["MLFLOW_PROXY_COOKIE"]}

    _request_header_provider_registry.register(ProxyCookieHeader)


def main() -> None:
    configure_proxy_cookie()

    mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])
    mlflow.set_workspace(os.environ["MLFLOW_WORKSPACE"])

    experiment_name = f"e2e-agent-tracing-{int(time.time())}-{uuid.uuid4().hex[:8]}"
    experiment = mlflow.set_experiment(experiment_name)
    client = mlflow.MlflowClient()

    try:
        mlflow.langchain.autolog(run_tracer_inline=True)
        model = ChatOpenAI(
            model=os.environ["AGENT_MODEL_ID"],
            base_url=os.environ["AGENT_MODEL_BASE_URL"],
            api_key=os.environ.get("AGENT_MODEL_API_KEY", "not-used"),
            temperature=0,
            max_tokens=64,
        )
        agent = create_agent(
            model=model,
            tools=[],
            system_prompt="You are an e2e test agent. Reply briefly.",
        )

        result = agent.invoke(
            {"messages": [{"role": "user", "content": "Say that tracing is ready."}]}
        )
        if not result["messages"][-1].content:
            raise AssertionError("agent returned an empty response")

        traces = mlflow.search_traces(
            locations=[experiment.experiment_id],
            max_results=10,
            return_type="list",
            flush=True,
        )
        if len(traces) != 1:
            raise AssertionError(f"expected one trace, found {len(traces)}")

        trace = traces[0]
        spans = trace.data.spans
        if not any(span.name == "LangGraph" for span in spans):
            raise AssertionError("trace does not contain the LangGraph agent span")
        if not any(span.span_type == "CHAT_MODEL" for span in spans):
            raise AssertionError("trace does not contain a chat-model span")

        print(
            "PASS: "
            f"experiment_id={experiment.experiment_id} "
            f"trace_id={trace.info.trace_id} "
            f"spans={len(spans)}"
        )
    finally:
        client.delete_experiment(experiment.experiment_id)


if __name__ == "__main__":
    main()
