#!/usr/bin/env python3
"""Run a bounded OpenAI API-powered architecture swarm for Vapor.

This script intentionally uses direct Responses API calls instead of adding an
agent framework first. That keeps cost accounting and failure behavior easy to
inspect for the initial $10 experiment.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import sys
import time
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


DEFAULT_KEY_PATH = Path.home() / ".config" / "openai" / "api_key"
DEFAULT_RUN_ROOT = Path("/tmp") / "vapor-api-swarm-runs"

PRICE_PER_MILLION: dict[str, tuple[float, float]] = {
    "gpt-5.6": (5.00, 30.00),
    "gpt-5.6-sol": (5.00, 30.00),
    "gpt-5.6-terra": (2.50, 15.00),
    "gpt-5.6-luna": (1.00, 6.00),
}

CONTEXT_FILES: tuple[str, ...] = (
    "AGENTS.md",
    "docs/deployment-status.md",
    "docs/vertical-slice-contracts.md",
    "docs/decisions-and-backlog.md",
    "docs/github-deployment.md",
    "docs/identity-auth-runbook.md",
    "deploy/README.md",
    "Vapor-Diagnostics-Server/AGENTS.md",
    "Vapor-Diagnostics-Server/README.md",
    "Vapor-Diagnostics-Server/src/main.rs",
)

SHARED_SYSTEM_PROMPT = """\
You are an API-funded read-only architecture worker for Vapor server planning.

Hard rules:
- Do not claim live VPS state was verified.
- Do not request secrets.
- Do not suggest printing, committing, or copying secrets.
- Do not propose SSH/deploy/live mutation as part of this report.
- Treat checked-in repo docs/source context as implemented or documented state.
- Treat future services as speculative unless the context says they already exist.
- Preserve clear service/domain/authority boundaries.
- Prefer minimal future boundaries over fake implementation scaffolding.
- If a responsibility does not fit an existing service, name the missing domain
  or reject the responsibility.

