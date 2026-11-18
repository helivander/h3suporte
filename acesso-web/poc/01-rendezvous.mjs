// Passo 1: pergunta ao hbbs, por WebSocket (21118), se um ID existe e onde conectar.
// Uso: node 01-rendezvous.mjs <id>
import protobuf from 'protobufjs';
import WebSocket from 'ws';

const SERVIDOR = process.env.HBBS ?? 'ws://hbbsserver.h3info.com:21118';
const id = process.argv[2] ?? '999999999';

const root = await protobuf.load(new URL('../../libs/hbb_common/protos/rendezvous.proto', import.meta.url).pathname);
const Msg = root.lookupType('hbb.RendezvousMessage');

const ws = new WebSocket(SERVIDOR);
ws.binaryType = 'nodebuffer';
const fim = setTimeout(() => { console.log('sem resposta em 8 s'); process.exit(2); }, 8000);

ws.on('open', () => {
  console.log('conectado em', SERVIDOR);
  const pedido = Msg.create({
    punchHoleRequest: { id, natType: 1, licenceKey: process.env.CHAVE ?? 'ZCsYXRdFGM3S59i637iReSPtYe+UG4mKAwaqQAqRwJk=', connType: 0, version: '1.5.3', forceRelay: true },
  });
  ws.send(Msg.encode(pedido).finish());
});
ws.on('message', (dados) => {
  const m = Msg.decode(dados);
  console.log('resposta:', JSON.stringify(Msg.toObject(m, { enums: String, bytes: String, longs: String })));
  clearTimeout(fim); ws.close();
});
ws.on('error', (e) => { console.log('erro:', e.message); process.exit(1); });
