# Foundry agent options: walkthrough diagrams

These diagrams explain the demo step by step. The demo answers one question: what changes, and what stays the same, when the same trail plan review agent is built as a harness or as a workflow, with LangGraph or with Microsoft Agent Framework, and hosted as a Foundry hosted agent. A fifth variant runs the same review as a Foundry prompt agent without code, as the baseline for that choice.

All five agents review the same fictional group hike proposal from the Alpenglow Trail Club against the same illustrative rules. The rules are demo content and carry no safety or legal meaning.

## 1. The five variants

Two independent choices produce the four hosted agents. The framework choice is LangGraph or Microsoft Agent Framework. The control choice is a harness, where the model plans its own steps, or a workflow, where code fixes the steps. The prompt agent sits before both choices: Foundry runs its loop, and the agent is only a model, instructions, and the skill text.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#E6F2FA','primaryTextColor':'#323130','primaryBorderColor':'#0078D4','secondaryColor':'#E6F2FA','secondaryTextColor':'#323130','secondaryBorderColor':'#0078D4','tertiaryColor':'#E6F2FA','tertiaryTextColor':'#323130','tertiaryBorderColor':'#0078D4','clusterBkg':'#E6F2FA','clusterBorder':'#0078D4','titleColor':'#323130','textColor':'#323130','edgeLabelBackground':'#ffffff','lineColor':'#005A9E','fontFamily':'Segoe UI'}}}%%
flowchart LR
    Q["Review this group<br/>hike proposal"]

    subgraph PA["Foundry prompt agent"]
        P["trail-prompt-agent<br/><i>no code, Foundry runs the loop</i>"]
    end

    subgraph LC["LangGraph"]
        A["trail-deepagents<br/><i>Deep Agents harness</i>"]
        B["trail-langgraph-workflow<br/><i>StateGraph workflow</i>"]
    end

    subgraph MAF["Microsoft Agent Framework"]
        D["trail-maf-harness<br/><i>Harness agent</i>"]
        C["trail-maf-workflow<br/><i>WorkflowBuilder workflow</i>"]
    end

    V["Same review table<br/>and verdict: reject"]

    Q --> P & A & B & C & D
    P & A & B & C & D --> V

    classDef userNode fill:#005A9E,stroke:#004578,color:#fff
    classDef appNode fill:#0078D4,stroke:#004578,color:#fff
    classDef paasNode fill:#E6F2FA,stroke:#0078D4,color:#323130
    classDef dataNode fill:#107C10,stroke:#004578,color:#fff

    class Q userNode
    class A,B,C,D appNode
    class P paasNode
    class V dataNode
