mod chatmail;
mod pet_process;
mod teti_core;

use std::sync::{Arc, Mutex as StdMutex};

use chatmail::{
    account::{self, AccountError},
    attachments::{AttachmentGrant, AttachmentGrantStore},
    contacts::{self, AddedContact, ChatReadiness, ContactSummary},
    invite_parser::{self, ParseInviteResult},
    messages::{self, IncomingMessage, SendAttachmentInput, SendTaskInput, SendTextInput},
    relay_config::{CHATMAIL_DOMAIN, CHATMAIL_QR_TYPE},
    rpc_client::RpcClient,
    rpc_process::RpcProcess,
};
use chrono::Utc;
use pet_process::{DesktopPetProcess, PetStatusBridge};
use serde::{Deserialize, Serialize};
use tauri::{
    menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem, Submenu},
    Manager, State, Wry,
};
use teti_core::pet_profile::{validate_nickname, PetProfile, PetProfileStore};
use tokio::sync::{Mutex, RwLock};

const MENU_OPEN_MAIL: &str = "teti.open_mail";
const MENU_QUIT: &str = "teti.quit";
const MENU_HAT_PREFIX: &str = "teti.hat.";

const HAT_MENU_ITEMS: [(&str, &str); 18] = [
    ("none", "None"),
    ("beanie", "Beanie"),
    ("engineer", "Engineer"),
    ("antenna", "Antenna"),
    ("warning_light", "Warning Light"),
    ("sprout", "Sprout"),
    ("focus_goggles", "Focus Goggles"),
    ("happy_cap", "Happy Cap"),
    ("sad_hood", "Sad Hood"),
    ("loading_ring", "Loading Ring"),
    ("cpu_core", "CPU Core"),
    ("network_node", "Network Node"),
    ("mouse_cursor", "Mouse Cursor"),
    ("click_spark", "Click Spark"),
    ("drag_handle", "Drag Handle"),
    ("token_core", "Token Core"),
    ("gateway_node", "Gateway Node"),
    ("fleet_signal", "Fleet Signal"),
];

struct ChatmailManager {
    data_dir: std::path::PathBuf,
    process: Mutex<Option<RpcProcess>>,
    account_id: RwLock<Option<u32>>,
    profile_store: PetProfileStore,
    diagnostic: RwLock<Option<InitializationDiagnostic>>,
    attachments: AttachmentGrantStore,
}

struct TetiMenuState {
    current_hat: StdMutex<String>,
    hat_items: Vec<(String, CheckMenuItem<Wry>)>,
}

impl ChatmailManager {
    fn new(data_dir: std::path::PathBuf) -> Self {
        Self {
            profile_store: PetProfileStore::new(data_dir.join("pet-profile.json")),
            data_dir,
            process: Mutex::new(None),
            account_id: RwLock::new(None),
            diagnostic: RwLock::new(None),
            attachments: AttachmentGrantStore::default(),
        }
    }

    async fn client(&self) -> Result<RpcClient, String> {
        let mut process = self.process.lock().await;
        if process.is_none() {
            let accounts_dir = self.data_dir.join("delta-accounts");
            let spawned = RpcProcess::spawn(&accounts_dir)
                .await
                .map_err(|error| error.to_string())?;
            *process = Some(spawned);
        }
        Ok(process.as_ref().expect("process inserted").client())
    }

