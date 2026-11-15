# Central de Ativação: o que falta em produção para o h3suporte funcionar

Para repassar ao time da Central. Situação conferida no servidor (CT 110 do Proxmox, `10.0.4.19`, pasta
`/root/centralkeys`) em 14/11/2026, 21h:

- Feito: código das contas implantado (API e web; `/api/assinante/painel` responde 401), rota `/h3suporte` no
  `ops/Caddyfile` do repositório (validada com `caddy validate`) e **servidor-api publicado** em `/opt/h3suporte-api`
  (container `h3suporte-api-h3suporte-api-1`, saudável, na rede `central_interna`; o Caddy já o alcança).
- Falta: **reiniciar o Caddy** para carregar a rota (o container tem o Caddyfile antigo montado; `docker compose -p central
  -f docker-compose.prod.yml restart caddy`, cerca de 1 s fora do ar), criar o **produto H3 Suporte** com contas e a
  **credencial `sva_`** (hoje só existem os produtos Micron), a regra da **Cloudflare** e o **SMTP** (seções 3 a 6).
- Com a credencial em `/opt/h3suporte-api/.env`: `cd /opt/h3suporte-api && docker compose -f docker-compose.prod.yml up -d`.
  Até lá o login do app responde "Login indisponível"; heartbeat e saúde funcionam.

Como fica:

```
App h3suporte ──https──► keys.h3info.com/h3suporte/* ──Cloudflare──► Caddy da Central ──► h3suporte-api:21114
                                                                                              │ rede interna
                                                                                              ▼
                                                                                   API da Central (api:3001)
```

## 1. Implantar o código das contas

Commits na `main` do repositório da Central (todos já enviados ao Gitea e ao GitHub):

- `fd2b38c` Contas do assinante: titular, equipe e login de pessoas pelo serviço
- `90c8853` Contas na ficha da ativação, titularidade e exportação LGPD
- `7ce8f8e` Venda direta na vitrine da Central com cobrança pelo Asaas
- `33fd3c3` Contas do assinante: correções da revisão contra a spec
- `47a8cb9` Contas do assinante: titular automático e códigos de recuperação do 2FA
- `d41ff31` Caddy: rota /h3suporte para o servidor-api do h3suporte

```bash
git pull && make deploy
```

O `make deploy` aplica, em ordem, as migrações pendentes (nenhuma apaga dados):

| Migração                                         | O que faz                                                                    |
| ------------------------------------------------ | ---------------------------------------------------------------------------- |
| `20261114120000_venda_direta`                     | Preço da Central por plano, tabela `venda_direta`; `parceiro_id` passa a aceitar vazio |
| `20261114200000_contas_servico`                   | 4 tabelas das contas e 3 colunas com padrão                                  |
| `20261114210000_contas_servico_rls`               | Parceiro só lê contas e computadores (troca de policies)                     |
| `20261114220000_titular_automatico_recuperacao`   | Tipo de token para códigos de recuperação e `venda_direta.email`             |

Só não use `migrate dev` em produção.

Conferir: `curl -s https://keys.h3info.com/api/assinante/painel` deve dar **401** (“Sessão do assinante expirada”), não 404.

## 2. Rota `/h3suporte` no Caddy

Já está em `ops/Caddyfile` (commit `d41ff31`), **antes** do bloco `handle` do painel web; o `make deploy` reinicia o Caddy
(a menos que `SEM_PROXY=1`). O bloco é este:

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
- Só para recarregar o Caddy sem deploy: `docker compose -p central -f docker-compose.prod.yml restart caddy`.

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
   > Crie a conta do responsável em https://keys.h3info.com/assinante/criar-conta com esta chave. Você recebe um e-mail
   > para criar a senha. Depois convide sua equipe no portal e entre no H3 Suporte com o seu e-mail e senha.

   Na venda direta da Central e na habilitação pelo app, o titular é criado sozinho com o e-mail da compra e recebe o
   link para criar a senha; a chave serve só se esse e-mail não chegar (dá para corrigir o e-mail com a chave enquanto a
   senha não foi criada).
6. Liberar o produto aos parceiros e definir preços, como qualquer produto.

## 5. Credencial do servidor-api

Admin → Produtos → H3 Suporte → Credenciais → **nova credencial de Licenciamento** (`sva_…`). Ela aparece uma vez.
Coloque direto no servidor, em `/opt/h3suporte-api/.env`:

```
CENTRAL_CREDENCIAL=sva_...
```

Não mande a credencial por chat ou e-mail. Ela nunca vai para o app.

## 6. E-mail (obrigatório antes de vender)

Toda conta nasce sem senha e define a senha por um link enviado por e-mail: o titular (pela chave ou automático), o
convite da equipe e o “esqueci minha senha”. Sem SMTP configurado (Admin → E-mail), criar a conta pela chave e convidar
membro respondem `503` “A Central não consegue enviar e-mails agora”. Configure e teste o SMTP antes de liberar o produto.

## 7. O que mudou na Central e afeta o h3suporte

Contrato de `/api-servico/contas/*` igual; mudou o comportamento:

- **Códigos de recuperação do 2FA:** o `codigoTotp` do segundo passo aceita também um código no formato `ABCDE-FGHJK`
  (uso único). O servidor-api já repassa o `tfaCode` (até 32 caracteres), mas o campo do app
  (`Dialog2FaField` em `flutter/lib/common/widgets/dialog.dart`) só aceita 6 dígitos. Até mudar o app, quem perdeu o
  celular usa o código no portal do assinante (e reconfigura o 2FA em Minha conta) ou pede ao titular para zerar.
- **`CONTA_BLOQUEADA` só com a senha certa:** durante o bloqueio, senha errada responde `401 CREDENCIAIS_INVALIDAS`.
- **Limite por e-mail:** 5 tentativas de `entrar` em 10 min (antes 10); o 6º responde `429 MUITAS_TENTATIVAS`.
- **`validar` informa o motivo** também para sessão encerrada: `CONTA_DESATIVADA` e `DISPOSITIVO_REMOVIDO` passam a
  aparecer de fato.
- **Assinatura que sai de `ATIVA`** derruba as sessões abertas; com a reativação, cada pessoa entra de novo.
- **Conta sem senha** (convite ou titular que ainda não abriu o link) responde `CREDENCIAIS_INVALIDAS` no `entrar`.

## 8. Publicar o servidor-api

Do repositório do h3suporte (precisa de acesso SSH ao servidor e Docker lá):

```bash
servidor-api/publicar.sh usuario@servidor
```

## 9. Verificação final

```bash
curl -s https://keys.h3info.com/h3suporte/saude              # {"ok":true}
curl -s https://keys.h3info.com/h3suporte/api/login-options  # []
```

Depois: criar uma conta de titular de teste com uma chave real em `/assinante/criar-conta`, abrir o link do e-mail e
criar a senha, entrar no app h3suporte (build novo, que já aponta para `https://keys.h3info.com/h3suporte`) e conferir em
Admin → Ativações → a ativação → **Contas do assinante** se o computador aparece.
