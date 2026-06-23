const tauriInvoke = window.__TAURI__?.core?.invoke;
const invoke = tauriInvoke ?? (async (command) => {
  if (command === "chatmail_status") {
    return { status: "uninitialized", server: "mail.seep.im", nickname: null, addr: null, securityStatus: "未初始化", diagnostic: null };
  }
  throw new Error("请在 Teti macOS 应用中完成此操作");
});

const $ = (id) => document.getElementById(id);
const statusLabels = { uninitialized: "未初始化", connecting: "连接中", connected: "已连接", failed: "失败" };
const securityLabels = { ordinary: "普通联系人", encrypted: "已加密", verified: "已安全验证" };
const contactSecurityCopy = { ordinary: "普通认识", encrypted: "已加密通信", verified: "已安全认识" };
const componentCatalog = new Set([
  "TaskRequestCard",
  "TaskReplyCard",
  "TaskResultCard",
  "TaskAcceptCard",
  "TaskRejectCard",
  "TaskProgressCard",
  "FilePackageCard",
  "LetterCard",
]);
const modeLabels = {
  task_request: "请求任务",
  task_reply: "回复任务",
  task_result: "回复任务",
  file_package: "发包裹",
  letter: "写信",
  unknown: "选择类型",
};
const eventLabels = {
  task_request: "任务请求",
  task_reply: "任务回复",
  task_accepted: "接受回执",
  task_rejected: "拒绝回执",
  task_result: "任务结果",
  file_package: "文件包裹",
  letter: "信件",
};
const petStatusLabels = {
  draft: "准备任务",
  sent: "送信中",
  received: "收到任务",
  accepted: "等待执行",
  rejected: "任务被拒绝",
  in_progress: "执行中",
  done: "带回结果",
  failed: "任务失败",
  communication_error: "通信异常",
  idle: "等待任务",
};
const connectionDotLabels = { uninitialized: "未连接", connecting: "同步中", connected: "已连接", failed: "通信异常" };
const TASK_STORE_KEY = "teti.task.records.v1";
const WORKSPACE_STORE_KEY = "teti.task.workspace.v1";

const state = {
  chatId: null,
  contact: null,
  chatReady: false,
  readinessToken: 0,
  seen: new Set(),
  status: "uninitialized",
  snapshot: null,
  lastNickname: "",
  mode: "task_request",
  modeExplicit: false,
  pendingRecipe: null,
  pendingAttachment: null,
  petStatus: null,
  selectedEntry: null,
  contacts: [],
  taskRecords: loadJson(TASK_STORE_KEY, {}),
  workspaceEntries: loadJson(WORKSPACE_STORE_KEY, {}),
};

function loadJson(key, fallback) {
  try {
    const value = localStorage.getItem(key);
    return value ? JSON.parse(value) : fallback;
  } catch {
    return fallback;
  }
}

function saveJson(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    /* local persistence is best effort */
  }
}

function nowIso() { return new Date().toISOString(); }
function newId(prefix) {
  const id = crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  return `${prefix}-${id}`;
}

function showToast(text) {
  const toast = $("toast");
  toast.textContent = text;
  toast.classList.add("show");
  setTimeout(() => toast.classList.remove("show"), 1800);
}

function publicError(error) { return typeof error === "string" ? error : error?.message || "操作失败，请重试"; }

function nicknameUnits(value) {
  return Array.from(value).reduce((total, char) => total + (/[\u3400-\u9fff]/u.test(char) ? 2 : 1), 0);
}

function validateNickname(value) {
  if (/\r|\n|\p{Cc}/u.test(value)) return "昵称不能包含换行或控制字符";
  const nickname = value.trim();
  if (!nickname) return "请输入 Teti 昵称";
  if (nicknameUnits(nickname) > 10) return "昵称最长为 10 个英文字符或 5 个汉字";
  return "";
}

function showAdoptionState(id) {
  ["adoptionForm", "adoptionProgress", "adoptionSuccess", "adoptionFailure"].forEach((name) => { $(name).hidden = name !== id; });
  $("onboarding").hidden = false;
}

function diagnosticText(diagnostic) {
  if (!diagnostic) return "暂无诊断信息";
  return [`domain: ${diagnostic.domain}`, `qr type: ${diagnostic.qrType}`, `stage: ${diagnostic.stage}`, `error kind: ${diagnostic.errorKind}`, `timestamp: ${diagnostic.timestamp}`].join("\n");
}

function renderStatus(snapshot, { showSuccess = false, autoRefresh = true } = {}) {
  state.snapshot = snapshot; state.status = snapshot.status;
  const label = statusLabels[snapshot.status] || statusLabels.failed;
  renderPetIdentity(snapshot.nickname || state.lastNickname || "Teti");
  renderConnectionDot(snapshot.status);
  $("communicationState").textContent = label;
  $("communicationAddress").textContent = snapshot.addr || "尚未创建";
  $("communicationSecurity").textContent = snapshot.securityStatus || "未初始化";
  $("statusDiagnostic").textContent = diagnosticText(snapshot.diagnostic);
  $("statusDiagnostic").hidden = !snapshot.diagnostic;
  if (snapshot.status === "failed") {
    $("diagnosticInfo").textContent = diagnosticText(snapshot.diagnostic);
    $("diagnosticInfo").hidden = true;
    setPetStatus("communication_error");
  }
  if (snapshot.status === "connected" && showSuccess) {
    $("successNickname").textContent = snapshot.nickname;
    showAdoptionState("adoptionSuccess");
  }
  if (snapshot.status === "connecting" && autoRefresh) setTimeout(refreshStatus, 1500);
}

function renderPetIdentity(name) {
  $("petNameLabel").textContent = name || "Teti";
  $("petNameInput").value = name || "Teti";
}

function renderConnectionDot(status) {
  const dot = $("connectionDot");
  dot.className = `connection-dot ${status || "uninitialized"}`;
  dot.title = connectionDotLabels[status] || connectionDotLabels.uninitialized;
  $("connectionText").textContent = connectionDotLabels[status] || connectionDotLabels.uninitialized;
}

