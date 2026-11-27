#!/usr/bin/env bash
# Publica o servidor-api no servidor da Central: copia esta pasta, sobe o container e confere a saúde.
# Uso: ./publicar.sh usuario@servidor [/opt/h3suporte-api]
# Na 1a vez crie no servidor <destino>/.env com CENTRAL_CREDENCIAL=sva_... (veja .env.example); o script não envia .env.
# Sem a credencial o serviço sobe, mas o login responde "indisponível".
set -Eeuo pipefail

DESTINO_SSH="${1:?uso: ./publicar.sh usuario@servidor [pasta]}"
PASTA="${2:-/opt/h3suporte-api}"
cd "$(dirname "$0")"

echo "==> copiando para $DESTINO_SSH:$PASTA"
# tar em vez de rsync: funciona em qualquer servidor. Apaga só o código antigo (src), nunca .env nem dados.
COPYFILE_DISABLE=1 tar -czf - --exclude .env --exclude dados --exclude node_modules --exclude test . |
  ssh "$DESTINO_SSH" "mkdir -p '$PASTA' && rm -rf '$PASTA/src' && tar -xzf - -C '$PASTA'"

echo "==> conferindo .env e rede da Central"
ssh "$DESTINO_SSH" "test -f '$PASTA/.env' || { echo 'Falta $PASTA/.env (copie de .env.example e preencha CENTRAL_CREDENCIAL)'; exit 1; }
  grep -q '^CENTRAL_CREDENCIAL=sva_' '$PASTA/.env' || echo 'AVISO: sem CENTRAL_CREDENCIAL no .env, o login fica desligado até ela ser colocada (depois: docker compose up -d)';
  docker network inspect \"\${REDE_CENTRAL:-central_interna}\" >/dev/null || { echo 'Rede da Central não encontrada (REDE_CENTRAL)'; exit 1; }"

echo "==> subindo"
ssh "$DESTINO_SSH" "cd '$PASTA' && docker compose -f docker-compose.prod.yml up -d --build"

echo "==> saúde (dentro da rede da Central)"
ssh "$DESTINO_SSH" "for i in 1 2 3 4 5 6 7 8 9 10; do
    docker exec \"\${CADDY_CENTRAL:-central-caddy-1}\" wget -qO- http://h3suporte-api:21114/saude && exit 0
    sleep 2
  done; echo 'servidor-api não respondeu'; docker compose -f '$PASTA/docker-compose.prod.yml' logs --tail 50; exit 1"
echo
echo "==> pelo domínio (só funciona depois do bloco /h3suporte no Caddy da Central)"
curl -fsS -m 10 https://h3info.com/h3suporte/saude && echo || echo "ainda não: falta a rota /h3suporte no Caddy da Central"
