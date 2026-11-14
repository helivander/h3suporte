# Central de Ativação: o que falta em produção para o h3suporte funcionar

Para repassar ao time da Central. Situação conferida em 14/11/2026 em `https://keys.h3info.com`:

- `GET /api/saude` responde, mas `/assinante/entrar` e `/api/assinante/painel` dão **404**: o código das contas ainda não
  foi implantado.
- `https://keys.h3info.com/h3suporte/*` cai no painel web: a rota do servidor-api ainda não existe no Caddy.

Como fica:

```
App h3suporte ──https──► keys.h3info.com/h3suporte/* ──Cloudflare──► Caddy da Central ──► h3suporte-api:21114
                                                                                              │ rede interna
                                                                                              ▼
                                                                                   API da Central (api:3001)
```

## 1. Implantar o código das contas

Commits na `main` do repositório da Central:

- `fd2b38c` Contas do assinante: titular, equipe e login de pessoas pelo serviço
- `90c8853` Contas na ficha da ativação, titularidade e exportação LGPD

```bash
git pull && make deploy
```

Aplica a migração `20261114200000_contas_servico` (só aditiva: 4 tabelas novas e 3 colunas com padrão).

**Atenção:** existe no checkout de desenvolvimento uma migração ainda não commitada, `20261114120000_venda_direta`, com data
**anterior** à das contas. Se ela for para produção depois, `prisma migrate deploy` (usado pelo `make deploy`) aplica as
pendentes sem reclamar da ordem. Só não use `migrate dev` em produção.

Conferir: `curl -s https://keys.h3info.com/api/assinante/painel` deve dar **401** (“Sessão do assinante expirada”), não 404.

## 2. Rota `/h3suporte` no Caddy

Em `ops/Caddyfile`, **antes** do bloco `handle` do painel web:

```caddy
	# Servidor de API do h3suporte (app de suporte remoto): /h3suporte/<rota> -> servidor-api em /<rota>
	handle_path /h3suporte/* {
		request_body {
			max_size 3MB
		}
		reverse_proxy h3suporte-api:21114 {
			header_up X-Forwarded-For {client_ip}
		}
	}
```

- `h3suporte-api` é o container do servidor-api, que entra na rede `interna` do Compose da Central (nome Docker
  `central_interna`). Se o container não estiver no ar, só essa rota responde 502; o resto da Central não é afetado.
- 3 MB porque o app envia o catálogo de endereços inteiro de uma vez.
- Depois: `make deploy` (ou `docker compose -p central -f docker-compose.prod.yml restart caddy`).

Conferir o nome da rede no servidor: `docker network ls | grep interna` deve mostrar `central_interna`. Se for outro,
informe para colocarmos em `REDE_CENTRAL` no `.env` do servidor-api.

## 3. Cloudflare

O app h3suporte não é um navegador e manda `POST` com JSON a cada 15 s (heartbeat) de cada computador. A Cloudflare hoje
injeta o script anti-robô nas páginas (`/cdn-cgi/challenge-platform`). Para não bloquear o app:

- Regra (Security → WAF → Custom rules): se o caminho começa com `/h3suporte/`, **Skip** em Bot Fight Mode / Super Bot
  Fight Mode, gerenciadores de desafio e rate limiting da Cloudflare (os limites ficam no servidor-api e na Central).
- Regra de cache: `/h3suporte/*` **sem cache** (Bypass).

Conferir de fora (não pode vir HTML de desafio):

```bash
curl -s -X POST https://keys.h3info.com/h3suporte/api/heartbeat -d '{"id":"teste"}'   # deve responder {}
```

## 4. Produto h3suporte no painel (Admin → Produtos)

1. Criar o produto **H3 Suporte** (ou usar o existente), situação **Publicado**.
2. **Contas do assinante: Sim (titular e equipe)**.
3. **Limite de instalações** = quantos computadores de técnico cada assinatura pode usar.
4. Em cada plano, **Limite de contas por assinatura** (ex.: plano Equipe 5 → 5).
5. Instruções do produto (aparecem na entrega da chave), por exemplo:
   > Crie a conta do responsável em https://keys.h3info.com/assinante/criar-conta com esta chave. Depois convide sua
   > equipe no portal e entre no H3 Suporte com o seu e-mail e senha.
6. Liberar o produto aos parceiros e definir preços, como qualquer produto.

## 5. Credencial do servidor-api

Admin → Produtos → H3 Suporte → Credenciais → **nova credencial de Licenciamento** (`sva_…`). Ela aparece uma vez.
Coloque direto no servidor, em `/opt/h3suporte-api/.env`:

```
CENTRAL_CREDENCIAL=sva_...
```

Não mande a credencial por chat ou e-mail. Ela nunca vai para o app.

## 6. E-mail

O convite da equipe e o “esqueci minha senha” do portal mandam e-mail. Sem SMTP configurado (Admin → E-mail), convidar
membro responde “A Central não consegue enviar e-mails agora”. O titular cria a própria conta com a chave mesmo sem e-mail.

## 7. Publicar o servidor-api

Do repositório do h3suporte (precisa de acesso SSH ao servidor e Docker lá):

```bash
servidor-api/publicar.sh usuario@servidor
```

## 8. Verificação final

```bash
curl -s https://keys.h3info.com/h3suporte/saude              # {"ok":true}
curl -s https://keys.h3info.com/h3suporte/api/login-options  # []
```

Depois: criar uma conta de titular de teste com uma chave real, entrar no app h3suporte (build novo, que já aponta para
`https://keys.h3info.com/h3suporte`) e conferir em Admin → Ativações → a ativação → **Contas do assinante** se o
computador aparece.
