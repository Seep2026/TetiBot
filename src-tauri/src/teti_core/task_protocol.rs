use std::path::Path;

use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

pub const TASK_FILENAME: &str = "teti-task.json";
pub const TASK_EVENT_FILENAME: &str = "teti-task-event.json";
const MAX_TASK_BYTES: u64 = 64 * 1024;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TetiTaskProtocol {
    pub protocol: String,
    pub version: String,
    pub task_id: String,
    pub event_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub task: Option<TetiTaskPayload>,
    #[serde(default)]
    pub permissions: TetiTaskPermissions,
    pub compat_text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TetiTaskPayload {
    pub title: String,
    pub action: String,
    pub payload: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TetiTaskPermissions {
    pub network_access: bool,
    pub file_read: bool,
    pub shell_exec: bool,
    pub requires_user_approval: bool,
}

impl Default for TetiTaskPermissions {
    fn default() -> Self {
        Self {
            network_access: false,
            file_read: false,
            shell_exec: false,
            requires_user_approval: true,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
struct LegacyTetiTaskProtocol {
    protocol: String,
    version: String,
    message_type: String,
    title: String,
    action: String,
    payload: Value,
    compat_text: String,
}

#[derive(Debug, Error)]
pub enum TaskProtocolError {
    #[error("unsupported Teti task protocol")]
    Unsupported,
    #[error("this task action is forbidden in the MVP")]
    ForbiddenAction,
    #[error("invalid task attachment: {0}")]
    InvalidJson(#[from] serde_json::Error),
    #[error("failed to read task attachment: {0}")]
    Io(#[from] std::io::Error),
}

impl TetiTaskProtocol {
    #[cfg(test)]
    pub fn new(
        title: String,
        action: String,
        payload: Value,
        compat_text: String,
    ) -> Result<Self, TaskProtocolError> {
        Self::event(
            "task_request".into(),
            uuid::Uuid::new_v4().to_string(),
            Some(TetiTaskPayload {
                title,
                action,
                payload,
            }),
            TetiTaskPermissions::default(),
            compat_text,
            None,
            None,
        )
    }

    pub fn event(
        event_type: String,
        task_id: String,
        task: Option<TetiTaskPayload>,
        permissions: TetiTaskPermissions,
        compat_text: String,
        status: Option<String>,
        description: Option<String>,
    ) -> Result<Self, TaskProtocolError> {
        let task = Self {
            protocol: "teti.task".into(),
            version: "0.1".into(),
            task_id,
            event_type,
            task,
            permissions,
            compat_text,
            status,
            description,
        };
        task.validate()?;
        Ok(task)
    }

    pub fn validate(&self) -> Result<(), TaskProtocolError> {
        if self.protocol != "teti.task" || self.version != "0.1" {
            return Err(TaskProtocolError::Unsupported);
        }
        const MVP_EVENTS: [&str; 7] = [
            "task_request",
            "task_reply",
            "task_accepted",
            "task_rejected",
            "task_result",
            "file_package",
            "letter",
        ];
        if !MVP_EVENTS.contains(&self.event_type.as_str()) || self.task_id.trim().is_empty() {
            return Err(TaskProtocolError::Unsupported);
        }
        if self.permissions.shell_exec || self.permissions.file_read {
            return Err(TaskProtocolError::ForbiddenAction);
        }
        if let Some(task) = &self.task {
            validate_action(&task.action)?;
        }
        if self.compat_text.trim().is_empty() {
            return Err(TaskProtocolError::Unsupported);
        }
        Ok(())
    }

    pub fn compatibility_body(&self) -> String {
        self.compat_text.clone()
    }

    pub fn attachment_filename(&self) -> &'static str {
        if self.event_type == "task_request" {
            TASK_FILENAME
        } else {
            TASK_EVENT_FILENAME
        }
    }
}

pub fn parse_task_attachment(
    path: &Path,
    filename: &str,
) -> Result<Option<TetiTaskProtocol>, TaskProtocolError> {
    if filename != TASK_FILENAME && filename != TASK_EVENT_FILENAME {
        return Ok(None);
    }
    if std::fs::metadata(path)?.len() > MAX_TASK_BYTES {
        return Err(TaskProtocolError::Unsupported);
    }
    let value: Value = serde_json::from_slice(&std::fs::read(path)?)?;
    let task = parse_task_value(value)?;
    task.validate()?;
    Ok(Some(task))
}

fn parse_task_value(value: Value) -> Result<TetiTaskProtocol, TaskProtocolError> {
    if value
        .get("protocol")
        .and_then(Value::as_str)
        .is_some_and(|protocol| protocol == "teti")
    {
        let legacy: LegacyTetiTaskProtocol = serde_json::from_value(value)?;
        return legacy_to_task(legacy);
    }
    Ok(serde_json::from_value(value)?)
}

fn legacy_to_task(legacy: LegacyTetiTaskProtocol) -> Result<TetiTaskProtocol, TaskProtocolError> {
    if legacy.protocol != "teti" || legacy.version != "0.1" || legacy.message_type != "task_request"
    {
        return Err(TaskProtocolError::Unsupported);
    }
    TetiTaskProtocol::event(
        "task_request".into(),
        uuid::Uuid::new_v4().to_string(),
        Some(TetiTaskPayload {
            title: legacy.title,
            action: legacy.action,
            payload: legacy.payload,
        }),
        TetiTaskPermissions {
            network_access: true,
            file_read: false,
            shell_exec: false,
            requires_user_approval: true,
        },
        legacy.compat_text,
        None,
        None,
    )
}

fn validate_action(action: &str) -> Result<(), TaskProtocolError> {
    const MVP_ACTIONS: [&str; 7] = [
        "browser.screenshot",
        "task.reply",
        "task.accepted",
        "task.rejected",
        "task.result",
        "file.package",
        "letter.send",
    ];
    let action_lower = action.to_ascii_lowercase();
    if action_lower.contains("shell")
        || action_lower.contains("keychain")
        || action_lower.contains("cookie")
        || action_lower.contains("ssh")
        || action_lower.starts_with("file.")
    {
        return Err(TaskProtocolError::ForbiddenAction);
    }
    if !MVP_ACTIONS.contains(&action) {
        return Err(TaskProtocolError::ForbiddenAction);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{TetiTaskPayload, TetiTaskPermissions, TetiTaskProtocol};
    use serde_json::json;

    #[test]
    fn blocks_remote_shell() {
        assert!(
            TetiTaskProtocol::new("bad".into(), "shell.exec".into(), json!({}), "bad".into())
                .is_err()
        );
    }

    #[test]
    fn allows_screenshot_request_without_executing_it() {
        assert!(TetiTaskProtocol::new(
            "capture".into(),
            "browser.screenshot".into(),
            json!({ "url": "https://example.com" }),
            "capture example.com".into(),
        )
        .is_ok());
    }

    #[test]
    fn serializes_task_request_protocol_for_teti_to_teti_cards() {
        let task = TetiTaskProtocol::event(
            "task_request".into(),
            "task-1".into(),
            Some(TetiTaskPayload {
                title: "打开网页并截图".into(),
                action: "browser.screenshot".into(),
                payload: json!({ "url": "https://example.com" }),
            }),
            TetiTaskPermissions {
                network_access: true,
                ..TetiTaskPermissions::default()
            },
            "Teti 任务请求：\n\n请帮忙打开 https://example.com 并返回截图。".into(),
            None,
            None,
        )
        .unwrap();
        assert_eq!(task.protocol, "teti.task");
        assert_eq!(task.attachment_filename(), super::TASK_FILENAME);
    }
}