```

| | Harness: the model plans the steps | Workflow: code fixes the steps |
|---|---|---|
| Foundry prompt agent | `trail-prompt-agent` (Foundry's own loop) | |
| LangGraph | `trail-deepagents` | `trail-langgraph-workflow` |
| Microsoft Agent Framework | `trail-maf-harness` | `trail-maf-workflow` |

## 2. Shared layers across the variants

Everything around the agent code is shared. One skill holds the review rules, one set of model deployments serves all five agents, one Foundry project hosts them, and one client command calls them. The agent name is the only difference in the call. The hosted agents can read the skill from a Foundry toolbox (diagram 9), and the prompt agent carries it in its instructions.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#E6F2FA','primaryTextColor':'#323130','primaryBorderColor':'#0078D4','secondaryColor':'#E6F2FA','secondaryTextColor':'#323130','secondaryBorderColor':'#0078D4','tertiaryColor':'#E6F2FA','tertiaryTextColor':'#323130','tertiaryBorderColor':'#0078D4','clusterBkg':'#E6F2FA','clusterBorder':'#0078D4','titleColor':'#323130','textColor':'#323130','edgeLabelBackground':'#ffffff','lineColor':'#005A9E','fontFamily':'Segoe UI'}}}%%
flowchart TB
    CLI["Client<br/><i>azd ai agent invoke</i>"]

    subgraph Project["Foundry project"]
        P["trail-prompt-agent<br/><i>prompt agent</i>"]
        subgraph Agents["Hosted agents, Responses protocol"]
            A["trail-deepagents"]
            B["trail-langgraph-workflow"]
            C["trail-maf-workflow"]
            D["trail-maf-harness"]
        end
        M["Model deployments<br/><i>gpt-5.4-mini, gpt-6-sol, gpt-5.6-sol</i>"]
    end

    S[("Trail-review skill<br/><i>SKILL.md and rule files</i>")]
    TB["Foundry toolbox<br/><i>skill over MCP</i>"]
    AI[("Application Insights<br/><i>traces</i>")]

    CLI -->|"same request body"| P & A & B & C & D
    S -->|"published"| TB
    TB -.->|"read at startup"| A & B & C & D
    S -.->|"inlined in instructions"| P
    P & A & B & C & D -->|"agent identity"| M
    A & B & C & D -.->|"OpenTelemetry"| AI

    classDef userNode fill:#005A9E,stroke:#004578,color:#fff
    classDef appNode fill:#0078D4,stroke:#004578,color:#fff
    classDef paasNode fill:#E6F2FA,stroke:#0078D4,color:#323130
    classDef dataNode fill:#107C10,stroke:#004578,color:#fff

    class CLI userNode
    class A,B,C,D appNode
    class P,M,TB paasNode
    class S,AI dataNode
```

| Shared element | Value in the demo |
|---|---|
| Skill | `trail-review`, in the open Agent Skills `SKILL.md` format; served by a Foundry toolbox to the hosted agents, with a bundled copy as fallback |
| Model | `gpt-5.4-mini` by default, with `gpt-6-sol` and `gpt-5.6-sol` as alternatives, all GlobalStandard |
| Hosting | Foundry hosted agents, Responses protocol, code deploy on Python 3.13; one Foundry prompt agent |
| Client | `azd ai agent invoke <name> --input-file <request>` |
| Evaluation | One eval suite run against every agent (diagram 10) |
| Observability | One Application Insights resource connected to the project |

## 3. Workflow variants: code fixes the steps

Both workflows run three model calls in a fixed order. A safety reviewer checks the safety rules, an environment reviewer checks the environment rules, and a summarizer combines both into the review table and verdict. The code reads the rule files and places them in each reviewer's prompt. The graph is written in code, so every run follows the same path.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#E6F2FA','primaryTextColor':'#323130','primaryBorderColor':'#0078D4','secondaryColor':'#E6F2FA','secondaryTextColor':'#323130','secondaryBorderColor':'#0078D4','tertiaryColor':'#E6F2FA','tertiaryTextColor':'#323130','tertiaryBorderColor':'#0078D4','clusterBkg':'#E6F2FA','clusterBorder':'#0078D4','titleColor':'#323130','textColor':'#323130','edgeLabelBackground':'#ffffff','lineColor':'#005A9E','fontFamily':'Segoe UI'}}}%%
flowchart LR
    P["Proposal<br/><i>in the request</i>"]
    R[("Rule files from the skill<br/><i>read by the code</i>")]

    subgraph LG["trail-langgraph-workflow: LangGraph StateGraph"]
        direction LR
        L1["safety_reviewer<br/><i>node</i>"] --> L2["environment_reviewer<br/><i>node</i>"] --> L3["summarizer<br/><i>node</i>"]
    end

    subgraph MW["trail-maf-workflow: Agent Framework WorkflowBuilder"]
        direction LR
        W1["Safety reviewer<br/><i>AgentExecutor</i>"] --> W2["Environment reviewer<br/><i>AgentExecutor</i>"] --> W3["Summarizer<br/><i>AgentExecutor</i>"]
    end

    O["Review table<br/>and verdict"]

    P --> L1
    P --> W1
    R -.-> LG
    R -.-> MW
    L3 --> O
    W3 --> O

    classDef userNode fill:#005A9E,stroke:#004578,color:#fff
    classDef appNode fill:#0078D4,stroke:#004578,color:#fff
    classDef paasNode fill:#E6F2FA,stroke:#0078D4,color:#323130
    classDef dataNode fill:#107C10,stroke:#004578,color:#fff

    class P userNode
    class L1,L2,L3,W1,W2,W3,O appNode
    class R dataNode
