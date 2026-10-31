# Patient Record API image
FROM python:3.12-slim

# No .pyc writes (app dir is read-only at runtime) and unbuffered logs
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# /app is owned by the app user, so "modify app code" is only blocked by
# AppArmor / read-only filesystem - not by plain file permissions.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
COPY --chown=appuser:appuser app/app.py app/security_test.py ./

USER 10001
EXPOSE 5000

# --preload imports app.py once in the master, so a DB failure at startup
# exits the container (exit code 1) instead of looping worker restarts.
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--preload", \
     "--worker-tmp-dir", "/dev/shm", "--access-logfile", "-", "app:app"]
