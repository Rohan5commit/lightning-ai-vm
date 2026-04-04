#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from typing import Any


API_BASE = "https://api.lightning.ai"


def clean(value: str | None) -> str:
    return (value or "").strip()


def request_json(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    request_headers = dict(headers or {})
    data = None
    if payload is not None:
        request_headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(url, headers=request_headers, data=data, method=method)
    with urllib.request.urlopen(request) as response:
        raw = response.read().decode("utf-8", errors="replace")
    return json.loads(raw) if raw else {}


def login() -> str:
    username = clean(os.environ.get("LIGHTNING_USERNAME"))
    api_key = clean(os.environ.get("LIGHTNING_API_KEY"))
    if not username or not api_key:
        raise RuntimeError("Missing LIGHTNING_USERNAME or LIGHTNING_API_KEY.")
    payload = request_json(
        f"{API_BASE}/v1/auth/login",
        method="POST",
        payload={"username": username, "apiKey": api_key},
    )
    token = clean(str(payload.get("token") or ""))
    if not token:
        raise RuntimeError("Lightning login did not return a token.")
    return token


def auth_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def list_cloudspaces(token: str, project_id: str) -> list[dict[str, Any]]:
    payload = request_json(
        f"{API_BASE}/v1/projects/{project_id}/cloudspaces",
        headers=auth_headers(token),
    )
    return list(payload.get("cloudspaces") or [])


def delete_cloudspace(token: str, project_id: str, studio_id: str) -> None:
    request_json(
        f"{API_BASE}/v1/projects/{project_id}/cloudspaces/{studio_id}",
        method="DELETE",
        headers=auth_headers(token),
    )


def fork_cloudspace(
    token: str,
    *,
    source_project_id: str,
    source_studio_id: str,
    target_project_id: str,
    target_cluster_id: str,
) -> dict[str, Any]:
    return request_json(
        f"{API_BASE}/v1/projects/{source_project_id}/cloudspaces/{source_studio_id}/fork",
        method="PUT",
        headers=auth_headers(token),
        payload={
            "targetProjectId": target_project_id,
            "targetClusterId": target_cluster_id,
            "versionId": "",
        },
    )


def choose_clone(target_cloudspaces: list[dict[str, Any]], source_name: str, source_size: int, source_files: int) -> dict[str, Any] | None:
    for cloudspace in target_cloudspaces:
        if (
            clean(str(cloudspace.get("name") or "")) == source_name
            and int(cloudspace.get("totalSizeBytes") or 0) == source_size
            and int(cloudspace.get("numberOfFiles") or 0) == source_files
        ):
            return cloudspace
    return None


def main() -> int:
    source_project_id = clean(os.environ.get("SOURCE_LIGHTNING_PROJECT_ID"))
    source_studio_id = clean(os.environ.get("SOURCE_LIGHTNING_STUDIO_ID"))
    target_project_id = clean(os.environ.get("TARGET_LIGHTNING_PROJECT_ID"))
    if not source_project_id or not source_studio_id or not target_project_id:
        raise RuntimeError("Missing SOURCE_LIGHTNING_PROJECT_ID, SOURCE_LIGHTNING_STUDIO_ID, or TARGET_LIGHTNING_PROJECT_ID.")

    token = login()
    source_cloudspaces = list_cloudspaces(token, source_project_id)
    source = next((item for item in source_cloudspaces if clean(str(item.get("id") or "")) == source_studio_id), None)
    if source is None:
        raise RuntimeError(f"Source cloudspace {source_studio_id} was not found in project {source_project_id}.")

    source_name = clean(str(source.get("name") or ""))
    source_size = int(source.get("totalSizeBytes") or 0)
    source_files = int(source.get("numberOfFiles") or 0)
    target_cloudspaces = list_cloudspaces(token, target_project_id)

    existing_clone = choose_clone(target_cloudspaces, source_name, source_size, source_files)
    if existing_clone is not None:
        result = {
            "action": "reuse_existing_clone",
            "source_studio_id": source_studio_id,
            "target_project_id": target_project_id,
            "target_studio_id": clean(str(existing_clone.get("id") or "")),
            "target_studio_name": clean(str(existing_clone.get("name") or "")),
            "target_cluster_id": clean(str(existing_clone.get("clusterId") or "")),
            "target_total_size_bytes": source_size,
            "target_number_of_files": source_files,
            "state": clean(str(existing_clone.get("state") or "")),
        }
        print(json.dumps(result, indent=2))
        return 0

    for cloudspace in target_cloudspaces:
        if int(cloudspace.get("totalSizeBytes") or 0) == 0 and int(cloudspace.get("numberOfFiles") or 0) == 0:
            delete_cloudspace(token, target_project_id, clean(str(cloudspace.get("id") or "")))

    target_cluster_id = clean(
        os.environ.get("TARGET_LIGHTNING_CLUSTER_ID")
        or str(source.get("clusterId") or "")
        or "gcp-lightning-public-prod"
    )

    clone = fork_cloudspace(
        token,
        source_project_id=source_project_id,
        source_studio_id=source_studio_id,
        target_project_id=target_project_id,
        target_cluster_id=target_cluster_id,
    )

    clone_id = clean(str(clone.get("id") or ""))
    time.sleep(2)
    target_cloudspaces = list_cloudspaces(token, target_project_id)
    refreshed = next((item for item in target_cloudspaces if clean(str(item.get("id") or "")) == clone_id), clone)

    result = {
        "action": "forked_exact_clone",
        "source_studio_id": source_studio_id,
        "target_project_id": target_project_id,
        "target_studio_id": clone_id,
        "target_studio_name": clean(str(refreshed.get("name") or "")),
        "target_cluster_id": clean(str(refreshed.get("clusterId") or "")),
        "target_total_size_bytes": int(refreshed.get("totalSizeBytes") or 0),
        "target_number_of_files": int(refreshed.get("numberOfFiles") or 0),
        "state": clean(str(refreshed.get("state") or "")),
        "sync_percentage": clean(str(refreshed.get("syncPercentage") or "")),
    }
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        print(
            json.dumps(
                {
                    "error": "http_error",
                    "status": exc.code,
                    "reason": exc.reason,
                    "body": body,
                },
                indent=2,
            ),
            file=sys.stderr,
        )
        raise SystemExit(1)
    except Exception as exc:  # pragma: no cover - shell entrypoint
        print(json.dumps({"error": str(exc)}, indent=2), file=sys.stderr)
        raise SystemExit(1)
