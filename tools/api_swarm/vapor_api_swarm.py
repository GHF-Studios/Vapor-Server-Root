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
DEFAULT_PROMPT_PACK_DIR = Path("/home/leslieghf/Documents/AGENT_NOTES")

PRICE_PER_MILLION: dict[str, tuple[float, float]] = {
    "gpt-5.6": (5.00, 30.00),
    "gpt-5.6-sol": (5.00, 30.00),
    "gpt-5.6-terra": (2.50, 15.00),
    "gpt-5.6-luna": (1.00, 6.00),
}

PROFILE_DESCRIPTIONS: dict[str, str] = {
    "lean": (
        "9 calls: 7 grouped Terra workers plus Sol security QA and final synthesis. "
        "Cheapest useful prompt-pack run."
    ),
    "balanced": (
        "13 calls: 11 Terra workers plus Sol security QA and final synthesis. "
        "Default; preserves the prompt-pack workload while merging obvious overlaps."
    ),
    "full": (
        "16 calls: one worker per non-manager prompt file plus Sol security QA "
        "and final synthesis. Most exhaustive prompt-pack run."
    ),
    "implementation-campaign": (
        "14 calls: 12 source-aware workers plus Sol implementation QA and final "
        "integration manager. Targets concrete vertical-slice changes, tests, "
        "docs alignment, and safe sequencing."
    ),
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

IMPLEMENTATION_CONTEXT_FILES: tuple[str, ...] = (
    "README.md",
    "server-root.toml",
    ".gitmodules",
    ".github/workflows/deploy.yml",
    "docs/server-domain-boundaries.md",
    "docs/steam-authority-model.md",
    "docs/publish-pipeline-authority-model.md",
    "deploy/caddy/Caddyfile.example",
    "deploy/caddy/Caddyfile.template",
    "deploy/systemd/README.md",
    "deploy/systemd/vapor-homepage.service",
    "deploy/systemd/vapor-docs.service",
    "deploy/systemd/vapor-identity.service",
    "deploy/systemd/vapor-diagnostics.service",
    "deploy/systemd/vapor-deploy.service",
    "deploy/systemd/vapor-deploy.timer",
    "deploy/systemd/vapor-state-export.service",
    "deploy/systemd/vapor-state-export.timer",
    "deploy/scripts/lib.sh",
    "deploy/scripts/bootstrap-ubuntu.sh",
    "deploy/scripts/install-systemd.sh",
    "deploy/scripts/install-caddy.sh",
    "deploy/scripts/deploy.sh",
    "deploy/scripts/health-check.sh",
    "deploy/scripts/public-http-check.sh",
    "deploy/scripts/smoke-docs-upload.sh",
    "deploy/scripts/smoke-diagnostics.sh",
    "deploy/scripts/install-auto-deploy.sh",
    "deploy/scripts/export-state.sh",
    "deploy/scripts/restore-state.sh",
    "deploy/scripts/build-vapor-root-docs-bundle.sh",
    "deploy/scripts/upload-docs-via-http.sh",
    "deploy/scripts/deploy-vapor-root-docs.sh",
    "deploy/scripts/smoke-identity-auth.sh",
    "deploy/scripts/grant-identity-role.sh",
    "deploy/scripts/revoke-identity-role.sh",
    "deploy/scripts/list-identity-audit.sh",
    "deploy/scripts/install-state-backup.sh",
    "Vapor-Homepage-Server/AGENTS.md",
    "Vapor-Homepage-Server/README.md",
    "Vapor-Homepage-Server/Cargo.toml",
    "Vapor-Homepage-Server/src/main.rs",
    "Vapor-Docs-Server/AGENTS.md",
    "Vapor-Docs-Server/README.md",
    "Vapor-Docs-Server/Cargo.toml",
    "Vapor-Docs-Server/src/main.rs",
    "Vapor-Identity-Server/AGENTS.md",
    "Vapor-Identity-Server/README.md",
    "Vapor-Identity-Server/Cargo.toml",
    "Vapor-Identity-Server/src/main.rs",
    "Vapor-Identity-Server/src/config.rs",
    "Vapor-Identity-Server/src/types.rs",
    "Vapor-Identity-Server/src/api_handlers.rs",
    "Vapor-Identity-Server/src/browser_handlers.rs",
    "Vapor-Identity-Server/src/db.rs",
    "Vapor-Identity-Server/src/auth_attempts.rs",
    "Vapor-Identity-Server/src/profiles.rs",
    "Vapor-Identity-Server/src/providers.rs",
    "Vapor-Identity-Server/src/util.rs",
    "Vapor-Identity-Server/src/persistence.rs",
    "Vapor-Identity-Server/src/status_handlers.rs",
    "Vapor-Identity-Server/src/session_handlers.rs",
    "Vapor-Identity-Server/src/provider_handlers.rs",
    "Vapor-Identity-Server/src/admin_handlers.rs",
    "Vapor-Diagnostics-Server/README.md",
    "Vapor-Diagnostics-Server/Cargo.toml",
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
- Prefer real vertical-slice implementation plans over abstract speculation.
- Prefer minimal future boundaries over fake implementation scaffolding.
- It is acceptable to propose early high-level repositories or modules when the
  boundary is genuinely clear, but do not fill them with speculative framework
  code.
- If a responsibility does not fit an existing service, name the missing domain
  or reject the responsibility.
- When asked for implementation work, produce patch-ready guidance: exact files,
  functions, data shapes, tests, risks, and rollback notes.

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
    source_prompts: tuple[int, ...] = ()


@dataclass(frozen=True)
class PromptFile:
    number: int
    name: str
    path: str
    text: str


@dataclass(frozen=True)
class PromptPack:
    source_dir: Path
    base_text: str
    prompts: dict[int, PromptFile]

    def selected_text(self, numbers: tuple[int, ...]) -> str:
        sections = []
        for number in numbers:
            prompt = self.prompts[number]
            sections.append(f"\n\n===== {prompt.name} =====\n{prompt.text.strip()}")
        return "\n".join(sections).strip()

    def all_text(self) -> str:
        return self.selected_text(tuple(sorted(self.prompts)))

    def manifest(self) -> dict[str, Any]:
        return {
            "source_dir": str(self.source_dir),
            "base": {
                "name": "Agent_Prompt_Base.txt",
                "bytes": len(self.base_text.encode("utf-8")),
                "approx_tokens": approximate_tokens(self.base_text),
            },
            "prompts": [
                {
                    "number": prompt.number,
                    "name": prompt.name,
                    "path": prompt.path,
                    "bytes": len(prompt.text.encode("utf-8")),
                    "approx_tokens": approximate_tokens(prompt.text),
                }
                for prompt in sorted(self.prompts.values(), key=lambda item: item.number)
            ],
        }


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
        "--prompt-pack-dir",
        type=Path,
        default=DEFAULT_PROMPT_PACK_DIR,
        help=(
            "Directory containing Agent_Prompt_Base.txt and Agent_Prompt_001.txt "
            f"style files. Default: {DEFAULT_PROMPT_PACK_DIR}"
        ),
    )
    parser.add_argument(
        "--include-source-context",
        action="store_true",
        help=(
            "Include source files, deployment scripts, workflow config, and "
            "service READMEs in addition to the required handoff context. "
            "Automatically enabled by --profile implementation-campaign."
        ),
    )
    parser.add_argument(
        "--extra-context-file",
        type=Path,
        action="append",
        default=[],
        help=(
            "Add an extra read-only context file, such as a prior swarm synthesis. "
            "May be passed more than once."
        ),
    )
    parser.add_argument(
        "--profile",
        default="balanced",
        choices=sorted(PROFILE_DESCRIPTIONS),
        help="Workload profile. Default: balanced.",
    )
    parser.add_argument(
        "--list-profiles",
        action="store_true",
        help="List workload profiles and exit without making API calls.",
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
        help="Model for worker calls. Default: gpt-5.6-terra.",
    )
    parser.add_argument(
        "--manager-model",
        default="gpt-5.6-sol",
        choices=sorted(PRICE_PER_MILLION),
        help="Model for manager calls. Default: gpt-5.6-sol.",
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


def load_context(
    repo_root: Path,
    *,
    include_source_context: bool,
    extra_context_files: list[Path],
) -> tuple[str, list[dict[str, Any]]]:
    sections: list[str] = []
    manifest: list[dict[str, Any]] = []
    relative_files = list(dict.fromkeys(CONTEXT_FILES))
    if include_source_context:
        relative_files = list(dict.fromkeys(relative_files + list(IMPLEMENTATION_CONTEXT_FILES)))

    for relative in relative_files:
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

    for extra_file in extra_context_files:
        path = extra_file.expanduser().resolve()
        if not path.exists():
            raise FileNotFoundError(f"Extra context file missing: {path}")
        text = path.read_text(encoding="utf-8", errors="replace")
        label = f"extra:{path}"
        sections.append(f"\n\n===== FILE: {label} =====\n{text}")
        manifest.append(
            {
                "path": label,
                "bytes": len(text.encode("utf-8")),
                "approx_tokens": approximate_tokens(text),
            }
        )

    context = "\n".join(sections).strip()
    return context, manifest


def load_prompt_pack(prompt_pack_dir: Path) -> PromptPack:
    source_dir = prompt_pack_dir.expanduser().resolve()
    base_path = source_dir / "Agent_Prompt_Base.txt"
    if not base_path.exists():
        raise FileNotFoundError(f"Prompt-pack base file missing: {base_path}")

    prompts: dict[int, PromptFile] = {}
    for path in sorted(source_dir.glob("Agent_Prompt_*.txt")):
        if path.name == "Agent_Prompt_Base.txt":
            continue
        match = re.fullmatch(r"Agent_Prompt_(\d{3})\.txt", path.name)
        if not match:
            continue
        number = int(match.group(1))
        prompts[number] = PromptFile(
            number=number,
            name=path.name,
            path=str(path),
            text=path.read_text(encoding="utf-8", errors="replace"),
        )

    missing = [number for number in range(1, 17) if number not in prompts]
    if missing:
        formatted = ", ".join(f"{number:03}" for number in missing)
        raise FileNotFoundError(f"Prompt pack is missing prompt file(s): {formatted}")

    return PromptPack(
        source_dir=source_dir,
        base_text=base_path.read_text(encoding="utf-8", errors="replace"),
        prompts=prompts,
    )


def approximate_tokens(text: str) -> int:
    return max(1, len(text) // 4)


def make_worker_specs(
    profile: str,
    prompt_pack: PromptPack,
    worker_model: str,
    effort: str,
) -> list[AgentSpec]:
    if profile == "implementation-campaign":
        return make_implementation_worker_specs(worker_model, effort)

    prompt_groups = worker_prompt_groups(profile)
    return [
        AgentSpec(
            agent_id=f"worker-{index:02}-{slug}",
            title=title,
            model=worker_model,
            reasoning_effort=effort,
            max_output_tokens=2600,
            task=task_from_prompts(prompt_pack, prompts, title),
            source_prompts=prompts,
        )
        for index, (slug, title, prompts) in enumerate(prompt_groups, start=1)
    ]


def make_implementation_worker_specs(worker_model: str, effort: str) -> list[AgentSpec]:
    tasks: list[tuple[str, str, str]] = [
        (
            "diagnostics-v2",
            "Diagnostics v2 vertical slice",
            """\
Task: Produce a patch-ready plan for the next Diagnostics vertical slice.

Target concrete service code in Vapor-Diagnostics-Server and matching root
smoke tests/docs. Keep upload explicit opt-in and do not add hostnames or
persistent machine identifiers. Prefer small, testable Rust changes that improve
schema, run IDs, listing, redaction, retention, and operator ergonomics without
requiring identity integration first.
""",
        ),
        (
            "diagnostics-auth",
            "Diagnostics authorization migration path",
            """\
Task: Produce a patch-ready plan for moving Diagnostics read/list/export from
admin-token scaffolding toward identity-root authorization.

Do not require the migration to happen in one commit. Identify the smallest safe
intermediate implementation: headers/claims accepted, fail-closed behavior,
status reporting, tests, and documentation. Preserve bootstrap/emergency token
semantics until a real cross-service auth contract exists.
""",
        ),
        (
            "docs-release",
            "Docs release/current vertical slice",
            """\
Task: Produce a patch-ready plan for improving Vapor-Docs-Server from mutable
current upload toward immutable releases plus controlled current-pointer
promotion.

Target exact changes in Vapor-Docs-Server/src/main.rs, README, root docs upload
scripts, and smoke tests. Keep the slice small enough to implement locally:
release IDs, metadata/digests, current pointer, rollback/export behavior, and
tests.
""",
        ),
        (
            "identity-assertions",
            "Identity cross-service assertion slice",
            """\
Task: Produce a patch-ready plan for the first identity-issued authorization
surface usable by docs/diagnostics later.

Use current Identity code as source context. Preserve SteamID64 + GitHub login
as operator-facing authority, hide internal profile IDs, and avoid JWT/tooling
overreach unless justified. Specify endpoint/data shape, expiry/audience,
failure behavior, tests, and which services consume it in later commits.
""",
        ),
        (
            "identity-admin-ux",
            "Identity admin ergonomics",
            """\
Task: Produce a patch-ready plan for improving current identity root/admin
operator ergonomics without changing core authority rules.

Focus browser/dashboard and scripts: role grant/revoke/list audit, clear
operator-facing SteamID64/GitHub identifiers, last-root protection messaging,
tests, and docs. Avoid exposing internal profile IDs.
""",
        ),
        (
            "ops-recovery",
            "Operations evidence and recovery vertical slice",
            """\
Task: Produce a patch-ready plan for hardening local backup/export/restore
evidence in Vapor-Server-Root without touching the live VPS.

Target deploy/scripts/export-state.sh, restore-state.sh, install-state-backup.sh,
deployment-status/docs, and smoke tests. Include manifest checks,
service-by-service evidence, retention behavior, dry-run/verify commands, and
rollback notes.
""",
        ),
        (
            "deploy-cutover",
            "DNS/HTTPS cutover preparation",
            """\
Task: Produce a patch-ready plan for preparing DNS/HTTPS cutover without doing
the live cutover.

Target Caddy templates, deployment docs, smoke checks, secure-cookie docs, and
branch protection/GitHub deployment docs. Separate pre-DNS HTTP behavior from
future HTTPS behavior with exact operator verification steps.
""",
        ),
        (
            "server-shell",
            "Vapor Shell server wrapper contract",
            """\
Task: Produce a patch-ready plan for server-operation wrappers that Vapor Shell
can later implement.

Do not assume Vapor Shell source is in this repo. Define command contracts,
underlying server/root script/API targets, authentication boundaries, expected
outputs, and a staged implementation order. Identify any small root-side changes
that make wrappers easier and are safe now.
""",
        ),
        (
            "publishing-seed",
            "Publishing authority seed slice",
            """\
Task: Produce a patch-ready plan for seeding publishing/pipeline authority
without prematurely implementing Steam credential custody or pipeline execution.

Use the current publish-pipeline authority docs as context. Identify exact docs,
state roots, route reservations to avoid or define, audit/event shape, tests, and
minimal repository-boundary decision records that would unblock later work.
""",
        ),
        (
            "artifact-registry-toolchain",
            "Artifact, registry, and toolchain trigger plan",
            """\
Task: Produce a patch-ready plan for artifact storage, registry/catalog, and
toolchain authority triggers.

Do not implement fake services. Specify when each boundary becomes real, what
minimal files/repos/manifests would be justified, how they relate to docs and
publishing, and what root docs/backlog changes should happen now.
""",
        ),
        (
            "qa-tests",
            "Cross-service QA and test expansion",
            """\
Task: Produce a patch-ready QA plan across root scripts, Docs, Diagnostics, and
Identity.

Identify concrete missing tests, low-risk test additions, commands to run, smoke
check improvements, and invariants to preserve. Prefer tests that can run
locally without SSH, secrets, or live DNS.
""",
        ),
        (
            "integration-order",
            "Ambitious integration order",
            """\
Task: Produce an implementation campaign plan that sequences all safe changes
from this run into commits.

Be aggressive but realistic. Separate immediate local code/docs changes, changes
requiring user/domain/VPS authority, and speculative future boundaries. Include
which submodule gets which commit, root submodule pointer updates, validation,
and rollback anchors.
""",
        ),
    ]

    return [
        AgentSpec(
            agent_id=f"worker-{index:02}-{slug}",
            title=title,
            model=worker_model,
            reasoning_effort=effort,
            max_output_tokens=4300,
            task=task.strip(),
            source_prompts=(),
        )
        for index, (slug, title, task) in enumerate(tasks, start=1)
    ]


def worker_prompt_groups(profile: str) -> list[tuple[str, str, tuple[int, ...]]]:
    if profile == "lean":
        return [
            ("boundaries-gaps", "Boundary map and missing domains", (1, 15)),
            ("publish-artifacts", "Publish, pipeline, and artifact split", (2, 3)),
            ("toolchain-registry-repos", "Toolchain, registry, and repo topology", (4, 5, 13)),
            ("identity-security", "Identity pressure with authority risks", (6,)),
            ("diagnostics-docs", "Diagnostics and docs contracts", (7, 8)),
            ("mcp-ops-shell", "MCP, operations, and Vapor Shell", (9, 10, 11)),
            ("roadmap-sequencing", "Roadmap sequencing", (14,)),
        ]
    if profile == "balanced":
        return [
            ("boundaries-gaps", "Boundary map and missing domains", (1, 15)),
            ("publish-pipeline", "Publish/pipeline authority", (2,)),
            ("artifacts", "Artifact service boundary", (3,)),
            ("toolchain", "Toolchain service boundary", (4,)),
            ("registry-catalog", "Registry/catalog boundary", (5,)),
            ("identity-pressure", "Identity expansion pressure", (6,)),
            ("diagnostics-contract", "Diagnostics future contract", (7,)),
            ("docs-truth", "Docs truth surface", (8,)),
            ("mcp-capabilities", "MCP/capability surface", (9,)),
            ("ops-shell", "Operations/recovery and Vapor Shell", (10, 11)),
            ("repo-roadmap", "Repository topology and roadmap sequencing", (13, 14)),
        ]
    if profile == "full":
        return [
            ("boundary-map", "Future service/domain boundary map", (1,)),
            ("publish-pipeline", "Publish/pipeline authority", (2,)),
            ("artifacts", "Artifact service boundary", (3,)),
            ("toolchain", "Toolchain service boundary", (4,)),
            ("registry-catalog", "Registry/catalog boundary", (5,)),
            ("identity-pressure", "Identity expansion pressure", (6,)),
            ("diagnostics-contract", "Diagnostics future contract", (7,)),
            ("docs-truth", "Docs truth surface", (8,)),
            ("mcp-capabilities", "MCP/capability surface", (9,)),
            ("ops-recovery", "Operations/recovery capability", (10,)),
            ("shell-operator-ux", "Vapor Shell operator UX", (11,)),
            ("repo-topology", "Repository topology", (13,)),
            ("roadmap-sequencing", "Roadmap sequencing", (14,)),
            ("missing-domains", "Missing domains and false assumptions", (15,)),
        ]
    raise ValueError(f"Unknown profile: {profile}")


def task_from_prompts(
    prompt_pack: PromptPack,
    numbers: tuple[int, ...],
    title: str,
) -> str:
    if len(numbers) == 1:
        return prompt_pack.prompts[numbers[0]].text.strip()
    prompt_names = ", ".join(f"Agent_Prompt_{number:03}.txt" for number in numbers)
    return (
        f"Task: Produce one integrated report for {title}.\n\n"
        f"Use these source prompt files as the workload definition: {prompt_names}.\n"
        "Merge overlapping concerns, preserve disagreements, and do not treat the "
        "grouping as permission to collapse real authority boundaries."
    )


def make_manager_specs(
    prompt_pack: PromptPack,
    manager_model: str,
    effort: str,
    profile: str,
) -> list[AgentSpec]:
    if profile == "implementation-campaign":
        return [
            AgentSpec(
                agent_id="manager-01-implementation-security-qa",
                title="Implementation security and feasibility QA",
                model=manager_model,
                reasoning_effort=effort,
                max_output_tokens=5600,
                task="""\
Review all worker reports for security, authority, privacy, implementation
feasibility, and scope control.

Reject changes that would expose secrets, touch the live VPS, weaken identity
boundaries, collect hostname/persistent machine identifiers, collapse future
domains into existing services, or require speculative frameworks. Identify the
highest-value safe local patches and the tests required before commit.
""",
            ),
            AgentSpec(
                agent_id="manager-02-final-implementation-plan",
                title="Final implementation campaign synthesis",
                model=manager_model,
                reasoning_effort=effort,
                max_output_tokens=6500,
                task="""\
Produce the final implementation campaign for Codex to apply.

Return:
1. exact local changes to implement now, grouped by repo;
2. exact docs/contracts to update now;
3. exact tests/checks to run;
4. commit sequence and submodule pointer handling;
5. rollback notes;
6. deferred changes requiring user/VPS/DNS/secret authority;
7. speculative future work to keep out of this patch set.

Prioritize an ambitious but safe vertical-stack widening over purely conceptual
documentation. Be specific enough that a code agent can start editing files.
""",
            ),
        ]

    return [
        AgentSpec(
            agent_id="manager-01-security-authority-qa",
            title="Security and authority QA",
            model=manager_model,
            reasoning_effort=effort,
            max_output_tokens=3600,
            task=prompt_pack.prompts[12].text.strip(),
            source_prompts=(12,),
        ),
        AgentSpec(
            agent_id="manager-02-final-synthesis",
            title="Final architecture synthesis",
            model=manager_model,
            reasoning_effort=effort,
            max_output_tokens=5200,
            task=prompt_pack.prompts[16].text.strip(),
            source_prompts=(16,),
        ),
    ]


def build_worker_input(context: str, prompt_pack: PromptPack, spec: AgentSpec) -> str:
    assigned_prompts = prompt_pack.selected_text(spec.source_prompts)
    if not spec.source_prompts:
        return f"""\
<vapor_context>
{context}
</vapor_context>

<manual_swarm_prompt_base>
{prompt_pack.base_text}
</manual_swarm_prompt_base>

<task>
{spec.task}
</task>

Return markdown with these headings:

1. Scope
2. Current implementation facts
3. Proposed local changes
4. Exact files and functions to edit
5. Data/API/CLI contract changes
6. Tests to add or update
7. Security, privacy, and authority checks
8. Rollback and compatibility notes
9. Deferred work
10. Apply-order recommendation
"""

    return f"""\
<vapor_context>
{context}
</vapor_context>

<manual_swarm_prompt_base>
{prompt_pack.base_text}
</manual_swarm_prompt_base>

<assigned_prompt_files>
{assigned_prompts}
</assigned_prompt_files>

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
    prompt_pack: PromptPack,
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

<manual_swarm_prompt_base>
{prompt_pack.base_text}
</manual_swarm_prompt_base>

<manual_swarm_prompt_pack>
{prompt_pack.all_text()}
</manual_swarm_prompt_pack>

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
    prompt_pack: PromptPack,
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
                user_input=build_worker_input(context, prompt_pack, spec),
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


def planned_call_estimates(
    context: str,
    prompt_pack: PromptPack,
    workers: list[AgentSpec],
    managers: list[AgentSpec],
) -> list[dict[str, Any]]:
    estimates: list[dict[str, Any]] = []
    for spec in workers:
        planned_input = build_worker_input(context, prompt_pack, spec)
        input_tokens = approximate_tokens(SHARED_SYSTEM_PROMPT + planned_input)
        estimates.append(planned_record("worker", spec, input_tokens))

    placeholder_reports = {
        spec.agent_id: "x" * (spec.max_output_tokens * 4) for spec in workers
    }
    manager_1_input = build_manager_input(
        context=context,
        prompt_pack=prompt_pack,
        spec=managers[0],
        reports=placeholder_reports,
    )
    manager_1_input_tokens = approximate_tokens(SHARED_SYSTEM_PROMPT + manager_1_input)
    estimates.append(planned_record("manager", managers[0], manager_1_input_tokens))

    manager_2_input = build_manager_input(
        context=context,
        prompt_pack=prompt_pack,
        spec=managers[1],
        reports=placeholder_reports,
        manager_qa="x" * (managers[0].max_output_tokens * 4),
    )
    manager_2_input_tokens = approximate_tokens(SHARED_SYSTEM_PROMPT + manager_2_input)
    estimates.append(planned_record("manager", managers[1], manager_2_input_tokens))
    return estimates


def planned_record(phase: str, spec: AgentSpec, input_tokens: int) -> dict[str, Any]:
    return {
        "phase": phase,
        "agent_id": spec.agent_id,
        "title": spec.title,
        "model": spec.model,
        "reasoning_effort": spec.reasoning_effort,
        "source_prompts": [f"Agent_Prompt_{number:03}.txt" for number in spec.source_prompts],
        "estimated_input_tokens": input_tokens,
        "max_output_tokens": spec.max_output_tokens,
        "worst_case_cost_usd": estimate_cost(
            spec.model,
            input_tokens,
            spec.max_output_tokens,
        ),
    }


def print_dry_run(
    args: argparse.Namespace,
    output_dir: Path,
    context_manifest: list[dict[str, Any]],
    context: str,
    prompt_pack: PromptPack,
    workers: list[AgentSpec],
    managers: list[AgentSpec],
) -> None:
    total_context_tokens = approximate_tokens(context)
    planned = planned_call_estimates(context, prompt_pack, workers, managers)
    planned_worker_cost = sum(
        item["worst_case_cost_usd"] for item in planned if item["phase"] == "worker"
    )
    planned_manager_cost = sum(
        item["worst_case_cost_usd"] for item in planned if item["phase"] == "manager"
    )
    planned_total_cost = planned_worker_cost + planned_manager_cost
    print("Vapor API swarm dry run")
    print(f"Repo root: {args.repo_root.resolve()}")
    print(f"Output dir: {output_dir}")
    print(f"Profile: {args.profile} — {PROFILE_DESCRIPTIONS[args.profile]}")
    print(f"Prompt pack: {prompt_pack.source_dir}")
    print(f"Source context included: {args.include_source_context or args.profile == 'implementation-campaign'}")
    if args.extra_context_file:
        print("Extra context files:")
        for path in args.extra_context_file:
            print(f"- {path}")
    print(f"Budget guard: ${args.max_budget_usd:.2f}")
    print(f"Approx shared context tokens per call: {total_context_tokens:,}")
    print(
        "Planned calls: "
        f"{len(workers)} workers + {len(managers)} managers = {len(workers) + len(managers)}"
    )
    print(
        "Worst-case token-plan estimate: "
        f"${planned_total_cost:.4f} "
        f"(workers ${planned_worker_cost:.4f}, managers ${planned_manager_cost:.4f})"
    )
    if planned_total_cost > args.max_budget_usd:
        print(
            "WARNING: worst-case plan estimate exceeds the budget guard. "
            "Use a cheaper profile/model or lower output limits before a real run."
        )
    print("\nContext files:")
    for item in context_manifest:
        print(f"- {item['path']} ({item['bytes']} bytes, ~{item['approx_tokens']} tokens)")
    print("\nPrompt pack:")
    manifest = prompt_pack.manifest()
    print(
        f"- {manifest['base']['name']} "
        f"({manifest['base']['bytes']} bytes, ~{manifest['base']['approx_tokens']} tokens)"
    )
    for item in manifest["prompts"]:
        print(
            f"- {item['name']} "
            f"({item['bytes']} bytes, ~{item['approx_tokens']} tokens)"
        )
    print("\nWorkers:")
    planned_by_agent = {item["agent_id"]: item for item in planned}
    for spec in workers:
        item = planned_by_agent[spec.agent_id]
        print(
            f"- {spec.agent_id}: {spec.title} "
            f"[{spec.model}, {spec.reasoning_effort}] "
            f"prompts={','.join(item['source_prompts']) or '(custom task)'} "
            f"in~{item['estimated_input_tokens']:,} "
            f"out≤{item['max_output_tokens']:,} "
            f"cost≤${item['worst_case_cost_usd']:.4f}"
        )
    print("\nManagers:")
    for spec in managers:
        item = planned_by_agent[spec.agent_id]
        print(
            f"- {spec.agent_id}: {spec.title} "
            f"[{spec.model}, {spec.reasoning_effort}] "
            f"prompts={','.join(item['source_prompts']) or '(custom task)'} "
            f"in~{item['estimated_input_tokens']:,} "
            f"out≤{item['max_output_tokens']:,} "
            f"cost≤${item['worst_case_cost_usd']:.4f}"
        )
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
    if args.list_profiles:
        print("Vapor API swarm workload profiles")
        for name in sorted(PROFILE_DESCRIPTIONS):
            print(f"- {name}: {PROFILE_DESCRIPTIONS[name]}")
        return 0

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

    include_source_context = args.include_source_context or args.profile == "implementation-campaign"
    context, context_manifest = load_context(
        repo_root,
        include_source_context=include_source_context,
        extra_context_files=args.extra_context_file,
    )
    prompt_pack = load_prompt_pack(args.prompt_pack_dir)
    workers = make_worker_specs(
        profile=args.profile,
        prompt_pack=prompt_pack,
        worker_model=args.worker_model,
        effort=args.worker_effort,
    )
    managers = make_manager_specs(
        prompt_pack,
        args.manager_model,
        args.manager_effort,
        args.profile,
    )
    planned = planned_call_estimates(context, prompt_pack, workers, managers)
    planned_total_cost = sum(item["worst_case_cost_usd"] for item in planned)

    write_json(output_dir / "context_manifest.json", context_manifest)
    write_json(output_dir / "prompt_pack_manifest.json", prompt_pack.manifest())
    write_json(
        output_dir / "run_config.json",
        {
            "repo_root": str(repo_root),
            "prompt_pack_dir": str(prompt_pack.source_dir),
            "profile": args.profile,
            "profile_description": PROFILE_DESCRIPTIONS[args.profile],
            "include_source_context": include_source_context,
            "extra_context_files": [str(path) for path in args.extra_context_file],
            "max_budget_usd": args.max_budget_usd,
            "worker_model": args.worker_model,
            "manager_model": args.manager_model,
            "worker_effort": args.worker_effort,
            "manager_effort": args.manager_effort,
            "concurrency": args.concurrency,
            "context_approx_tokens": approximate_tokens(context),
            "planned_worst_case_cost_usd": planned_total_cost,
            "planned_calls": planned,
            "workers": [asdict(spec) for spec in workers],
            "managers": [asdict(spec) for spec in managers],
        },
    )

    if args.dry_run:
        print_dry_run(
            args,
            output_dir,
            context_manifest,
            context,
            prompt_pack,
            workers,
            managers,
        )
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
    logger.write(
        "PLAN",
        (
            f"Profile={args.profile}; calls={len(workers) + len(managers)}; "
            f"planned worst-case estimate=${planned_total_cost:.4f}; "
            f"budget guard=${args.max_budget_usd:.2f}"
        ),
    )
    if planned_total_cost > args.max_budget_usd:
        logger.write(
            "WARN",
            (
                "Planned worst-case estimate exceeds the budget guard. "
                "Actual spend may still be lower, but consider a cheaper profile/model."
            ),
        )
    client = AsyncOpenAI(api_key=api_key)

    usage_records: list[UsageRecord] = []
    manager_reports: dict[str, str] = {}

    logger.write("PHASE", f"Starting {len(workers)} workers with concurrency={args.concurrency}")
    worker_reports, worker_records = await run_workers(
        client=client,
        specs=workers,
        context=context,
        prompt_pack=prompt_pack,
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
            user_input=build_manager_input(context, prompt_pack, manager_1, worker_reports),
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
                    prompt_pack=prompt_pack,
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
