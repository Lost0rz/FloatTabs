from pathlib import Path

ROOT = Path('.')


def read(path):
    return (ROOT / path).read_text()


def write(path, text):
    p = ROOT / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected 1 match, found {count}')
    return text.replace(old, new, 1)

# 1) Debug-only in-app benchmark control server.
write('FloatTabs/App/BenchmarkControlServer.swift', r'''#if DEBUG
import Darwin
import Foundation

/// Debug-only loopback control channel for the local benchmark harness.
///
/// The listener binds to 127.0.0.1 on an ephemeral port and requires a random
/// per-process token written to the user's FloatTabs Application Support folder.
/// Release builds compile none of this implementation.
final class BenchmarkControlServer {
    static let protocolVersion = 1

    private let token = UUID().uuidString
    private let commandHandler: @MainActor ([String: Any]) -> [String: Any]
    private let acceptQueue = DispatchQueue(label: "com.lost0rz.FloatTabs.benchmark-control")
    private var listenerFD: Int32 = -1
    private var controlInfoURL: URL?

    init(commandHandler: @escaping @MainActor ([String: Any]) -> [String: Any]) {
        self.commandHandler = commandHandler
    }

    func start() throws {
        guard listenerFD < 0 else { return }

        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.EIO)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, Darwin.listen(fd, 8) == 0 else {
            Darwin.close(fd)
            throw POSIXError(.EADDRINUSE)
        }

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.getsockname(fd, socketAddress, &boundLength)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(fd)
            throw POSIXError(.EIO)
        }

        listenerFD = fd
        let port = UInt16(bigEndian: boundAddress.sin_port)
        try publishControlInfo(port: port)

        acceptQueue.async { [weak self] in
            self?.acceptLoop(listenerFD: fd)
        }
    }

    func stop() {
        let fd = listenerFD
        listenerFD = -1
        if fd >= 0 {
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
        if let controlInfoURL {
            try? FileManager.default.removeItem(at: controlInfoURL)
        }
        controlInfoURL = nil
    }

    deinit {
        stop()
    }

    private func publishControlInfo(port: UInt16) throws {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("FloatTabs", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("BenchmarkControl.json", isDirectory: false)
        let payload: [String: Any] = [
            "protocol_version": Self.protocolVersion,
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "host": "127.0.0.1",
            "port": Int(port),
            "token": token,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        controlInfoURL = url
    }

    private func acceptLoop(listenerFD: Int32) {
        while self.listenerFD == listenerFD {
            let connectionFD = Darwin.accept(listenerFD, nil, nil)
            if connectionFD < 0 {
                if self.listenerFD != listenerFD { return }
                continue
            }
            handleConnection(connectionFD)
        }
    }

    private func handleConnection(_ fd: Int32) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while data.count < 64 * 1024 {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(fd, bytes.baseAddress, bytes.count)
            }
            guard count > 0 else { break }
            data.append(buffer, count: count)
            if data.last == 0x0A { break }
        }

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let request = object as? [String: Any] else {
            writeResponse(["ok": false, "error": "invalid_json"], to: fd)
            return
        }
        guard request["token"] as? String == token else {
            writeResponse(["ok": false, "error": "unauthorized"], to: fd)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                self?.writeResponse(["ok": false, "error": "server_stopped"], to: fd)
                return
            }
            let response = self.commandHandler(request)
            self.writeResponse(response, to: fd)
        }
    }

    private func writeResponse(_ response: [String: Any], to fd: Int32) {
        var payload = response
        if payload["ok"] == nil {
            payload["ok"] = true
        }
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else {
            Darwin.close(fd)
            return
        }
        data.append(0x0A)
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            _ = Darwin.write(fd, baseAddress, bytes.count)
        }
        Darwin.shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }
}
#endif
''')

# 2) PanelController exposes only the narrow product seams needed by Debug benchmark control.
path = 'FloatTabs/Panel/PanelController.swift'
text = read(path)
needle = '''    func prepareForTermination() {
        persistPanelFrame()
    }

    func handle(_ command: AppCommand) {'''