function showPetNameEditor() {
  $("petNameInput").value = state.snapshot?.nickname || $("petNameLabel").textContent || "Teti";
  $("petNameError").textContent = "";
  $("petNameError").hidden = true;
  $("petNameLabel").hidden = true;
  $("petNameInput").hidden = false;
  $("editPetNameButton").hidden = true;
  $("savePetNameButton").hidden = false;
  $("cancelPetNameButton").hidden = false;
  $("petNameInput").focus();
  $("petNameInput").select();
}

function hidePetNameEditor() {
  $("petNameLabel").hidden = false;
  $("petNameInput").hidden = true;
  $("editPetNameButton").hidden = false;
  $("savePetNameButton").hidden = true;
  $("cancelPetNameButton").hidden = true;
  $("petNameError").textContent = "";
  $("petNameError").hidden = true;
}

async function savePetName() {
  const nickname = $("petNameInput").value.trim();
  const validationError = validateNickname(nickname);
  $("petNameError").textContent = validationError;
  $("petNameError").hidden = !validationError;
  $("petNameInput").classList.toggle("invalid", Boolean(validationError));
  if (validationError) return;
  try {
    const snapshot = await invoke("update_pet_nickname", { input: { nickname } });
    renderStatus(snapshot);
    hidePetNameEditor();
    showToast("名字已更新");
  } catch (error) {
    $("petNameError").textContent = publicError(error);
  }
}

async function refreshStatus() {
  try {
    const snapshot = await invoke("chatmail_status");
    renderStatus(snapshot);
    if (snapshot.status === "connected") await refreshContacts();
  } catch {
    renderStatus({ status: "failed", server: "mail.seep.im", nickname: null, addr: null, securityStatus: "不可用", diagnostic: null });
  }
}

async function startAdoption() {
  const raw = $("nicknameInput").value;
  const validationError = validateNickname(raw);
  $("nicknameError").textContent = validationError;
  $("nicknameInput").classList.toggle("invalid", Boolean(validationError));
  if (validationError) return;
  state.lastNickname = raw.trim();
  showAdoptionState("adoptionProgress");
  renderStatus({ status: "connecting", server: "mail.seep.im", nickname: state.lastNickname, addr: null, securityStatus: "初始化中", diagnostic: null }, { autoRefresh: false });
  try {
    const snapshot = await invoke("adopt_teti", { input: { nickname: state.lastNickname } });
    renderStatus(snapshot, { showSuccess: snapshot.status === "connected" });
    if (snapshot.status === "connected") await refreshContacts();
    if (snapshot.status === "failed") showAdoptionState("adoptionFailure");
  } catch (error) {
    $("nicknameError").textContent = publicError(error);
    showAdoptionState("adoptionForm");
  }
}

async function refreshContacts() {
  if (state.status !== "connected") return;
  state.contacts = await invoke("list_contacts");
  const root = $("contacts");
  root.replaceChildren(...state.contacts.filter((contact) => contact.chatId).map((contact) => {
    const button = document.createElement("button");
    button.className = `contact${state.chatId === contact.chatId ? " active" : ""}`;
    const strong = document.createElement("strong");
    const small = document.createElement("small");
    const tag = document.createElement("span");
    const status = contactTaskStatus(contact.chatId);
    strong.textContent = contact.displayName || contact.address;
    small.textContent = `${status.summary} · ${capabilityLabel(contact, status)}`;
    tag.className = `contact-status ${status.kind}`;
    tag.textContent = status.label;
    button.append(strong, small, tag);
    button.addEventListener("click", () => selectContact(contact));
    return button;
  }));
}

function selectContact(contact) {
  state.chatId = contact.chatId; state.contact = contact; state.pendingRecipe = null;
  state.selectedEntry = null;
  $("chatName").textContent = contact.displayName || contact.address;
  renderContactSubtitle(contact);
  renderWorkspace();
  refreshContacts().catch(() => {});
  const token = ++state.readinessToken;
  setComposerReady(false);
  refreshChatReadiness(contact.chatId, token);
}

function capabilityLabel(contact, status = null) {
  if (status?.kind === "letter") return "仅聊天";
  const entries = entriesForChat(contact.chatId);
  if (entries.some((entry) => entry.kind === "file_package")) return "可收附件";
  if (contact.security === "verified" || contact.security === "encrypted") return "可互发任务";
  return "标准 Delta Chat";
}

function renderContactSubtitle(contact = state.contact) {
  if (!contact) {
    $("contactSubtitle").textContent = "选择联系人后开始协作";
    return;
  }
  const secure = contactSecurityCopy[contact.security] || "普通认识";
  $("contactSubtitle").textContent = `${secure} · ${capabilityLabel(contact)}`;
}

function setComposerReady(ready) {
  state.chatReady = ready;
  $("messageInput").disabled = !ready;
  ["sendButton", "attachButton"].forEach((id) => { $(id).disabled = !ready; });
  updateComposerContext();
}

async function refreshChatReadiness(chatId, token) {
  try {
    const readiness = await invoke("chat_readiness", { chatId });
    if (state.chatId !== chatId || state.readinessToken !== token) return;
    if (readiness.contact) {
      state.contact = readiness.contact;
      $("chatName").textContent = readiness.contact.displayName || readiness.contact.address;
      if (readiness.canSend) renderContactSubtitle(readiness.contact);
      else $("contactSubtitle").textContent = "正在建立安全连接";
    }
    setComposerReady(readiness.canSend);
    if (readiness.canSend) {
      await refreshContacts();
    } else {
      setTimeout(() => refreshChatReadiness(chatId, token), 1200);
    }
  } catch {
    if (state.chatId === chatId && state.readinessToken === token) {
      $("contactSubtitle").textContent = "安全连接异常";
      setComposerReady(false);
      setPetStatus("communication_error");
      setTimeout(() => refreshChatReadiness(chatId, token), 2500);
    }
  }
}

function setMode(mode, explicit = true) {
  state.mode = mode;
  state.modeExplicit = explicit;
  document.querySelectorAll(".mode-button").forEach((button) => {
    button.classList.toggle("active", button.dataset.mode === mode);
  });
  updateComposerContext();
  if (mode === "file_package") $("attachButton").focus();
}

