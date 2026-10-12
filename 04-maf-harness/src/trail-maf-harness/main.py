# Copyright (c) Microsoft. All rights reserved.
# Adapted from the Foundry hosted-agents Agent Framework basic sample.

"""Microsoft Agent Framework Harness Agent reviewer (Responses protocol).

The MAF counterpart of the Deep Agents variant: the harness decides its
own steps and discovers the shared ``trail-review`` skill through
progressive disclosure (`load_skill` and `read_skill_resource`).
With `TOOLBOX_ENDPOINT` set, the skill comes from that Foundry toolbox
through the native `FoundryToolbox` skills provider; otherwise the
bundled copy is used.
"""

import asyncio
import os
from pathlib import Path

from agent_framework import (
    InMemoryHistoryProvider,
    SkillsProvider,
    create_harness_agent,
)
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import FoundryToolbox, ResponsesHostServer
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

load_dotenv()

_SKILLS_DIR = Path(__file__).parent / "skills"

# ResponsesHostServer rejects any history provider that loads messages,
# except its own per-request buffer with this source id. The harness always
# installs a history provider, so it gets that buffer and the Foundry host
# keeps owning the conversation history.
_HOSTED_HISTORY_SOURCE_ID = "_foundry_responses_history"

INSTRUCTIONS = """You review group hike proposals.
Use the trail-review skill for every review request. Follow its steps and
its output format exactly. Return only the review result."""


def _toolbox(credential) -> FoundryToolbox | None:
    """The Foundry toolbox in TOOLBOX_ENDPOINT, or None when unset."""
    if not os.environ.get("TOOLBOX_ENDPOINT", "").strip():
        os.environ.pop("TOOLBOX_ENDPOINT", None)
        return None
    # load_tools=False: the toolbox contributes skills only, no tools.
    return FoundryToolbox(credential, load_tools=False)


def _skills_options(toolbox: FoundryToolbox | None) -> dict:
    """Skill source: the Foundry toolbox when configured, else bundled."""
    if toolbox is None:
        print("Skills source: bundled (TOOLBOX_ENDPOINT not set)", flush=True)
        return {
            "skills_paths": [_SKILLS_DIR],
            # Skill tools require approval by default. Auto-approve only the
            # read-only ones (load_skill, read_skill_resource); scripts still
            # need approval.
            "auto_approval_rules": [
                SkillsProvider.read_only_tools_auto_approval_rule
            ],
        }
    print(f"Skills source: toolbox {toolbox.url}", flush=True)
    return {
        # The hosted agent runs unattended, so the read-only skill tools
        # need no approval; scripts still do.
        "skills_provider": toolbox.as_skills_provider(
            disable_load_skill_approval=True,
            disable_read_skill_resource_approval=True,
        ),
    }


def build_agent(credential, toolbox: FoundryToolbox | None = None):
    """Build the Harness Agent reviewer with the shared skill loaded."""
    client = FoundryChatClient(
        project_endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
        model=os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"],
        credential=credential,
    )
    return create_harness_agent(
        client=client,
        name="trail-maf-harness",
        agent_instructions=INSTRUCTIONS,
        **_skills_options(toolbox),
        history_provider=InMemoryHistoryProvider(
            source_id=_HOSTED_HISTORY_SOURCE_ID
        ),
        # Keep the demo scoped to the proposal and the skill.
        disable_web_search=True,
        # Plan mode is interactive; the demo sends one-shot requests.
        disable_mode=True,
        # File memory writes under the working directory, which is
        # read-only (/app) in the hosted container.
        disable_file_memory=True,
        # The hosting layer manages history, so the service does not store it.
        default_options={"store": False},
    )


async def main():
    credential = DefaultAzureCredential()
    toolbox = _toolbox(credential)
    server = ResponsesHostServer(build_agent(credential, toolbox))
    if toolbox is None:
        await server.run_async()
        return
    # The skills provider reads through the toolbox MCP session, so keep it
    # open for the lifetime of the server.
    async with toolbox:
        await server.run_async()


if __name__ == "__main__":
    asyncio.run(main())