```

The two workflows map concept for concept:

| Concept | LangGraph | Microsoft Agent Framework |
|---|---|---|
| Step | Node function | `AgentExecutor` wrapping an `Agent` |
| Order | `add_edge` on a `StateGraph` | `add_edge` on a `WorkflowBuilder` |
| Context between steps | Typed graph state | Full conversation passed on (`context_mode="full"`) |
| Final output | Summarizer node | `output_executors=[summarizer]` |
| Hosting adapter | `langchain_azure_ai` Responses host | `agent_framework_foundry_hosting` Responses host |

## 4. Harness variants: the model plans the steps

Both harnesses get one instruction: use the `trail-review` skill. The model sees the short skill description, decides to load the full skill, reads the two rule files it references, and then writes the review. This pattern is called progressive disclosure. The number and order of tool calls can change from run to run. The Agent Framework harness typically follows the sequence below, while Deep Agents can read all three files in one parallel tool round and need fewer model calls.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#E6F2FA','primaryTextColor':'#323130','primaryBorderColor':'#0078D4','secondaryColor':'#E6F2FA','secondaryTextColor':'#323130','secondaryBorderColor':'#0078D4','tertiaryColor':'#E6F2FA','tertiaryTextColor':'#323130','tertiaryBorderColor':'#0078D4','clusterBkg':'#E6F2FA','clusterBorder':'#0078D4','titleColor':'#323130','textColor':'#323130','edgeLabelBackground':'#ffffff','lineColor':'#005A9E','fontFamily':'Segoe UI'}}}%%
sequenceDiagram
    autonumber
    participant C as Client
    participant H as Harness
    participant M as Model deployment
    participant S as Skill files in the container

    C->>H: Proposal text
    H->>M: Instructions, skill description, proposal
    M-->>H: Tool call: load the trail-review skill
    H->>S: Read SKILL.md
    S-->>H: Steps, rules, output format
    H->>M: Skill content
    M-->>H: Tool calls: read both rule files
    H->>S: Read the safety and environment rules
    S-->>H: Rules S1-S3 and E1-E3
    H->>M: Rule content
    M-->>H: Review table and verdict
    H-->>C: Review result
    Note over H,M: The model chooses steps 3 and 7. A workflow fixes these steps in code.
```

| Concept | Deep Agents on LangGraph | Microsoft Agent Framework harness |
|---|---|---|
| Entry point | `create_deep_agent` | `create_harness_agent` |
| Skill discovery | `skills=["/skills/"]` on a `FilesystemBackend` in virtual mode | `skills_paths=[...]` |
| Skill tools | File tools such as `read_file` | `load_skill`, `read_skill_resource` |
| Tool approval | File reads run without approval | Skill tools need approval by default; the demo auto-approves the read-only ones |
| Session state in Foundry | `FoundryCheckpointSaver` stores graph state | The Foundry host owns the conversation history |

## 5. What gets deployed and what the caller sends