function detectIntent(text) {
  const normalized = text.trim();
  if (!normalized) return "unknown";
  if (/发文件|发截图|发送文件|包裹/.test(normalized)) return "file_package";
  if (/结果|已完成|发回|返回截图/.test(normalized)) return "task_result";
  if (/回复|告诉他|说明|拒绝|同意/.test(normalized)) return "task_reply";
  if (/帮我|请对方|让\s*[\w-]+|请求|打开网页|截图|访问/.test(normalized)) return "task_request";
  return "unknown";
}

function extractUrl(text) {
  return text.match(/https?:\/\/[^\s，。！？、)）\]]+/i)?.[0] || "";
}

function titleFromText(text, fallback) {
  const clean = text.replace(/\s+/g, " ").trim();
  if (!clean) return fallback;
  const chars = Array.from(clean);
  return chars.length > 18 ? `${chars.slice(0, 18).join("")}…` : clean;
}

function latestTaskForChat(chatId) {
  return Object.values(state.taskRecords)
    .filter((task) => task.chat_id === chatId)
    .sort((a, b) => String(b.updated_at).localeCompare(String(a.updated_at)))[0] || null;
}

function createRecipe(text, forcedIntent = null) {
  if (!state.contact || !state.chatId) throw new Error("请先选择联系人");
  const detected = detectIntent(text);
  const intent = forcedIntent || (state.modeExplicit ? state.mode : (detected !== "unknown" ? detected : "unknown"));
  if (intent === "unknown") {
    return unknownRecipe(text);
  }
  const target = { contact_id: String(state.contact.contactId), display_name: state.contact.displayName || state.contact.address };
  const selectedTaskId = state.selectedEntry?.recipe?.task_id;
  const taskId = intent === "task_request" ? newId("task") : (selectedTaskId || latestTaskForChat(state.chatId)?.task_id || newId("task"));
  const url = extractUrl(text);
  const permissions = [
    { key: "network_access", label: "网络访问", value: Boolean(url || /打开网页|访问/.test(text)) },
    { key: "file_read", label: "读取本地文件", value: false },
    { key: "shell_exec", label: "远程 Shell", value: false },
    { key: "requires_user_approval", label: "需要确认", value: true },
  ];
  const base = {
    type: "teti.task.recipe",
    version: "0.1",
    intent,
    task_id: taskId,
    target,
    ui: { component: "UnsupportedCard", title: titleFromText(text, "Teti 任务"), description: text.trim(), fields: [], permissions, actions: [] },
    delta_chat: { compat_text: text.trim(), attachments: [] },
  };

  if (intent === "task_request") {
    const title = url ? "打开网页并截图" : titleFromText(text, "任务请求");
    const description = url ? `请帮忙打开 ${url} 并返回截图。` : text.trim();
    return {
      ...base,
      ui: {
        component: "TaskRequestCard",
        title,
        description,
        fields: [
          { label: "目标联系人", value: target.display_name },
          { label: "任务类型", value: url ? "网页截图" : "协作请求" },
          ...(url ? [{ label: "URL", value: url }] : []),
          { label: "任务说明", value: description },
        ],
        permissions,
        actions: ["confirm", "edit", "cancel"],
      },
      delta_chat: {
        compat_text: [
          "Teti 任务请求：",
          "",
          description,
          "",
          "如果你使用标准 Delta Chat，可以直接回复“同意”或“拒绝”。",
          "如果你使用 Teti，可以打开附件中的任务卡。",
        ].join("\n"),
        attachments: ["teti-task.json"],
      },
    };
  }

  if (intent === "task_reply") {
    const description = text.trim();
    return {
      ...base,
      ui: {
        component: "TaskReplyCard",
        title: /同意/.test(text) ? "同意任务" : /拒绝/.test(text) ? "拒绝任务" : "任务回复",
        description,
        fields: [
          { label: "相关任务", value: taskId },
          { label: "回复说明", value: description },
        ],
        permissions,
        actions: ["confirm", "edit", "cancel"],
      },
      delta_chat: {
        compat_text: ["Teti 任务回复：", "", description, "", `相关任务：${taskId}`].join("\n"),
        attachments: ["teti-task-event.json"],
      },
    };
  }

  if (intent === "task_result") {
    const description = text.trim();
    return {
      ...base,
      ui: {
        component: "TaskResultCard",
        title: "任务结果",
        description,
        fields: [
          { label: "task_id", value: taskId },
          { label: "状态", value: /失败/.test(text) ? "failed" : "done" },
          { label: "说明", value: description },
          { label: "附件列表", value: state.pendingAttachment?.name || "无" },
        ],
        permissions,
        actions: ["confirm", "edit", "cancel"],
      },
      delta_chat: {
        compat_text: ["Teti 任务结果：", "", description, "", `相关任务：${taskId}`].join("\n"),
        attachments: ["teti-task-event.json"],
      },
    };
  }

  if (intent === "file_package") {
    const description = text.trim() || "给你发送一个文件包裹。";
    return {
      ...base,
      ui: {
        component: "FilePackageCard",
        title: "文件包裹",
        description,
        fields: [
          { label: "目标联系人", value: target.display_name },
          { label: "文件", value: state.pendingAttachment?.name || "尚未选择" },
          { label: "说明", value: description },
        ],
        permissions,
        actions: ["confirm", "edit", "cancel"],
      },
      delta_chat: { compat_text: description, attachments: state.pendingAttachment ? [state.pendingAttachment.name] : [] },
    };
  }

  if (intent === "letter") {
    const description = text.trim();
    return {
      ...base,
      ui: {
        component: "LetterCard",
        title: "一封信",
        description,
        fields: [{ label: "正文", value: description }],
        permissions,
        actions: ["confirm", "edit", "cancel"],
      },
      delta_chat: { compat_text: description, attachments: [] },
    };
  }

  return unknownRecipe(text);
}

function unknownRecipe(text) {
  return {
    type: "teti.task.recipe",
    version: "0.1",
    intent: "unknown",
    task_id: newId("draft"),
    target: { contact_id: state.contact ? String(state.contact.contactId) : "", display_name: state.contact?.displayName || "" },
    ui: {
      component: "UnsupportedCard",
      title: "需要选择任务类型",
      description: text.trim(),
      fields: [{ label: "原始输入", value: text.trim() || "空" }],
      permissions: [],
      actions: ["choose"],
    },
    delta_chat: { compat_text: text.trim(), attachments: [] },
  };
}

