"""Compares the tool versions pinned in the Dockerfile with the latest upstream releases.

Prints a Markdown report and writes outdated=<count> to $GITHUB_OUTPUT when it is set.
GITHUB_TOKEN in the environment raises the GitHub API rate limit.
"""
import json
import os
import re
import sys
import urllib.request

DOCKERFILE = sys.argv[1] if len(sys.argv) > 1 else "Dockerfile"


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "actions-runner-sysbox-version-check"})
    if url.startswith("https://api.github.com/") and os.environ.get("GITHUB_TOKEN"):
        req.add_header("Authorization", f"Bearer {os.environ['GITHUB_TOKEN']}")
    with urllib.request.urlopen(req, timeout=30) as response:
        return response.read().decode()


def github_release(repo):
    return lambda pinned: json.loads(fetch(f"https://api.github.com/repos/{repo}/releases/latest"))["tag_name"]


def node_same_major(pinned):
    # Stay on the pinned major; a new major is a deliberate upgrade, reported separately below.
    major = pinned.split(".")[0]
    for release in json.loads(fetch("https://nodejs.org/dist/index.json")):
        if release["version"].startswith(f"v{major}."):
            return release["version"].lstrip("v")
    raise ValueError(f"no Node {major}.x release found")


def node_latest_lts(pinned):
    return next(r["version"].lstrip("v") for r in json.loads(fetch("https://nodejs.org/dist/index.json")) if r["lts"])


# ARG name -> (display name, function returning the latest version in the ARG's format)
SOURCES = {
    "NVM_VERSION": ("nvm", github_release("nvm-sh/nvm")),
    "NODE_VERSION": ("Node.js", node_same_major),
    "PNPM_VERSION": ("pnpm", lambda pinned: json.loads(fetch("https://registry.npmjs.org/pnpm/latest"))["version"]),
    "TEMPORAL_CLI_VERSION": ("Temporal CLI", lambda pinned: github_release("temporalio/cli")(pinned).lstrip("v")),
    "DEVSPACE_VERSION": ("devspace", github_release("devspace-sh/devspace")),
    "RANCHER_CLI_VERSION": ("Rancher CLI", github_release("rancher/cli")),
    "KUBECTL_VERSION": ("kubectl", lambda pinned: fetch("https://dl.k8s.io/release/stable.txt").strip()),
    "DOCKER_COMPOSE_VERSION": ("Docker Compose", github_release("docker/compose")),
}

pinned = dict(re.findall(r"^ARG\s+(\w+_VERSION)=(\S+)", open(DOCKERFILE).read(), re.M))
rows, outdated, errors = [], 0, 0
for arg, version in pinned.items():
    if arg not in SOURCES:
        rows.append(f"| {arg} | `{version}` | no upstream check configured | ❔ |")
        errors += 1
        continue
    name, latest_of = SOURCES[arg]
    try:
        latest = latest_of(version)
    except Exception as err:  # report and keep checking the other tools
        rows.append(f"| {name} | `{version}` | lookup failed: {err} | ❔ |")
        errors += 1
        continue
    behind = latest != version
    outdated += behind
    rows.append(f"| {name} | `{version}` | `{latest}` | {'⬆️ update' if behind else '✅'} |")

lines = ["| Tool | Pinned | Latest | Status |", "|---|---|---|---|", *rows]
if "NODE_VERSION" in pinned:
    # Informational only: it would otherwise reopen the issue every week until the major is bumped.
    try:
        lts = node_latest_lts(pinned["NODE_VERSION"])
        if lts.split(".")[0] != pinned["NODE_VERSION"].split(".")[0]:
            lines.append(f"\nA newer Node.js LTS major is out: `{lts}`.")
    except Exception as err:
        lines.append(f"\nNode.js LTS lookup failed: {err}")
print("\n".join(lines))

if os.environ.get("GITHUB_OUTPUT"):
    with open(os.environ["GITHUB_OUTPUT"], "a") as out:
        out.write(f"outdated={outdated}\nerrors={errors}\n")
