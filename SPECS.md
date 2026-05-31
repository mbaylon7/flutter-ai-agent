# Updated App Flow & Agent Connection Specifications

## Objective

Revise the current application flow to support optional agent setup while keeping the core speech-to-text functionality operational even without a connected agent.

---

# 1. Post-Login Onboarding Flow

After successful login:

- Do not immediately redirect the user to the Home Screen.
- Show a dedicated **Onboarding Screen** first.

The onboarding screen should explain that users can optionally connect their own agent.

---

# 2. Onboarding Form Inputs

The onboarding screen must contain the following inputs only:

1. Agent URL
2. Port
3. Token

Buttons:

- Connect
- Skip

---

# 3. Skip Onboarding Support

Users must be allowed to skip onboarding.

If the user taps **Skip**:

- Redirect directly to the Home Screen
- Do not trigger any pairing or connection process
- App should still remain usable

---

# 4. Pairing / Connection Logic

Pairing or connection should only happen when:

- The user provides valid agent credentials
- The user taps the Connect button

No automatic pairing should occur during:

- Login
- App startup
- Skip flow

---

# 5. Behavior Without Connected Agent

If the user skipped onboarding or has no connected agent:

- Speech-to-text functionality should still work
- Voice transcription should still process normally
- AI response generation should be disabled

Instead of generating a response, the app should display:

> "Please connect to your agent"

---

# 6. Agent Setup via Settings

Users who skipped onboarding must still be able to connect later.

Inside Settings:

- Add an "Agent Setup" section
- Reuse the same 3 onboarding inputs:
  - URL
  - Port
  - Token

Buttons:

- Connect
- Disconnect (optional if already connected)

When Connect is tapped:

- Start pairing/connection immediately
- No app restart required

---

# 7. Connection Status Feedback

The app must display clear status messages during connection attempts.

Success Examples:

- "Agent connected successfully"
- "Connection established"

Error Examples:

- "Unable to connect to agent"
- "Invalid connection details"
- "Connection timeout"

Avoid displaying raw technical/server errors directly to users.

---

# 8. Loading State During Connection

Add a loading/progress state while connecting to the agent.

Examples:

- Disable Connect button temporarily
- Show loading spinner
- Display message:
  - "Connecting to agent..."
  - "Establishing secure connection..."

This prevents multiple connection attempts and improves UX.

---

# 9. Logout Placement

Add the Logout button inside the Settings screen.

Requirements:

- Clearly visible
- Text-based button is acceptable
- Must properly clear:
  - Session
  - Tokens
  - Cached agent connection state

After logout:

- Redirect user back to Login Screen

---

# 10. Error Handling & Debugger System

The app should not rely on AI-generated responses for internal app errors.

Instead:

- Add a proper internal error handler/debugger system
- Errors should be logged internally for debugging
- User-facing errors should be simplified and readable

Example:
Instead of:

> "SocketException: Failed host lookup..."

Display:

> "Network connection failed"

Or:

> "Something went wrong while connecting"

---

# 11. UX Goals

Primary UX goals for this update:

- Remove forced pairing flow
- Allow users to use the app without an agent
- Make agent connection optional
- Improve onboarding experience
- Improve connection transparency
- Improve error handling and app stability