function renderWorkspace({ scrollToPreview = false, preserveScroll = true } = {}) {
  const root = $("workspace");
  const previousScroll = root.scrollTop;
  root.replaceChildren();
  if (!state.chatId) {
    root.append(emptyWorkspace("选择联系人", "选择一位 Teti 好友后，就可以发起任务、交付结果、发送包裹或写信。"));
    return;
  }
  const entries = orderedEntriesForChat(state.chatId);
  if (entries.length === 0 && !state.pendingRecipe) {
    root.append(connectedEmpty());
    return;
  }
  if (state.pendingRecipe) root.append(renderRecipeCard(state.pendingRecipe, { preview: true }));
  entries.forEach((entry) => root.append(renderEntry(entry)));
  if (scrollToPreview) {
    root.scrollTop = 0;
  } else if (preserveScroll) {
    root.scrollTop = previousScroll;
  }
}

function emptyWorkspace(title, description) {
  const empty = document.createElement("div");
  empty.className = "workspace-empty";
  const h2 = document.createElement("h2");
  h2.textContent = title;
  const p = document.createElement("p");
  p.textContent = description;
  empty.append(h2, p);
  return empty;
}

function connectedEmpty() {
  const empty = emptyWorkspace("你们已经安全连接", "Teti 可以帮你向对方发起任务请求、发送文件包裹，也可以写一封普通信。");
  const actions = document.createElement("div");
  actions.className = "empty-actions";
  [
    ["请求对方帮忙", "task_request"],
    ["回复一个任务", "task_reply"],
    ["发送文件包裹", "file_package"],
    ["写一封信", "letter"],
  ].forEach(([label, mode]) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = mode === "task_request" ? "primary-button" : "secondary-button";
    button.textContent = label;
    button.addEventListener("click", () => { setMode(mode); $("messageInput").focus(); });
    actions.append(button);
  });
  empty.append(actions);
  return empty;
}

function entriesForChat(chatId) {
  return state.workspaceEntries[String(chatId)] || [];
}

function orderedEntriesForChat(chatId) {
  return [...entriesForChat(chatId)].sort((a, b) => {
    const priority = entryPriority(a) - entryPriority(b);
    if (priority !== 0) return priority;
    return timestampOf(b).localeCompare(timestampOf(a));
  });
}

function timestampOf(entry) {
  return entry.updatedAt || entry.createdAt || "";
}

function entryPriority(entry) {
  if (entry.kind === "task") {
    const intent = entry.recipe?.intent;
    if (entry.direction === "in" && intent === "task_request" && !entry.handled) return 1;
    if (entry.direction === "in" && ["task_reply", "task_accepted", "task_rejected"].includes(intent) && !entry.handled) return 2;
    if (intent === "task_result" && !entry.handled) return 3;
    if (entry.direction === "out" && intent === "task_request") return 5;
    return 6;
  }
  if (entry.kind === "file_package") return entry.read ? 7 : 3;
  if (entry.kind === "letter") return entry.read ? 7 : 4;
  return 7;
}

function addEntry(entry) {
  const chatKey = String(entry.chatId);
  const entries = entriesForChat(chatKey);
  const nextEntry = { createdAt: nowIso(), updatedAt: nowIso(), read: entry.direction === "out", ...entry };
  const next = [...entries.filter((existing) => existing.id !== nextEntry.id), nextEntry].slice(-80);
  state.workspaceEntries[chatKey] = next;
  saveJson(WORKSPACE_STORE_KEY, state.workspaceEntries);
  recordTaskEvent(entry);
  if (state.chatId === entry.chatId) renderWorkspace();
  refreshContacts().catch(() => {});
}

function renderEntry(entry) {
  if (entry.kind === "task") return renderRecipeCard(entry.recipe, { entry });
  if (entry.kind === "file_package") return renderFilePackageCard(entry);
  return renderLetterCard(entry);
}

function renderRecipeCard(recipe, { preview = false, entry = null } = {}) {
  const component = componentCatalog.has(recipe.ui.component) ? recipe.ui.component : "UnsupportedCard";
  const card = document.createElement("article");
  card.className = `workspace-card ${component} ${preview ? "preview" : ""} ${entry?.direction || ""}${entry && state.selectedEntry?.id === entry.id ? " selected" : ""}`;
  if (entry) {
    card.tabIndex = 0;
    card.addEventListener("click", (event) => {
      if (event.target.closest("button")) return;
      enterContext(entry);
    });
    card.addEventListener("keydown", (event) => {
      if (event.key === "Enter") enterContext(entry);
    });
  }
  const meta = document.createElement("div");
  meta.className = "card-meta";
  meta.textContent = preview ? "发送前预览" : `${entry?.direction === "out" ? "你发出的" : entry?.sender || "Teti"} · ${modeLabels[recipe.intent] || eventLabels[recipe.intent] || "任务"}`;
  const h3 = document.createElement("h3");
  h3.textContent = recipe.ui.title;
  const p = document.createElement("p");
  p.textContent = recipe.ui.description || recipe.delta_chat.compat_text;
  card.append(meta, h3, p);
  if (component !== "LetterCard" && recipe.ui.fields?.length) card.append(renderFields(recipe.ui.fields));
  if (recipe.ui.permissions?.length) card.append(renderPermissions(recipe.ui.permissions));
  card.append(renderCardActions(recipe, { preview, entry }));
  return card;
}

function renderFields(fields) {
  const list = document.createElement("dl");
  list.className = "card-fields";
  fields.forEach((field) => {
    const wrap = document.createElement("div");
    const dt = document.createElement("dt");
    const dd = document.createElement("dd");
    dt.textContent = field.label;
    dd.textContent = field.value || "无";
    wrap.append(dt, dd);
    list.append(wrap);
  });
  return list;
}

function renderPermissions(permissions) {
  const list = document.createElement("div");
  list.className = "permission-row";
  permissions.forEach((permission) => {
    const chip = document.createElement("span");
    chip.className = `permission ${permission.value ? "on" : "off"}`;
    chip.textContent = `${permission.label}：${permission.value ? "是" : "否"}`;
    list.append(chip);
  });
  return list;
}