`azd up` packages each agent's source folder, including its copy of the skill, and deploys it as a new hosted agent version. The proposal stays with the caller, who sends it in every request. This explains why a playground prompt without a proposal returns six `concern` rows and the verdict approve with conditions.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#E6F2FA','primaryTextColor':'#323130','primaryBorderColor':'#0078D4','secondaryColor':'#E6F2FA','secondaryTextColor':'#323130','secondaryBorderColor':'#0078D4','tertiaryColor':'#E6F2FA','tertiaryTextColor':'#323130','tertiaryBorderColor':'#0078D4','clusterBkg':'#E6F2FA','clusterBorder':'#0078D4','titleColor':'#323130','textColor':'#323130','edgeLabelBackground':'#ffffff','lineColor':'#005A9E','fontFamily':'Segoe UI'}}}%%
flowchart LR
    subgraph Dev["Developer machine"]
        SRC["Agent source folder<br/><i>code and skill copy</i>"]
        YAML["azure.yaml<br/><i>entry point, protocol, model</i>"]
        PROP[("Sample proposal<br/><i>kept outside the package</i>")]
    end

    subgraph Foundry["Foundry project"]
        VER["Hosted agent version<br/><i>immutable</i>"]
        SES["Session container<br/><i>per conversation</i>"]
    end

    U["Caller<br/><i>demo script or playground</i>"]

    SRC -->|"azd up: code deploy"| VER
    YAML --> VER
    VER -->|"starts on demand"| SES
    PROP -->|"read by the caller"| U
    U -->|"proposal in the request"| SES

    classDef userNode fill:#005A9E,stroke:#004578,color:#fff
    classDef appNode fill:#0078D4,stroke:#004578,color:#fff
    classDef paasNode fill:#E6F2FA,stroke:#0078D4,color:#323130
    classDef dataNode fill:#107C10,stroke:#004578,color:#fff

    class U userNode
    class SRC,YAML appNode
    class VER,SES paasNode
    class PROP dataNode
```

## 6. One request through Foundry hosting

The hosting path is identical for the four hosted agents. Foundry authenticates the caller, routes the request to a session container for the agent version, and stores the response and conversation history. The framework code runs inside the container behind a Responses protocol adapter. Only the framework code differs between the variants. The prompt agent skips the container: Foundry calls the model with the agent's instructions itself.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#E6F2FA','primaryTextColor':'#323130','primaryBorderColor':'#0078D4','secondaryColor':'#E6F2FA','secondaryTextColor':'#323130','secondaryBorderColor':'#0078D4','tertiaryColor':'#E6F2FA','tertiaryTextColor':'#323130','tertiaryBorderColor':'#0078D4','clusterBkg':'#E6F2FA','clusterBorder':'#0078D4','titleColor':'#323130','textColor':'#323130','edgeLabelBackground':'#ffffff','lineColor':'#005A9E','fontFamily':'Segoe UI'}}}%%
sequenceDiagram
    autonumber
    participant C as Client
    participant F as Foundry agent endpoint
    participant X as Session container
    participant A as Responses adapter
    participant G as Framework code
    participant M as Model deployment
    participant T as Application Insights

    C->>F: Responses request with Entra ID token
    F->>X: Route to the session for the agent version
    X->>A: Input and conversation history
    A->>G: Run the agent or workflow
    loop One or more model calls
        G->>M: Chat call with managed identity
        M-->>G: Text or tool calls
    end
    G-->>A: Streamed output
    A-->>F: Response events, stored by Foundry
    F-->>C: Review result and trace ID
    X-)T: Spans and logs over OpenTelemetry
```

## 7. Swapping LangGraph and Microsoft Agent Framework

A framework swap touches one layer: the agent code and the entry point in its `azure.yaml`. The skill, model deployment, Foundry project, Responses protocol, client call, and tracing all stay as they are. Switching between a harness and a workflow is a design change in the same layer.

