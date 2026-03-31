from __future__ import annotations

import argparse
import json
import os
import time
import urllib.request
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from lightning_app.utilities.cloud import _get_project
from lightning_app.utilities.network import LightningClient
from lightning_cloud.openapi import IdCodeconfigBody, IdStartBody, V1UserRequestedComputeConfig


RUNNING_PHASE = "CLOUD_SPACE_INSTANCE_STATE_RUNNING"
DEFAULT_COMPUTE_NAME = "cpu-4"
DEFAULT_DISK_SIZE_GB = 400
DEFAULT_IDE = "jupyterlab"
DEFAULT_AUTH_URL = "https://api.lightning.ai"
DEFAULT_POLL_SECONDS = 5
DEFAULT_TIMEOUT_SECONDS = 300


@dataclass
class HealReport:
    studio_id: str
    project_id: str
    action: str
    studio_found: bool
    instance_found: bool
    instance_phase: str


def request_json(url: str, *, method: str = "GET", headers: dict[str, str] | None = None, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    request_headers = dict(headers or {})
    data = None
    if payload is not None:
        request_headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(url, headers=request_headers, data=data, method=method)
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def clean(value: str | None) -> str:
    return (value or "").strip()


def ensure_auth_env() -> tuple[str, str]:
    username = clean(os.environ.get("LIGHTNING_USERNAME"))
    api_key = clean(os.environ.get("LIGHTNING_API_KEY"))
    if not username or not api_key:
        raise RuntimeError("Missing LIGHTNING_USERNAME or LIGHTNING_API_KEY in this repo.")
    login_payload = request_json(
        f"{DEFAULT_AUTH_URL}/v1/auth/login",
        method="POST",
        payload={"username": username, "apiKey": api_key},
    )
    token = clean(str(login_payload.get("token") or ""))
    if not token:
        raise RuntimeError("Lightning login did not return a token.")
    user_payload = request_json(
        f"{DEFAULT_AUTH_URL}/v1/auth/user",
        headers={"Authorization": f"Bearer {token}"},
    )
    user_id = clean(str(user_payload.get("id") or ""))
    if not user_id:
        raise RuntimeError("Lightning user lookup did not return a user id.")
    os.environ["LIGHTNING_USER_ID"] = user_id
    return username, api_key


def get_client_and_project():
    client = LightningClient(retry=False)
    project = _get_project(client, project_id=None, verbose=False)
    return client, project


def list_studios(client, project_id: str) -> list[Any]:
    response = client.cloud_space_service_list_cloud_spaces(project_id=project_id)
    return list(getattr(response, "cloudspaces", []) or [])


def list_instances(client, project_id: str) -> list[Any]:
    response = client.cloud_space_service_list_cloud_space_instances(project_id=project_id)
    return list(getattr(response, "cloudspace_instances", []) or [])


def studio_id_from_target() -> tuple[str, str]:
    target = clean(os.environ.get("LIGHTNING_VM_TARGET"))
    if not target:
        raise RuntimeError("Missing LIGHTNING_VM_TARGET.")
    studio_id = target.split("@", 1)[0]
    if not studio_id:
        raise RuntimeError("Could not parse studio id from LIGHTNING_VM_TARGET.")
    return studio_id, target


def resolve_studio(client, project_id: str, studio_id: str):
    for studio in list_studios(client, project_id):
        if clean(str(getattr(studio, "id", "") or "")) == studio_id:
            return studio
    return None


def resolve_instance(client, project_id: str, studio_id: str):
    for instance in list_instances(client, project_id):
        if clean(str(getattr(instance, "cloud_space_id", "") or "")) == studio_id:
            return instance
    return None


def ensure_running(client, project_id: str, studio_id: str, *, timeout_seconds: int) -> Any:
    body = IdCodeconfigBody(
        compute_config=V1UserRequestedComputeConfig(
            name=os.environ.get("LIGHTNING_STUDIO_COMPUTE_NAME", DEFAULT_COMPUTE_NAME),
            disk_size=int(os.environ.get("LIGHTNING_STUDIO_DISK_SIZE_GB", DEFAULT_DISK_SIZE_GB)),
            spot=False,
            same_compute_on_resume=False,
        ),
        disable_auto_shutdown=False,
        idle_shutdown_seconds=0,
        ide=os.environ.get("LIGHTNING_STUDIO_IDE", DEFAULT_IDE),
    )
    client.cloud_space_service_update_cloud_space_instance_config(body=body, project_id=project_id, id=studio_id)
    client.cloud_space_service_start_cloud_space_instance(
        body=IdStartBody(compute_config=body.compute_config),
        project_id=project_id,
        id=studio_id,
    )

    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
      instance = resolve_instance(client, project_id, studio_id)
      if instance is not None and clean(str(getattr(instance, "phase", "") or "")) == RUNNING_PHASE:
          return instance
      time.sleep(DEFAULT_POLL_SECONDS)
    raise TimeoutError(f"Timed out waiting for studio {studio_id} to reach RUNNING.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="")
    parser.add_argument("--restart-if-needed", action="store_true")
    parser.add_argument("--timeout-seconds", type=int, default=DEFAULT_TIMEOUT_SECONDS)
    args = parser.parse_args()

    ensure_auth_env()
    client, project = get_client_and_project()
    studio_id, target = studio_id_from_target()
    studio = resolve_studio(client, project.project_id, studio_id)
    if studio is None:
        raise RuntimeError(f"Studio {studio_id} was not found in Lightning project {project.project_id}.")

    instance = resolve_instance(client, project.project_id, studio_id)
    phase = clean(str(getattr(instance, "phase", "") or ""))
    action = "noop"
    if args.restart_if_needed and phase != RUNNING_PHASE:
        instance = ensure_running(client, project.project_id, studio_id, timeout_seconds=args.timeout_seconds)
        phase = clean(str(getattr(instance, "phase", "") or ""))
        action = "started"

    payload = asdict(
        HealReport(
            studio_id=studio_id,
            project_id=project.project_id,
            action=action,
            studio_found=studio is not None,
            instance_found=instance is not None,
            instance_phase=phase or "unknown",
        )
    )
    text = json.dumps(payload, indent=2)
    print(text)
    if args.out:
        Path(args.out).write_text(text + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