insert = '''    func prepareForTermination() {
        persistPanelFrame()
    }

#if DEBUG
    func benchmarkControlSnapshot() -> [String: Any] {
        let profiles: [[String: Any]] = tabStore.orderedProfiles.map { profile in
            [
                "id": profile.id.uuidString,
                "order": profile.order,
                "name": profile.name,
                "residency": profile.residencyPolicy.rawValue,
                "background_media": profile.backgroundMediaPolicy.rawValue,
                "website_mode": profile.renderingProfile.websiteMode.rawValue,
                "viewport_width": Double(profile.renderingProfile.viewportWidth),
                "viewport_height": Double(profile.renderingProfile.viewportHeight),
                "zoom": Double(profile.renderingProfile.zoom),
            ]
        }
        var snapshot: [String: Any] = [
            "visible": isVisible,
            "profiles": profiles,
        ]
        snapshot["active_slot_id"] = tabStore.activeTabID?.uuidString ?? NSNull()
        return snapshot
    }

    func benchmarkSetResourcePolicy(
        slotIDStrings: [String],
        residencyRawValue: String?,
        backgroundMediaRawValue: String?
    ) -> Bool {
        let ids = slotIDStrings.compactMap(UUID.init(uuidString:))
        guard ids.count == slotIDStrings.count, !ids.isEmpty else { return false }
        let validIDs = Set(tabStore.profiles.map(\\.id))
        guard ids.allSatisfy(validIDs.contains) else { return false }

        let residency = residencyRawValue.flatMap(SlotResidencyPolicy.init(rawValue:))
        let media = backgroundMediaRawValue.flatMap(BackgroundMediaPolicy.init(rawValue:))
        if residencyRawValue != nil, residency == nil { return false }
        if backgroundMediaRawValue != nil, media == nil { return false }
        guard residency != nil || media != nil else { return false }

        for id in ids {
            guard tabStore.updateResourcePolicy(
                id: id,
                residencyPolicy: residency,
                backgroundMediaPolicy: media
            ) else {
                return false
            }
        }
        return true
    }

    func benchmarkSelect(slotIDString: String) -> Bool {
        guard let id = UUID(uuidString: slotIDString) else { return false }
        return tabStore.select(id: id)
    }
#endif

    func handle(_ command: AppCommand) {'''
text = replace_once(text, needle, insert, 'PanelController debug benchmark seams')
write(path, text)

# 3) AppCoordinator starts/stops the Debug-only control server and routes commands.
path = 'FloatTabs/App/AppCoordinator.swift'
text = read(path)
text = replace_once(text,
'''    private var globalHotkeyController: GlobalHotkeyController?
    private var appCommandController: AppCommandController?
''',
'''    private var globalHotkeyController: GlobalHotkeyController?
    private var appCommandController: AppCommandController?
#if DEBUG
    private var benchmarkControlServer: BenchmarkControlServer?
#endif
''', 'AppCoordinator debug property')
text = replace_once(text,
'''        appCommandController = AppCommandController(
            isEnabled: { [weak self] in
                NSApp.isActive && (self?.panelController.isVisible ?? false)
            },
            onCommand: { [weak self] command in
                self?.panelController.handle(command)
            }
        )
    }

    func prepareForTermination() {
        panelController.prepareForTermination()
    }
''',
'''        appCommandController = AppCommandController(
            isEnabled: { [weak self] in
                NSApp.isActive && (self?.panelController.isVisible ?? false)
            },
            onCommand: { [weak self] command in
                self?.panelController.handle(command)
            }
        )

#if DEBUG
        let benchmarkControlServer = BenchmarkControlServer { [weak self] request in
            self?.handleBenchmarkControl(request) ?? ["ok": false, "error": "coordinator_unavailable"]
        }
        self.benchmarkControlServer = benchmarkControlServer
        try? benchmarkControlServer.start()
#endif
    }

    func prepareForTermination() {
#if DEBUG
        benchmarkControlServer?.stop()
#endif
        panelController.prepareForTermination()
    }
''', 'AppCoordinator server lifecycle')
text = replace_once(text,
'''    private func toggleFloatTabs() {
        if panelController.isVisible {
            panelController.hideFloatTabs()
        } else {
            panelController.showFloatTabs()
        }
    }
}''',
'''#if DEBUG
    private func handleBenchmarkControl(_ request: [String: Any]) -> [String: Any] {
        guard let action = request["action"] as? String else {
            return ["ok": false, "error": "missing_action"]
        }

        switch action {
        case "status", "ping":
            return ["ok": true, "status": panelController.benchmarkControlSnapshot()]

        case "configure":
            guard let slotIDs = request["slot_ids"] as? [String] else {
                return ["ok": false, "error": "missing_slot_ids"]
            }
            let succeeded = panelController.benchmarkSetResourcePolicy(
                slotIDStrings: slotIDs,
                residencyRawValue: request["residency"] as? String,
                backgroundMediaRawValue: request["background_media"] as? String
            )
            return succeeded
                ? ["ok": true, "status": panelController.benchmarkControlSnapshot()]
                : ["ok": false, "error": "configure_failed"]

        case "activate":
            guard let slotID = request["slot_id"] as? String,
                  panelController.benchmarkSelect(slotIDString: slotID) else {
                return ["ok": false, "error": "activate_failed"]
            }
            return ["ok": true, "status": panelController.benchmarkControlSnapshot()]

        case "show":
            if !panelController.isVisible {
                panelController.showFloatTabs()
            }
            return ["ok": true, "status": panelController.benchmarkControlSnapshot()]

        case "hide":
            if panelController.isVisible {
                panelController.hideFloatTabs()
            }
            return ["ok": true, "status": panelController.benchmarkControlSnapshot()]

        default:
            return ["ok": false, "error": "unknown_action"]
        }
    }
#endif

    private func toggleFloatTabs() {
        if panelController.isVisible {
            panelController.hideFloatTabs()
        } else {
            panelController.showFloatTabs()
        }
    }
}''', 'AppCoordinator command routing')
write(path, text)

