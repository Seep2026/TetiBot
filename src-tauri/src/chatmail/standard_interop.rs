use std::path::Path;

use serde::Serialize;
use serde_json::Value;

use crate::teti_core::task_protocol::{self, TetiTaskProtocol};

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum IncomingMessage {
    Text {
        message_id: u32,
        chat_id: u32,
        sender: String,
        text: String,
        encrypted: bool,
    },
    Attachment {
        message_id: u32,
        chat_id: u32,
        sender: String,
        text: String,
        file_name: String,
        mime_type: Option<String>,
        size: u64,
        encrypted: bool,
    },
    Task {
        message_id: u32,
        chat_id: u32,
        sender: String,
        text: String,
        task: Box<TetiTaskProtocol>,
        requires_confirmation: bool,
        encrypted: bool,
    },
}

pub fn classify(message_id: u32, value: &Value) -> IncomingMessage {
    let chat_id = value
        .get("chatId")
        .and_then(Value::as_u64)
        .unwrap_or_default() as u32;
    let sender = value
        .get("sender")
        .and_then(|sender| sender.get("displayName").or_else(|| sender.get("address")))
        .and_then(Value::as_str)
        .unwrap_or("Unknown")
        .to_owned();
    let text = value
        .get("text")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned();
    let encrypted = value
        .get("showPadlock")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let file_name = value.get("fileName").and_then(Value::as_str);
    let file_path = value.get("file").and_then(Value::as_str);
    if let (Some(name), Some(path)) = (file_name, file_path) {
        if let Ok(Some(task)) = task_protocol::parse_task_attachment(Path::new(path), name) {
            return IncomingMessage::Task {
                message_id,
                chat_id,
                sender,
                text,
                task: Box::new(task),
                requires_confirmation: true,
                encrypted,
            };
        }
        return IncomingMessage::Attachment {
            message_id,
            chat_id,
            sender,
            text,
            file_name: name.to_owned(),
            mime_type: value
                .get("fileMime")
                .and_then(Value::as_str)
                .map(str::to_owned),
            size: value
                .get("fileBytes")
                .and_then(Value::as_u64)
                .unwrap_or_default(),
            encrypted,
        };
    }
    IncomingMessage::Text {
        message_id,
        chat_id,
        sender,
        text,
        encrypted,
    }
}

#[cfg(test)]
mod tests {
    use super::{classify, IncomingMessage};
    use std::io::Write;

    use serde_json::json;

    #[test]
    fn standard_text_stays_standard() {
        let message = classify(
            1,
            &json!({"chatId": 7, "text": "hello", "sender": {"displayName": "Alice"}}),
        );
        assert!(matches!(message, IncomingMessage::Text { text, .. } if text == "hello"));
    }

    #[test]
    fn teti_task_attachment_becomes_task_card_event() {
        let mut file = tempfile::NamedTempFile::new().unwrap();
        write!(
            file,
            "{}",
            json!({
                "protocol": "teti.task",
                "version": "0.1",
                "task_id": "task-1",
                "event_type": "task_request",
                "task": {
                    "title": "打开网页并截图",
                    "action": "browser.screenshot",
                    "payload": { "url": "https://example.com" }
                },
                "permissions": {
                    "network_access": true,
                    "file_read": false,
                    "shell_exec": false,
                    "requires_user_approval": true
                },
                "compat_text": "Teti 任务请求：请帮忙打开 https://example.com 并返回截图。"
            })
        )
        .unwrap();
        let message = classify(
            2,
            &json!({
                "chatId": 7,
                "text": "Teti 任务请求",
                "sender": { "displayName": "Alice" },
                "fileName": "teti-task.json",
                "file": file.path().to_string_lossy()
            }),
        );
        assert!(matches!(message, IncomingMessage::Task { task, .. } if task.task_id == "task-1"));
    }
}
