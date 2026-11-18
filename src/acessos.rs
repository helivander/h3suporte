//! Acessos remotos simultâneos, limitados pelo plano da assinatura (Central de ativação).
//!
//! Antes de conectar, o app pede uma vaga ao servidor-api (`/api/acessos/abrir`), renova enquanto a conexão
//! existe e devolve ao encerrar (`/api/acessos/fechar`). O servidor recusa com `409` quando o plano já está no
//! limite e com `401` quando o login não vale mais. Servidor fora do ar ou sem essa rota não impede o acesso.

use hbb_common::{
    log,
    tokio::{
        self,
        task::JoinHandle,
        time::{interval, timeout, Duration},
    },
};

const RENOVACAO: Duration = Duration::from_secs(60);
const ESPERA: Duration = Duration::from_secs(3);

/// Vaga de um acesso aberto; ao sair de escopo, devolve a vaga ao servidor.
pub struct Acesso {
    servidor: String,
    corpo: String,
    cabecalho: String,
    renovacao: JoinHandle<()>,
}

impl Drop for Acesso {
    fn drop(&mut self) {
        self.renovacao.abort();
        let url = format!("{}/api/acessos/fechar", self.servidor);
        let corpo = std::mem::take(&mut self.corpo);
        let cabecalho = std::mem::take(&mut self.cabecalho);
        std::thread::spawn(move || {
            if let Err(e) = crate::post_request_sync(url, corpo, &cabecalho) {
                log::debug!("acesso: não foi possível avisar o encerramento: {e}");
            }
        });
    }
}

/// Motivo da recusa quando a resposta do servidor impede o acesso; None nas demais respostas.
fn recusa(status: u16, corpo: &str) -> Option<String> {
    if status != 401 && status != 409 {
        return None;
    }
    let motivo = serde_json::from_str::<serde_json::Value>(corpo)
        .ok()
        .and_then(|v| v.get("error")?.as_str().map(str::to_owned));
    Some(motivo.unwrap_or_else(|| {
        if status == 401 {
            "Entre de novo com sua conta H3 Suporte para fazer acessos remotos.".to_owned()
        } else {
            "O limite de acessos remotos simultâneos do plano foi atingido.".to_owned()
        }
    }))
}

/// Pede a vaga para acessar `peer`. `Err` traz o motivo para mostrar ao usuário; `Ok(None)` quando não há
/// servidor de API ou login (o bloqueio por falta de login é de `crate::plano`).
pub async fn abrir(peer: &str, token: &str) -> Result<Option<Acesso>, String> {
    let servidor = crate::ui_interface::get_api_server();
    if servidor.is_empty() || token.is_empty() {
        return Ok(None);
    }
    let url = format!("{servidor}/api/acessos/abrir");
    let corpo = serde_json::json!({ "id": uuid::Uuid::new_v4().to_string(), "peer": peer }).to_string();
    let cabecalho = format!("Authorization: Bearer {token}");
    match timeout(
        ESPERA,
        crate::post_request_with_status(url.clone(), corpo.clone(), &cabecalho),
    )
    .await
    {
        Ok(Ok((status, resposta))) => {
            if let Some(motivo) = recusa(status, &resposta) {
                return Err(motivo);
            }
        }
        Ok(Err(e)) => log::warn!("acesso: servidor de API não respondeu, seguindo sem a vaga: {e}"),
        Err(_) => log::warn!("acesso: servidor de API demorou, seguindo sem a vaga"),
    }
    let renovacao = {
        let (corpo, cabecalho) = (corpo.clone(), cabecalho.clone());
        tokio::spawn(async move {
            let mut relogio = interval(RENOVACAO);
            relogio.tick().await;
            loop {
                relogio.tick().await;
                if let Err(e) =
                    crate::post_request_with_status(url.clone(), corpo.clone(), &cabecalho).await
                {
                    log::trace!("acesso: renovação falhou: {e}");
                }
            }
        })
    };
    Ok(Some(Acesso {
        servidor,
        corpo,
        cabecalho,
        renovacao,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn limite_do_plano_recusa_com_a_mensagem_do_servidor() {
        assert_eq!(
            recusa(409, r#"{"error":"O plano permite 2 acessos remotos ao mesmo tempo."}"#).as_deref(),
            Some("O plano permite 2 acessos remotos ao mesmo tempo.")
        );
        assert!(recusa(401, "").is_some());
    }

    #[test]
    fn servidor_antigo_ou_fora_do_ar_nao_impede() {
        assert_eq!(recusa(200, r#"{"limite":null,"em_uso":1}"#), None);
        assert_eq!(recusa(404, r#"{"error":"Não encontrado."}"#), None);
        assert_eq!(recusa(503, ""), None);
    }
}