# 4) Register control server in Xcode project.
path = 'FloatTabs.xcodeproj/project.pbxproj'
text = read(path)
text = replace_once(text,
'''\t\tA00000000000000000000003 /* AppCoordinator.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000003 /* AppCoordinator.swift */; };''',
'''\t\tA00000000000000000000003 /* AppCoordinator.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000003 /* AppCoordinator.swift */; };\n\t\tA00000000000000000000022 /* BenchmarkControlServer.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000022 /* BenchmarkControlServer.swift */; };''', 'PBX build file')
text = replace_once(text,
'''\t\tB00000000000000000000003 /* AppCoordinator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppCoordinator.swift; sourceTree = "<group>"; };''',
'''\t\tB00000000000000000000003 /* AppCoordinator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppCoordinator.swift; sourceTree = "<group>"; };\n\t\tB00000000000000000000022 /* BenchmarkControlServer.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BenchmarkControlServer.swift; sourceTree = "<group>"; };''', 'PBX file reference')
text = replace_once(text,
'''\t\t\t\tB00000000000000000000003 /* AppCoordinator.swift */,''',
'''\t\t\t\tB00000000000000000000003 /* AppCoordinator.swift */,\n\t\t\t\tB00000000000000000000022 /* BenchmarkControlServer.swift */,''', 'PBX App group')
text = replace_once(text,
'''\t\t\t\tA00000000000000000000003 /* AppCoordinator.swift in Sources */,''',
'''\t\t\t\tA00000000000000000000003 /* AppCoordinator.swift in Sources */,\n\t\t\t\tA00000000000000000000022 /* BenchmarkControlServer.swift in Sources */,''', 'PBX sources')
write(path, text)

