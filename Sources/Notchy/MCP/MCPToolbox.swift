import Foundation

/// JSON-RPC / MCP request handling and the tools exposed to AI agents.
/// Calendar tools are read-only, mirroring the app's own guarantees.
@MainActor
final class MCPToolbox {
    struct ToolError: Error { let message: String }

    static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    var onClientInitialized: ((String, String) -> Void)?
    var onRequest: ((String?) -> Void)?

    private let store: Store
    private let timer: FocusTimer
    private let calendar: CalendarService
    private var lastClientName: String?

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    init(store: Store, timer: FocusTimer, calendar: CalendarService) {
        self.store = store
        self.timer = timer
        self.calendar = calendar
    }

    // MARK: JSON-RPC

    func handle(_ data: Data) -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return encode(rpcError(id: NSNull(), code: -32700, message: "Parse error"))
        }
        if let batch = json as? [Any] {
            let responses = batch.compactMap { handleMessage($0) }
            return responses.isEmpty ? nil : encode(responses)
        }
        return handleMessage(json).flatMap { encode($0) }
    }

    private func handleMessage(_ message: Any) -> [String: Any]? {
        guard let message = message as? [String: Any] else {
            return rpcError(id: NSNull(), code: -32600, message: "Invalid request")
        }
        guard let id = message["id"], !(id is NSNull) else { return nil }
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]
        onRequest?(lastClientName)

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            let version = Self.supportedProtocolVersions.contains(requested) ? requested : Self.supportedProtocolVersions[0]
            if let info = params["clientInfo"] as? [String: Any] {
                let name = info["name"] as? String ?? "Unknown client"
                lastClientName = name
                onClientInitialized?(name, info["version"] as? String ?? "")
            }
            return rpcResult(id: id, [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "notchy", "title": AppInfo.name, "version": AppInfo.version],
                "instructions": "HappyNotch is the user's local task list, focus timer, daily notepad and read-only calendar. Dates are ISO 8601 in the user's time zone. add_task understands natural language like 'call mom tomorrow at 5pm'.",
            ])
        case "ping":
            return rpcResult(id: id, [:])
        case "tools/list":
            return rpcResult(id: id, ["tools": Self.toolDefinitions])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                let value = try call(name, arguments)
                return rpcResult(id: id, ["content": [["type": "text", "text": jsonString(value)]], "isError": false])
            } catch let error as ToolError {
                return rpcResult(id: id, ["content": [["type": "text", "text": error.message]], "isError": true])
            } catch {
                return rpcResult(id: id, ["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
            }
        default:
            return rpcError(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: Tools

    private func call(_ name: String, _ args: [String: Any]) throws -> Any {
        let cal = Calendar.current
        switch name {
        case "list_tasks":
            let status = args["status"] as? String ?? "open"
            var items = store.tasks
            switch status {
            case "completed": items = items.filter(\.isCompleted)
            case "all": break
            default: items = items.filter { !$0.isCompleted }
            }
            if let dateString = args["date"] as? String {
                guard let day = parseDay(dateString) else { throw ToolError(message: "`date` must be YYYY-MM-DD") }
                items = items.filter { $0.dueDate.map { cal.isDate($0, inSameDayAs: day) } ?? false }
            }
            return items.sorted { $0.sortIndex < $1.sortIndex }.map(taskJSON)

        case "add_task":
            guard let text = (args["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                throw ToolError(message: "`text` is required")
            }
            guard let task = store.addTask(text: text) else { throw ToolError(message: "Couldn't create a task from that text") }
            if let notes = args["notes"] as? String { store.updateTask(task.id) { $0.notes = notes } }
            return taskJSON(store.task(task.id) ?? task)

        case "complete_task":
            let task = try requireTask(args)
            store.setCompleted(task.id, (args["completed"] as? Bool) ?? true)
            return taskJSON(store.task(task.id) ?? task)

        case "update_task":
            let task = try requireTask(args)
            store.updateTask(task.id) { t in
                if let title = args["title"] as? String, !title.isEmpty { t.title = title }
                if let notes = args["notes"] as? String { t.notes = notes }
                if let priority = args["priority"] as? String, let p = Priority.allCases.first(where: { $0.label.lowercased() == priority.lowercased() }) {
                    t.priority = p
                }
                if let due = args["due"] as? String {
                    if due.isEmpty {
                        t.dueDate = nil
                        t.hasTime = false
                    } else if let date = iso.date(from: due) {
                        t.dueDate = date
                        t.hasTime = true
                    } else if let day = parseDay(due) {
                        t.dueDate = day
                        t.hasTime = false
                    }
                }
            }
            return taskJSON(store.task(task.id) ?? task)

        case "get_notepad":
            let day = try (args["date"] as? String).map { try requireDay($0) } ?? Date()
            return ["date": DayKey.key(for: day), "text": store.note(for: day)]

        case "append_to_notepad":
            guard let text = args["text"] as? String, !text.isEmpty else { throw ToolError(message: "`text` is required") }
            let day = Date()
            let existing = store.note(for: day)
            store.setNote(existing.isEmpty ? text : existing + "\n" + text, for: day)
            return ["date": DayKey.key(for: day), "text": store.note(for: day)]

        case "list_events":
            guard calendar.hasAccess else { throw ToolError(message: "Calendar access hasn't been granted in HappyNotch.") }
            let days = min(max(args["days"] as? Int ?? 1, 1), 31)
            let start = try (args["start_date"] as? String).map { try requireDay($0) } ?? cal.startOfDay(for: Date())
            let end = cal.date(byAdding: .day, value: days, to: start) ?? start
            return calendar.fetch(from: start, to: end).map { event in
                var json: [String: Any] = [
                    "title": event.title,
                    "start": iso.string(from: event.start),
                    "end": iso.string(from: event.end),
                    "all_day": event.isAllDay,
                    "calendar": event.calendarTitle,
                ]
                if let location = event.location { json["location"] = location }
                return json
            }

        case "get_focus_status":
            return focusJSON()

        case "start_focus":
            var taskID: UUID?
            if args["task_id"] != nil { taskID = try requireTask(args).id }
            let mode: TimerMode = (args["mode"] as? String) == "stopwatch" ? .stopwatch : .countdown
            let minutes = (args["minutes"] as? Int).map { min(max($0, 1), 480) }
            timer.start(taskID: taskID, minutes: minutes ?? store.settings.defaultFocusMinutes, mode: mode)
            return focusJSON()

        case "pause_focus":
            timer.pause()
            return focusJSON()

        case "resume_focus":
            timer.resume()
            return focusJSON()

        case "stop_focus":
            timer.finish(markTaskComplete: (args["complete_task"] as? Bool) ?? false)
            return focusJSON()

        case "get_insights":
            let summary = InsightsSummary.compute(tasks: store.tasks, sessions: store.sessions)
            return [
                "current_streak_days": summary.currentStreak,
                "best_streak_days": summary.bestStreak,
                "completed_today": summary.completedToday,
                "completed_this_week": summary.completedThisWeek,
                "focus_minutes_today": Int(summary.focusMinutesToday),
                "focus_minutes_this_week": Int(summary.focusMinutesThisWeek),
                "total_completed": summary.totalCompleted,
            ]

        default:
            throw ToolError(message: "Unknown tool: \(name)")
        }
    }

    private func requireTask(_ args: [String: Any]) throws -> TaskItem {
        guard let raw = args["task_id"] as? String, let id = UUID(uuidString: raw), let task = store.task(id) else {
            throw ToolError(message: "`task_id` must be the id of an existing task (see list_tasks)")
        }
        return task
    }

    private func requireDay(_ string: String) throws -> Date {
        guard let day = parseDay(string) else { throw ToolError(message: "Dates must be YYYY-MM-DD") }
        return day
    }

    private func parseDay(_ string: String) -> Date? {
        DayKey.date(from: String(string.prefix(10)))
    }

    private func taskJSON(_ task: TaskItem) -> [String: Any] {
        var json: [String: Any] = [
            "id": task.id.uuidString,
            "title": task.title,
            "completed": task.isCompleted,
            "priority": task.priority.label.lowercased(),
            "focused_minutes": Int(task.focusedSeconds / 60),
        ]
        if !task.notes.isEmpty { json["notes"] = task.notes }
        if let due = task.dueDate { json["due"] = task.hasTime ? iso.string(from: due) : DayKey.key(for: due) }
        if let done = task.completedAt { json["completed_at"] = iso.string(from: done) }
        return json
    }

    private func focusJSON() -> [String: Any] {
        let phase: String
        switch timer.phase {
        case .idle: phase = "idle"
        case .running: phase = "running"
        case .paused: phase = "paused"
        case .finished: phase = "finished"
        }
        var json: [String: Any] = [
            "state": phase,
            "mode": timer.mode.rawValue,
            "elapsed_seconds": Int(timer.elapsed),
        ]
        if timer.mode == .countdown { json["remaining_seconds"] = Int(timer.remaining) }
        if let task = timer.task { json["task"] = taskJSON(task) }
        return json
    }

    // MARK: Encoding

    private func rpcResult(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func rpcError(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private func encode(_ value: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes])
    }

    private func jsonString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return "\(value)" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Definitions

    private static func tool(_ name: String, _ description: String, properties: [String: Any] = [:], required: [String] = [], readOnly: Bool = false) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        return [
            "name": name,
            "description": description,
            "inputSchema": schema,
            "annotations": ["readOnlyHint": readOnly],
        ]
    }

    static let toolDefinitions: [[String: Any]] = [
        tool("list_tasks", "List the user's tasks.", properties: [
            "status": ["type": "string", "enum": ["open", "completed", "all"], "description": "Defaults to open"],
            "date": ["type": "string", "description": "Only tasks due on this day (YYYY-MM-DD)"],
        ], readOnly: true),
        tool("add_task", "Add a task. Natural language dates and times in the text are parsed, e.g. 'Review PR friday at 3pm !high'.", properties: [
            "text": ["type": "string"],
            "notes": ["type": "string"],
        ], required: ["text"]),
        tool("complete_task", "Mark a task as completed (or not).", properties: [
            "task_id": ["type": "string"],
            "completed": ["type": "boolean", "description": "Defaults to true"],
        ], required: ["task_id"]),
        tool("update_task", "Update a task's title, notes, priority or due date.", properties: [
            "task_id": ["type": "string"],
            "title": ["type": "string"],
            "notes": ["type": "string"],
            "priority": ["type": "string", "enum": ["none", "low", "medium", "high"]],
            "due": ["type": "string", "description": "ISO 8601 date-time, YYYY-MM-DD for an all-day date, or empty to clear"],
        ], required: ["task_id"]),
        tool("get_notepad", "Read the daily notepad.", properties: [
            "date": ["type": "string", "description": "YYYY-MM-DD, defaults to today"],
        ], readOnly: true),
        tool("append_to_notepad", "Append a line to today's notepad.", properties: [
            "text": ["type": "string"],
        ], required: ["text"]),
        tool("list_events", "List calendar events (read-only).", properties: [
            "start_date": ["type": "string", "description": "YYYY-MM-DD, defaults to today"],
            "days": ["type": "integer", "description": "Number of days, 1-31. Defaults to 1"],
        ], readOnly: true),
        tool("get_focus_status", "Get the focus timer state.", readOnly: true),
        tool("start_focus", "Start a focus timer, optionally for a task.", properties: [
            "task_id": ["type": "string"],
            "minutes": ["type": "integer"],
            "mode": ["type": "string", "enum": ["countdown", "stopwatch"]],
        ]),
        tool("pause_focus", "Pause the running focus timer."),
        tool("resume_focus", "Resume a paused focus timer."),
        tool("stop_focus", "Stop the focus timer and log the session.", properties: [
            "complete_task": ["type": "boolean", "description": "Also mark the linked task as completed"],
        ]),
        tool("get_insights", "Productivity stats: streaks, completed tasks and focus minutes.", readOnly: true),
    ]
}
