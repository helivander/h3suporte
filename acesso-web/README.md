# Acesso remoto pelo navegador (prova de conceito)

Objetivo: o assinante, logado no portal da Central, abrir o acesso remoto a um dos seus dispositivos **sem instalar
nada**. Hoje só existe um cliente de teste em Node (`poc/`), que valida o protocolo; ainda não há navegador.

## O que já foi provado (17/11/2026)

Contra o servidor de produção `hbbsserver.h3info.com`, por WebSocket (`ws://…:21118` e `ws://…:21119`):

1. **Rendezvous** (`poc/01-rendezvous.mjs`): o hbbs responde ao `PunchHoleRequest` com a chave assinada do dispositivo
   e o relay. Exige a chave pública do servidor em `licence_key`, senão responde `LICENSE_MISMATCH`.
2. **Relay**: `RequestRelay` no hbbs (21118) e de novo no hbbr (21119).
3. **Troca de chaves com o dispositivo** (`poc/02-sessao.mjs`): verifica a assinatura do servidor e a do dispositivo,
   envia a chave simétrica selada (`crypto_box`), deriva as chaves por direção (BLAKE2b, `kx_version` 1) e passa a
   cifrar cada mensagem com `secretbox` e nonce por contador.
4. **Login por senha**: `sha256(sha256(senha + salt) + challenge)`; o dispositivo aceitou e devolveu `PeerInfo`
   (nome, plataforma, telas).
5. **Vídeo**: chegaram quadros de vídeo, além de cursor e áudio.

## O que falta

- Decodificar o vídeo (WebCodecs no navegador) e mostrar na tela; enviar mouse e teclado.
- **`wss://`**: uma página `https://` não abre `ws://`. Precisa de TLS: o nginx (CT 118) expor `/ws/id` e `/ws/relay`
  para `10.0.4.6:21118` e `:21119` (é o que o cliente oficial usa para domínios). As portas 21118 e 21119 já foram
  abertas no UniFi para este teste; ao migrar para `wss://` elas deveriam ser fechadas.
- Passar o login da Central (o dispositivo exige conta H3 Suporte para acesso remoto) e usar a senha guardada em
  "Meus dispositivos", sem o usuário digitar.
- O servidor-api/portal da Central: botão "Acessar pelo navegador" e a página do cliente.

## Como rodar o teste

```bash
cd acesso-web/poc && npm install
node 01-rendezvous.mjs <id>                 # o dispositivo está online?
SENHA='…' node 02-sessao.mjs <id>           # sessão completa; a senha vem só do ambiente
```

A senha de **uso único** do app muda depois do primeiro login: para repetir o teste, use uma senha permanente de
teste. Nunca grave a senha em arquivo.