    async fn account_id(&self, client: &RpcClient) -> Result<u32, String> {
        if let Some(id) = *self.account_id.read().await {
            return Ok(id);
        }
        if let Some(profile) = self
            .profile_store
            .load()
            .map_err(|error| error.to_string())?
        {
            *self.account_id.write().await = Some(profile.dc_account_id);
            return Ok(profile.dc_account_id);
        }
        let selected = account::selected_or_first_account(client)
            .await
            .map_err(|error| error.to_string())?;
        *self.account_id.write().await = Some(selected);
        Ok(selected)
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
enum InitializationStatus {
    Uninitialized,
    Connecting,
    Connected,
    Failed,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct InitializationDiagnostic {
    domain: String,
    qr_type: String,
    stage: String,
    error_kind: String,
    timestamp: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct InitializationSnapshot {
    status: InitializationStatus,
    server: String,
    nickname: Option<String>,
    addr: Option<String>,
    security_status: String,
    diagnostic: Option<InitializationDiagnostic>,
}

impl InitializationSnapshot {
    fn uninitialized() -> Self {
        Self {
            status: InitializationStatus::Uninitialized,
            server: CHATMAIL_DOMAIN.to_owned(),
            nickname: None,
            addr: None,
            security_status: "未初始化".to_owned(),
            diagnostic: None,
        }
    }

    fn failed(profile: Option<&PetProfile>, diagnostic: InitializationDiagnostic) -> Self {
        Self {
            status: InitializationStatus::Failed,
            server: CHATMAIL_DOMAIN.to_owned(),
            nickname: profile.map(|value| value.nickname.clone()),
            addr: profile.and_then(|value| (!value.addr.is_empty()).then(|| value.addr.clone())),
            security_status: "不可用".to_owned(),
            diagnostic: Some(diagnostic),
        }
    }
}

#[derive(Debug, Deserialize)]
struct AdoptTetiInput {
    nickname: String,
}

#[derive(Debug, Deserialize)]
struct UpdatePetNicknameInput {
    nickname: String,
}

#[tauri::command]
async fn chatmail_status(
    manager: State<'_, Arc<ChatmailManager>>,
) -> Result<InitializationSnapshot, String> {
    let Some(profile) = manager
        .profile_store
        .load()
        .map_err(|error| error.to_string())?
    else {
        return Ok(InitializationSnapshot::uninitialized());
    };
    *manager.account_id.write().await = Some(profile.dc_account_id);
    let client = match manager.client().await {
        Ok(client) => client,
        Err(_) => {
            let diagnostic = diagnostic("rpc_start", "rpc_unavailable");
            *manager.diagnostic.write().await = Some(diagnostic.clone());
            return Ok(InitializationSnapshot::failed(Some(&profile), diagnostic));
        }
    };
    match account::reconnect(&client, profile.dc_account_id).await {
        Ok(status) => {
            let initialization_status = if status.connected() {
                InitializationStatus::Connected
            } else if status.configured && status.connectivity.unwrap_or_default() >= 2000 {
                InitializationStatus::Connecting
            } else {
                InitializationStatus::Failed
            };
            let diagnostic = if matches!(initialization_status, InitializationStatus::Failed) {
                Some(diagnostic("connectivity", "not_connected"))
            } else {
                None
            };
            *manager.diagnostic.write().await = diagnostic.clone();
            Ok(InitializationSnapshot {
                status: initialization_status,
                server: CHATMAIL_DOMAIN.to_owned(),
                nickname: Some(profile.nickname),
                addr: status
                    .addr
                    .or_else(|| (!profile.addr.is_empty()).then_some(profile.addr)),
                security_status: if status.configured {
                    "Delta Chat Core"
                } else {
                    "未初始化"
                }
                .to_owned(),
                diagnostic,
            })
        }
        Err(error) => {
            let diagnostic = diagnostic("status", error.kind());
            *manager.diagnostic.write().await = Some(diagnostic.clone());
            Ok(InitializationSnapshot::failed(Some(&profile), diagnostic))
        }
    }
}

#[tauri::command]
async fn adopt_teti(
    manager: State<'_, Arc<ChatmailManager>>,
    input: AdoptTetiInput,
) -> Result<InitializationSnapshot, String> {
    let nickname = validate_nickname(&input.nickname).map_err(|error| error.to_string())?;
    let client = manager
        .client()
        .await
        .map_err(|_| "无法启动通信服务".to_owned())?;
    let existing_profile = manager
        .profile_store
        .load()
        .map_err(|error| error.to_string())?;
    let account_result = account::create_or_open_account(
        &client,
        existing_profile
            .as_ref()
            .map(|profile| profile.dc_account_id),
    )
    .await;
    let account_id = match account_result {
        Ok(id) => id,
        Err(error) => {
            return Ok(record_failure(
                &manager,
                existing_profile.as_ref(),
                "account_context",
                &error,
            )
            .await)
        }
    };
    *manager.account_id.write().await = Some(account_id);

    let mut profile =
        existing_profile.unwrap_or_else(|| PetProfile::draft(nickname.clone(), account_id));
    profile.nickname = nickname;
    profile.dc_account_id = account_id;
    profile.chatmail_domain = CHATMAIL_DOMAIN.to_owned();
    if manager.profile_store.save(&profile).is_err() {
        let diagnostic = diagnostic("local_profile", "profile_write_failed");
        *manager.diagnostic.write().await = Some(diagnostic.clone());
        return Ok(InitializationSnapshot::failed(Some(&profile), diagnostic));
    }

    let addr =
        match account::configure_chatmail_identity(&client, account_id, &profile.nickname).await {
            Ok(addr) => addr,
            Err(error) => {
                let stage = if matches!(error, AccountError::AddressUnavailable) {
                    "read_address"
                } else {
                    "configure"
                };
                return Ok(record_failure(&manager, Some(&profile), stage, &error).await);
            }
        };
    if !account::address_matches_mvp_domain(&addr) {
        let diagnostic = diagnostic("read_address", "unexpected_domain");
        *manager.diagnostic.write().await = Some(diagnostic.clone());
        return Ok(InitializationSnapshot::failed(Some(&profile), diagnostic));
    }
    profile.addr = addr.clone();
    manager
        .profile_store
        .save(&profile)
        .map_err(|error| error.to_string())?;
    *manager.diagnostic.write().await = None;
    Ok(InitializationSnapshot {
        status: InitializationStatus::Connected,
        server: CHATMAIL_DOMAIN.to_owned(),
        nickname: Some(profile.nickname),
        addr: Some(addr),
        security_status: "Delta Chat Core".to_owned(),
        diagnostic: None,
    })
}

#[tauri::command]
async fn update_pet_nickname(
    manager: State<'_, Arc<ChatmailManager>>,
    input: UpdatePetNicknameInput,
) -> Result<InitializationSnapshot, String> {
    let nickname = validate_nickname(&input.nickname).map_err(|error| error.to_string())?;
    let mut profile = manager
        .profile_store
        .load()
        .map_err(|error| error.to_string())?
        .ok_or_else(|| "通信身份尚未初始化".to_owned())?;
    let client = manager.client().await?;
    let account_id = manager.account_id(&client).await?;
    account::set_display_name(&client, account_id, &nickname)
        .await
        .map_err(|error| error.to_string())?;
    profile.nickname = nickname;
    profile.dc_account_id = account_id;
    manager
        .profile_store
        .save(&profile)
        .map_err(|error| error.to_string())?;
    Ok(InitializationSnapshot {
        status: InitializationStatus::Connected,
        server: CHATMAIL_DOMAIN.to_owned(),
        nickname: Some(profile.nickname),
        addr: (!profile.addr.is_empty()).then_some(profile.addr),
        security_status: "Delta Chat Core".to_owned(),
        diagnostic: None,
    })
}

#[tauri::command]
async fn reconnect_chatmail(
    manager: State<'_, Arc<ChatmailManager>>,
) -> Result<InitializationSnapshot, String> {
    let profile = manager
        .profile_store
        .load()
        .map_err(|error| error.to_string())?
        .ok_or_else(|| "通信身份尚未初始化".to_owned())?;
    let client = manager.client().await?;
    match account::reconnect(&client, profile.dc_account_id).await {
        Ok(_) => chatmail_status(manager).await,
        Err(error) => Ok(record_failure(&manager, Some(&profile), "reconnect", &error).await),
    }
}

#[tauri::command]
async fn reset_chatmail_identity(
    manager: State<'_, Arc<ChatmailManager>>,
) -> Result<InitializationSnapshot, String> {
    if let Some(profile) = manager
        .profile_store
        .load()
        .map_err(|error| error.to_string())?
    {
        let client = manager.client().await?;
        account::remove_account(&client, profile.dc_account_id)
            .await
            .map_err(|error| error.to_string())?;
    }
    manager
        .profile_store
        .delete()
        .map_err(|error| error.to_string())?;
    *manager.account_id.write().await = None;
    *manager.diagnostic.write().await = None;
    Ok(InitializationSnapshot::uninitialized())
}

#[tauri::command]
async fn parse_invite(text: String) -> ParseInviteResult {
    invite_parser::parse(&text)
}

#[tauri::command]
async fn add_friend(
    manager: State<'_, Arc<ChatmailManager>>,
    text: String,
) -> Result<AddedContact, String> {
    let client = manager.client().await?;
    let account_id = manager.account_id(&client).await?;
    contacts::add_from_text(&client, account_id, &text)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn list_contacts(
    manager: State<'_, Arc<ChatmailManager>>,
) -> Result<Vec<ContactSummary>, String> {
    let client = manager.client().await?;
    let account_id = manager.account_id(&client).await?;
    contacts::list_contacts(&client, account_id)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn chat_readiness(
    manager: State<'_, Arc<ChatmailManager>>,
    chat_id: u32,
) -> Result<ChatReadiness, String> {
    let client = manager.client().await?;
    let account_id = manager.account_id(&client).await?;
    contacts::chat_readiness(&client, account_id, chat_id)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn send_text(
    manager: State<'_, Arc<ChatmailManager>>,
    input: SendTextInput,
) -> Result<u32, String> {
    let client = manager.client().await?;
    let account_id = manager.account_id(&client).await?;
    messages::send_text(&client, account_id, input)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn pick_attachment(
    manager: State<'_, Arc<ChatmailManager>>,
) -> Result<Option<AttachmentGrant>, String> {
    manager
        .attachments
        .pick_file()
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn send_attachment(
    manager: State<'_, Arc<ChatmailManager>>,
    input: SendAttachmentInput,
) -> Result<u32, String> {
    let client = manager.client().await?;
    let account_id = manager.account_id(&client).await?;
    let file = manager
        .attachments
        .consume(&input.attachment_token)
        .await
        .map_err(|error| error.to_string())?;
    messages::send_attachment(&client, account_id, input.chat_id, input.text, &file)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn send_task(
    manager: State<'_, Arc<ChatmailManager>>,
    input: SendTaskInput,
) -> Result<u32, String> {
    let client = manager.client().await?;
    let account_id = manager.account_id(&client).await?;
    messages::send_task(&client, account_id, input)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn poll_incoming(
    manager: State<'_, Arc<ChatmailManager>>,
) -> Result<Vec<IncomingMessage>, String> {
    let client = manager.client().await?;
    let account_id = manager.account_id(&client).await?;
    messages::get_fresh_messages(&client, account_id)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn open_message_attachment(
    manager: State<'_, Arc<ChatmailManager>>,
    message_id: u32,
) -> Result<(), String> {
    let client = manager.client().await?;
    let account_id = manager.account_id(&client).await?;
    messages::open_message_attachment(&client, account_id, message_id)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn set_pet_status(
    bridge: State<'_, Arc<PetStatusBridge>>,
    status: String,
) -> Result<(), String> {
    const ALLOWED: [&str; 10] = [
        "draft",
        "sent",
        "received",
        "accepted",
        "rejected",
        "in_progress",
        "done",
        "failed",
        "communication_error",
        "idle",
    ];
    if !ALLOWED.contains(&status.as_str()) {
        return Err("unsupported pet status".to_owned());
    }
    bridge
        .write_status(&status)
        .map_err(|error| error.to_string())
}

fn diagnostic(stage: &str, error_kind: &str) -> InitializationDiagnostic {
    InitializationDiagnostic {
        domain: CHATMAIL_DOMAIN.to_owned(),
        qr_type: CHATMAIL_QR_TYPE.to_owned(),
        stage: stage.to_owned(),
        error_kind: error_kind.to_owned(),
        timestamp: Utc::now().to_rfc3339(),
    }
}

async fn record_failure(
    manager: &ChatmailManager,
    profile: Option<&PetProfile>,
    stage: &str,
    error: &AccountError,
) -> InitializationSnapshot {
    let diagnostic = diagnostic(stage, error.kind());
    *manager.diagnostic.write().await = Some(diagnostic.clone());
    InitializationSnapshot::failed(profile, diagnostic)
}

fn show_mail_window(app: &tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("mail") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

fn set_selected_hat(menu: &TetiMenuState, selected: &str) {
    if let Ok(mut current) = menu.current_hat.lock() {
        *current = selected.to_owned();
    }
    for (hat_id, item) in &menu.hat_items {
        let _ = item.set_checked(hat_id == selected);
    }
}

fn build_teti_menu(app: &tauri::AppHandle) -> tauri::Result<Menu<Wry>> {
    let open_mail = MenuItem::with_id(app, MENU_OPEN_MAIL, "Open Teti Mail", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, MENU_QUIT, "Quit Teti", true, Some("CmdOrCtrl+Q"))?;

    let hat_items = HAT_MENU_ITEMS
        .iter()
        .map(|(hat_id, label)| {
            CheckMenuItem::with_id(
                app,
                format!("{MENU_HAT_PREFIX}{hat_id}"),
                *label,
                true,
                *hat_id == "none",
                None::<&str>,
            )
            .map(|item| ((*hat_id).to_owned(), item))
        })
        .collect::<tauri::Result<Vec<_>>>()?;

    let hat_refs = hat_items
        .iter()
        .map(|(_, item)| item as &dyn tauri::menu::IsMenuItem<Wry>)
        .collect::<Vec<_>>();

    let hats = Submenu::with_items(app, "Hats", true, &hat_refs)?;
    drop(hat_refs);
    app.manage(Arc::new(TetiMenuState {
        current_hat: StdMutex::new("none".to_owned()),
        hat_items,
    }));

    let teti = Submenu::with_items(
        app,
        "Teti",
        true,
        &[
            &open_mail,
            &PredefinedMenuItem::separator(app)?,
            &hats,
            &PredefinedMenuItem::separator(app)?,
            &quit,
        ],
    )?;

    let edit = Submenu::with_items(
        app,
        "Edit",
        true,
        &[
            &PredefinedMenuItem::undo(app, None)?,
            &PredefinedMenuItem::redo(app, None)?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::cut(app, None)?,
            &PredefinedMenuItem::copy(app, None)?,
            &PredefinedMenuItem::paste(app, None)?,
            &PredefinedMenuItem::select_all(app, None)?,
        ],
    )?;

    let window = Submenu::with_items(
        app,
        "Window",
        true,
        &[
            &PredefinedMenuItem::minimize(app, None)?,
            &PredefinedMenuItem::maximize(app, None)?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::close_window(app, None)?,
        ],
    )?;

    Menu::with_items(app, &[&teti, &edit, &window])
}

fn main() {
    tauri::Builder::default()
        .menu(build_teti_menu)
        .on_menu_event(|app, event| {
            let id = event.id().as_ref();
            if id == MENU_OPEN_MAIL {
                show_mail_window(app);
                return;
            }
            if id == MENU_QUIT {
                app.exit(0);
                return;
            }
            if let Some(hat_id) = id.strip_prefix(MENU_HAT_PREFIX) {
                if HAT_MENU_ITEMS.iter().any(|(known, _)| *known == hat_id) {
                    if let Some(bridge) = app.try_state::<Arc<PetStatusBridge>>() {
                        let _ = bridge.write_hat(hat_id);
                    }
                    if let Some(menu) = app.try_state::<Arc<TetiMenuState>>() {
                        set_selected_hat(&menu, hat_id);
                    }
                }
            }
        })
        .setup(|app| {
            let data_dir = app.path().app_data_dir()?;
            std::fs::create_dir_all(&data_dir)?;
            app.manage(Arc::new(ChatmailManager::new(data_dir)));
            if let Some(mail) = app.get_webview_window("mail") {
                mail.hide()?;
            }
            let bridge_path = app
                .path()
                .data_dir()?
                .join("ai.seep.tetibot.prototype")
                .join("save.json");
            app.manage(Arc::new(PetStatusBridge::new(bridge_path.clone())));
            let desktop_pet = DesktopPetProcess::spawn(app.handle().clone())?;
            pet_process::watch_bridge(app.handle().clone(), bridge_path);
            app.manage(desktop_pet);
            Ok(())
        })
        .on_window_event(|window, event| {
            if window.label() == "mail" {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                    api.prevent_close();
                    let _ = window.hide();
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            chatmail_status,
            adopt_teti,
            update_pet_nickname,
            reconnect_chatmail,
            reset_chatmail_identity,
            parse_invite,
            add_friend,
            list_contacts,
            chat_readiness,
            send_text,
            pick_attachment,
            send_attachment,
            send_task,
            poll_incoming,
            open_message_attachment,
            set_pet_status
        ])
        .build(tauri::generate_context!())
        .expect("error while building Teti")
        .run(|app, event| match event {
            tauri::RunEvent::ExitRequested { .. } | tauri::RunEvent::Exit => {
                if let Some(pet) = app.try_state::<DesktopPetProcess>() {
                    pet.terminate();
                }
            }
            _ => {}
        });
}