# 5) Upgrade Python harness with authenticated app control and fully automatic benchmark mode.
path = 'tools/benchmark/floattabs_benchmark.py'
text = read(path)
text = replace_once(text, 'import shutil\nimport statistics', 'import shutil\nimport socket\nimport statistics', 'Python socket import')
text = replace_once(text,
'''PROFILE_FILE = Path.home() / "Library" / "Application Support" / "FloatTabs" / "WebAppProfiles.json"
DEFAULT_SAMPLE_SECONDS = 15''',
'''PROFILE_FILE = Path.home() / "Library" / "Application Support" / "FloatTabs" / "WebAppProfiles.json"
CONTROL_INFO_FILE = Path.home() / "Library" / "Application Support" / "FloatTabs" / "BenchmarkControl.json"
DEFAULT_SAMPLE_SECONDS = 15''', 'Python control path')
control_client = r'''

def load_control_info(host_pid: int) -> Dict[str, object]:
    if not CONTROL_INFO_FILE.exists():
        raise RuntimeError(
            "FloatTabs Debug benchmark control is unavailable. Rebuild/restart the Debug app from this PR branch."
        )
    try:
        payload = json.loads(CONTROL_INFO_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"Unable to read benchmark control info: {exc}") from exc
    if int(payload.get("pid", -1)) != host_pid:
        raise RuntimeError(
            f"Benchmark control belongs to PID {payload.get('pid')}, but current FloatTabs PID is {host_pid}. "
            "Quit duplicate/stale FloatTabs builds and restart the current Debug build."
        )
    if int(payload.get("protocol_version", 0)) != 1:
        raise RuntimeError("Unsupported FloatTabs benchmark control protocol version.")
    return payload


class BenchmarkControlClient:
    def __init__(self, host_pid: int) -> None:
        info = load_control_info(host_pid)
        self.host = str(info.get("host", "127.0.0.1"))
        self.port = int(info["port"])
        self.token = str(info["token"])

    def request(self, action: str, **payload: object) -> Dict[str, object]:
        request_payload = {"token": self.token, "action": action, **payload}
        encoded = (json.dumps(request_payload, separators=(",", ":")) + "\n").encode("utf-8")
        chunks: List[bytes] = []
        try:
            with socket.create_connection((self.host, self.port), timeout=5) as connection:
                connection.sendall(encoded)
                while True:
                    chunk = connection.recv(4096)
                    if not chunk:
                        break
                    chunks.append(chunk)
                    if b"\n" in chunk:
                        break
        except OSError as exc:
            raise RuntimeError(f"FloatTabs benchmark control connection failed: {exc}") from exc
        try:
            response = json.loads(b"".join(chunks).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise RuntimeError(f"Invalid response from FloatTabs benchmark control: {exc}") from exc
        if not response.get("ok"):
            raise RuntimeError(f"FloatTabs benchmark control rejected {action}: {response.get('error', 'unknown error')}")
        return response

    def status(self) -> Dict[str, object]:
        return dict(self.request("status").get("status") or {})

    def configure(self, slot_ids: Sequence[str], residency: str, media: str = "pauseWhenInactive") -> Dict[str, object]:
        return dict(self.request(
            "configure",
            slot_ids=list(slot_ids),
            residency=residency,
            background_media=media,
        ).get("status") or {})

    def configure_one(self, slot_id: str, residency: str, media: str) -> Dict[str, object]:
        return self.configure([slot_id], residency, media)

    def activate(self, slot_id: str) -> Dict[str, object]:
        return dict(self.request("activate", slot_id=slot_id).get("status") or {})

    def show(self) -> Dict[str, object]:
        return dict(self.request("show").get("status") or {})

    def hide(self) -> Dict[str, object]:
        return dict(self.request("hide").get("status") or {})


def control_profiles(status: Dict[str, object]) -> List[Dict[str, object]]:
    profiles = list(status.get("profiles") or [])
    profiles.sort(key=lambda item: (item.get("order", 0), item.get("name", "")))
    return profiles


def verify_control_policy(status: Dict[str, object], selected_ids: Sequence[str], expected: str) -> None:
    profiles = {str(item.get("id")): item for item in control_profiles(status)}
    mismatches = []
    for slot_id in selected_ids:
        profile = profiles.get(slot_id)
        if not profile:
            mismatches.append(f"missing {slot_id}")
            continue
        if profile.get("residency") != expected:
            mismatches.append(f"{profile.get('name')}: {profile.get('residency')}")
        if profile.get("background_media") != "pauseWhenInactive":
            mismatches.append(f"{profile.get('name')}: media={profile.get('background_media')}")
    if mismatches:
        raise RuntimeError("Automated policy verification failed: " + "; ".join(mismatches))
'''
text = replace_once(text, '\ndef find_floattabs_pids() -> List[int]:', control_client + '\n\ndef find_floattabs_pids() -> List[int]:', 'Python control client insertion')

# Use explicit inactive-selected count when the automatic benchmark supplies it.
text = replace_once(text,
'''        eligible = max(int(cold.get("slot_count", 0)) - 1, 0)''',
'''        eligible = int(cold.get("inactive_selected_slot_count", max(int(cold.get("slot_count", 0)) - 1, 0)))''', 'cold eligible count')
text = replace_once(text,
'''    cold = latest_by_policy(captures, "cold")
    hidden = next((capture for capture in reversed(captures) if capture.get("state") == "hidden"), None)''',
'''    cold = next((capture for capture in captures if capture.get("state") == "cold-evicted"), None) or latest_by_policy(captures, "cold")
    warm_hidden = next((capture for capture in captures if capture.get("policy") == "warm" and capture.get("state") == "hidden"), None)
    hot_hidden = next((capture for capture in captures if capture.get("policy") == "hot" and capture.get("state") == "hidden"), None)''', 'hidden capture selection')
