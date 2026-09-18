#!/bin/bash
set -euo pipefail

compose_file="${compose_file:-$PWD/compose/docker-compose.yml}"
BEAMLINE_ACRONYM="${BEAMLINE_ACRONYM:-hex}"
BEAMLINE_REPO="${BEAMLINE_REPO:-hex-profile-collection}"

docker compose -f "${compose_file}" up -d base tiled caddy

# Run the bootstrap client from the base workspace container.
docker compose -f "${compose_file}" exec -T \
  -e TILED_SERVER_API_KEY="${TILED_SERVER_API_KEY:-secret}" \
  -e BEAMLINE_ACRONYM="${BEAMLINE_ACRONYM}" \
    -e BEAMLINE_REPO="${BEAMLINE_REPO}" \
    base bash -lc 'cd "/workspace/${BEAMLINE_REPO}" && pixi run -e terminal python - <<"PY"
import os
import urllib3

from tiled.client import from_profile

urllib3.disable_warnings()

tla = os.getenv("BEAMLINE_ACRONYM", "hex").lower()
TLA = tla.upper()

api_key = os.getenv(
    f"TILED_BLUESKY_WRITING_API_KEY_{TLA}",
    os.getenv("TILED_SERVER_API_KEY", "secret"),
)
client = from_profile("nsls2", api_key=api_key)


def get_or_create_container(parent, key, specs=None, metadata=None):
    metadata = metadata or {}
    try:
        return parent[key]
    except Exception:
        try:
            if specs is None:
                return parent.create_container(key, metadata=metadata)
            return parent.create_container(key, specs=specs, metadata=metadata)
        except Exception:
            return parent[key]

beamline = get_or_create_container(client, tla)

get_or_create_container(beamline, "migration", specs=["CatalogOfBlueskyRuns"])
get_or_create_container(beamline, "raw", specs=["CatalogOfBlueskyRuns"])

if tla == "opls":
    client[tla]["raw"].update_metadata(
        metadata={"proposal_number": 123456, "main_proposer": "test_user"}
    )
PY'
echo "finish"