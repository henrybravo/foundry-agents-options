# Copyright (c) Microsoft. All rights reserved.
# Adapted from the Foundry hosted-agents Agent Framework workflow sample.

"""Microsoft Agent Framework reviewer workflow (Responses protocol).

The same fixed topology as the LangGraph workflow variant: safety
reviewer -> environment reviewer -> summarizer. Each agent reads its
rules from the shared ``trail-review`` skill files.
"""

import os
from pathlib import Path

from agent_framework import Agent, AgentExecutor, WorkflowBuilder
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import ResponsesHostServer
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

from toolbox_skills import skills_root

load_dotenv()

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


_SUMMARY_PROMPT = (
    "You are the review summarizer. Combine the domain findings in the "
    "conversation into the final review result. Follow the skill's output "
    "format and verdict rules exactly. Return only the review result.\n\n"
    f"# Skill\n\n{_read('SKILL.md')}"
)


def build_agent():
    """Build the workflow and expose it as a single agent."""
    client = FoundryChatClient(
        project_endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
        model=os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"],
        credential=DefaultAzureCredential(),
    )

    def executor(name: str, instructions: str) -> AgentExecutor:
        agent = Agent(client=client, instructions=instructions, name=name)
        # "full" lets later steps see the proposal and earlier findings.
        return AgentExecutor(agent, context_mode="full")

    safety = executor(
        "safety_reviewer",
        _domain_prompt("references/safety.md"),
    )
    environment = executor(
        "environment_reviewer",
        _domain_prompt("references/environment.md"),
    )
    summarizer = executor("summarizer", _SUMMARY_PROMPT)

    return (
        WorkflowBuilder(
            start_executor=safety,
            # Return only the summarizer's output to the caller.
            output_executors=[summarizer],
        )
        .add_edge(safety, environment)
        .add_edge(environment, summarizer)
        .build()
        .as_agent(name="trail-maf-workflow")
    )


def main():
    ResponsesHostServer(build_agent()).run()


if __name__ == "__main__":
    main()