function renderCardActions(recipe, { preview, entry }) {
  const actions = document.createElement("div");
  actions.className = "card-actions";
  if (recipe.intent === "unknown") {
    ["task_request", "task_reply", "file_package", "letter"].forEach((mode) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "secondary-button";
      button.textContent = modeLabels[mode];
      button.addEventListener("click", () => {
        setMode(mode);
        state.pendingRecipe = createRecipe($("messageInput").value, mode);
        renderWorkspace();
      });
      actions.append(button);
    });
    return actions;
  }
  if (preview) {
    const confirm = actionButton("确认发送", "primary-button", () => confirmRecipe(recipe));
    const edit = actionButton("修改", "secondary-button", () => $("messageInput").focus());
    const cancel = actionButton("取消", "secondary-button", () => { state.pendingRecipe = null; renderWorkspace(); setPetStatus("idle"); });
    actions.append(confirm, edit, cancel);
    return actions;
  }
  if (!entry) return actions;

  if (recipe.ui.component === "LetterCard") {
    actions.append(
      actionButton("回复", "primary-button", () => enterContext(entry)),
      actionButton("转为任务", "secondary-button", () => convertEntryToTask(entry)),
      actionButton("发包裹", "secondary-button", () => startPackageForEntry(entry)),
    );
    return actions;
  }

  if (recipe.ui.component === "TaskRequestCard") {
    if (entry.direction === "in") {
      actions.append(
        actionButton("接受", "primary-button", () => sendTaskResponse(entry, "task_accepted")),
        actionButton("拒绝", "secondary-button", () => sendTaskResponse(entry, "task_rejected")),
        actionButton("回复说明", "secondary-button", () => enterContext(entry)),
      );
    } else {
      actions.append(
        actionButton("补充说明", "primary-button", () => enterContext(entry)),
        actionButton("取消任务", "secondary-button", () => sendTaskResponse(entry, "task_reply", "我想取消这个任务。")),
        actionButton("催一下", "secondary-button", () => sendTaskResponse(entry, "task_reply", "辛苦看一下这个任务的进展。")),
      );
    }
    return actions;
  }

  if (["TaskReplyCard", "TaskAcceptCard", "TaskRejectCard"].includes(recipe.ui.component)) {
    actions.append(
      actionButton("继续回复", "primary-button", () => enterContext(entry)),
      actionButton("转为任务", "secondary-button", () => convertEntryToTask(entry)),
      actionButton("标记已处理", "secondary-button", () => markEntryHandled(entry)),
    );
    return actions;
  }

  if (recipe.intent === "task_result") {
    actions.append(
      actionButton("打开结果", "secondary-button", () => showToast("结果附件会显示在包裹卡片中")),
      actionButton("保存", "secondary-button", () => showToast("第一版先保留在任务记录里")),
      actionButton("继续请求", "secondary-button", () => { setMode("task_request"); $("messageInput").focus(); }),
    );
  }
  return actions;
}

function actionButton(label, className, onClick) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = className;
  button.textContent = label;
  button.addEventListener("click", onClick);
  return button;
}

function updateEntry(entryId, patch) {
  const chatKey = String(state.chatId);
  state.workspaceEntries[chatKey] = entriesForChat(chatKey).map((entry) => (
    entry.id === entryId ? { ...entry, ...patch, updatedAt: nowIso() } : entry
  ));
  if (state.selectedEntry?.id === entryId) {
    state.selectedEntry = state.workspaceEntries[chatKey].find((entry) => entry.id === entryId) || null;
  }
  saveJson(WORKSPACE_STORE_KEY, state.workspaceEntries);
  renderWorkspace();
  refreshContacts().catch(() => {});
}

function markEntryHandled(entry) {
  updateEntry(entry.id, { handled: true, read: true });
  showToast("已标记处理");
}

function enterContext(entry) {
  state.selectedEntry = entry;
  if (entry.kind === "letter" && !entry.read) updateEntry(entry.id, { read: true });
  const mode = contextModeFor(entry);
  setMode(mode, true);
  $("contextHint").hidden = false;
  $("contextHint").textContent = contextLabelFor(entry);
  updateComposerContext();
  renderWorkspace();
  $("messageInput").focus();
}

function contextModeFor(entry) {
  if (entry.kind === "file_package") return "letter";
  if (entry.kind === "letter") return "letter";
  return "task_reply";
}

function contextLabelFor(entry) {
  if (entry.kind === "letter") return `正在回复 ${entry.sender || "对方"} 的信`;
  if (entry.kind === "file_package") return `正在回复文件包裹 ${entry.fileName || ""}`.trim();
  if (entry.recipe?.ui?.component === "TaskRequestCard" && entry.direction === "out") return "正在为你发出的任务补充说明";
  if (entry.recipe?.ui?.component === "TaskRequestCard") return "正在回复这个任务请求";
  return "正在继续回复这个任务";
}

function contextPlaceholderFor(entry) {
  if (!entry) return "告诉 Teti 你想请求、回复或交付什么……";
  if (entry.kind === "letter") return "回复这封信，或把它转成任务……";
  if (entry.kind === "file_package") return "回复这个文件包裹……";
  if (entry.recipe?.ui?.component === "TaskRequestCard" && entry.direction === "out") return "为这个任务补充说明……";
  if (entry.recipe?.ui?.component === "TaskRequestCard") return "回复这个任务请求……";
  return "继续回复这个任务……";
}

function updateComposerContext() {
  if (!state.chatReady) {
    $("messageInput").placeholder = "正在建立安全连接…";
    return;
  }
  $("messageInput").placeholder = contextPlaceholderFor(state.selectedEntry);
  $("contextHint").hidden = !state.selectedEntry;
  if (state.selectedEntry) $("contextHint").textContent = contextLabelFor(state.selectedEntry);
}

function convertEntryToTask(entry) {
  state.selectedEntry = entry;
  setMode("task_request", true);
  if (!$("messageInput").value.trim()) {
    $("messageInput").value = entry.text || entry.recipe?.ui?.description || "";
  }
  $("contextHint").hidden = false;
  $("contextHint").textContent = "将当前内容转为任务请求";
  updateComposerContext();
  $("messageInput").focus();
}

function startPackageForEntry(entry) {
  state.selectedEntry = entry;
  setMode("file_package", true);
  $("contextHint").hidden = false;
  $("contextHint").textContent = "选择文件后作为包裹发送";
  updateComposerContext();
  $("attachButton").focus();
}

