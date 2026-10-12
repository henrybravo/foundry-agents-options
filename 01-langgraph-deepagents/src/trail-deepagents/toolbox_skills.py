# Copyright (c) Microsoft. All rights reserved.
# Canonical copy; scripts\sync-shared.ps1 copies it into 01-03.

"""Load agent skills from a Foundry toolbox, with a bundled fallback.

A Foundry toolbox serves its skills over MCP as resources:
``skill://index.json`` lists them and each archive skill is a ZIP at
``skill://<name>.zip``. This module downloads those archives once at
startup and unpacks them into a local ``skills`` folder, so frameworks
that read skills from disk (Deep Agents, or plain file reads) can use
them unchanged.

Set ``TOOLBOX_ENDPOINT`` to the toolbox MCP URL to enable it. When it is
unset, or the toolbox cannot be read, the skills bundled in the code
package are used and a warning says so.
"""

from __future__ import annotations

import asyncio
import base64
import io
import json
import os
import sys
import tempfile
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

_SCOPE = "https://ai.azure.com/.default"
_INDEX_URI = "skill://index.json"


def _report(message: str) -> None:
    print(f"[toolbox_skills] {message}", file=sys.stderr, flush=True)


async def _download(endpoint: str, target: Path) -> list[str]:
    from azure.identity import DefaultAzureCredential
    from mcp import ClientSession
    from mcp.client.streamable_http import streamablehttp_client
    from pydantic import AnyUrl

    token = DefaultAzureCredential().get_token(_SCOPE).token
    headers = {"Authorization": f"Bearer {token}"}

    names: list[str] = []
    async with streamablehttp_client(endpoint, headers=headers) as streams:
        read, write, _ = streams
        async with ClientSession(read, write) as session:
            await session.initialize()
            index = await session.read_resource(AnyUrl(_INDEX_URI))
            skills = json.loads(index.contents[0].text)["skills"]
            for skill in skills:
                name = skill["name"]
                result = await session.read_resource(AnyUrl(skill["url"]))
                part = result.contents[0]
                folder = target / name
                folder.mkdir(parents=True, exist_ok=True)
                if skill.get("type") == "archive":
                    data = base64.b64decode(part.blob)
                    with zipfile.ZipFile(io.BytesIO(data)) as archive:
                        archive.extractall(folder)
                else:
                    (folder / "SKILL.md").write_text(
                        part.text, encoding="utf-8"
                    )
                names.append(name)
    return names


def skills_root(bundled: Path) -> Path:
    """Return a folder that holds one subfolder per skill.

    ``bundled`` is the ``skills`` folder shipped in the code package. The
    returned folder is always named ``skills``.
    """
    endpoint = os.environ.get("TOOLBOX_ENDPOINT", "").strip()
    if not endpoint:
        _report("Skills source: bundled (TOOLBOX_ENDPOINT not set)")
        return bundled

    target = Path(tempfile.mkdtemp(prefix="toolbox-")) / "skills"
    try:
        # Runs in its own thread so it also works inside a running loop.
        with ThreadPoolExecutor(max_workers=1) as pool:
            names = pool.submit(
                asyncio.run, _download(endpoint, target)
            ).result(timeout=60)
    except Exception as error:
        _report(
            f"Skills source: bundled (toolbox {endpoint} could not be "
            f"read: {error!r})"
        )
        return bundled
    if not names:
        _report(f"Skills source: bundled (toolbox {endpoint} has no skills)")
        return bundled
    _report(f"Skills source: toolbox {endpoint} ({', '.join(names)})")
    return target
