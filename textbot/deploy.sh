#!/bin/sh
# Обновить бота на VPS: код и кампании — rsync, база и .env на сервере не трогаются.
# Адрес сервера — в локальном .env: DEPLOY_HOST=root@<ip>, DEPLOY_PORT=2222.
set -eu
cd "$(dirname "$0")"
DEPLOY_HOST=$(sed -n 's/^DEPLOY_HOST=//p' .env)
DEPLOY_PORT=$(sed -n 's/^DEPLOY_PORT=//p' .env)
DIR=/opt/gaz_quest_bot
[ -n "$DEPLOY_HOST" ] || { echo "В .env нет DEPLOY_HOST"; exit 1; }
rsync -az --delete -e "ssh -p ${DEPLOY_PORT:-22}" \
  --exclude .env --exclude data/ --exclude .venv --exclude .pytest_cache --exclude __pycache__ \
  ./ "$DEPLOY_HOST:$DIR/"
ssh -p "${DEPLOY_PORT:-22}" "$DEPLOY_HOST" "cd $DIR && docker compose up -d --build && docker compose logs --tail 5"
