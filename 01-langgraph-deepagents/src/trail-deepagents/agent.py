"""Deep Agents harness that reviews group hike proposals.

The harness decides its own steps. It discovers the shared
``trail-review`` skill through progressive disclosure and reads the
skill's reference files only when it needs them. The skill comes from the
Foundry toolbox in ``TOOLBOX_ENDPOINT`` when set, else from the bundled
copy.
"""

from pathlib import Path
from typing import Any

from deepagents import create_deep_agent
from deepagents.backends.filesystem import FilesystemBackend
from langchain_openai import ChatOpenAI
from langgraph.checkpoint.base import BaseCheckpointSaver

from toolbox_skills import skills_root

AGENT_ROOT = Path(__file__).parent

INSTRUCTIONS = """You review group hike proposals.
Use the trail-review skill for every review request. Follow its steps and
its output format exactly. Return only the review result."""


def build_agent(
    model: ChatOpenAI,
    checkpointer: BaseCheckpointSaver[Any] | None = None,
):
    """Build the Deep Agents reviewer with the shared skill loaded."""
    # The backend root holds the "skills" folder the harness reads as /skills/.
    root = skills_root(AGENT_ROOT / "skills").parent
    backend = FilesystemBackend(root_dir=root, virtual_mode=True)
    return create_deep_agent(
        model=model,
        system_prompt=INSTRUCTIONS,
        skills=["/skills/"],
        backend=backend,
        checkpointer=checkpointer,
        name="trail-deepagents",
    )
