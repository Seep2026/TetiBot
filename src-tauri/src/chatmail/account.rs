use serde_json::{json, Value};
use thiserror::Error;

use super::{
    relay_config::{CHATMAIL_DOMAIN, CHATMAIL_QR},
    rpc_client::{RpcClient, RpcError},
};

#[derive(Debug, Clone)]
pub struct AccountStatus {
    pub configured: bool,
    pub addr: Option<String>,
    pub connectivity: Option<u32>,
}

impl AccountStatus {
    pub fn connected(&self) -> bool {
        self.configured && self.connectivity.unwrap_or_default() >= 3000
    }
}

#[derive(Debug, Error)]
pub enum AccountError {
    #[error(transparent)]
    Rpc(#[from] RpcError),
    #[error("no Delta Chat account context exists")]
    NoAccount,
    #[error("Delta Chat did not return the generated chatmail address")]
    AddressUnavailable,
}

impl AccountError {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::Rpc(RpcError::Unavailable | RpcError::Io(_)) => "rpc_unavailable",
            Self::Rpc(RpcError::Remote(_)) => "core_configuration_failed",
            Self::Rpc(RpcError::InvalidResponse(_)) => "invalid_core_response",
            Self::NoAccount => "account_context_missing",
            Self::AddressUnavailable => "address_unavailable",
        }
    }
}

pub async fn create_or_open_account(
    client: &RpcClient,
    preferred_account_id: Option<u32>,
) -> Result<u32, AccountError> {
    let ids = client
        .call::<Vec<u32>>("get_all_account_ids", json!([]))
        .await?;
    let existing = preferred_account_id
        .filter(|id| ids.contains(id))
        .or_else(|| ids.first().copied());
    let account_id = match existing {
        Some(id) => id,
        None => client.call::<u32>("add_account", json!([])).await?,
    };
    client
        .call::<Value>("select_account", json!([account_id]))
        .await?;
    Ok(account_id)
}

pub async fn configure_chatmail_identity(
    client: &RpcClient,
    account_id: u32,
    nickname: &str,
) -> Result<String, AccountError> {
    // Unconfigured contexts may not expose displayname yet, so set it both before and after setup.
    let _ = set_display_name(client, account_id, nickname).await;
    match client
        .call::<Value>("add_transport_from_qr", json!([account_id, CHATMAIL_QR]))
        .await
    {
        Ok(_) => {}
        Err(error) if method_is_unavailable(&error) => {
            client
                .call::<Value>("set_config_from_qr", json!([account_id, CHATMAIL_QR]))
                .await?;
            client
                .call::<Value>("configure", json!([account_id]))
                .await?;
        }
        Err(error) => return Err(error.into()),
    }

    client
        .call::<Value>("start_io", json!([account_id]))
        .await?;
    client.call::<Value>("maybe_network", json!([])).await?;

    let addr = wait_for_generated_address(client, account_id).await?;
    let _ = set_display_name(client, account_id, nickname).await;
    Ok(addr)
}

pub async fn reconnect(client: &RpcClient, account_id: u32) -> Result<AccountStatus, AccountError> {
    client
        .call::<Value>("start_io", json!([account_id]))
        .await?;
    client.call::<Value>("maybe_network", json!([])).await?;
    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    account_status(client, Some(account_id)).await
}

pub async fn remove_account(client: &RpcClient, account_id: u32) -> Result<(), AccountError> {
    client
        .call::<Value>("remove_account", json!([account_id]))
        .await?;
    Ok(())
}

pub async fn selected_or_first_account(client: &RpcClient) -> Result<u32, AccountError> {
    if let Some(id) = client
        .call::<Option<u32>>("get_selected_account_id", json!([]))
        .await?
    {
        return Ok(id);
    }
    client
        .call::<Vec<u32>>("get_all_account_ids", json!([]))
        .await?
        .into_iter()
        .next()
        .ok_or(AccountError::NoAccount)
}

pub async fn account_status(
    client: &RpcClient,
    account_id: Option<u32>,
) -> Result<AccountStatus, AccountError> {
    let account_id = match account_id {
        Some(id) => Some(id),
        None => {
            client
                .call::<Option<u32>>("get_selected_account_id", json!([]))
                .await?
        }
    };
    let Some(id) = account_id else {
        return Ok(AccountStatus {
            configured: false,
            addr: None,
            connectivity: None,
        });
    };
    let configured = client.call::<bool>("is_configured", json!([id])).await?;
    let connectivity = client
        .call::<u32>("get_connectivity", json!([id]))
        .await
        .ok();
    let addr = if configured {
        client
            .call_value("get_account_info", json!([id]))
            .await
            .ok()
            .and_then(|value| value.get("addr").and_then(Value::as_str).map(str::to_owned))
    } else {
        None
    };
    Ok(AccountStatus {
        configured,
        addr,
        connectivity,
    })
}

async fn wait_for_generated_address(
    client: &RpcClient,
    account_id: u32,
) -> Result<String, AccountError> {
    for _ in 0..30 {
        let status = account_status(client, Some(account_id)).await?;
        if let Some(addr) = status.addr.filter(|value| !value.trim().is_empty()) {
            return Ok(addr);
        }
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
    }
    Err(AccountError::AddressUnavailable)
}

pub async fn set_display_name(
    client: &RpcClient,
    account_id: u32,
    nickname: &str,
) -> Result<(), AccountError> {
    client
        .call::<Value>("set_config", json!([account_id, "displayname", nickname]))
        .await?;
    Ok(())
}

fn method_is_unavailable(error: &RpcError) -> bool {
    matches!(error, RpcError::Remote(message) if {
        let message = message.to_ascii_lowercase();
        message.contains("method not found") || message.contains("unknown method")
    })
}

pub fn address_matches_mvp_domain(addr: &str) -> bool {
    addr.rsplit_once('@')
        .is_some_and(|(_, domain)| domain.eq_ignore_ascii_case(CHATMAIL_DOMAIN))
}

#[cfg(test)]
mod tests {
    use super::address_matches_mvp_domain;

    #[test]
    fn accepts_only_the_fixed_chatmail_domain() {
        assert!(address_matches_mvp_domain("random@mail.seep.im"));
        assert!(!address_matches_mvp_domain("random@example.org"));
    }
}
