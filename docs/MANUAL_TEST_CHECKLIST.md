# HeroTerm — Manual test checklist (macOS)

Run on a real Mac against a real server before calling a release
done. Automated tests (91+) cover logic on the authoring VM; the
items below need the actual app, sandbox, and Finder.

## Sessions (Milestone 1)
- [ ] Create / edit / duplicate / delete a session and a folder;
      invalid host/port/username are rejected per field.
- [ ] Create a session **with a password**, quit with **Cmd+Q**,
      reopen: the session is still there and Connect does not ask
      for the password again (Keychain persistence). ⬅ still open
      from Milestone 1 acceptance.
- [ ] Private-key session: pick the key with **Browse…** (not a
      typed path), connect works after an app restart.

## Connection & terminal (Milestone 2)
- [ ] First connect shows the host-key fingerprint dialog; Abort
      refuses the connection; Trust connects.
- [ ] Wrong password gives a clear authentication error, no crash.
- [ ] Unreachable host gives a network/timeout error.
- [ ] Terminal: run `ls`, `vim`/`top` briefly, resize the window —
      the remote app redraws at the new size.
- [ ] Vietnamese Telex input: typing `w` twice yields `w` (not `ưư`).
- [ ] Typing robustness (ADR-014): type a long command slowly
      and quickly — no dropped characters, no cursor jumps, no
      overlapping text. Then click into the Explorer/sidebar,
      click back into the terminal and keep typing a long command
      (focus round-trip): still no lost characters and the line
      is never cut in two. Repeat with a long hyphenated word
      (e.g. `docker compose build queue-worker`).
- [ ] Typing robustness in the RELEASE build (ADR-017): install
      from the DMG (or `install_macos.sh`), then in one session
      run a dozen commands, typing `docker compose ...` and other
      long lines at full speed — no dropped first letters after
      each command, no line wipes, no duplicated command text at
      the fresh prompt. (Debug runs did not reproduce the old
      bug; this check only counts on the release build.) If it
      still corrupts: reproduce once with ⌘⇧L logging on and
      send `heroterm-input-log.txt` — the log now classifies
      RESTART / PHANTOM / REBASE / ECHO events.
- [ ] Typing on the delta input model (ADR-020): in the deep
      docker directory, type `docker compose` and `docker
      system`, pressing Space after each word — the cursor must
      stay at the end of the text throughout; repeat the
      completion flow (`nano .en` → Tab → backspace through the
      completed name) — no text may vanish. If anything still
      misbehaves, capture ONE ⌘⇧L log of it: the log must
      contain DELTA lines (proof the delta model is active);
      a log with only UEV lines is itself the key finding.
- [ ] Windows typing + paste integrity (ADR-023): on the
      Windows build, connect and type a full command (letters,
      spaces, backspace) — every character must land; paste a
      long multi-line command immediately after connecting —
      no shell-integration text may appear inside it and no
      overlapping redraws; type Vietnamese with Unikey/EVKey
      and confirm composed characters arrive whole.
- [ ] Syntax highlighting (ADR-024): connect to a Linux server
      and read the MOTD — links underlined, the IPv4 address
      pink, percentages amber, "information" blue, "enabled"
      green; run `ls --color` and vim/htop — their own colours
      unchanged; Settings → Terminal → Syntax highlighting off
      returns everything to plain theme colour instantly.
- [ ] Typing + resize (ADR-018): type a long command (past the
      right edge so the line wraps), then drag the window edge
      or the Explorer sidebar to change the width, then keep
      typing — the cursor stays at the end of the text, the line
      is never duplicated onto another row, and Enter runs the
      command exactly as shown.
- [ ] Disconnect button works; **Reconnect** button (and ⌘⇧R)
      reconnects the same session; ⌘⇧C / ⌘⇧D shortcuts work.

## Remote Explorer (Milestones 3–5)
- [ ] `cd` in the terminal moves the explorer (follow mode);
      pausing follow stops it.
