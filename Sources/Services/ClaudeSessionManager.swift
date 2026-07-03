import Foundation
import Combine

/// Manages Claude Code / Codex CLI session state by subscribing to HookSocketServer events
/// and mapping them to observable session phases for UI binding.
///
/// Supports two independent sessions ("claude" and "codex") tracked via separate
/// `SessionState` structs.  The `@Published` properties always reflect the *active*
/// source — the one most recently surfaced to the user.
class ClaudeSessionManager: ObservableObject {

    // MARK: - Published Properties (reflect the ACTIVE source's state)

    @Published var currentPhase: ClaudeSessionPhase = .idle
    @Published var activeSessionId: String? = nil
    @Published var projectName: String? = nil
    @Published var lastToolName: String? = nil
    @Published var isSubagentActive: Bool = false
    @Published var activeSource: String = "claude"
    @Published var toolCount: Int = 0
    @Published var activeSessionCount: Int = 0
    @Published var pendingApprovalCount: Int = 0
    let eventQueue = EventQueueManager()

    // MARK: - Private State (per-source tracking)

    private var cancellables = Set<AnyCancellable>()
    private let server: HookSocketServer
    private var claudeState = SessionState()
    private var codexState = SessionState()
    private var activeSessions: Set<String> = []
    private var waitingForInputWorkItems: [String: DispatchWorkItem] = [:]

    // MARK: - Initializer

    init(server: HookSocketServer = .shared) {
        self.server = server

        server.eventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.processEvent(event)
            }
            .store(in: &cancellables)