Output concise markdown with concrete architecture judgment. Do not include long
quotes from the input context.
"""


@dataclass(frozen=True)
class AgentSpec:
    agent_id: str
    title: str
    model: str
    reasoning_effort: str
    max_output_tokens: int
    task: str


@dataclass
class UsageRecord:
    agent_id: str
    title: str
    model: str
    input_tokens: int
    output_tokens: int
    total_tokens: int
    estimated_cost_usd: float
    response_id: str | None
    elapsed_seconds: float
    output_file: str


class Logger:
    def __init__(self, log_path: Path) -> None:
        self.log_path = log_path
        self.log_path.parent.mkdir(parents=True, exist_ok=True)

    def write(self, level: str, message: str) -> None:
        timestamp = datetime.now().strftime("%H:%M:%S")
        line = f"[{timestamp}] [{level}] {message}"
        print(line, flush=True)
        with self.log_path.open("a", encoding="utf-8") as log_file:
            log_file.write(f"{line}\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a bounded OpenAI API swarm for Vapor architecture planning.",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="Path to Vapor-Server-Root. Default: inferred from this script.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=None,
        help=f"Output directory. Default: {DEFAULT_RUN_ROOT}/<timestamp>",
    )
    parser.add_argument(
        "--key-file",
        type=Path,
        default=DEFAULT_KEY_PATH,
        help=f"API key file fallback if OPENAI_API_KEY is unset. Default: {DEFAULT_KEY_PATH}",
    )
    parser.add_argument(
        "--max-budget-usd",
        type=float,
        default=8.50,
        help="Budget guard for estimated API spend. Default: 8.50.",
    )
    parser.add_argument(
        "--worker-model",
        default="gpt-5.6-terra",
        choices=sorted(PRICE_PER_MILLION),
        help="Model for the 10 worker calls. Default: gpt-5.6-terra.",
    )
    parser.add_argument(
        "--manager-model",
        default="gpt-5.6-sol",
        choices=sorted(PRICE_PER_MILLION),
        help="Model for the 2 manager calls. Default: gpt-5.6-sol.",
    )
    parser.add_argument(
        "--worker-effort",
        default="medium",
        choices=("none", "low", "medium", "high", "xhigh", "max"),
        help="Reasoning effort for workers. Default: medium.",
    )
    parser.add_argument(
        "--manager-effort",
        default="high",
        choices=("none", "low", "medium", "high", "xhigh", "max"),
        help="Reasoning effort for managers. Default: high.",
    )
    parser.add_argument(
        "--concurrency",
        type=int,
        default=10,
        help="Maximum concurrent worker API calls. Default: 10.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print plan and context sizes without making API calls.",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Skip the interactive confirmation before spending API tokens.",
    )
    parser.add_argument(
        "--save-raw",
        action="store_true",
        help="Save raw SDK response JSON for debugging. Off by default.",
    )
    return parser.parse_args()


def utc_stamp() -> str:
    return datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")


def read_api_key(key_file: Path) -> str:
    env_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if env_key:
        return env_key

    key_path = key_file.expanduser()
    if key_path.exists():
        return key_path.read_text(encoding="utf-8").strip()

    return ""


def load_context(repo_root: Path) -> tuple[str, list[dict[str, Any]]]:
    sections: list[str] = []
    manifest: list[dict[str, Any]] = []

    for relative in CONTEXT_FILES:
        path = repo_root / relative
        if not path.exists():
            raise FileNotFoundError(f"Required context file missing: {path}")
        text = path.read_text(encoding="utf-8", errors="replace")
        sections.append(f"\n\n===== FILE: {relative} =====\n{text}")
        manifest.append(
            {
                "path": relative,
                "bytes": len(text.encode("utf-8")),
                "approx_tokens": approximate_tokens(text),
            }
        )

    context = "\n".join(sections).strip()
    return context, manifest


def approximate_tokens(text: str) -> int:
    return max(1, len(text) // 4)


def make_worker_specs(worker_model: str, effort: str) -> list[AgentSpec]:
    tasks = [
        (
            "worker-01-boundary-map",
            "Future service/domain boundary map",
            "Produce a future Vapor server domain/service boundary map. Focus on homepage, docs, identity, diagnostics, publish/pipeline, toolchain, artifact, registry/catalog, MCP/capability surface, operations/recovery, and any missing domains. Do not design internals; focus on ownership and authority separation.",
        ),
        (
            "worker-02-publish-pipeline",
            "Publish/pipeline authority",
            "Speculate deeply on Vapor-Publish-Server / Vapor-Pipeline-Server. Design conceptual authority for local root/developer request, identity verification, GitHub link verification, Vapor role verification, signed publish jobs, protected runner execution, Steam/Workshop credential isolation, audit logs, and artifacts. Recommend whether publish and pipeline start as one service or separate names.",
        ),
        (
            "worker-03-artifacts",
            "Artifact service boundary",
            "Analyze whether Vapor-Artifact-Server deserves a separate boundary. Compare it against docs, pipeline, registry/catalog, and backups. Focus on build outputs, generated docs bundles, crash symbols, release manifests, checksums, provenance metadata, retention, and download authorization.",
        ),
        (
            "worker-04-toolchain",
            "Toolchain service boundary",
            "Speculate on Vapor-Toolchain-Server. Focus on blessed tool versions, checksums, Rust/toolchain manifests, Steamworks SDK versions, content build tools, app-local manifests, and binary caches later. Define what can start as static docs/manifests versus what eventually needs a service API.",
        ),
        (
            "worker-05-registry-catalog",
            "Registry/catalog boundary",
            "Determine whether Vapor needs a Registry/Catalog server boundary. Focus on known apps, packages, game modules, Workshop content records, compatibility constraints, visibility states, ownership metadata, and dependency graphs. Separate clearly from artifact storage and publishing actions.",
        ),
        (
            "worker-06-identity-pressure",
            "Identity expansion pressure",
            "Stress-test Vapor-Identity-Server's boundary. Identify what should stay in Identity and what should not. Consider roles, teams, entitlements, developer membership, Steam profiles, GitHub links, root authorization, service tokens/JWTs, publishing authority, and audit. Recommend future split points without splitting prematurely.",
        ),
        (
            "worker-07-diagnostics-contract",
            "Diagnostics future contract",
            "Design the next diagnostics contract from the current implementation baseline. Focus on upload schema, storage shape, redaction, size limits, retention, listing/download UX, root authorization, player privacy, no hostname, no persistent machine id, and useful coarse system fields.",
        ),
        (
            "worker-08-docs-truth",
            "Docs truth surface",
            "Speculate on Vapor-Docs-Server as the truth surface. Consider uploaded docs bundles, generated API docs, versioned docs, current pointers, provenance, docs publishing authorization, docs generated from engine/game repos, and overlap with Artifact/Pipeline.",
        ),
        (
            "worker-09-mcp-capabilities",
            "MCP/capability surface",
            "Design a future Vapor-MCP-Server boundary. MCP must not own the backend. Define useful resources and tools over existing services: docs, diagnostics, deployment status, backup manifests, identity summaries, publish job status, and audit summaries. Mark read-only-first tools versus gated authority later.",
        ),
        (
            "worker-10-ops-shell-roadmap",
            "Operations, recovery, and Vapor Shell",
            "Speculate on Vapor operations/recovery and Vapor Shell operator UX. Focus on state export/import, backup listing, restore drills, fresh VPS restore, deploy status, service health, last-known-good versions, disaster recovery evidence, and commands that avoid raw curl/admin tokens/internal routes.",
        ),
    ]

    return [
        AgentSpec(
            agent_id=agent_id,
            title=title,
            model=worker_model,
            reasoning_effort=effort,
            max_output_tokens=2600,
            task=task,
        )
        for agent_id, title, task in tasks
    ]


def make_manager_specs(manager_model: str, effort: str) -> list[AgentSpec]:
    return [
        AgentSpec(
            agent_id="manager-01-security-authority-qa",
            title="Security and authority QA",
            model=manager_model,
            reasoning_effort=effort,
            max_output_tokens=3600,
            task=(
                "Review all worker reports for security, authority, privacy, and operations risks. "
                "Find incorrect boundary assumptions, unsafe sequencing, premature credential exposure, "
                "identity/publishing conflation, diagnostics privacy problems, and live-system mutation risks. "
                "Return prioritized findings and concrete corrections."
            ),
        ),
        AgentSpec(
            agent_id="manager-02-final-synthesis",
            title="Final architecture synthesis",
            model=manager_model,
            reasoning_effort=effort,
            max_output_tokens=5200,
            task=(
                "Synthesize the worker reports plus the security/authority QA into a final recommendation. "
                "Return: recommended boundary map, near-term sequence, disagreements/tradeoffs, candidate docs "
                "to create/update, candidate repos to create now versus defer, and the single best next concrete action."
            ),
        ),
    ]


def build_worker_input(context: str, spec: AgentSpec) -> str:
    return f"""\
