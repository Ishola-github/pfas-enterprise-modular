# PFAS Enterprise 5 — operational FastAPI image.
# Reproducibility note: bookworm pins the Debian release. For production
# you can additionally pin to a digest:
#   FROM python:3.11-slim-bookworm@sha256:<...>
# Cap the build in CI to the digest you actually shipped.
FROM python:3.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# 1) Dependencies first so layer cache works when only source changes.
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# 2) Application source (.dockerignore selects what enters the image).
COPY api/        /app/api/
COPY scripts/    /app/scripts/
COPY modules/    /app/modules/
COPY data/       /app/data/

# Non-root runtime user (UID 10001 is well outside any host range).
RUN groupadd --system --gid 10001 pfas \
  && useradd  --system --uid 10001 --gid pfas --home /app --shell /usr/sbin/nologin pfas \
  && chown -R pfas:pfas /app

USER pfas

ENV APP_ENV=production \
    PORT=8000 \
    PFAS_API_LOG_JSON=true \
    PFAS_API_AD_STRICT_REFUSAL=true

EXPOSE 8000

# Liveness probe uses stdlib so the image stays small (no curl/wget).
HEALTHCHECK --interval=20s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request, sys; \
sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=3).status == 200 else 1)" \
  || exit 1

CMD ["sh", "-c", "uvicorn api.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --no-server-header --access-log"]
