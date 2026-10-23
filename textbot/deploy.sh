#!/bin/sh
# Обновить бота на VPS и разослать игрокам новость: ./deploy.sh news.txt
# Код и кампании — rsync, база и .env на сервере не трогаются. Без файла новости не выкладывает.
# Адрес сервера — в локальном .env: DEPLOY_HOST=root@<ip>, DEPLOY_PORT=2222.
set -eu
cd "$(dirname "$0")"
NEWS=${1:-}
[ -n "$NEWS" ] && [ -s "$NEWS" ] || { echo "Нужен файл с описанием обновления: ./deploy.sh news.txt"; exit 1; }
DEPLOY_HOST=$(sed -n 's/^DEPLOY_HOST=//p' .env)
DEPLOY_PORT=$(sed -n 's/^DEPLOY_PORT=//p' .env)
DIR=/opt/gaz_quest_bot
[ -n "$DEPLOY_HOST" ] || { echo "В .env нет DEPLOY_HOST"; exit 1; }
SSH="ssh -p ${DEPLOY_PORT:-22} $DEPLOY_HOST"
rsync -az --delete -e "ssh -p ${DEPLOY_PORT:-22}" \
  --exclude .env --exclude data/ --exclude .venv --exclude .pytest_cache --exclude __pycache__ \
  --exclude 'news*.txt' ./ "$DEPLOY_HOST:$DIR/"
$SSH "cd $DIR && docker compose up -d --build && docker compose logs --tail 5"
# Рассылка — только если бот поднялся
$SSH "cd $DIR && until [ \"\$(docker inspect -f '{{.State.Health.Status}}' textbot)\" != starting ]; do sleep 2; done; \
  [ \"\$(docker inspect -f '{{.State.Health.Status}}' textbot)\" = healthy ] || { echo 'Бот нездоров — рассылки не будет'; exit 1; }; \
  docker compose exec -T bot python -m textbot.broadcast" < "$NEWS"
