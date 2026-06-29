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

    // MARK: - Private State (per-source tracking)

    private var cancellables = Set<AnyCancellable>()
    private let server: HookSocketServer
    private var claudeState = SessionState()
    private var codexState = SessionState()

    // MARK: - Initializer

    init(server: HookSocketServer = .shared) {
        self.server = server

        server.eventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.processEvent(event)
            }
            .store(in: &cancellables)
    }

    // MARK: - Event Processing

    private func processEvent(_ event: HookEvent) {
        let source = event.source

        // If the active source is showing an approval prompt and this event is
        // from the *other* source, don't clobber the approval UI — just update
        // the other source's internal state silently.
        if source != activeSource && currentPhase.isWaitingForApproval {
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
                state.phase = .waitingForInput
                state.toolCount = 0

            case "waiting_for_response":
                state.phase = .waitingForResponse(event.message)
                // No auto-dismiss — persists until next event

            case "waiting_for_approval":
                let context = PermissionContext(
                    toolUseId: event.toolUseId ?? "",
                    toolName: event.tool ?? "unknown",
                    toolInput: event.toolInput,
                    receivedAt: Date()
                )
                state.phase = .waitingForApproval(context)

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
            scheduleAutoDismiss(for: source, after: 5.0)
        default:
            if event.event == "StopFailure" {
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

        // Reset current source's phase to idle
        updateState(activeSource) { state in
            state.phase = .idle
        }

        // If the other source also has a pending approval, switch to it
        let otherSource = activeSource == "codex" ? "claude" : "codex"
        let otherState = otherSource == "codex" ? codexState : claudeState
        if otherState.phase.isWaitingForApproval {
            activeSource = otherSource
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

    // MARK: - Private Helpers

    /// Resets the current source's state (not both sources).
    private func resetSession() {
        cancelAutoDismiss(for: activeSource)
        updateState(activeSource) { state in
            state = SessionState()
        }
        syncPublishedProperties()
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