function renderLetterCard(entry) {
  const recipe = {
    intent: "letter",
    ui: {
      component: "LetterCard",
      title: `一封来自 ${entry.direction === "out" ? "你" : entry.sender || "对方"} 的信`,
      description: entry.text,
      fields: [],
      permissions: [],
    },
    delta_chat: { compat_text: entry.text, attachments: [] },
  };
  return renderRecipeCard(recipe, { entry });
}

function renderFilePackageCard(entry) {
  const card = document.createElement("article");
  card.className = `workspace-card FilePackageCard ${entry.direction || ""}${state.selectedEntry?.id === entry.id ? " selected" : ""}`;
  card.tabIndex = 0;
  card.addEventListener("click", (event) => {
    if (event.target.closest("button")) return;
    enterContext(entry);
  });
  const meta = document.createElement("div");
  meta.className = "card-meta";
  meta.textContent = `${entry.direction === "out" ? "你发出的" : entry.sender || "Teti"} · 文件包裹`;
  const title = document.createElement("h3");
  title.textContent = "收到一个文件包裹";
  const p = document.createElement("p");
  p.textContent = entry.text || "包裹已经放到工作区。";
  card.append(meta, title, p, renderFields([
    { label: "文件", value: entry.fileName || "未命名" },
    { label: "大小", value: entry.size ? `${Math.ceil(entry.size / 1024)} KB` : "未知" },
  ]));
  const actions = document.createElement("div");
  actions.className = "card-actions";
  if (entry.messageId) {
    actions.append(actionButton("打开", "primary-button", () => invoke("open_message_attachment", { messageId: entry.messageId }).catch((error) => showToast(publicError(error)))));
  }
  actions.append(
    actionButton("保存", "secondary-button", () => showToast("第一版先使用系统打开/保存文件")),
    actionButton("回复", "secondary-button", () => enterContext(entry)),
  );
  card.append(actions);
  return card;
}

async function confirmRecipe(recipe) {
  if (!state.chatId) return showToast("请先选择联系人");
  if (recipe.intent === "file_package" && !state.pendingAttachment) return showToast("请先选择一个文件包裹");
  setPetStatus("sent");
  try {
    if (recipe.intent === "letter") {
      await invoke("send_text", { input: { chatId: state.chatId, text: recipe.delta_chat.compat_text } });
      addEntry({ id: newId("letter"), chatId: state.chatId, direction: "out", sender: "Teti", kind: "letter", text: recipe.delta_chat.compat_text, createdAt: nowIso() });
    } else if (recipe.intent === "file_package") {
      const attachment = state.pendingAttachment;
      await invoke("send_attachment", { input: { chatId: state.chatId, text: recipe.delta_chat.compat_text, attachmentToken: attachment.token } });
      addEntry({ id: newId("package"), chatId: state.chatId, direction: "out", sender: "Teti", kind: "file_package", text: recipe.delta_chat.compat_text, fileName: attachment.name, size: attachment.size, createdAt: nowIso() });
      state.pendingAttachment = null;
    } else {
      await invoke("send_task", { input: sendTaskInput(recipe) });
      addEntry({ id: newId("task-entry"), chatId: state.chatId, direction: "out", sender: "Teti", kind: "task", recipe, createdAt: nowIso() });
    }
    state.pendingRecipe = null;
    state.selectedEntry = null;
    $("messageInput").value = "";
    updateComposerContext();
    setPetStatus(recipe.intent === "task_result" ? "done" : "sent");
    renderWorkspace();
  } catch (error) {
    setPetStatus("communication_error");
    showToast(publicError(error));
  }
}

function sendTaskInput(recipe) {
  const permissions = Object.fromEntries((recipe.ui.permissions || []).map((permission) => [permission.key, permission.value]));
  const url = recipe.ui.fields?.find((field) => field.label === "URL")?.value || extractUrl(recipe.ui.description || "");
  const eventType = {
    task_request: "task_request",
    task_reply: "task_reply",
    task_result: "task_result",
  }[recipe.intent] || recipe.intent;
  const action = {
    task_reply: "task.reply",
    task_result: "task.result",
  }[recipe.intent] || "browser.screenshot";
  return {
    chatId: state.chatId,
    taskId: recipe.task_id,
    eventType,
    title: recipe.ui.title,
    action,
    payload: { url, text: recipe.ui.description },
    compatText: recipe.delta_chat.compat_text,
    status: recipe.intent === "task_result" ? (/失败/.test(recipe.ui.description) ? "failed" : "done") : null,
    description: recipe.ui.description,
    permissions: {
      network_access: Boolean(permissions.network_access),
      file_read: false,
      shell_exec: false,
      requires_user_approval: true,
    },
  };
}

async function sendTaskResponse(entry, eventType, noteOverride = null) {
  const source = entry.recipe;
  const noteMap = {
    task_accepted: "同意，我会处理这个任务。",
    task_rejected: "抱歉，我先拒绝这个任务。",
    task_reply: "收到，我补充一下任务说明。",
  };
  const note = noteOverride || (eventType === "task_reply" ? (window.prompt("回复说明", noteMap[eventType]) || "").trim() : noteMap[eventType]);
  if (!note) return;
  const component = eventType === "task_accepted" ? "TaskAcceptCard" : eventType === "task_rejected" ? "TaskRejectCard" : "TaskReplyCard";
  const recipe = {
    type: "teti.task.recipe",
    version: "0.1",
    intent: eventType,
    task_id: source.task_id,
    target: source.target,
    ui: {
      component,
      title: eventLabels[eventType],
      description: note,
      fields: [
        { label: "相关任务", value: source.task_id },
        { label: "说明", value: note },
      ],
      permissions: [
        { key: "network_access", label: "网络访问", value: false },
        { key: "file_read", label: "读取本地文件", value: false },
        { key: "shell_exec", label: "远程 Shell", value: false },
        { key: "requires_user_approval", label: "需要确认", value: true },
      ],
      actions: [],
    },
    delta_chat: {
      compat_text: [`Teti ${eventLabels[eventType]}：`, "", note, "", `相关任务：${source.task_id}`].join("\n"),
      attachments: ["teti-task-event.json"],
    },
  };
  setPetStatus(eventType === "task_accepted" ? "accepted" : eventType === "task_rejected" ? "rejected" : "sent");
  try {
    await invoke("send_task", { input: { ...sendTaskInput(recipe), eventType, action: actionForEvent(eventType) } });
    addEntry({ id: newId("task-entry"), chatId: state.chatId, direction: "out", sender: "Teti", kind: "task", recipe, createdAt: nowIso() });
    if (entry.direction === "in") updateEntry(entry.id, { handled: true, read: true });
  } catch (error) {
    setPetStatus("communication_error");
    showToast(publicError(error));
  }
}