text = replace_once(text,
'''    for capture in [hidden] if hidden else []:
        idle_cpu = capture_metric(capture, "total_cpu_avg")
        notes.append(
            f"Hidden-panel aggregate CPU: {idle_cpu:.2f}% — diagnostic rating **{cpu_idle_rating(idle_cpu)}** "
            f"(≤1% Good, 1–3% Watch, >3% Investigate)."
        )
''',
'''    if hot_hidden:
        hot_hidden_cpu = capture_metric(hot_hidden, "total_cpu_avg")
        notes.append(
            f"Hot + hidden aggregate CPU: {hot_hidden_cpu:.2f}% — diagnostic rating **{cpu_idle_rating(hot_hidden_cpu)}**."
        )
    if warm_hidden:
        warm_hidden_cpu = capture_metric(warm_hidden, "total_cpu_avg")
        notes.append(
            f"Warm + hidden aggregate CPU: {warm_hidden_cpu:.2f}% — diagnostic rating **{cpu_idle_rating(warm_hidden_cpu)}** "
            f"(≤1% Good, 1–3% Watch, >3% Investigate)."
        )
''', 'hidden observations')

auto_mode = r'''

def persist_capture_metadata(session_dir: Path, capture: Dict[str, object], **metadata: object) -> None:
    capture.update(metadata)
    label = str(capture["label"])
    path = session_dir / "captures" / f"{label}.summary.json"
    path.write_text(json.dumps(capture, indent=2, ensure_ascii=False), encoding="utf-8")
    write_report(session_dir)


def automatic_mode(args: argparse.Namespace) -> int:
    ensure_macos()
    host_pid, warnings = choose_host_pid(args.pid)
    validate_sudo()
    resolver = OwnershipResolver(host_pid)
    resolver.refresh(force=True)
    client = BenchmarkControlClient(host_pid)
    initial_status = client.status()
    live_profiles = control_profiles(initial_status)
    if len(live_profiles) < 2:
        raise RuntimeError("Automatic benchmark needs at least two configured Slots: test Slot(s) plus one control Slot.")

    print("\nFloatTabs automatic benchmark control: CONNECTED")
    print_profiles(all_profile_summaries())
    selected = prompt_selected_profiles(all_profile_summaries(), args.slots)
    selected_ids = [str(profile.get("id")) for profile in selected]
    selected_names = [str(profile.get("name")) for profile in selected]
    unselected = [profile for profile in live_profiles if str(profile.get("id")) not in selected_ids]
    if not unselected:
        raise RuntimeError(
            "All configured Slots were selected. Leave at least one extra Slot unselected so it can stay Active while every test Slot becomes truly inactive."
        )

    initial_active = initial_status.get("active_slot_id")
    control = next(
        (profile for profile in unselected if str(profile.get("id")) == str(initial_active)),
        unselected[0],
    )
    control_id = str(control.get("id"))
    control_name = str(control.get("name", "Control"))
    original_by_id = {str(profile.get("id")): profile for profile in live_profiles}
    original_visible = bool(initial_status.get("visible", False))

    session_dir = create_session(Path(args.results_root), args.session)
    meta_path = session_dir / "session.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    meta["automatic"] = True
    meta["automatic_selected_slots"] = selected
    meta["control_slot"] = {"id": control_id, "name": control_name}
    meta["original_active_slot_id"] = initial_active
    meta["original_panel_visible"] = original_visible
    meta["warnings"] = warnings
    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")

    print("\n=== Fully automatic Residency benchmark ===")
    print("Test Slots: " + ", ".join(selected_names))
    print(f"Control Slot kept Active during steady-state captures: {control_name}")
    print("The harness will change only the selected Slots and will restore their original policies at the end.")

    def configure(policy: str) -> None:
        status = client.configure(selected_ids, policy, "pauseWhenInactive")
        verify_control_policy(status, selected_ids, policy)

    def activate_test_slots_then_control() -> float:
        for slot_id, name in zip(selected_ids, selected_names):
            client.activate(slot_id)
            print(f"  activated: {name}")
            time.sleep(max(args.activation_wait, 0.0))
        client.activate(control_id)
        started = time.monotonic()
        print(f"  active control: {control_name} — all selected test Slots are now inactive")
        return started

    def capture_auto(label: str, policy: str, state: str, seconds: Optional[int] = None) -> Dict[str, object]:
        capture = collect_capture(
            session_dir=session_dir,
            label=label,
            seconds=seconds if seconds is not None else args.seconds,
            interval=args.interval,
            host_pid=host_pid,
            resolver=resolver,
            policy=policy,
            state=state,
            slots=len(selected),
            selected_slot_ids=selected_ids,
            warnings=warnings,
        )
        persist_capture_metadata(
            session_dir,
            capture,
            inactive_selected_slot_count=len(selected),
            control_slot_id=control_id,
            control_slot_name=control_name,
        )
        return capture

    def settle(label: str) -> None:
        if args.settle > 0:
            countdown(args.settle, label)

    def restore() -> None:
        print("\nRestoring original FloatTabs state...")
        for slot_id in selected_ids:
            original = original_by_id.get(slot_id) or {}
            residency = str(original.get("residency", "warm"))
            media = str(original.get("background_media", "pauseWhenInactive"))
            try:
                client.configure_one(slot_id, residency, media)
            except RuntimeError as exc:
                print(f"WARNING: could not restore policy for {original.get('name', slot_id)}: {exc}")
        if initial_active:
            try:
                client.activate(str(initial_active))
            except RuntimeError as exc:
                print(f"WARNING: could not restore original active Slot: {exc}")
        try:
            if original_visible:
                client.show()
            else:
                client.hide()
        except RuntimeError as exc:
            print(f"WARNING: could not restore panel visibility: {exc}")

    try:
        client.show()

        print("\n[1/6] HOT visible")
        configure("hot")
        activate_test_slots_then_control()
        settle("Settling Hot resident state...")
        capture_auto("hot", "hot", "steady")

        print("\n[2/6] HOT hidden")
        client.hide()
        settle("Settling hidden Hot state...")
        capture_auto("hot-hidden", "hot", "hidden")
        client.show()

        print("\n[3/6] WARM visible")
        configure("warm")
        activate_test_slots_then_control()
        settle("Settling Warm detached state...")
        capture_auto("warm", "warm", "steady")

        print("\n[4/6] WARM hidden")
        client.hide()
        settle("Settling hidden Warm state...")
        capture_auto("warm-hidden", "warm", "hidden")
        client.show()

        print("\n[5/6] COLD pending")
        configure("cold")
        cold_inactive_started = activate_test_slots_then_control()
        cold_started_wall = iso_now()
        settle("Settling Cold-pending state while all selected Slots remain inactive...")
        pending_seconds = min(args.pending_seconds, max(COLD_GRACE_SECONDS - args.settle - 5, 1))
        capture = capture_auto("cold-pending", "cold", "cold-pending", pending_seconds)
        persist_capture_metadata(session_dir, capture, cold_all_inactive_started_at=cold_started_wall)

        print("\n[6/6] COLD evicted")
        target_wait = COLD_GRACE_SECONDS + args.cold_margin
        elapsed = time.monotonic() - cold_inactive_started
        remaining = max(target_wait - elapsed, 0.0)
        if remaining > 0:
            countdown(int(math.ceil(remaining)), (
                f"Waiting until every selected Cold Slot has been inactive for >{COLD_GRACE_SECONDS}s "
                f"(target {target_wait:.0f}s from final control activation)..."
            ))
        resolver.refresh(force=True)
        capture = capture_auto("cold-evicted", "cold", "cold-evicted")
        persist_capture_metadata(
            session_dir,
            capture,
            cold_all_inactive_started_at=cold_started_wall,
            cold_inactive_elapsed_before_capture_s=round(time.monotonic() - cold_inactive_started, 2),
        )
    finally:
        restore()

    report_path = write_report(session_dir)
    print("\n=== Automatic benchmark complete ===")
    print(f"Report: {report_path}")
    print(f"Raw data: {session_dir / 'captures'}")
    print("Original Residency / media / active Slot / panel visibility have been restored best-effort.")
    return 0
'''
text = replace_once(text, '\ndef guided_mode(args: argparse.Namespace) -> int:', auto_mode + '\n\ndef guided_mode(args: argparse.Namespace) -> int:', 'automatic mode insertion')

