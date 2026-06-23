use std::{io::Write, path::Path, process::Stdio};

use serde::Deserialize;
use serde_json::{json, Value};
use thiserror::Error;

use crate::teti_core::task_protocol::{
    TaskProtocolError, TetiTaskPayload, TetiTaskPermissions, TetiTaskProtocol,
};

use super::{
    attachments::GrantedAttachment,
    rpc_client::{RpcClient, RpcError},
    standard_interop,
};

pub use super::standard_interop::IncomingMessage;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SendTextInput {
    pub chat_id: u32,
    pub text: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SendAttachmentInput {
    pub chat_id: u32,
    pub text: Option<String>,
    pub attachment_token: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SendTaskInput {
    pub chat_id: u32,
    pub task_id: Option<String>,
    pub event_type: Option<String>,
    pub title: String,
    pub action: Option<String>,
    pub payload: Value,
    pub compat_text: String,
    pub status: Option<String>,
    pub description: Option<String>,
    pub permissions: Option<TetiTaskPermissions>,
}

#[derive(Debug, Error)]
pub enum MessageError {
    #[error(transparent)]
    Rpc(#[from] RpcError),
    #[error(transparent)]
    Task(#[from] TaskProtocolError),
    #[error("message text is empty")]
    EmptyText,
    #[error("message has no attachment")]
    NoAttachment,
    #[error("正在建立安全连接，请稍后再试")]
    ChatNotReady,
    #[error("failed to prepare attachment: {0}")]
    Io(#[from] std::io::Error),
}

pub async fn send_text(
    client: &RpcClient,
    account_id: u32,
    input: SendTextInput,
) -> Result<u32, MessageError> {
    let text = input.text.trim();
    if text.is_empty() {
        return Err(MessageError::EmptyText);
    }
    wait_until_can_send(client, account_id, input.chat_id).await?;
    Ok(client
        .call(
            "send_msg",
            json!([account_id, input.chat_id, { "text": text }]),
        )
        .await?)
}

pub async fn send_attachment(
    client: &RpcClient,
    account_id: u32,
    chat_id: u32,
    text: Option<String>,
    file: &GrantedAttachment,
) -> Result<u32, MessageError> {
    wait_until_can_send(client, account_id, chat_id).await?;
    let viewtype = image_viewtype(&file.path);
    Ok(client
        .call(
            "send_msg",
            json!([account_id, chat_id, {
                "text": text.map(|value| value.trim().to_owned()).filter(|value| !value.is_empty()),
                "viewtype": viewtype,
                "file": file.path.to_string_lossy(),
                "filename": file.name
            }]),
        )
        .await?)
}

pub async fn send_task(
    client: &RpcClient,
    account_id: u32,
    input: SendTaskInput,
) -> Result<u32, MessageError> {
    wait_until_can_send(client, account_id, input.chat_id).await?;
    let event_type = input
        .event_type
        .unwrap_or_else(|| "task_request".to_owned());
    let action = input
        .action
        .unwrap_or_else(|| default_action_for_event(&event_type).to_owned());
    let task = TetiTaskProtocol::event(
        event_type,
        input
            .task_id
            .unwrap_or_else(|| uuid::Uuid::new_v4().to_string()),
        Some(TetiTaskPayload {
            title: input.title,
            action,
            payload: input.payload,
        }),
        input.permissions.unwrap_or_default(),
        input.compat_text,
        input.status,
        input.description,
    )?;
    let body = task.compatibility_body();
    let mut file = tempfile::Builder::new()
        .prefix("teti-task-")
        .suffix(".json")
        .tempfile()?;
    let filename = task.attachment_filename();
    serde_json::to_writer_pretty(&mut file, &task).map_err(TaskProtocolError::from)?;
    file.flush()?;
    Ok(client
        .call(
            "send_msg",
            json!([account_id, input.chat_id, {
                "text": body,
                "viewtype": "File",
                "file": file.path().to_string_lossy(),
                "filename": filename
            }]),
        )
        .await?)
}

pub async fn get_fresh_messages(
    client: &RpcClient,
    account_id: u32,
) -> Result<Vec<IncomingMessage>, MessageError> {
    let ids = client
        .call::<Vec<u32>>("get_fresh_msgs", json!([account_id]))
        .await?;
    let mut messages = Vec::with_capacity(ids.len());
    for id in ids.into_iter().rev() {
        let value = client
            .call_value("get_message", json!([account_id, id]))
            .await?;
        messages.push(standard_interop::classify(id, &value));
    }
    Ok(messages)
}

pub async fn open_message_attachment(
    client: &RpcClient,
    account_id: u32,
    message_id: u32,
) -> Result<(), MessageError> {
    let value = client
        .call_value("get_message", json!([account_id, message_id]))
        .await?;
    let path = value
        .get("file")
        .and_then(Value::as_str)
        .ok_or(MessageError::NoAttachment)?;
    let path = Path::new(path);
    if !path.is_file() {
        return Err(MessageError::NoAttachment);
    }
    std::process::Command::new("/usr/bin/open")
        .arg(path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    Ok(())
}

fn image_viewtype(path: &Path) -> &'static str {
    match path
        .extension()
        .and_then(|value| value.to_str())
        .map(str::to_ascii_lowercase)
        .as_deref()
    {
        Some("png" | "jpg" | "jpeg" | "gif" | "webp") => "Image",
        _ => "File",
    }
}

fn default_action_for_event(event_type: &str) -> &'static str {
    match event_type {
        "task_reply" => "task.reply",
        "task_accepted" => "task.accepted",
        "task_rejected" => "task.rejected",
        "task_result" => "task.result",
        "file_package" => "file.package",
        "letter" => "letter.send",
        _ => "browser.screenshot",
    }
}

async fn wait_until_can_send(
    client: &RpcClient,
    account_id: u32,
    chat_id: u32,
) -> Result<(), MessageError> {
    for _ in 0..30 {
        if client
            .call::<bool>("can_send", json!([account_id, chat_id]))
            .await?
        {
            return Ok(());
        }
        tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    }
    Err(MessageError::ChatNotReady)
}
