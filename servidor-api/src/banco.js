import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";

const DIA = 86_400_000;

export function abrirBanco(caminho) {
  if (caminho !== ":memory:") mkdirSync(dirname(caminho), { recursive: true });
  const db = new DatabaseSync(caminho);
  db.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA busy_timeout = 5000;
    CREATE TABLE IF NOT EXISTS sessao (
      token_hash TEXT PRIMARY KEY,
      conta_id TEXT NOT NULL,
      assinatura_id TEXT NOT NULL,
      dados TEXT NOT NULL,
      validada_em INTEGER NOT NULL,
      criada_em INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS sessao_conta ON sessao (conta_id);
    CREATE TABLE IF NOT EXISTS catalogo (
      conta_id TEXT PRIMARY KEY,
      dados TEXT NOT NULL,
      atualizado_em INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS dispositivo (
      id TEXT PRIMARY KEY,
      uuid TEXT,
      nome TEXT,
      so TEXT,
      versao TEXT,
      conta_id TEXT,
      assinatura_id TEXT,
      visto_em INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS dispositivo_assinatura ON dispositivo (assinatura_id);
    CREATE TABLE IF NOT EXISTS auditoria (
      id INTEGER PRIMARY KEY,
      tipo TEXT NOT NULL,
      dispositivo TEXT,
      nonce TEXT UNIQUE,
      dados TEXT NOT NULL,
      criado_em INTEGER NOT NULL
    );
  `);

  const q = (sql) => db.prepare(sql);
  const st = {
    salvarSessao: q(`INSERT INTO sessao (token_hash, conta_id, assinatura_id, dados, validada_em, criada_em)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT (token_hash) DO UPDATE SET conta_id = excluded.conta_id,
        assinatura_id = excluded.assinatura_id, dados = excluded.dados, validada_em = excluded.validada_em`),
    lerSessao: q("SELECT dados, validada_em FROM sessao WHERE token_hash = ?"),
    apagarSessao: q("DELETE FROM sessao WHERE token_hash = ?"),
    lerCatalogo: q("SELECT dados FROM catalogo WHERE conta_id = ?"),
    salvarCatalogo: q(`INSERT INTO catalogo (conta_id, dados, atualizado_em) VALUES (?, ?, ?)
      ON CONFLICT (conta_id) DO UPDATE SET dados = excluded.dados, atualizado_em = excluded.atualizado_em`),
    vincular: q(`INSERT INTO dispositivo (id, uuid, nome, so, conta_id, assinatura_id, visto_em)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (id) DO UPDATE SET uuid = excluded.uuid, nome = coalesce(excluded.nome, dispositivo.nome),
        so = coalesce(excluded.so, dispositivo.so), conta_id = excluded.conta_id,
        assinatura_id = excluded.assinatura_id, visto_em = excluded.visto_em`),
    desvincular: q("UPDATE dispositivo SET conta_id = NULL, assinatura_id = NULL WHERE id = ? AND conta_id = ?"),
    sysinfo: q(`INSERT INTO dispositivo (id, uuid, nome, so, versao, visto_em) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT (id) DO UPDATE SET uuid = excluded.uuid, nome = excluded.nome, so = excluded.so,
        versao = excluded.versao, visto_em = excluded.visto_em`),
    visto: q("UPDATE dispositivo SET visto_em = ? WHERE id = ?"),
    daAssinatura: q(`SELECT id, nome, so, conta_id, visto_em FROM dispositivo
      WHERE assinatura_id = ? ORDER BY nome, id`),
    auditoria: q(`INSERT OR IGNORE INTO auditoria (tipo, dispositivo, nonce, dados, criado_em)
      VALUES (?, ?, ?, ?, ?)`),
    limparAuditoria: q("DELETE FROM auditoria WHERE criado_em < ?"),
    limparDispositivos: q("DELETE FROM dispositivo WHERE conta_id IS NULL AND visto_em < ?"),
    limparSessoes: q("DELETE FROM sessao WHERE validada_em < ?"),
  };

  return {
    salvarSessao(tokenHash, { conta, assinatura }, agora) {
      st.salvarSessao.run(tokenHash, conta.id, assinatura.id, JSON.stringify({ conta, assinatura }), agora, agora);
    },
    lerSessao(tokenHash) {
      const r = st.lerSessao.get(tokenHash);
      return r ? { ...JSON.parse(r.dados), validadaEm: r.validada_em } : null;
    },
    apagarSessao: (tokenHash) => st.apagarSessao.run(tokenHash),
    lerCatalogo: (contaId) => st.lerCatalogo.get(contaId)?.dados ?? null,
    salvarCatalogo: (contaId, dados, agora) => st.salvarCatalogo.run(contaId, dados, agora),
    vincularDispositivo: ({ id, uuid, nome, so, contaId, assinaturaId }, agora) =>
      st.vincular.run(id, uuid ?? null, nome ?? null, so ?? null, contaId, assinaturaId, agora),
    desvincularDispositivo: (id, contaId) => st.desvincular.run(id, contaId),
    registrarSysinfo: ({ id, uuid, nome, so, versao }, agora) =>
      st.sysinfo.run(id, uuid ?? null, nome ?? null, so ?? null, versao ?? null, agora),
    marcarVisto: (id, agora) => st.visto.run(agora, id),
    dispositivosDaAssinatura: (assinaturaId) => st.daAssinatura.all(assinaturaId),
    registrarAuditoria: ({ tipo, dispositivo, nonce, dados }, agora) =>
      st.auditoria.run(tipo, dispositivo ?? null, nonce ?? null, dados, agora),
    limpar(agora) {
      st.limparAuditoria.run(agora - 180 * DIA);
      st.limparDispositivos.run(agora - 90 * DIA);
      st.limparSessoes.run(agora - 90 * DIA);
    },
    fechar: () => db.close(),
  };
}