- [ ] Breadcrumb has its own background; the path field shows the
      current path, can be copied, typing a path + Enter navigates;
      the dropdown lists recent folders.
- [ ] Right-click a file: Rename (collision is rejected),
      Download (progress + cancel in the bottom panel, no partial
      file left after cancel), Delete asks with the full path.
- [ ] Drag files **and a folder** from Finder into the sidebar:
      uploads land in the visible folder, collisions prompt
      (overwrite / keep both / skip), progress shows at the bottom.
- [ ] The header **Upload** button (file picker) also uploads.

## Metrics footer (Milestone 6)
- [ ] Right after connecting: "Collecting server metrics…", then
      real CPU / Memory / Disk values for the **remote** server,
      updating every ~4 s (CPU appears from the second update).
- [ ] Compare once with `top` / `free -h` / `df -h /` on the server:
      values are in the same ballpark.
- [ ] Disconnect: footer returns to "Server metrics unavailable".

## Explorer table view (post-MVP)
- [ ] Listing shows the columns Name / Size / Last modified /
      Owner / Group / Permission; folder sizes show `—`; Owner
      shows account names when the server has them (e.g. `root`),
      otherwise the numeric UID.
- [ ] Clicking each header sorts (arrow shows direction), folders
      stay first; clicking again reverses.
- [ ] Dragging a column edge resizes it; double-click auto-fits;
      dragging the sidebar edge resizes the sidebar; quit and
      reopen — both widths are remembered.
- [ ] Long file names ellipsize with the full path in a tooltip;
      the table scrolls horizontally when narrower than the table.
- [ ] Drag a file from Finder onto the **table** — it uploads
      (this exercises the drop target mounting fixed with this
      feature; previously only the Upload button path was live).

## Multi-session tabs (post-MVP)
- [ ] Connect one session, then open two more via the **+**
      button / ⌘T picker (search + folder groups visible); all
      three tabs stay connected, each tab keeps its own terminal
      output and scrollback when switching back and forth.
- [ ] In the picker, an already-open session shows **Open**:
      tapping it switches to its tab (no duplicate); the
      **+ circle** button opens a second tab of the same server
      titled `name (2)`.
- [ ] Close the middle tab: the neighbouring tab becomes active
      and the other sessions keep running (e.g. a long `top` or a
      download in the explorer is unaffected).
- [ ] Disconnect one tab (⌘⇧D) and reconnect it (⌘⇧R) while
      another tab stays connected the whole time.
- [ ] Connect to a server whose host key is unknown in two tabs
      in quick succession: the trust dialogs appear one at a
      time, not stacked.
- [ ] Try ⌘1 / ⌘2 / ⌘3 and Ctrl+Tab to move between tabs;
      ⌘⇧W closes the active tab; closing the last tab returns
      to the session list.
- [ ] The explorer and the metrics footer follow the ACTIVE
      tab's server; each tab's explorer directory is remembered
      when switching away and back.

## SSH profile management (post-MVP, SSH-PROFILE-001)
- [ ] **Migration (ADR-013):** on first launch of this build,
      profiles that had an Environment or Tags show matching
      coloured **Labels** instead (Production red, Staging
      orange, Development blue); no profile data is lost.
- [ ] Session items show **no** `user@host` line; hovering an
      item shows it as a tooltip (with last-connected info).
- [ ] Assign two labels to one session in the form (create one
      inline via **New label**): both appear as coloured pills on
      the item. Filter chips under search: selecting both labels
      shows only sessions carrying both; **Clear filters**
      restores the full list.
- [ ] Manage labels (🏷 button): rename, recolour and delete a
      label; deleting detaches it from its sessions without
      deleting any session.
- [ ] Pick an icon + colour for a session and for a folder:
      they render in the sidebar, the tab picker and the tab
      strip, and survive quit/reopen.