A model swap is smaller still: a configuration value. Each agent reads its model deployment name from one environment variable, and every hosted agent version keeps the model it was deployed with. The demo deploys one version per model, so the caller picks `gpt-5.4-mini`, `gpt-6-sol`, or `gpt-5.6-sol` by agent version at call time, and the agent code stays the same.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#E6F2FA','primaryTextColor':'#323130','primaryBorderColor':'#0078D4','secondaryColor':'#E6F2FA','secondaryTextColor':'#323130','secondaryBorderColor':'#0078D4','tertiaryColor':'#E6F2FA','tertiaryTextColor':'#323130','tertiaryBorderColor':'#0078D4','clusterBkg':'#E6F2FA','clusterBorder':'#0078D4','titleColor':'#323130','textColor':'#323130','edgeLabelBackground':'#ffffff','lineColor':'#005A9E','fontFamily':'Segoe UI'}}}%%
flowchart TB
    subgraph Swap["Changes in a framework swap"]
        direction LR
        LGC["LangGraph code<br/><i>Deep Agents or StateGraph</i>"]
        MAFC["Agent Framework code<br/><i>harness or WorkflowBuilder</i>"]
        LGC <-->|"rewrite the agent file,<br/>update the entry point"| MAFC
    end

    subgraph Stable["Stays the same"]
        direction LR
        CL["Client call<br/><i>Responses protocol</i>"]
        FP["Foundry project<br/><i>hosting, identity, storage</i>"]
        MD["Model deployment"]
        OB[("Application Insights<br/><i>traces</i>")]
        SK[("Trail-review skill")]
    end

    Swap -->|"runs on"| Stable

    classDef userNode fill:#005A9E,stroke:#004578,color:#fff
    classDef appNode fill:#0078D4,stroke:#004578,color:#fff
    classDef paasNode fill:#E6F2FA,stroke:#0078D4,color:#323130
    classDef dataNode fill:#107C10,stroke:#004578,color:#fff

    class CL userNode
    class LGC,MAFC appNode
    class FP,MD paasNode
    class OB,SK dataNode
```

## 8. Reading the traces

Every call returns a trace ID. Paste it into the Traces view of the agent in the Foundry portal, or search for it as `OperationId` in Application Insights. Typical shapes are described below.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#E6F2FA','primaryTextColor':'#323130','primaryBorderColor':'#0078D4','secondaryColor':'#E6F2FA','secondaryTextColor':'#323130','secondaryBorderColor':'#0078D4','tertiaryColor':'#E6F2FA','tertiaryTextColor':'#323130','tertiaryBorderColor':'#0078D4','clusterBkg':'#E6F2FA','clusterBorder':'#0078D4','titleColor':'#323130','textColor':'#323130','edgeLabelBackground':'#ffffff','lineColor':'#005A9E','fontFamily':'Segoe UI'}}}%%
flowchart LR
    ID["Trace ID<br/><i>printed by the client</i>"]

    subgraph Trace["One trace in Application Insights"]
        direction TB
        INV["invoke_agent<br/><i>platform span</i>"]
        CH["chat gpt-5.4-mini<br/><i>model calls</i>"]
        TO["execute_tool<br/><i>harness tool calls</i>"]
        IN[("HTTP and log records<br/><i>identity, storage, checkpoints</i>")]
    end

    PT["Foundry portal<br/><i>agent traces view</i>"]

    ID --> INV
    INV --> CH & TO & IN
    Trace --> PT

    classDef userNode fill:#005A9E,stroke:#004578,color:#fff
    classDef appNode fill:#0078D4,stroke:#004578,color:#fff
    classDef paasNode fill:#E6F2FA,stroke:#0078D4,color:#323130
    classDef dataNode fill:#107C10,stroke:#004578,color:#fff

    class ID userNode
    class INV,CH,TO appNode
    class IN dataNode
    class PT paasNode
```

| Agent | Model calls | Tool calls | What the trace shows |
|---|---|---|---|
| `trail-langgraph-workflow` | 3 | None | Same three steps on every run |
| `trail-maf-workflow` | 3 | None | Same three steps on every run |
| `trail-maf-harness` | One per tool round, plus the answer | `load_skill`, then `read_skill_resource` for the rule files | The model chooses which skill files to read |
| `trail-deepagents` | Fewer, when file reads are batched | File reads, often in one parallel batch | Many records are identity log lines and checkpoint storage calls |

Compare `chat` and `execute_tool` spans to compare reasoning. The total record count mostly reflects logging and state storage.

## 9. Skills from a Foundry toolbox