        eventQueue.$pendingCount
            .receive(on: DispatchQueue.main)
            .assign(to: &$pendingApprovalCount)
    }

    // MARK: - Event Processing

    private func processEvent(_ event: HookEvent) {
        // Track active sessions
        if !event.sessionId.isEmpty && event.sessionId != "unknown" {
            if event.status == "ended" {
                activeSessions.remove(event.sessionId)
            } else {
                activeSessions.insert(event.sessionId)
            }
            activeSessionCount = activeSessions.count
        }

        let source = event.source

        // If this is an approval request and we're already showing one, enqueue it
        if event.status == "waiting_for_approval" && currentPhase.isWaitingForApproval {
            // Build the context for queuing
            let context = PermissionContext(
                toolUseId: event.toolUseId ?? "",
                toolName: event.tool ?? "unknown",
                toolInput: event.toolInput,
                suggestions: event.permissionSuggestions,
                receivedAt: Date()
            )
            let projName = URL(fileURLWithPath: event.cwd).lastPathComponent
            eventQueue.enqueue(source: source, context: context, projectName: projName)
            // Still update the internal state (tool count etc) but don't change phase
            updateInternalStateWithoutPhase(for: source, event: event)
            return
        }

        // If the active source is showing an approval prompt or question and this event is
        // from the *other* source, don't clobber the UI — just update
        // the other source's internal state silently.
        if source != activeSource && (currentPhase.isWaitingForApproval || currentPhase.isAskingQuestion) {
            updateInternalState(for: source, event: event)
            return
        }

        // Otherwise, make this source active and update its state.
        activeSource = source
        updateInternalState(for: source, event: event)
        syncPublishedProperties()
    }

    // MARK: - Internal State Update

    /// Updates the `SessionState` for the given source ("claude" or "codex") based
    /// on the incoming hook event.
    private func updateInternalState(for source: String, event: HookEvent) {
        // Cancel any pending auto-dismiss for this source.
        cancelAutoDismiss(for: source)

        updateState(source) { state in
            // Session metadata
            state.sessionId = event.sessionId
            state.projectName = URL(fileURLWithPath: event.cwd).lastPathComponent
            if let tool = event.tool {
                state.lastToolName = tool
            }

            // Subagent tracking
            if event.event == "SubagentStart" {
                state.isSubagentActive = true
            } else if event.event == "SubagentStop" {
                state.isSubagentActive = false
            }

            // Map event status to session phase + tool count
            switch event.status {
            case "processing":
                state.phase = .processing

            case "running_tool":
                state.phase = .processing
                state.toolCount += 1

            case "waiting_for_input":
                // Don't set phase immediately — delay 3s to confirm agent truly stopped
                // (agent may continue with next tool call)
                state.toolCount = 0

            case "waiting_for_response":
                state.phase = .waitingForResponse(event.message)

            case "waiting_for_approval":
                let context = PermissionContext(
                    toolUseId: event.toolUseId ?? "",
                    toolName: event.tool ?? "unknown",
                    toolInput: event.toolInput,
                    suggestions: event.permissionSuggestions,
                    receivedAt: Date()
                )
                state.phase = .waitingForApproval(context)

            case "asking_question":
                if let toolInput = event.toolInput,
                   let questionsValue = toolInput["questions"]?.value as? [[String: Any]] {
                    let items = questionsValue.compactMap { dict -> QuestionItem? in
                        guard let question = dict["question"] as? String else { return nil }
                        let header = dict["header"] as? String
                        let multiSelect = dict["multiSelect"] as? Bool ?? false
                        var options: [QuestionOption]? = nil
                        if let optArr = dict["options"] as? [[String: Any]] {
                            options = optArr.compactMap { opt in
                                guard let label = opt["label"] as? String else { return nil }
                                return QuestionOption(label: label, description: opt["description"] as? String)
                            }
                        }
                        return QuestionItem(question: question, header: header, options: options, multiSelect: multiSelect)
                    }
                    let context = QuestionContext(
                        toolUseId: event.toolUseId ?? "",
                        questions: items,
                        receivedAt: Date()
                    )
                    state.phase = .askingQuestion(context)
                } else {
                    // Fallback: treat as a simple question with message text
                    let item = QuestionItem(
                        question: event.message ?? "Question",
                        header: nil,
                        options: nil,
                        multiSelect: false
                    )
                    let context = QuestionContext(
                        toolUseId: event.toolUseId ?? "",
                        questions: [item],
                        receivedAt: Date()
                    )
                    state.phase = .askingQuestion(context)
                }

            case "compacting":
                state.phase = .compacting

            case "ended":
                state = SessionState()

            default:
                // Handle StopFailure event
                if event.event == "StopFailure" {
                    state.phase = .error(event.message ?? "Unknown error")
                }
            }
        }

        // Schedule auto-dismiss if needed (outside the updateState closure to
        // avoid re-entrant mutation).
        switch event.status {
        case "waiting_for_input":
            // Delayed notification: only show "task complete" if no new event arrives within 3s
            waitingForInputWorkItems[source]?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.updateState(source) { state in
                    // Only transition if still not processing (agent didn't resume)
                    if state.phase == .processing || state.phase == .idle {
                        state.phase = .waitingForInput
                    }
                }
                if source == self.activeSource {
                    self.syncPublishedProperties()
                }
                // Auto-dismiss 5s after confirmed notification
                self.scheduleAutoDismiss(for: source, after: 5.0)
            }
            waitingForInputWorkItems[source] = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
        case "waiting_for_response":
            waitingForInputWorkItems[source]?.cancel()  // Cancel pending "task complete" if response needed
            waitingForInputWorkItems[source] = nil
            scheduleAutoDismiss(for: source, after: 10.0)
        default:
            waitingForInputWorkItems[source]?.cancel()  // Cancel pending "task complete" on any other event
            waitingForInputWorkItems[source] = nil
            // Auto-dismiss any error state (StopFailure or other errors)
            let currentState = source == "codex" ? codexState : claudeState
            if case .error = currentState.phase {
                scheduleAutoDismiss(for: source, after: 5.0)
            }
        }
    }

    // MARK: - Sync Published Properties

    /// Syncs all `@Published` properties to reflect the active source's `SessionState`.
    private func syncPublishedProperties() {
        let state = activeSource == "codex" ? codexState : claudeState
        currentPhase = state.phase
        activeSessionId = state.sessionId
        projectName = state.projectName
        lastToolName = state.lastToolName
        toolCount = state.toolCount
        isSubagentActive = state.isSubagentActive
    }

    // MARK: - Public Methods

    /// Approve the current pending permission request
    func approvePermission() {
        guard case .waitingForApproval(let context) = currentPhase else { return }
        server.respondToPermission(toolUseId: context.toolUseId, decision: "allow", reason: nil)

        // Try to pop next from queue
        if let next = eventQueue.popNext() {
            // Switch to next queued approval
            activeSource = next.source
            updateState(next.source) { state in
                state.phase = .waitingForApproval(next.context)
                if let proj = next.projectName {
                    state.projectName = proj
                }
            }
        } else {
            // No more pending — return to processing
            updateState(activeSource) { state in
                state.phase = .processing
            }
        }

        syncPublishedProperties()
    }

    /// Approve with "always allow" — sends updatedPermissions back so agent persists the rule
    func approvePermissionAlways() {
        guard case .waitingForApproval(let context) = currentPhase else { return }
        server.respondToPermission(
            toolUseId: context.toolUseId,
            decision: "allow",
            reason: nil,
            updatedPermissions: context.suggestions
        )

        // Reset current source's phase to processing
        updateState(activeSource) { state in
            state.phase = .processing
        }

        // If the other source also has a pending approval, switch to it
        let otherSource = activeSource == "codex" ? "claude" : "codex"
        let otherState = otherSource == "codex" ? codexState : claudeState
        if otherState.phase.isWaitingForApproval {
            activeSource = otherSource
        }

        syncPublishedProperties()
    }

    /// Deny the current pending permission request
    func denyPermission(reason: String? = nil) {
        guard case .waitingForApproval(let context) = currentPhase else { return }
        server.respondToPermission(toolUseId: context.toolUseId, decision: "deny", reason: reason)

        // Try to pop next from queue
        if let next = eventQueue.popNext() {
            // Switch to next queued approval
            activeSource = next.source
            updateState(next.source) { state in
                state.phase = .waitingForApproval(next.context)
                if let proj = next.projectName {
                    state.projectName = proj
                }
            }
        } else {
            // No more pending — return to processing
            updateState(activeSource) { state in
                state.phase = .processing
            }
        }

        syncPublishedProperties()
    }

    /// Dismiss any notification and return to idle
    func dismissNotification() {
        cancelAutoDismiss(for: activeSource)
        updateState(activeSource) { state in
            state.phase = .idle
        }
        syncPublishedProperties()
    }

    /// Answer the current pending question
    func answerQuestion(answers: [String: String]) {
        guard case .askingQuestion(let context) = currentPhase else { return }
        server.respondToQuestion(toolUseId: context.toolUseId, answers: answers)

        // Return to processing
        updateState(activeSource) { state in
            state.phase = .processing
        }
        syncPublishedProperties()
    }

    // MARK: - Private Helpers

    /// Updates metadata for a source without changing the phase (used when enqueuing).
    private func updateInternalStateWithoutPhase(for source: String, event: HookEvent) {
        updateState(source) { state in
            state.sessionId = event.sessionId
            state.projectName = URL(fileURLWithPath: event.cwd).lastPathComponent
            if let tool = event.tool {
                state.lastToolName = tool
            }
            if event.event == "SubagentStart" {
                state.isSubagentActive = true
            } else if event.event == "SubagentStop" {
                state.isSubagentActive = false
            }
        }
    }

    /// Schedules an auto-dismiss for the given source.
    private func scheduleAutoDismiss(for source: String, after seconds: TimeInterval) {
        cancelAutoDismiss(for: source)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.updateState(source) { state in
                state.phase = .idle
                state.autoDismissWorkItem = nil
            }
            // Only sync if this source is still the active one
            if source == self.activeSource {
                self.syncPublishedProperties()
            }
        }

        updateState(source) { state in
            state.autoDismissWorkItem = workItem
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
    }

    /// Cancels any pending auto-dismiss for the given source.
    private func cancelAutoDismiss(for source: String) {
        updateState(source) { state in
            state.autoDismissWorkItem?.cancel()
            state.autoDismissWorkItem = nil
        }
    }

    /// Helper to mutate the `SessionState` for a given source.
    private func updateState(_ source: String, _ transform: (inout SessionState) -> Void) {
        if source == "codex" {
            transform(&codexState)
        } else {
            transform(&claudeState)
        }
    }
}