- [ ] Search finds a profile by a word that only appears in its
      Description, in a label's name, or in its folder's name.
- [ ] In the form, **Test Connection** with correct settings
      reports success without opening a tab; with a wrong password
      it reports an actionable error and the form keeps your input.
      Cancelling the form after edits asks "Discard changes?".
- [ ] Duplicate a profile that has a saved password: the copy is
      named `<name> Copy` and connects WITHOUT asking for the
      password. Then change the copy's password in Edit — the
      original must still connect with its old password.
- [ ] Set a profile's key path to a non-existent file: the form
      shows a warning but still saves; Test Connection then fails
      with the key-file error.
- [ ] Export all profiles and open the JSON: it must contain no
      password, no passphrase and no `credentialRef`. Import it
      back: the preview marks duplicates; **Skip** adds nothing,
      **Import as copies** adds `… Copy 2` entries, **Update
      existing** applies changed fields while the old profiles
      still connect with their saved passwords.
- [ ] Import a hand-broken JSON file (bad port, unknown
      environment, wrong schemaVersion): the import is refused
      with a readable reason and nothing is added.
- [ ] A failed connect marks the profile "Last attempt failed";
      a later successful connect clears it.
- [ ] Collapse and expand a folder group with the chevron; the
      folder editor offers a group type (Project/Client/Custom).

## Packaging (Milestone 7)
- [ ] `./scripts/package_macos.sh` produces a `.dmg`; installing
      from it and launching works; the app icon is the dark
      terminal tile, and the app is named **HeroTerm**.

## Edit File (ADR-016) — Mac acceptance

Built-in editor:
- [ ] Right-click a `.conf`/`.env`/`.php` file → Edit: opens in a
      tab beside the terminal tabs, with highlighting, line
      numbers, full path in the header.
- [ ] Type a change: orange dirty dot appears on the tab and in
      the header; ⌘S saves (status returns to "Saved"); verify the
      change on the server with `cat` in the terminal tab.
- [ ] ⌘F: find highlights matches; Next/Previous move; Replace
      and Replace All work; Esc/close removes highlighting.
- [ ] ⌘Z / ⌘⇧Z undo/redo; undo button enables/disables correctly.
- [ ] Open a >2 MB log and a binary (e.g. `/bin/ls` copied into
      the home dir): both refused with a clear message.
- [ ] Close a dirty tab (× and ⌘W): Save / Don't Save / Cancel
      dialog appears; Save closes only after a successful upload;
      Cancel keeps everything.
- [ ] Conflict: open a file, change it on the server from the
      terminal (`echo x >> file`), then Save in the editor →
      conflict dialog; Reload remote shows the server content;
      repeat and choose Overwrite → server gets the editor text.
- [ ] Disconnect the tab, then Save in a still-open editor:
      error shown, content kept.

External editor:
- [ ] Open With… lists the editors installed on this Mac
      (VS Code / Sublime / TextEdit); pick one with "Set as
      default" → the file opens in that app.
- [ ] Edit + save in the external app: within ~1 s the change is
      on the server (check with `cat`); the pane shows a fresh
      "Last synced" time.
- [ ] Settings: turn Auto Sync off → external edits mark the tab
      "Changes are waiting to sync"; Sync now uploads.
- [ ] Close an external session with unsynced changes: Sync /
      Discard / Cancel offered; after a synced close the temp
      copy under the temp dir is gone.
- [ ] Settings round trip: default editor = External, double-
      click a file opens the external app; gear dialog's Smart
      Save list shows skipped files after the flow below.

Smart Save:
- [ ] Settings: enable Save Confirmation + Smart Save. Save a
      file 3 times (confirmation each time) → the "Remember this
      file?" prompt appears once; choose Don't Ask Again → the
      4th save uploads without asking; the close warning for a
      dirty file STILL appears.
- [ ] Settings lists the file under "Files that skip the save
      confirmation"; Ask again restores the confirmation.
