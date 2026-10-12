# Copyright (c) Microsoft. All rights reserved.
# Adapted from the Foundry hosted-agents Deep Agents sample for the Trail review demo.

"""Host the Deep Agents reviewer on Microsoft Foundry over Responses."""

from __future__ import annotations

import asyncio
import os

from dotenv import load_dotenv
from langchain_azure_ai.agents.hosting import (
    FoundryCheckpointSaver,
    ResponsesHostServer,
)

from agent import build_agent
from utils import build_chat_model

load_dotenv()


async def main() -> None:
    async with FoundryCheckpointSaver() as checkpointer:
        agent = build_agent(build_chat_model(), checkpointer)
        port = int(os.environ.get("PORT", "8088"))
        await ResponsesHostServer(agent).run_async(port=port)


if __name__ == "__main__":
    asyncio.run(main())