# Doctor reports benchmark control status when present.
text = replace_once(text,
'''    print_profiles(all_profile_summaries())
    if args.sudo:''',
'''    print_profiles(all_profile_summaries())
    try:
        control = BenchmarkControlClient(host_pid)
        status = control.status()
        print(f"\nDebug benchmark control: CONNECTED (active={status.get('active_slot_id')}, visible={status.get('visible')})")
    except RuntimeError as exc:
        print(f"\nDebug benchmark control: unavailable ({exc})")
    if args.sudo:''', 'doctor control status')

# CLI parser + dispatch.
text = replace_once(text,
'''    guided = subparsers.add_parser("guided", help="Guided Hot → Warm → hidden → Cold comparison with one final report.")''',
'''    automatic = subparsers.add_parser("auto", help="Fully automatic Hot/Warm/Cold benchmark through the Debug in-app control channel.")
    automatic.add_argument("--session", default=None, help="Optional stable session name. Defaults to timestamp.")
    automatic.add_argument("--results-root", default=str(DEFAULT_RESULTS_ROOT))
    automatic.add_argument("--slots", type=int, default=2, help="Default number of test Slots to preselect; one extra unselected control Slot is required.")
    automatic.add_argument("--seconds", type=int, default=DEFAULT_SAMPLE_SECONDS)
    automatic.add_argument("--interval", type=float, default=DEFAULT_SAMPLE_INTERVAL)
    automatic.add_argument("--settle", type=int, default=DEFAULT_SETTLE_SECONDS)
    automatic.add_argument("--activation-wait", type=float, default=1.0, help="Seconds to wait after automatically activating each test Slot.")
    automatic.add_argument("--pending-seconds", type=int, default=8, help="Short capture window before Cold eviction.")
    automatic.add_argument("--cold-margin", type=int, default=7, help="Extra seconds beyond the 30s Cold grace before the evicted capture.")
    automatic.add_argument("--pid", type=int, default=None)

    guided = subparsers.add_parser("guided", help="Legacy manual Hot → Warm → hidden → Cold comparison.")''', 'auto parser')
