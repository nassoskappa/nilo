# Nilo

Nilo is a native assistant for Apple devices that finishes whole jobs across apps, and shows its plan before it acts. Tagline: "Blink, and it's done." It is sold once, with no subscription.

The owner is a product designer, not an iOS engineer. Explain choices in plain words, keep steps small, and make every sitting end with something that runs.

## How to work in this repo

- Read this file first, every session.
- Plan before code. Write the plan in a few lines, wait for a yes, then build.
- One task per sitting. Tasks come from the build plan (see "Phases").
- Build and run before you say it's done. Say how to test it by hand.
- Small commits with clear messages. Never commit secrets.
- When a decision is made twice, add it here.

## Commands

```bash
brew install xcodegen          # once
xcodegen generate              # after any change to project.yml or new files
open Nilo.xcodeproj
cd Packages/NiloKit && swift test
```

`Nilo.xcodeproj` is generated. Never edit it by hand: edit `project.yml` and regenerate.

## Layout

```
project.yml                     XcodeGen spec: Nilo-macOS, Nilo-iOS
Packages/NiloKit/
  Sources/NiloCore/             models, tools, approvals, memory. No UI.
  Sources/NiloUI/               brand, MarkView, Wordmark, shared SwiftUI
  Tests/NiloCoreTests/          Swift Testing
Apps/macOS/                     Mac app (menu bar, later the notch panel)
Apps/iOS/                       iPhone and iPad app
```

Platforms: macOS 26, iOS 26 and later, Swift 6 with strict concurrency, SwiftUI only. Watch and Apple TV come after the first TestFlight.

## Architecture rules

- **Providers.** Every model sits behind `ModelProvider`. Three providers: `onDevice` (Apple Foundation Models, free), `claudeOwnKey` (user's API key, v1), `claudeCredits` (our proxy, later). The UI never knows which one answered.
- **Router.** On-device first. Escalate to Claude for multi-step jobs, long documents, writing sent as the user, or low confidence. No key: stay on device and say once what Claude would add. Rules live in one plain table in code.
- **Tools.** Each action is one `AssistantTool`, defined once in NiloKit and exposed as a Claude tool, a Foundation Models tool and an App Intent. Every job gets App Shortcut phrases starting "Ask Nilo to…".
- **Approvals.** Providers never run actions. The app runs them through `ApprovalPolicy`. `.read` runs at once, `.change` shows a preview with undo, `.send` and `.delete` always ask and show the exact text, recipients or items. No setting lowers this.
- **Memory.** SwiftData on device, synced with the CloudKit private database. Only the few relevant lines go to Claude. Nothing is learned silently: learned items are proposed and saved only on yes. Every item is visible and deletable in Settings.
- **Keys and privacy.** The API key lives in the Keychain only, synced with iCloud Keychain. Never log it, never put it in analytics or crash reports. We run no servers in v1.

## Platform limits (do not try to work around these)

- Messages and WhatsApp can't be sent silently: open the compose sheet or a prefilled link, the user taps Send.
- EventKit can't invite people. Real invitations go through the Google Calendar API; on iCloud calendars the heads-up message carries the details.
- Apple Mail has no reading API. Read Gmail via its API and iCloud Mail via IMAP (app-specific password in the Keychain).
- Messenger and other chat apps: share sheet only.
- Cross-app file search is Mac only (Spotlight). iPhone searches iCloud Drive.

## Brand rules

- **Colour.** Signature cyan `#4EF2E5`, "needs you" tint `#A6FAF3`, light mode `#00807A`, text on cyan `#041413`. Bright cyan only ever touches black. On glass or light surfaces the mark sits in a black capsule; buttons and links use `#00807A`. Where Apple sets the tint (menu bar, tinted icons, Lock Screen widgets) the mark is monochrome. Use `NiloColor`, never raw hex in views.
- **The mark.** A small cursor bar with seven states: idle, listening, thinking, working, needs you, done, noted. Motion carries the state; colour never changes hue. Use `MarkView`.
- **Type.** SF Pro for everything people read, approve or tap, with Dynamic Type. SF Mono (`NiloFont.mono`) only for state labels, counters, timestamps and the wordmark.
- **Icons.** SF Symbols, and only where removing the icon would make something harder to find or understand.
- **Accessibility.** Every control is a real button with a label. VoiceOver reads the mark's state. Sounds and haptics match each state.

## Voice

Short sentences, plain words, lead with the result. "Done. Thursday's clear after 2pm." Say what's next once, then wait. No exclamation marks in errors, no jokes in approvals. Never: "Certainly!", "As an AI…", emoji in system copy. In marketing copy never mention Siri by name, except in "Ask Nilo to…" phrases.

## The five jobs (v1)

1. Add a meeting and send people a heads-up.
2. Reschedule a meeting and tell people why.
3. Turn an email into actions, reminders and messages to others.
4. Find the file worked on a given day; share as file or iCloud link.
5. Summarise unread mail since yesterday, then offer job 3.

## Phases

- [x] 0. Setup: this repo
- [ ] 1. Motion prototype: the mark in a notch panel, mic-driven listening, hotkey cycles states
- [ ] 2. Mac core: tools for calendar, contacts, Messages, WhatsApp; on-device router; plan card; jobs 1 and 2
- [ ] 3. Claude own-key provider, spend meter, memory
- [ ] 4. Mail: Gmail, iCloud IMAP, reminders, Google invites; jobs 5 and 3
- [ ] 5. Files: Spotlight, iCloud links; job 4
- [ ] 6. Mac TestFlight
- [ ] 7. iPhone app into the same beta
- [ ] 8. Safari Web Extension and share extension, inside the Nilo app (Mac and iPhone)

Target: Mac TestFlight in the week of 5 April 2027, iPhone in the week of 17 May 2027, Safari and share sheet by early June 2027.

Not now: a standalone Nilo browser. Revisit only if people use Nilo most while browsing.