The skill is published once to a Foundry toolbox, which serves it over MCP. Each hosted agent reads it when its session starts, with its own agent identity. Publishing a new skill version changes the rules for every agent without a redeploy; each agent picks it up in its next new session. The toolbox can live in a different Foundry project than the agents, which is useful when the Skills API preview is not yet available in the region of the agent project.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#E6F2FA','primaryTextColor':'#323130','primaryBorderColor':'#0078D4','secondaryColor':'#E6F2FA','secondaryTextColor':'#323130','secondaryBorderColor':'#0078D4','tertiaryColor':'#E6F2FA','tertiaryTextColor':'#323130','tertiaryBorderColor':'#0078D4','clusterBkg':'#E6F2FA','clusterBorder':'#0078D4','titleColor':'#323130','textColor':'#323130','edgeLabelBackground':'#ffffff','lineColor':'#005A9E','fontFamily':'Segoe UI'}}}%%
sequenceDiagram
    autonumber
    participant O as Skill owner
    participant K as Foundry skill
    participant T as Foundry toolbox
    participant X as Hosted agent session
    participant M as Model deployment

    O->>K: publish-skill.ps1 (new default version)
    K-->>T: Toolbox serves the default version
    Note over X: New session starts
    X->>T: MCP read skill://index.json (agent identity)
    T-->>X: Skill list
    X->>T: MCP read skill://trail-review.zip
    T-->>X: SKILL.md and rule files
    X->>M: Review with the toolbox rules
```

| Variant | How it reads the toolbox skill | If the toolbox is unreachable |
|---|---|---|
| 01, 02, 03 | A small loader downloads the skill into a local folder; the agent code reads it as before | Falls back to the skill copy in the package and logs it |
| 04 | Agent Framework's `FoundryToolbox` hands the toolbox skills to the harness | Does not start |
| 00 | Skill text in the prompt agent's instructions | Not applicable |

## 10. Evaluating the variants

One sample proposal shows that the agents work. An eval suite scores each agent on many proposals, so the variants and models can be compared on numbers. The beta `azd ai agent eval` commands generate the suite from the agent's instructions and run it against each agent.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#E6F2FA','primaryTextColor':'#323130','primaryBorderColor':'#0078D4','secondaryColor':'#E6F2FA','secondaryTextColor':'#323130','secondaryBorderColor':'#0078D4','tertiaryColor':'#E6F2FA','tertiaryTextColor':'#323130','tertiaryBorderColor':'#0078D4','clusterBkg':'#E6F2FA','clusterBorder':'#0078D4','titleColor':'#323130','textColor':'#323130','edgeLabelBackground':'#ffffff','lineColor':'#005A9E','fontFamily':'Segoe UI'}}}%%
flowchart LR
    I["Agent instructions<br/><i>agent-instruction.md</i>"]
    G["azd ai agent eval generate"]
    DS[("Test proposals<br/><i>generated samples</i>")]
    RB[("Rubric evaluator<br/><i>7 weighted dimensions</i>")]
    BI["Built-in evaluators<br/><i>task adherence, intent resolution</i>"]
    R["azd ai agent eval run<br/><i>once per agent</i>"]
    AG["Agent under test<br/><i>00 to 04</i>"]
    SC[("Scores per agent<br/><i>portal report</i>")]

    I --> G --> DS & RB
    DS & RB & BI --> R
    R -->|"sends each proposal"| AG
    AG -->|"answers scored"| SC

    classDef userNode fill:#005A9E,stroke:#004578,color:#fff
    classDef appNode fill:#0078D4,stroke:#004578,color:#fff
    classDef paasNode fill:#E6F2FA,stroke:#0078D4,color:#323130
    classDef dataNode fill:#107C10,stroke:#004578,color:#fff

    class I userNode
    class G,R,AG appNode
    class BI paasNode
    class DS,RB,SC dataNode
```

For a trial, the generated proposals become a starting point next to real anonymized proposals with a human reviewer's verdict.

## 11. Exploring the demo yourself

