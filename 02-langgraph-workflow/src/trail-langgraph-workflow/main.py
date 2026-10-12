# Copyright (c) Microsoft. All rights reserved.
# Adapted from the Foundry hosted-agents LangGraph workflow sample.

"""LangGraph reviewer workflow (Responses protocol).

A fixed, code-defined graph: safety reviewer -> environment
reviewer -> summarizer. No model decides what runs next. Each node reads
its rules from the shared ``trail-review`` skill files, so the same
skill drives this workflow and the harness variants.

Exports ``create_graph`` for the configuration-driven
``langchain_azure_ai.agents.hosting.run`` entrypoint (see langgraph.json).
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Annotated

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from dotenv import load_dotenv
from langchain_core.messages import (
    AIMessage,
    BaseMessage,
    HumanMessage,
    SystemMessage,
)
from langchain_openai import ChatOpenAI
from langgraph.graph import END, START, StateGraph
from langgraph.graph.message import add_messages
from typing_extensions import TypedDict

from toolbox_skills import skills_root

load_dotenv()

_AZURE_AI_SCOPE = "https://ai.azure.com/.default"
# From the Foundry toolbox in TOOLBOX_ENDPOINT when set, else bundled.
_SKILL_DIR = skills_root(Path(__file__).parent / "skills") / "trail-review"


def _read(relative: str) -> str:
    return (_SKILL_DIR / relative).read_text(encoding="utf-8")


def _domain_prompt(reference: str) -> str:
    return (
        "You are a domain reviewer. Follow the skill below, but assess only "
        "the rules in the reference below. Return only the table rows for "
        "those rules, in the skill's table format, without a header.\n\n"
        f"# Skill\n\n{_read('SKILL.md')}\n\n# Reference\n\n{_read(reference)}"
    )


_SAFETY_PROMPT = _domain_prompt("references/safety.md")
_ENVIRONMENT_PROMPT = _domain_prompt("references/environment.md")
_SUMMARY_PROMPT = (
    "You are the review summarizer. Combine the domain findings into the "
    "final review result. Follow the skill's output format and verdict "
    "rules exactly. Return only the review result.\n\n"
    f"# Skill\n\n{_read('SKILL.md')}"
)


def _build_chat_model() -> ChatOpenAI:
    project_endpoint = os.environ["FOUNDRY_PROJECT_ENDPOINT"].rstrip("/")
    deployment = os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"]
    credential = DefaultAzureCredential()
    project = AIProjectClient(endpoint=project_endpoint, credential=credential)
    openai_client = project.get_openai_client()
    token_provider = get_bearer_token_provider(credential, _AZURE_AI_SCOPE)

    return ChatOpenAI(
        model=deployment,
        base_url=str(openai_client.base_url),
        api_key=token_provider,
        use_responses_api=True,
        output_version="responses/v1",
    )


class State(TypedDict):
    """Graph state.

    ``messages`` is the channel the Responses host reads. Only the
    summarizer writes to it, so only the final review is returned. The
    other fields are private channels between the nodes.
    """

    messages: Annotated[list[BaseMessage], add_messages]
    proposal: str
    safety: str
    environment: str


def _build_graph(model: ChatOpenAI):
    # The Responses host streams every model call in the graph. Reviewer
    # calls are tagged "nostream" so only the summarizer reaches the client.
    quiet_model = model.with_config(tags=["nostream"])

    async def ask(system: str, user: str, llm=quiet_model) -> AIMessage:
        return await llm.ainvoke(
            [SystemMessage(content=system), HumanMessage(content=user)]
        )

    async def safety_reviewer(state: State) -> dict:
        proposal = state["messages"][-1].text
        rows = (await ask(_SAFETY_PROMPT, proposal)).text
        return {"proposal": proposal, "safety": rows}

    async def environment_reviewer(state: State) -> dict:
        rows = (await ask(_ENVIRONMENT_PROMPT, state["proposal"])).text
        return {"environment": rows}

    async def summarizer(state: State) -> dict:
        findings = (
            f"# Proposal\n\n{state['proposal']}\n\n"
            f"# Safety findings\n\n{state['safety']}\n\n"
            f"# Environment findings\n\n{state['environment']}"
        )
        # Return the streamed message itself so it is not emitted twice.
        review = await ask(_SUMMARY_PROMPT, findings, llm=model)
        return {"messages": [review]}

    builder = StateGraph(State)
    builder.add_node("safety_reviewer", safety_reviewer)
    builder.add_node("environment_reviewer", environment_reviewer)
    builder.add_node("summarizer", summarizer)
    builder.add_edge(START, "safety_reviewer")
    builder.add_edge("safety_reviewer", "environment_reviewer")
    builder.add_edge("environment_reviewer", "summarizer")
    builder.add_edge("summarizer", END)
    return builder.compile()


def create_graph():
    """Create the workflow graph loaded by the hosting entrypoint."""
    return _build_graph(_build_chat_model())