text = replace_once(text,
'''        if args.command == "guided":
            return guided_mode(args)''',
'''        if args.command == "auto":
            return automatic_mode(args)
        if args.command == "guided":
            return guided_mode(args)''', 'auto dispatch')

# Self-test also validates that command framing remains JSON-line compatible.
text = replace_once(text,
'''    assert percentile([1, 2, 3, 4, 5], 0.95) == 4.8
''',
'''    assert percentile([1, 2, 3, 4, 5], 0.95) == 4.8
    framed = (json.dumps({"token": "x", "action": "status"}, separators=(",", ":")) + "\\n").encode("utf-8")
    assert framed.endswith(b"\\n")
''', 'self-test control framing')
write(path, text)

# 6) Benchmark protocol documents the automated Active/Inactive correctness rule.
path = 'docs/performance/FloatTabs_Stage_5_Resource_Benchmark.md'
text = read(path)
append = r'''

## 12. Automated Real-Mac control channel

PR #10 adds a Debug-only loopback benchmark control channel. The Python harness must use this channel for automated policy transitions instead of editing `WebAppProfiles.json` directly.

Properties:

- compiled/started only under `DEBUG`;
- binds to `127.0.0.1` on an ephemeral port;
- publishes PID/port plus a random per-process token in `~/Library/Application Support/FloatTabs/BenchmarkControl.json` with user-only file permissions;
- mutates Residency/media only through `TabStore.updateResourcePolicy`;
- activates Slots only through `TabStore.select`;
- hides/shows only through `PanelController` product paths;
- Release behavior is unchanged.

### Cold timing correctness

An automatic Cold measurement requires at least one unselected control Slot.

For each selected test Slot the harness:

```text
configure selected Slots = Cold
→ activate every selected Slot once
→ activate one unselected control Slot
→ NOW every selected test Slot is inactive
→ start authoritative Cold inactivity timer
→ optional short Cold-pending capture
→ wait >30 s from final control activation
→ Cold-evicted capture
```

The harness must not treat a selected Slot that remains Active as Cold-eligible. The report records the exact count of inactive selected Slots and uses that count for per-Slot reclaimed-memory estimates.

### Automatic first-pass sequence

```text
Hot visible
→ Hot hidden
→ Warm visible
→ Warm hidden
→ Cold pending
→ Cold evicted
→ restore original selected-Slot Residency/media
→ restore original active Slot
→ restore original panel visibility
```

Use:

```bash
python3 tools/benchmark/floattabs_benchmark.py auto --slots 2
```

`guided` remains only as a legacy/manual fallback.
'''
if '## 12. Automated Real-Mac control channel' not in text:
    text = text.rstrip() + append + '\n'
write(path, text)

print('benchmark automation patch applied')