The steps below follow the diagrams in a practical order. The README in the repository root lists the commands for deploying, running, tracing, and evaluating the agents.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#E6F2FA','primaryTextColor':'#323130','primaryBorderColor':'#0078D4','secondaryColor':'#E6F2FA','secondaryTextColor':'#323130','secondaryBorderColor':'#0078D4','tertiaryColor':'#E6F2FA','tertiaryTextColor':'#323130','tertiaryBorderColor':'#0078D4','clusterBkg':'#E6F2FA','clusterBorder':'#0078D4','titleColor':'#323130','textColor':'#323130','edgeLabelBackground':'#ffffff','lineColor':'#005A9E','fontFamily':'Segoe UI'}}}%%
flowchart TD
    S1["1. Understand the variants<br/><i>diagrams 1 and 2</i>"]
    S2["2. Read the shared skill<br/><i>SKILL.md, rule files, toolbox, diagram 9</i>"]
    S3["3. Compare the code<br/><i>workflow file and harness file, diagrams 3 and 4</i>"]
    S4["4. Run all five agents<br/><i>same request, same verdict</i>"]
    S5["5. Open two traces<br/><i>one workflow, one harness, diagram 8</i>"]
    S6["6. Assess swappability<br/><i>diagram 7</i>"]
    S7["7. Switch the model<br/><i>demo.ps1 -Model gpt-6-sol</i>"]
    S8["8. Run the eval suite<br/><i>portal report, diagram 10</i>"]
    RD["Saved results<br/><i>evals/results, expected verdict in the README</i>"]

    S1 --> S2 --> S3 --> S4 --> S5 --> S6 --> S7 --> S8
    S4 -.->|"compare with"| RD

    classDef userNode fill:#005A9E,stroke:#004578,color:#fff
    classDef appNode fill:#0078D4,stroke:#004578,color:#fff
    classDef paasNode fill:#E6F2FA,stroke:#0078D4,color:#323130
    classDef dataNode fill:#107C10,stroke:#004578,color:#fff

    class S1,S6 userNode
    class S2,S3,S4,S5,S7,S8 appNode
    class RD dataNode
```

## Sources

- Microsoft Learn, Hosted agents in Foundry Agent Service: hosting model, sessions, and the Responses protocol. https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents
- Microsoft Learn, Set up tracing in Microsoft Foundry: connecting Application Insights and searching traces by trace ID. https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup (fetched 2026-09-28)
- Microsoft Learn, Export hosted agent telemetry by using OpenTelemetry: telemetry export from hosted agent containers. https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/configure-hosted-agent-telemetry (fetched 2026-09-28)
- Microsoft Learn, Agent Framework Agent Harness: `create_harness_agent` and its options. https://learn.microsoft.com/en-us/agent-framework/concepts/harness
- Microsoft Learn, Agent Framework Agent Skills: progressive disclosure and the skill tools. https://learn.microsoft.com/en-us/agent-framework/agents/skills
- LangChain docs, Deep Agents skills: the `skills` parameter and `FilesystemBackend`. https://docs.langchain.com/oss/python/deepagents/skills
- Agent Skills specification: the `SKILL.md` format. https://agentskills.io/specification
- Microsoft Foundry samples, Python hosted agents: the starting samples for all four hosted agents. https://github.com/microsoft-foundry/foundry-samples/tree/main/samples/python/hosted-agents
- Microsoft Learn, Curate intent-based toolbox in Foundry: toolbox MCP endpoint and skills. https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/toolbox (fetched 2026-09-29)
- Microsoft Learn, Agent Framework Foundry Toolbox: `FoundryToolbox` and its skills provider. https://learn.microsoft.com/en-us/agent-framework/integrations/by-component/tools/foundry-toolbox (fetched 2026-09-29)
- Microsoft Learn, Run agent evaluations with the azd CLI (preview): `eval generate` and `eval run`. https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/azure-developer-cli-evaluation (fetched 2026-09-29)
