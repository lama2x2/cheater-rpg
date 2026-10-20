FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 DATA_DIR=/data CAMPAIGNS_DIR=/app/campaigns
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY textbot ./textbot
COPY campaigns ./campaigns
VOLUME /data
# Бот раз в 30 с обновляет /data/heartbeat; старше 2 минут — контейнер «нездоров»
HEALTHCHECK --interval=60s --timeout=5s --start-period=30s --retries=3 \
  CMD python -c "import os,sys,time; sys.exit(0 if time.time()-os.path.getmtime('/data/heartbeat')<120 else 1)"
CMD ["python", "-m", "textbot"]
