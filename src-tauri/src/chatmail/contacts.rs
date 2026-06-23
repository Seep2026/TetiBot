use serde::Serialize;
use serde_json::{json, Value};
use thiserror::Error;

use super::{
    invite_parser,
    rpc_client::{RpcClient, RpcError},
};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ContactSecurity {
    Ordinary,
    Encrypted,
    Verified,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ContactSummary {
    pub contact_id: u32,
    pub chat_id: Option<u32>,
    pub display_name: String,
    pub address: String,
    pub security: ContactSecurity,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AddedContact {
    pub chat_id: u32,
    pub contact: Option<ContactSummary>,
    pub invite: invite_parser::ParseInviteResult,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatReadiness {
    pub can_send: bool,
    pub contact: Option<ContactSummary>,
}

#[derive(Debug, Error)]
pub enum ContactError {
    #[error(transparent)]
    Rpc(#[from] RpcError),
    #[error("no Delta Chat invite link or email address was found")]
    UnknownInvite,
}

pub async fn add_from_text(
    client: &RpcClient,
    account_id: u32,
    text: &str,
) -> Result<AddedContact, ContactError> {
    let invite = invite_parser::parse(text);
    if let Some(link) = invite.invite_link.clone() {
        let chat_id = client
            .call::<u32>("secure_join", json!([account_id, link]))
            .await?;
        let contact = contact_for_chat(client, account_id, chat_id).await?;
        return Ok(AddedContact {
            chat_id,
            contact,
            invite,
        });
    }
    let address = invite.address.clone().ok_or(ContactError::UnknownInvite)?;
    let contact_id = client
        .call::<u32>(
            "create_contact",
            json!([account_id, address, invite.display_name]),
        )
        .await?;
    let chat_id = client
        .call::<u32>("create_chat_by_contact_id", json!([account_id, contact_id]))
        .await?;
    let contact = client
        .call_value("get_contact", json!([account_id, contact_id]))
        .await?;
    Ok(AddedContact {
        chat_id,
        contact: Some(summarize(&contact, Some(chat_id))),
        invite,
    })
}

pub async fn chat_readiness(
    client: &RpcClient,
    account_id: u32,
    chat_id: u32,
) -> Result<ChatReadiness, ContactError> {
    let can_send = client
        .call::<bool>("can_send", json!([account_id, chat_id]))
        .await?;
    let contact = contact_for_chat(client, account_id, chat_id).await?;
    Ok(ChatReadiness { can_send, contact })
}

pub async fn list_contacts(
    client: &RpcClient,
    account_id: u32,
) -> Result<Vec<ContactSummary>, ContactError> {
    let contacts = client
        .call::<Vec<Value>>("get_contacts", json!([account_id, 0, null]))
        .await?;
    let mut result = Vec::with_capacity(contacts.len());
    for contact in contacts {
        let contact_id = contact
            .get("id")
            .and_then(Value::as_u64)
            .unwrap_or_default() as u32;
        let chat_id = if contact_id > 0 {
            client
                .call::<u32>("create_chat_by_contact_id", json!([account_id, contact_id]))
                .await
                .ok()
        } else {
            None
        };
        result.push(summarize(&contact, chat_id));
    }
    Ok(result)
}

fn summarize(value: &Value, chat_id: Option<u32>) -> ContactSummary {
    let verified = value
        .get("isVerified")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let encrypted = value
        .get("e2eeAvail")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let security = if verified {
        ContactSecurity::Verified
    } else if encrypted {
        ContactSecurity::Encrypted
    } else {
        ContactSecurity::Ordinary
    };
    ContactSummary {
        contact_id: value.get("id").and_then(Value::as_u64).unwrap_or_default() as u32,
        chat_id,
        display_name: value
            .get("displayName")
            .and_then(Value::as_str)
            .unwrap_or("Unknown")
            .to_owned(),
        address: value
            .get("address")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned(),
        security,
    }
}

async fn contact_for_chat(
    client: &RpcClient,
    account_id: u32,
    chat_id: u32,
) -> Result<Option<ContactSummary>, ContactError> {
    let contact_ids = client
        .call::<Vec<u32>>("get_chat_contacts", json!([account_id, chat_id]))
        .await?;
    let Some(contact_id) = contact_ids.first().copied() else {
        return Ok(None);
    };
    let contact = client
        .call_value("get_contact", json!([account_id, contact_id]))
        .await?;
    Ok(Some(summarize(&contact, Some(chat_id))))
}
