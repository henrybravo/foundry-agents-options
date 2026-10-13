# Trace logs for the five variants

Span listings from Application Insights for three runs of each hosted agent (the prompt agent has no client-visible trace ID), taken on 13 Oct 2026 in the swedencentral region. Each run used `./demo.sh` with the sample trail plan and the `gpt-5.4-mini` deployment. The listings show the semantic spans only (`invoke_agent`, `chat`, `execute_tool`) as an indented tree, with each span's offset from the first span and its duration; `HTTP` spans (token, storage, and model endpoint calls) are counted and omitted. No resource names or identifiers beyond trace IDs are included.

How to read them:

- The workflows made three model calls in all six runs. In two of the six traces a second instrumentation layer reported the same calls again, so those traces show extra `chat` and `invoke_agent` spans next to the real ones.
- Deep Agents varied its steps: one parallel tool round in two runs and four tool calls in the third.
- The MAF harness followed the same route in all three runs: `load_skill`, then a parallel call with two `read_skill_resource` reads. Its traces carry the second layer's duplicate spans in every run.
- Indentation shows parent and child links among the listed spans. Where the two layers interleave, a span's parent may be an omitted span, so read the order and offsets, not the nesting alone.
- Three runs per agent is a small sample. Treat the listings as observations from this repository on preview tooling, not as platform behavior.

## trail-langgraph-workflow (02 LangGraph workflow, workflow)

### Run 1, trace `5bb3efc44313ddb8978484ff1540aeb9`

6 semantic spans (3 chat, 0 tool, 3 invoke_agent) and 6 HTTP spans omitted.

```text
+    0 ms  invoke_agent trail-langgraph-workflow:1        1157 ms
  +    0 ms  chat gpt-5.4-mini-2026-03-17                   1042 ms
+ 1609 ms  invoke_agent trail-langgraph-workflow:1        1291 ms
  + 1610 ms  chat gpt-5.4-mini-2026-03-17                   1206 ms
+ 3535 ms  invoke_agent trail-langgraph-workflow:1        1800 ms
  + 3535 ms  chat gpt-5.4-mini-2026-03-17                   1692 ms
```

### Run 2, trace `301d8d4b899cd7ceda673396aa60d979`

10 semantic spans (6 chat, 0 tool, 4 invoke_agent) and 6 HTTP spans omitted. This trace also carries spans from a second instrumentation layer (plain `chat gpt-5.4-mini` names), so some model calls appear twice.

```text
+    0 ms  invoke_agent LangGraph                         6414 ms
  +   14 ms  chat gpt-5.4-mini                              2268 ms
+  808 ms  invoke_agent trail-langgraph-workflow:1        1380 ms
  + 1382 ms  chat gpt-5.4-mini-2026-03-17                    664 ms
  + 2286 ms  chat gpt-5.4-mini                              1804 ms
+ 2898 ms  invoke_agent trail-langgraph-workflow:1        1059 ms
  + 2898 ms  chat gpt-5.4-mini-2026-03-17                    938 ms
  + 4093 ms  chat gpt-5.4-mini                              2319 ms
+ 4438 ms  invoke_agent trail-langgraph-workflow:1        1884 ms
  + 4438 ms  chat gpt-5.4-mini-2026-03-17                   1748 ms
```

### Run 3, trace `e68b858964265e253ed28310f2205591`

6 semantic spans (3 chat, 0 tool, 3 invoke_agent) and 5 HTTP spans omitted.

```text
+    0 ms  invoke_agent trail-langgraph-workflow:1        1444 ms
  +    0 ms  chat gpt-5.4-mini-2026-03-17                   1341 ms
+ 2442 ms  invoke_agent trail-langgraph-workflow:1        1621 ms
  + 2442 ms  chat gpt-5.4-mini-2026-03-17                   1397 ms
+ 4620 ms  invoke_agent trail-langgraph-workflow:1        1909 ms
  + 4621 ms  chat gpt-5.4-mini-2026-03-17                   1798 ms
```

## trail-maf-workflow (03 MAF workflow, workflow)

### Run 1, trace `835ec5a1dbda0b39da9e27b797342bce`

11 semantic spans (5 chat, 0 tool, 6 invoke_agent) and 36 HTTP spans omitted. This trace also carries spans from a second instrumentation layer (plain `chat gpt-5.4-mini` names), so some model calls appear twice.

