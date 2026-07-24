# Vapor API Swarm Harness

This is a local experiment harness for spending OpenAI API credits on a bounded
Vapor architecture swarm.

The default run:

- reads only checked-in Vapor server docs/source context;
- makes 10 worker API calls with `gpt-5.6-terra`;
- makes 2 manager API calls with `gpt-5.6-sol`;
- writes markdown reports, usage data, and a terminal-friendly log;
- stops before starting manager work if worker usage already crosses the budget
  guard;
- does not deploy, SSH, inspect secrets, or mutate Vapor source files.

Outputs default to:

```text
/tmp/vapor-api-swarm-runs/<timestamp>/
```

## One-time key setup

Run this from `Vapor-Server-Root`:

```bash
python3 tools/api_swarm/save_openai_key.py
```

Paste the API key when prompted. The key is not printed. It is saved outside the
repository at:

```text
~/.config/openai/api_key
```

## Install dependencies and dry-run

This creates a temporary virtualenv under `/tmp`, installs the official OpenAI
Python SDK, and prints the planned swarm without spending tokens:

```bash
bash tools/api_swarm/run_swarm.sh --dry-run
```

## Run the experiment

```bash
bash tools/api_swarm/run_swarm.sh
```

The script asks for confirmation before making API calls.

## Useful options

```bash
# Lower the spend guard.
bash tools/api_swarm/run_swarm.sh --max-budget-usd 4.00

# Use Luna workers for a cheaper comparison run.
bash tools/api_swarm/run_swarm.sh --worker-model gpt-5.6-luna

# Use Sol for every worker. This is much more expensive.
bash tools/api_swarm/run_swarm.sh --worker-model gpt-5.6-sol

# Write results somewhere specific.
bash tools/api_swarm/run_swarm.sh --output-dir /tmp/vapor-swarm-test

# Keep results in your home directory if you want them to survive tmp cleanup.
bash tools/api_swarm/run_swarm.sh --output-dir ~/AGENT_NOTES/api_swarm_runs/latest
```

## Budget notes

The harness estimates cost from API-reported input/output token usage. It uses
published GPT-5.6 text token prices embedded in the script:

- `gpt-5.6-sol`: `$5.00 / 1M` input tokens, `$30.00 / 1M` output tokens.
- `gpt-5.6-terra`: `$2.50 / 1M` input tokens, `$15.00 / 1M` output tokens.
- `gpt-5.6-luna`: `$1.00 / 1M` input tokens, `$6.00 / 1M` output tokens.

Because worker calls run concurrently, no script can enforce an exact
penny-perfect hard cap mid-flight. This harness keeps output limits modest,
checks budget after each completed call, and does not start manager calls if the
worker phase already crosses the configured guard.
