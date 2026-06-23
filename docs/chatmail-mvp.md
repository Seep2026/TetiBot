# Teti macOS Chatmail MVP

## Decision

Teti is a Delta Chat client with a pet shell and a task enhancement layer. Delta Chat Core owns accounts, transport configuration, encryption, contacts, chats, and MIME messages. Teti does not introduce a private transport or replace standard message bodies with JSON.

The macOS process tree is:

```text
Teti (Tauri parent; Mail hidden at launch)
  -> usagi child process
    -> original Lua pet runtime and transparent pet window
  -> Rust chatmail commands
    -> JSON Lines over child stdin/stdout
      -> deltachat-rpc-server
        -> Delta Chat Core account database and mail transports
```

The two user surfaces have separate owners:

- usagi owns the only surface visible at launch. Its existing Lua state machine provides layered breathing, expression changes, animated tracks, natural random movement, cross-display dragging/falling, and the hat picker.
- Tauri owns `mail`, a normal communication window hidden at launch and opened from the usagi right-click menu.

Tauri is the only regular macOS application in this process tree. The child usagi process runs as a macOS UI Element (`USAGI_ACCESSORY_APP=1`), retaining its interactive transparent window while staying out of the Dock and application switcher.

The menu writes only a fixed `{ command, nonce }` signal through usagi's per-game save API. The Tauri parent accepts `open_mail` and `quit_teti`; it does not execute arbitrary commands from Lua. Closing Mail hides it instead of quitting Teti. **领养 Teti** and **通信状态** are explicit entries inside Mail; neither flow is shown automatically while the desktop pet starts.

The RPC server account directory is stored below Teti's macOS application data directory. First-run setup accepts only a Teti nickname and passes `DCACCOUNT:mail.seep.im` to Core. Core generates and stores the chatmail credentials in its own account database; Teti never receives or writes the password to its profile JSON.

## Adoption Flow

1. Validate a required nickname as at most 10 Unicode characters with no control characters.
2. Create or open the single Delta Chat account context.
3. Save a local draft `pet-profile.json` containing only public profile fields.
4. Set Core `displayname` and call `add_transport_from_qr` with `DCACCOUNT:mail.seep.im`.
5. Fall back to `set_config_from_qr` plus `configure` only when the preferred RPC method is unavailable.
6. Wait for Core to return the generated `@mail.seep.im` address, update the profile, and enter the pet UI.

The MVP has no traditional email login, custom relay, QR scanner, multi-account UI, HTTP DCACCOUNT URL, or credential export.

## Interoperability Contract

- Text is sent as the `text` field of Core `send_msg`.
- Images are sent as Core `Image` messages; other attachments use `File`.
- Incoming messages without `teti-task.json` are always rendered as standard Delta Chat messages.
- A Teti task contains a human-readable message body plus one file attachment named exactly `teti-task.json`.
- An invalid, oversized, unsupported, or differently named JSON attachment is treated as a normal file.
- Receiving a valid task creates a confirmation-required card. The MVP has no task execution command.

This preserves useful behavior in both directions with standard Delta Chat clients. A standard client can read the task request and open the JSON file even though it cannot render the Teti card.

## Security Boundary

- Remote tasks are never executed automatically.
- The MVP task action allowlist contains only `browser.screenshot`. Shell, terminal, process, arbitrary file-read, browser-cookie, Keychain, SSH, and unknown actions are rejected.
- Outgoing local files must be selected through the native picker. The frontend receives a one-use token, not a filesystem path.
- Known sensitive paths and filenames are rejected, and files are size/mtime checked again before sending.
- RPC errors expose the public error message only. RPC stderr is suppressed and passwords/tokens are not logged.
- Contact status is derived from Core as ordinary, encrypted, or verified.

## MVP Tradeoffs

Incoming messages are polled with `get_fresh_msgs` every 2.5 seconds. A production iteration should consume the RPC event stream, persist UI read state, and fetch chat history by chat ID.

The current development build resolves `deltachat-rpc-server` from `DELTA_CHAT_RPC_SERVER`, the local Core release target, or `PATH`. It resolves usagi from `USAGI_BIN` and the Lua project from `TETI_PET_PROJECT`; `make chatmail-run` supplies both paths after building the repository's `engine/usagi` source. Distribution builds should package signed usagi and RPC sidecars plus the Lua runtime, with Core pinned to the tested revision.

Delta Chat Core is an external source checkout, not a TetiBot submodule. Cross-Mac source setup and path configuration are documented in [`delta-chat-core-source.md`](delta-chat-core-source.md).

Creating a chat for each listed contact is acceptable for the MVP but should be replaced by a chat-list query before scaling to large address books. Secure-join links are passed directly to Core, including `https://i.delta.chat/#...` links.

## Run

```bash
make chatmail-run DELTA_CORE_DIR=/path/to/core
```

Right-click the desktop pet and choose **Mail** to open Mail; choose **Hats** to change its hat. Inside Mail, use **领养 Teti / 通信状态** or **添加好友**. First-run adoption asks only for a nickname; friend invites remain text-only and there is no QR scanner in this version.
