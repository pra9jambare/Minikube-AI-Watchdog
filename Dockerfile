FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ /app/app/

RUN useradd --create-home --uid 10001 watchdog \
    && mkdir -p /data \
    && chown -R 10001:10001 /app /data

USER 10001:10001

CMD ["python", "-m", "app.main"]
