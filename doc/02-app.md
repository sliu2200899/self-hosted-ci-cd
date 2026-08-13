# The sample app

A deliberately small FastAPI service. Its purpose is to give CI something real to
test and build — not to be interesting in itself.

## Files

| File | Purpose |
|---|---|
| `app/main.py` | Two routes: `/` and `/healthz` |
| `app/test_main.py` | Tests that gate the image build |
| `app/requirements.txt` | Runtime dependencies |
| `app/requirements-dev.txt` | Test dependencies (includes runtime via `-r`) |
| `app/Dockerfile` | Multi-stage build |
| `app/.dockerignore` | Keeps tests and caches out of the image |

## Routes

| Route | Returns | Why it exists |
|---|---|---|
| `GET /` | `{"app": "sample-app", "version": "<version>"}` | The version string is the visible proof a change travelled through the pipeline |
| `GET /healthz` | `{"status": "ok"}` | Probe target in Phase 1b |

`/healthz` intentionally has no dependencies. A probe that can fail for reasons
unrelated to the process being alive causes restart loops under load.

The version comes from the `APP_VERSION` environment variable, defaulting to `0.1.0`.

## Running locally

```bash
cd app
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
pytest -v
uvicorn main:app --reload
```

Then `curl localhost:8000/` and `curl localhost:8000/healthz`.

## The Dockerfile

Two stages:

1. **builder** — creates a venv at `/opt/venv` and installs `requirements.txt` into it.
2. **runtime** — copies only that venv. No pip cache, no compilers, no test code.

It runs as a non-root user (`appuser`, uid 10001). This is not decoration: the Phase 1b
Deployment sets `runAsNonRoot: true`, which refuses to start a container whose image
declares a root `USER`.

Build context is `./app`, so `.dockerignore` there excludes `test_main.py`,
`requirements-dev.txt`, and caches.

## Dependency pinning

`requirements.txt` uses bounded ranges (`fastapi>=0.115,<1.0`) rather than exact pins,
so a fresh resolve cannot fail on a yanked release.

This is a deliberate trade-off: **builds are not byte-reproducible**. Two builds of the
same commit weeks apart can resolve different patch versions. Once the pipeline is
green, tighten this by generating a lock file:

```bash
cd app
pip install pip-tools
pip-compile requirements.txt -o requirements.lock
```

and switching the Dockerfile and CI to install from `requirements.lock`.