function actionForEvent(eventType) {
  if (eventType === "task_accepted") return "task.accepted";
  if (eventType === "task_rejected") return "task.rejected";
  if (eventType === "task_result") return "task.result";
  return "task.reply";
}

function appendIncoming(message) {
  if (state.seen.has(message.message_id)) return;
  state.seen.add(message.message_id);
  if (!state.chatId) {
    const contact = state.contacts.find((item) => item.chatId === message.chat_id);
    if (contact) selectContact(contact);
  }
  if (message.kind === "text") {
    addEntry({ id: `msg-${message.message_id}`, messageId: message.message_id, chatId: message.chat_id, direction: "in", sender: message.sender, kind: "letter", text: message.text, createdAt: nowIso() });
    setPetStatus("received");
  }
  if (message.kind === "attachment") {
    addEntry({ id: `msg-${message.message_id}`, messageId: message.message_id, chatId: message.chat_id, direction: "in", sender: message.sender, kind: "file_package", text: message.text, fileName: message.file_name, size: message.size, createdAt: nowIso() });
    setPetStatus("received");
  }
  if (message.kind === "task") {
    const recipe = recipeFromProtocol(message.task, message);
    addEntry({ id: `msg-${message.message_id}`, messageId: message.message_id, chatId: message.chat_id, direction: "in", sender: message.sender, kind: "task", recipe, createdAt: nowIso() });
    setPetStatus(statusFromEvent(message.task.event_type, "in"));
  }
}

function recipeFromProtocol(task, message) {
  const payload = task.task?.payload || {};
  const title = task.task?.title || eventLabels[task.event_type] || "Teti 任务";
  const url = payload.url || extractUrl(task.compat_text || message.text || "");
  const permissions = permissionsFromProtocol(task.permissions || {});
  const component = componentFromEvent(task.event_type);
  return {
    type: "teti.task.recipe",
    version: task.version || "0.1",
    intent: task.event_type,
    task_id: task.task_id,
    target: { contact_id: "", display_name: message.sender },
    ui: {
      component,
      title,
      description: task.description || task.compat_text || message.text,
      fields: [
        { label: "task_id", value: task.task_id },
        { label: "事件", value: eventLabels[task.event_type] || task.event_type },
        ...(url ? [{ label: "URL", value: url }] : []),
        ...(task.status ? [{ label: "状态", value: task.status }] : []),
      ],
      permissions,
      actions: [],
    },
    delta_chat: { compat_text: task.compat_text || message.text, attachments: [task.event_type === "task_request" ? "teti-task.json" : "teti-task-event.json"] },
  };
}

function componentFromEvent(eventType) {
  if (eventType === "task_request") return "TaskRequestCard";
  if (eventType === "task_accepted") return "TaskAcceptCard";
  if (eventType === "task_rejected") return "TaskRejectCard";
  if (eventType === "task_result") return "TaskResultCard";
  return "TaskReplyCard";
}

function permissionsFromProtocol(permissions) {
  return [
    { key: "network_access", label: "网络访问", value: Boolean(permissions.network_access) },
    { key: "file_read", label: "读取本地文件", value: Boolean(permissions.file_read) },
    { key: "shell_exec", label: "远程 Shell", value: Boolean(permissions.shell_exec) },
    { key: "requires_user_approval", label: "需要确认", value: permissions.requires_user_approval !== false },
  ];
}

function recordTaskEvent(entry) {
  if (entry.kind === "letter") {
    markChatOnly(entry.chatId);
    return;
  }
  if (entry.kind !== "task") return;
  const recipe = entry.recipe;
  const taskId = recipe.task_id;
  const previous = state.taskRecords[taskId] || {
    task_id: taskId,
    chat_id: entry.chatId,
    contact_id: state.contact?.contactId || "",
    status: "draft",
    events: [],
    attachments: [],
    created_at: entry.createdAt || nowIso(),
  };
  previous.status = statusFromEvent(recipe.intent, entry.direction);
  previous.updated_at = nowIso();
  previous.events.push({
    event_type: recipe.intent,
    direction: entry.direction,
    title: recipe.ui.title,
    text: recipe.delta_chat.compat_text,
    created_at: previous.updated_at,
  });
  state.taskRecords[taskId] = previous;
  saveJson(TASK_STORE_KEY, state.taskRecords);
}

function markChatOnly(chatId) {
  const key = `chat-${chatId}`;
  if (Object.values(state.taskRecords).some((task) => task.chat_id === chatId)) return;
  state.taskRecords[key] = {
    task_id: key,
    chat_id: chatId,
    contact_id: state.contact?.contactId || "",
    status: "letter",
    events: [],
    attachments: [],
    created_at: nowIso(),
    updated_at: nowIso(),
  };
  saveJson(TASK_STORE_KEY, state.taskRecords);
}

function statusFromEvent(eventType, direction) {
  if (eventType === "task_request") return direction === "in" ? "received" : "sent";
  if (eventType === "task_accepted") return "accepted";
  if (eventType === "task_rejected") return "rejected";
  if (eventType === "task_result") return "done";
  if (eventType === "task_reply") return direction === "in" ? "received" : "sent";
  return "sent";
}

