//! Funções do aplicativo liberadas pelo plano da assinatura (Central de ativação).
//!
//! O servidor-api do H3 Suporte devolve no login e no `currentUser` o campo `funcoes`, guardado pelo app em
//! `user_info`. Regras:
//! * sem login (`user_info` vazio): nenhum acesso remoto abre, nem o controle remoto comum;
//! * logado e `funcoes` ausente ou `null`: o produto não separa por função, tudo liberado;
//! * logado e `funcoes` lista: só os códigos da lista.
//!
//! O controle remoto comum exige só o login (assinatura ativa); não depende de função do plano.
//! Quem recebe o acesso não precisa de conta: a regra vale para quem inicia a conexão.

use hbb_common::{config::LocalConfig, rendezvous_proto::ConnType};

pub const TRANSFERENCIA_ARQUIVOS: &str = "transferencia_arquivos";
pub const TERMINAL: &str = "terminal";
pub const TUNEL: &str = "tunel";
pub const CAMERA: &str = "camera";

/// Código da função do plano exigida por um tipo de conexão de saída (None = não depende do plano).
pub fn funcao_da_conexao(conn_type: ConnType) -> Option<&'static str> {
    match conn_type {
        ConnType::FILE_TRANSFER => Some(TRANSFERENCIA_ARQUIVOS),
        ConnType::TERMINAL => Some(TERMINAL),
        ConnType::PORT_FORWARD | ConnType::RDP => Some(TUNEL),
        ConnType::VIEW_CAMERA => Some(CAMERA),
        _ => None,
    }
}

const SEM_LOGIN: &str = "Entre com sua conta H3 Suporte para fazer acessos remotos.";

fn nome(funcao: &str) -> &str {
    match funcao {
        TRANSFERENCIA_ARQUIVOS => "Transferência de arquivos",
        TERMINAL => "Terminal remoto",
        TUNEL => "Túnel (TCP/RDP)",
        CAMERA => "Câmera remota",
        outra => outra,
    }
}

/// Objeto `user_info` válido quando há usuário logado.
fn parse_user_info(user_info: &str) -> Option<serde_json::Map<String, serde_json::Value>> {
    let trimmed = user_info.trim();
    if trimmed.is_empty() {
        return None;
    }
    match serde_json::from_str::<serde_json::Value>(trimmed).ok()? {
        serde_json::Value::Object(obj) => Some(obj),
        _ => None,
    }
}

fn liberada_em_obj(obj: &serde_json::Map<String, serde_json::Value>, funcao: &str) -> bool {
    match obj.get("funcoes") {
        None | Some(serde_json::Value::Null) => true,
        Some(serde_json::Value::Array(lista)) => lista.iter().any(|f| f.as_str() == Some(funcao)),
        Some(_) => false,
    }
}

/// `user_info` guardado pelo app libera a função?
#[cfg(test)]
fn liberada_em(user_info: &str, funcao: &str) -> bool {
    parse_user_info(user_info).is_some_and(|obj| liberada_em_obj(&obj, funcao))
}

/// Motivo para recusar a conexão, ou None se o plano libera.
pub fn bloqueio(conn_type: ConnType) -> Option<String> {
    let user_info = LocalConfig::get_option("user_info");
    bloqueio_em(&user_info, conn_type)
}

fn bloqueio_em(user_info: &str, conn_type: ConnType) -> Option<String> {
    let obj = parse_user_info(user_info);
    let Some(funcao) = funcao_da_conexao(conn_type) else {
        return obj.is_none().then(|| SEM_LOGIN.to_owned());
    };
    let Some(obj) = obj else {
        return Some(format!("{}: entre com sua conta H3 Suporte para usar.", nome(funcao)));
    };
    if liberada_em_obj(&obj, funcao) {
        return None;
    }
    Some(format!("{}: não incluída no plano da sua assinatura.", nome(funcao)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sem_login_bloqueia() {
        assert!(!liberada_em("", TERMINAL));
        assert!(!liberada_em("lixo", TERMINAL));
    }

    #[test]
    fn sem_funcoes_libera_tudo() {
        assert!(liberada_em(r#"{"name":"a@b.c"}"#, TERMINAL));
        assert!(liberada_em(r#"{"name":"a@b.c","funcoes":null}"#, TUNEL));
    }

    #[test]
    fn lista_libera_so_as_do_plano() {
        let info = r#"{"name":"a@b.c","funcoes":["terminal"]}"#;
        assert!(liberada_em(info, TERMINAL));
        assert!(!liberada_em(info, TRANSFERENCIA_ARQUIVOS));
        assert!(!liberada_em(r#"{"funcoes":[]}"#, CAMERA));
    }

    #[test]
    fn controle_remoto_comum_exige_login() {
        assert_eq!(bloqueio_em("", ConnType::DEFAULT_CONN).as_deref(), Some(SEM_LOGIN));
        assert_eq!(bloqueio_em(r#"{"name":"a@b.c","funcoes":[]}"#, ConnType::DEFAULT_CONN), None);
        assert!(bloqueio_em(r#"{"name":"a@b.c","funcoes":[]}"#, ConnType::TERMINAL).is_some());
    }

    #[test]
    fn conexao_comum_nao_depende_do_plano() {
        assert_eq!(funcao_da_conexao(ConnType::DEFAULT_CONN), None);
        assert_eq!(funcao_da_conexao(ConnType::FILE_TRANSFER), Some(TRANSFERENCIA_ARQUIVOS));
        assert_eq!(funcao_da_conexao(ConnType::TERMINAL), Some(TERMINAL));
        assert_eq!(funcao_da_conexao(ConnType::PORT_FORWARD), Some(TUNEL));
        assert_eq!(funcao_da_conexao(ConnType::RDP), Some(TUNEL));
        assert_eq!(funcao_da_conexao(ConnType::VIEW_CAMERA), Some(CAMERA));
    }

    #[test]
    fn json_nao_objeto_ou_invalido_conta_como_sem_login() {
        for invalido in ["   ", "null", "[]", "123", "lixo"] {
            assert!(!liberada_em(invalido, TERMINAL));
            assert_eq!(bloqueio_em(invalido, ConnType::DEFAULT_CONN).as_deref(), Some(SEM_LOGIN));
            let msg = bloqueio_em(invalido, ConnType::TERMINAL).unwrap();
            assert!(msg.contains("entre com sua conta"), "esperava pedido de login, veio: {msg}");
        }
    }

    #[test]
    fn funcoes_malformadas_bloqueiam_pelo_plano() {
        assert!(!liberada_em(r#"{"funcoes":"terminal"}"#, TERMINAL));
        assert!(!liberada_em(r#"{"funcoes":123}"#, TERMINAL));
        let msg = bloqueio_em(r#"{"funcoes":"terminal"}"#, ConnType::TERMINAL).unwrap();
        assert!(msg.contains("não incluída no plano"), "veio: {msg}");

        let misto = r#"{"funcoes":[null,123,"camera"]}"#;
        assert!(liberada_em(misto, CAMERA));
        assert!(!liberada_em(misto, TERMINAL));
    }
}
