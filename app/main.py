"""Sample service deployed by the self-hosted CI/CD pipeline.

The version string returned by ``/`` is deliberately the only interesting piece of
behaviour: changing it is how you prove, end to end, that a commit travelled through
CI, became a container image, and reached the cluster.
"""

import os

from fastapi import FastAPI

APP_VERSION = os.getenv("APP_VERSION", "0.1.0")

app = FastAPI(title="sample-app", version=APP_VERSION)


@app.get("/")
def root() -> dict[str, str]:
    return {"app": "sample-app", "version": APP_VERSION}


@app.get("/healthz")
def healthz() -> dict[str, str]:
    """Liveness and readiness probe target.

    Kept free of dependencies on purpose: a probe that can fail for reasons
    unrelated to the process being alive causes restart loops under load.
    """
    return {"status": "ok"}