<vapor_context>
{context}
</vapor_context>

<task>
{spec.task}
</task>

Return markdown with these headings:

1. Scope
2. Current implemented/documented facts
3. Recommended future boundary
4. Responsibilities
5. Non-responsibilities
6. Route/API implications
7. State/data implications
8. Auth/authority implications
9. Risks and open questions
10. What not to build yet
11. Next concrete step
"""


def build_manager_input(
    context: str,
    spec: AgentSpec,
    reports: dict[str, str],
    manager_qa: str | None = None,
) -> str:
    report_sections = []
    for agent_id, report in reports.items():
        report_sections.append(f"\n\n===== REPORT: {agent_id} =====\n{report}")

    qa_section = ""
    if manager_qa:
        qa_section = f"\n\n===== SECURITY/AUTHORITY QA =====\n{manager_qa}"

    return f"""\
<vapor_context>
{context}
</vapor_context>

<worker_reports>
{''.join(report_sections)}
</worker_reports>
{qa_section}

<task>
{spec.task}
</task>

Be strict about separating implemented behavior from speculative architecture.
Do not invent consensus where worker reports disagree.
Return concise markdown with concrete recommendations.
"""


def safe_filename(agent_id: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_.-]+", "_", agent_id).strip("_")


def usage_value(usage: Any, key: str) -> int:
    if usage is None:
        return 0
    if isinstance(usage, dict):
        return int(usage.get(key) or 0)
    return int(getattr(usage, key, 0) or 0)


def estimate_cost(model: str, input_tokens: int, output_tokens: int) -> float:
    input_price, output_price = PRICE_PER_MILLION[model]
    return (input_tokens * input_price / 1_000_000) + (
        output_tokens * output_price / 1_000_000
    )


def response_text(response: Any) -> str:
    direct = getattr(response, "output_text", None)
    if direct:
        return str(direct).strip()

    chunks: list[str] = []
    for item in getattr(response, "output", []) or []:
        for content in getattr(item, "content", []) or []:
            text = getattr(content, "text", None)
            if text:
                chunks.append(str(text))
    return "\n".join(chunks).strip()


def response_to_json(response: Any) -> str:
    if hasattr(response, "model_dump_json"):
        return response.model_dump_json(indent=2)
    if hasattr(response, "to_json"):
        return response.to_json()
    return json.dumps(str(response), indent=2)


async def run_agent(
    client: Any,
    spec: AgentSpec,
    user_input: str,
    output_dir: Path,
    logger: Logger,
    save_raw: bool,
) -> tuple[str, UsageRecord]:
    started = time.monotonic()
    logger.write("START", f"{spec.agent_id}: {spec.title} [{spec.model}, {spec.reasoning_effort}]")

    response = await client.responses.create(
        model=spec.model,
        input=[
            {"role": "system", "content": SHARED_SYSTEM_PROMPT},
            {"role": "user", "content": user_input},
        ],
        reasoning={"effort": spec.reasoning_effort},
        max_output_tokens=spec.max_output_tokens,
        text={"verbosity": "medium"},
    )

    elapsed = time.monotonic() - started
    text = response_text(response)
    if not text:
        text = "_No text output returned._"

    output_file = output_dir / f"{safe_filename(spec.agent_id)}.md"
    output_file.write_text(text + "\n", encoding="utf-8")

    if save_raw:
        raw_file = output_dir / f"{safe_filename(spec.agent_id)}.raw.json"
        raw_file.write_text(response_to_json(response), encoding="utf-8")

    usage = getattr(response, "usage", None)
    input_tokens = usage_value(usage, "input_tokens")
    output_tokens = usage_value(usage, "output_tokens")
    total_tokens = usage_value(usage, "total_tokens")
    cost = estimate_cost(spec.model, input_tokens, output_tokens)

    record = UsageRecord(
        agent_id=spec.agent_id,
        title=spec.title,
        model=spec.model,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        total_tokens=total_tokens,
        estimated_cost_usd=cost,
        response_id=getattr(response, "id", None),
        elapsed_seconds=elapsed,
        output_file=str(output_file),
    )
    logger.write(
        "DONE",
        (
            f"{spec.agent_id}: cost=${cost:.4f}, "
            f"in={input_tokens}, out={output_tokens}, elapsed={elapsed:.1f}s"
        ),
    )
    return text, record


async def run_workers(
    client: Any,
    specs: list[AgentSpec],
    context: str,
    concurrency: int,
    output_dir: Path,
    logger: Logger,
    save_raw: bool,
) -> tuple[dict[str, str], list[UsageRecord]]:
    semaphore = asyncio.Semaphore(max(1, concurrency))
    reports: dict[str, str] = {}
    records: list[UsageRecord] = []

    async def run_one(spec: AgentSpec) -> None:
        async with semaphore:
            report, record = await run_agent(
                client=client,
                spec=spec,
                user_input=build_worker_input(context, spec),
                output_dir=output_dir,
                logger=logger,
                save_raw=save_raw,
            )
            reports[spec.agent_id] = report
            records.append(record)

    await asyncio.gather(*(run_one(spec) for spec in specs))
    return reports, records


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_combined_report(output_dir: Path, reports: dict[str, str], manager_reports: dict[str, str]) -> None:
    parts = ["# Vapor API Swarm Combined Reports\n"]
    for agent_id in sorted(reports):
        parts.append(f"\n\n## {agent_id}\n\n{reports[agent_id].strip()}\n")
    for agent_id in sorted(manager_reports):
        parts.append(f"\n\n## {agent_id}\n\n{manager_reports[agent_id].strip()}\n")
    (output_dir / "ALL_REPORTS.md").write_text("".join(parts), encoding="utf-8")


def print_dry_run(
    args: argparse.Namespace,
    output_dir: Path,
    context_manifest: list[dict[str, Any]],
    context: str,
    workers: list[AgentSpec],
    managers: list[AgentSpec],
) -> None:
    total_context_tokens = approximate_tokens(context)
    print("Vapor API swarm dry run")
    print(f"Repo root: {args.repo_root.resolve()}")
    print(f"Output dir: {output_dir}")
    print(f"Budget guard: ${args.max_budget_usd:.2f}")
    print(f"Approx shared context tokens per call: {total_context_tokens:,}")
    print("\nContext files:")
    for item in context_manifest:
        print(f"- {item['path']} ({item['bytes']} bytes, ~{item['approx_tokens']} tokens)")
    print("\nWorkers:")
    for spec in workers:
        print(f"- {spec.agent_id}: {spec.title} [{spec.model}, {spec.reasoning_effort}]")
    print("\nManagers:")
    for spec in managers:
        print(f"- {spec.agent_id}: {spec.title} [{spec.model}, {spec.reasoning_effort}]")
    print("\nNo API calls were made.")


def confirm_or_exit(args: argparse.Namespace, logger: Logger) -> None:
    if args.yes:
        return

    logger.write(
        "CONFIRM",
        (
            "This will make OpenAI API calls using your key. "
            f"Budget guard: ${args.max_budget_usd:.2f}. Type RUN to continue."
        ),
    )
    answer = input("> ").strip()
    if answer != "RUN":
        logger.write("STOP", "Confirmation not received. No API calls made.")
        raise SystemExit(1)


async def async_main() -> int:
    args = parse_args()
    repo_root = args.repo_root.expanduser().resolve()
    if not (repo_root / "AGENTS.md").exists():
        print(f"Repo root does not look like Vapor-Server-Root: {repo_root}", file=sys.stderr)
        return 2

    output_dir = args.output_dir
    if output_dir is None:
        output_dir = DEFAULT_RUN_ROOT / utc_stamp()
    output_dir = output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    logger = Logger(output_dir / "run.log")
    logger.write("INIT", f"Output directory: {output_dir}")

    context, context_manifest = load_context(repo_root)
    workers = make_worker_specs(args.worker_model, args.worker_effort)
    managers = make_manager_specs(args.manager_model, args.manager_effort)

    write_json(output_dir / "context_manifest.json", context_manifest)
    write_json(
        output_dir / "run_config.json",
        {
            "repo_root": str(repo_root),
            "max_budget_usd": args.max_budget_usd,
            "worker_model": args.worker_model,
            "manager_model": args.manager_model,
            "worker_effort": args.worker_effort,
            "manager_effort": args.manager_effort,
            "concurrency": args.concurrency,
            "context_approx_tokens": approximate_tokens(context),
            "workers": [asdict(spec) for spec in workers],
            "managers": [asdict(spec) for spec in managers],
        },
    )

    if args.dry_run:
        print_dry_run(args, output_dir, context_manifest, context, workers, managers)
        return 0

    api_key = read_api_key(args.key_file)
    if not api_key:
        logger.write(
            "ERROR",
            (
                "No API key found. Run: python3 tools/api_swarm/save_openai_key.py "
                "or set OPENAI_API_KEY in this terminal."
            ),
        )
        return 2

    try:
        from openai import AsyncOpenAI
    except ImportError:
        logger.write(
            "ERROR",
            (
                "OpenAI Python SDK not installed. Run through: "
                "bash tools/api_swarm/run_swarm.sh"
            ),
        )
        return 2

    confirm_or_exit(args, logger)
    client = AsyncOpenAI(api_key=api_key)

    usage_records: list[UsageRecord] = []
    manager_reports: dict[str, str] = {}

    logger.write("PHASE", f"Starting {len(workers)} workers with concurrency={args.concurrency}")
    worker_reports, worker_records = await run_workers(
        client=client,
        specs=workers,
        context=context,
        concurrency=args.concurrency,
        output_dir=output_dir,
        logger=logger,
        save_raw=args.save_raw,
    )
    usage_records.extend(worker_records)
    worker_cost = sum(record.estimated_cost_usd for record in worker_records)
    logger.write("COST", f"Worker phase estimated cost: ${worker_cost:.4f}")

    if worker_cost >= args.max_budget_usd:
        logger.write(
            "STOP",
            (
                f"Worker phase reached budget guard (${worker_cost:.4f} >= "
                f"${args.max_budget_usd:.2f}). Manager calls skipped."
            ),
        )
    else:
        manager_1 = managers[0]
        manager_1_report, manager_1_record = await run_agent(
            client=client,
            spec=manager_1,
            user_input=build_manager_input(context, manager_1, worker_reports),
            output_dir=output_dir,
            logger=logger,
            save_raw=args.save_raw,
        )
        manager_reports[manager_1.agent_id] = manager_1_report
        usage_records.append(manager_1_record)

        cost_after_manager_1 = sum(record.estimated_cost_usd for record in usage_records)
        if cost_after_manager_1 >= args.max_budget_usd:
            logger.write(
                "STOP",
                (
                    f"Budget guard reached after manager 1 (${cost_after_manager_1:.4f} >= "
                    f"${args.max_budget_usd:.2f}). Final synthesis skipped."
                ),
            )
        else:
            manager_2 = managers[1]
            manager_2_report, manager_2_record = await run_agent(
                client=client,
                spec=manager_2,
                user_input=build_manager_input(
                    context=context,
                    spec=manager_2,
                    reports=worker_reports,
                    manager_qa=manager_1_report,
                ),
                output_dir=output_dir,
                logger=logger,
                save_raw=args.save_raw,
            )
            manager_reports[manager_2.agent_id] = manager_2_report
            usage_records.append(manager_2_record)

    total_cost = sum(record.estimated_cost_usd for record in usage_records)
    total_tokens = sum(record.total_tokens for record in usage_records)
    write_json(output_dir / "usage.json", [asdict(record) for record in usage_records])
    write_combined_report(output_dir, worker_reports, manager_reports)

    logger.write("SUMMARY", f"Estimated total cost: ${total_cost:.4f}")
    logger.write("SUMMARY", f"Total reported tokens: {total_tokens:,}")
    logger.write("SUMMARY", f"Combined report: {output_dir / 'ALL_REPORTS.md'}")
    if "manager-02-final-synthesis" in manager_reports:
        logger.write("SUMMARY", f"Final synthesis: {output_dir / 'manager-02-final-synthesis.md'}")
    logger.write("DONE", "API swarm run complete.")
    return 0


def main() -> int:
    try:
        return asyncio.run(async_main())
    except KeyboardInterrupt:
        print("\nInterrupted by user.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