```text
+    0 ms  invoke_agent safety_reviewer                   2628 ms
  +    0 ms  chat gpt-5.4-mini                              2626 ms
+ 1189 ms  invoke_agent trail-maf-workflow:1              1276 ms
  + 1190 ms  chat gpt-5.4-mini-2026-03-17                   1180 ms
+ 2942 ms  invoke_agent environment_reviewer              1517 ms
+ 3250 ms  invoke_agent trail-maf-workflow:1              1137 ms
  + 3251 ms  chat gpt-5.4-mini-2026-03-17                   1021 ms
+ 4711 ms  invoke_agent summarizer                        2155 ms
  + 4712 ms  chat gpt-5.4-mini                              2154 ms
+ 5329 ms  invoke_agent trail-maf-workflow:1              1446 ms
  + 5581 ms  chat gpt-5.4-mini-2026-03-17                   1109 ms
```

### Run 2, trace `c44ee10fa773564e601d8cb1c6e6ab2c`

6 semantic spans (3 chat, 0 tool, 3 invoke_agent) and 18 HTTP spans omitted.

```text
+    0 ms  invoke_agent trail-maf-workflow:1              1212 ms
  +  374 ms  chat gpt-5.4-mini-2026-03-17                    738 ms
+ 4097 ms  invoke_agent trail-maf-workflow:1              4284 ms
  + 4098 ms  chat gpt-5.4-mini-2026-03-17                   3791 ms
+ 9482 ms  invoke_agent trail-maf-workflow:1              1421 ms
  + 9483 ms  chat gpt-5.4-mini-2026-03-17                   1305 ms
```

### Run 3, trace `d9d6703c6d1739bf7f03fb26b007e700`

6 semantic spans (3 chat, 0 tool, 3 invoke_agent) and 15 HTTP spans omitted.

```text
+    0 ms  invoke_agent trail-maf-workflow:1              1446 ms
  +  600 ms  chat gpt-5.4-mini-2026-03-17                    724 ms
+ 2113 ms  invoke_agent trail-maf-workflow:1              1195 ms
  + 2113 ms  chat gpt-5.4-mini-2026-03-17                   1117 ms
+ 4021 ms  invoke_agent trail-maf-workflow:1              1777 ms
  + 4021 ms  chat gpt-5.4-mini-2026-03-17                   1660 ms
```

## trail-deepagents (01 Deep Agents on LangGraph, harness)

### Run 1, trace `2e81c482cbddb824de94361ad7f124b2`

6 semantic spans (2 chat, 1 tool, 3 invoke_agent) and 25 HTTP spans omitted.

```text
+    0 ms  invoke_agent trail-deepagents:1                 827 ms
  +  573 ms  chat gpt-5.4-mini-2026-03-17                    160 ms
+ 2428 ms  invoke_agent trail-deepagents:1                 857 ms
  + 2914 ms  execute_tool multi_tool_use.parallel            370 ms
+ 4919 ms  invoke_agent trail-deepagents:1                2749 ms
  + 5779 ms  chat gpt-5.4-mini-2026-03-17                   1720 ms
```

### Run 2, trace `c5a2bffa33f699eef8729632c02a9868`

7 semantic spans (3 chat, 1 tool, 3 invoke_agent) and 13 HTTP spans omitted.

```text
+    0 ms  invoke_agent trail-deepagents:1                1061 ms
  +  753 ms  chat gpt-5.4-mini-2026-03-17                    216 ms
+ 2747 ms  invoke_agent trail-deepagents:1                 789 ms
  + 3156 ms  execute_tool multi_tool_use.parallel            379 ms
+ 5291 ms  invoke_agent trail-deepagents:1                2470 ms
  + 5704 ms  chat gpt-5.4-mini-2026-03-17                     20 ms
  + 5724 ms  chat gpt-5.4-mini-2026-03-17                   1932 ms
```

### Run 3, trace `6391184c8c7e751982aefd25c47ff62a`

13 semantic spans (5 chat, 4 tool, 4 invoke_agent) and 87 HTTP spans omitted. This trace also carries spans from a second instrumentation layer (plain `chat gpt-5.4-mini` names), so some model calls appear twice.

```text
+    0 ms  invoke_agent trail-deepagents                 10844 ms
  + 1700 ms  chat gpt-5.4-mini                              1670 ms
+ 2394 ms  invoke_agent trail-deepagents:1                 801 ms
  + 2906 ms  chat gpt-5.4-mini-2026-03-17                    211 ms
  + 4025 ms  execute_tool read_file                            1 ms
  + 4512 ms  chat gpt-5.4-mini                              1350 ms
+ 4930 ms  invoke_agent trail-deepagents:1                 819 ms
  + 5437 ms  execute_tool multi_tool_use.parallel            311 ms
  + 6447 ms  execute_tool read_file                            3 ms
  + 6448 ms  execute_tool read_file                            3 ms
  + 7021 ms  chat gpt-5.4-mini                              3427 ms
+ 7589 ms  invoke_agent trail-deepagents:1                2697 ms
  + 7989 ms  chat gpt-5.4-mini-2026-03-17                   2154 ms
```