function contactTaskStatus(chatId) {
  if (state.status === "failed") return { kind: "error", label: "异常", summary: "通信异常" };
  const entries = entriesForChat(chatId);
  const needYou = entries.filter((entry) => entry.kind === "task" && entry.direction === "in" && entry.recipe?.intent === "task_request" && !entry.handled).length;
  if (needYou > 0) return { kind: "need-you", label: "待你确认", summary: `待你处理 ${needYou}` };
  const replies = entries.filter((entry) => entry.kind === "task" && entry.direction === "in" && ["task_reply", "task_accepted", "task_rejected"].includes(entry.recipe?.intent) && !entry.handled).length;
  if (replies > 0) return { kind: "reply", label: "新回复", summary: `有新回复 ${replies}` };
  const results = entries.filter((entry) => entry.kind === "task" && entry.recipe?.intent === "task_result" && !entry.handled).length;
  if (results > 0) return { kind: "done", label: "有结果", summary: `有结果 ${results}` };
  const tasks = Object.values(state.taskRecords)
    .filter((task) => task.chat_id === chatId)
    .sort((a, b) => String(b.updated_at).localeCompare(String(a.updated_at)));
  const latest = tasks[0];
  if (latest?.status === "sent") return { kind: "waiting", label: "等待对方", summary: "等待对方" };
  if (latest?.status === "accepted") return { kind: "progress", label: "处理中", summary: "对方处理中" };
  if (latest?.status === "letter") return { kind: "letter", label: "仅聊天", summary: "仅聊天" };
  if (entries.length > 0 && entries.every((entry) => entry.kind === "letter")) return { kind: "letter", label: "仅聊天", summary: "仅聊天" };
  return { kind: "idle", label: "空闲", summary: "空闲" };
}

function setPetStatus(status) {
  if (state.petStatus === status) return;
  state.petStatus = status;
  const petElement = $("mailPet");
  if (petElement) {
    petElement.dataset.status = status;
    petElement.title = petStatusLabels[status] || petStatusLabels.idle;
  }
  if (tauriInvoke) {
    invoke("set_pet_status", { status }).catch(() => {});
  }
}

$("adoptButton").addEventListener("click", startAdoption);
$("nicknameInput").addEventListener("keydown", (event) => { if (event.key === "Enter") { event.preventDefault(); startAdoption(); } });
$("enterTetiButton").addEventListener("click", () => { $("onboarding").hidden = true; });
$("retryAdoptionButton").addEventListener("click", () => {
  if (state.lastNickname || state.snapshot?.nickname) { $("nicknameInput").value = state.lastNickname || state.snapshot.nickname; startAdoption(); }
  else showAdoptionState("adoptionForm");
});
$("showDiagnosticButton").addEventListener("click", () => { $("diagnosticInfo").hidden = !$("diagnosticInfo").hidden; });

$("connectionStatusButton").addEventListener("click", () => {
  if (state.status === "uninitialized") showAdoptionState("adoptionForm");
  else $("statusModal").showModal();
});
$("editPetNameButton").addEventListener("click", () => {
  if (state.status === "uninitialized") showAdoptionState("adoptionForm");
  else showPetNameEditor();
});
$("savePetNameButton").addEventListener("click", savePetName);
$("cancelPetNameButton").addEventListener("click", hidePetNameEditor);
$("petNameInput").addEventListener("keydown", (event) => {
  if (event.key === "Enter") { event.preventDefault(); savePetName(); }
  if (event.key === "Escape") { event.preventDefault(); hidePetNameEditor(); }
});
$("addFriendEntry").addEventListener("click", () => {
  if (state.status === "uninitialized") showAdoptionState("adoptionForm");
  else $("friendModal").showModal();
});

$("reconnectButton").addEventListener("click", async () => {
  $("statusError").textContent = ""; $("communicationState").textContent = "连接中";
  try { const snapshot = await invoke("reconnect_chatmail"); renderStatus(snapshot); if (snapshot.status === "connected") showToast("通信已恢复"); }
  catch (error) { $("statusError").textContent = publicError(error); }
});

$("resetIdentityButton").addEventListener("click", async () => {
  if (!window.confirm("重置后需要重新领养 Teti。确定重置通信身份吗？")) return;
  try { const snapshot = await invoke("reset_chatmail_identity"); $("statusModal").close(); renderStatus(snapshot); }
  catch (error) { $("statusError").textContent = publicError(error); }
});

let parseTimer;
$("inviteText").addEventListener("input", () => {
  clearTimeout(parseTimer); parseTimer = setTimeout(async () => {
    const result = await invoke("parse_invite", { text: $("inviteText").value });
    const labels = { delta_invite_link: "Delta Chat 邀请链接", email_address: "Email / Delta Chat 地址", teti_invite: "Teti 增强邀请", unknown: "未识别" };
    $("invitePreview").textContent = [labels[result.kind], result.petName, result.inviteLink || result.address].filter(Boolean).join("\n");
  }, 180);
});

$("addFriendButton").addEventListener("click", async () => {
  $("friendError").textContent = "";
  try {
    const added = await invoke("add_friend", { text: $("inviteText").value });
    $("friendModal").close(); $("inviteText").value = ""; showToast("好友已添加"); await refreshContacts();
    if (added.contact) selectContact({ ...added.contact, chatId: added.chatId });
  } catch (error) { $("friendError").textContent = publicError(error); }
});

document.querySelectorAll(".mode-button").forEach((button) => button.addEventListener("click", () => setMode(button.dataset.mode)));

$("sendButton").addEventListener("click", () => {
  const text = $("messageInput").value.trim();
  if (!state.chatId) return showToast("请先选择联系人");
  if (!text && state.mode !== "file_package") return showToast("请先告诉 Teti 要做什么");
  try {
    state.pendingRecipe = createRecipe(text || "发送文件包裹", null);
    setPetStatus("draft");
    renderWorkspace({ scrollToPreview: true, preserveScroll: false });
  } catch (error) {
    showToast(publicError(error));
  }
});

$("messageInput").addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
    event.preventDefault();
    $("sendButton").click();
  }
});

$("attachButton").addEventListener("click", async () => {
  if (!state.chatId) return showToast("请先选择联系人");
  try {
    const grant = await invoke("pick_attachment");
    if (!grant) return;
    state.pendingAttachment = grant;
    setMode("file_package");
    showToast(`已选择包裹：${grant.name}`);
    state.pendingRecipe = createRecipe($("messageInput").value.trim() || "发送文件包裹", "file_package");
    renderWorkspace({ scrollToPreview: true, preserveScroll: false });
  } catch (error) { showToast(publicError(error)); }
});

async function poll() {
  if (state.status === "connected") {
    try { (await invoke("poll_incoming")).forEach(appendIncoming); } catch { /* reconnect remains user-controlled */ }
  }
  setTimeout(poll, 2500);
}

setPetStatus("idle");
renderWorkspace();
refreshStatus();
poll();