## trail-maf-harness (04 MAF Harness Agent, harness)

### Run 1, trace `baf907b02e13014a78660288a8cc5b66`

13 semantic spans (4 chat, 4 tool, 5 invoke_agent) and 10 HTTP spans omitted. This trace also carries spans from a second instrumentation layer (plain `chat gpt-5.4-mini` names), so some model calls appear twice.

```text
+    0 ms  invoke_agent trail-maf-harness:1                904 ms
  +  631 ms  chat gpt-5.4-mini-2026-03-17                    151 ms
+  909 ms  invoke_agent trail-maf-harness                 1401 ms
  +  912 ms  execute_tool load_skill                           2 ms
  +  915 ms  chat gpt-5.4-mini                              1394 ms
+ 1378 ms  invoke_agent trail-maf-harness:1                924 ms
  + 2011 ms  execute_tool multi_tool_use.parallel            290 ms
+ 2310 ms  invoke_agent trail-maf-harness                 3627 ms
  + 2313 ms  execute_tool read_skill_resource                  2 ms
  + 2314 ms  execute_tool read_skill_resource                  2 ms
  + 2317 ms  chat gpt-5.4-mini                              3619 ms
+ 3224 ms  invoke_agent trail-maf-harness:1               2697 ms
  + 4124 ms  chat gpt-5.4-mini-2026-03-17                   1643 ms
```

### Run 2, trace `2d0b744d6d16e9a5ed299a4efdf31e14`

16 semantic spans (6 chat, 4 tool, 6 invoke_agent) and 15 HTTP spans omitted. This trace also carries spans from a second instrumentation layer (plain `chat gpt-5.4-mini` names), so some model calls appear twice.

```text
+    0 ms  invoke_agent trail-maf-harness                 1642 ms
  +    8 ms  chat gpt-5.4-mini                              1633 ms
+ 1070 ms  invoke_agent trail-maf-harness:1                570 ms
  + 1476 ms  chat gpt-5.4-mini-2026-03-17                     74 ms
+ 1643 ms  invoke_agent trail-maf-harness                 1865 ms
  + 1647 ms  execute_tool load_skill                           2 ms
  + 1649 ms  chat gpt-5.4-mini                              1858 ms
+ 2155 ms  invoke_agent trail-maf-harness:1               1355 ms
  + 2782 ms  chat gpt-5.4-mini-2026-03-17                    453 ms
  + 3235 ms  execute_tool multi_tool_use.parallel            274 ms
+ 3508 ms  invoke_agent trail-maf-harness                 3322 ms
  + 3512 ms  execute_tool read_skill_resource                  3 ms
  + 3513 ms  execute_tool read_skill_resource                  2 ms
  + 3516 ms  chat gpt-5.4-mini                              3313 ms
+ 3994 ms  invoke_agent trail-maf-harness:1               2833 ms
  + 4586 ms  chat gpt-5.4-mini-2026-03-17                   2149 ms
```

### Run 3, trace `97caf068585d415b78f967994776723a`

13 semantic spans (4 chat, 4 tool, 5 invoke_agent) and 10 HTTP spans omitted. This trace also carries spans from a second instrumentation layer (plain `chat gpt-5.4-mini` names), so some model calls appear twice.

```text
+    0 ms  invoke_agent trail-maf-harness:1                536 ms
  +  384 ms  chat gpt-5.4-mini-2026-03-17                     72 ms
+  532 ms  invoke_agent trail-maf-harness                 6313 ms
  +  537 ms  execute_tool load_skill                           3 ms
  +  541 ms  chat gpt-5.4-mini                              6304 ms
+ 2286 ms  invoke_agent trail-maf-harness:1               4469 ms
  + 4147 ms  chat gpt-5.4-mini-2026-03-17                   1493 ms
  + 5641 ms  execute_tool multi_tool_use.parallel           1113 ms
+ 6846 ms  invoke_agent trail-maf-harness                 3080 ms
  + 6850 ms  execute_tool read_skill_resource                  3 ms
  + 6851 ms  execute_tool read_skill_resource                  3 ms
+ 7353 ms  invoke_agent trail-maf-harness:1               2567 ms
  + 7783 ms  chat gpt-5.4-mini-2026-03-17                   1940 ms
```
