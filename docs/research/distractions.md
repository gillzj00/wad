# Distraction research: setting off another player's phone or watch during their shot

Status: research only. Nothing here is decided. Section 8 lists the decisions the owner (@gillzj00) has to make before any of it is built. Apple's guideline text quoted below was read from the live page on 2026-10-18. Latency figures are estimates or third-party reports, never a measurement on the course, and are marked **(unverified)**; section 7 says how to measure them with what is already deployed.

## 1. Summary

- **What was asked (2026-10-18).** During a round a player can make another player's phone or watch vibrate and make a lot of noise to put them off their shot. Every player gets one free distraction a round; more can be bought, the money goes into a pot, and somebody wins the pot.
- **The hard part is the target's phone, not the message.** Phone to phone through the live relay that is already deployed ([ADR-0014](../adr/0014-live-relay-before-auth.md)) takes well under a second when the target has Wad on screen. But a player over the ball has the phone in a pocket with the screen locked, and iOS suspends Wad within seconds of it leaving the screen: the relay socket is dead until they come back. The only things that make a locked phone go off are an APNs push, which needs the paid Apple Developer Program the project is already waiting on, or an Apple Watch on the target's wrist.
- **How fast.** Relay: about 0.2 to 0.6 s one way with the phone on screen. Push: 1 to 3 s typical, a tail of ten seconds or more, never guaranteed. A watch forward adds about a second. A swing is roughly a second and a half from takeaway to impact, so a sender can hit the backswing over the relay but not over push. Design around it: a show that runs five to eight seconds and escalates, and a receipt back to the sender when it landed.
- **Sound is not ours to force.** A push makes no sound on a phone whose ringer switch is off; it still vibrates. Only Critical Alerts override the switch, and Apple grants that entitlement to health and safety apps. With Wad on screen the app can play through the speaker regardless of the switch (the `.playback` audio category) at the user's volume. On a watch the haptic lands even in silent mode; the sound does not.
- **Money: keep it in the ledger, not in in-app purchase.** Apple forbids in-app purchase of credit used in real money gaming (guideline 5.3.3), in-app purchase cannot pay anything out, and a prize pot funded by the players is consideration plus a prize, which is sweepstakes or gambling territory with state-by-state rules. Treat a bought distraction as a stake in the round's ledger, settled like Wad and Skins under [ADR-0007](../adr/0007-payments-venmo-deeplinks.md): no money through the app. If revenue is wanted, sell credits by in-app purchase with no pot attached. Never both from the same dollar.
- **Recommended plan.** Phase A now, over the relay: the free credit, ledger stakes and a pot engine; reaches phones that are on screen. Phase B after enrollment: push, which reaches locked phones and, for free, watches. Phase C, a watchOS app, only if the group wears watches and the wrist buzz from B is not enough. Section 7.

## 2. The feature as asked, and the words used here

- **Distraction**: one firing, by one sender at one target, on one hole.
- **Credit**: the right to fire once. One free credit per player per round was asked for.
- **Stake**: what a distraction beyond the free credit costs, in integer cents, set at round setup like the other game amounts.
- **Pot**: the stakes of a round, paid at settlement to whoever the pot rule names.
- **Sender** and **target**: both players in the round and in the game.

End to end: the sender picks a target; the message reaches the target's device; the device makes noise and vibrates; the sender learns that it landed; the use is recorded so that credits and the pot are right at settlement.

## 3. Reaching the target's device

### 3.1 What the target's phone is doing

At the moment of a shot the target's phone is in one of three states:

1. **Wad on screen**, in the hand or in a cart holder with the screen awake. The relay socket is open. Common in the cart, rare while actually swinging.
2. **Wad in the background or the phone locked**, in a pocket. The common case. An app with no background mode is suspended within seconds of leaving the screen, and its WebSocket dies with it; the app already assumes this (`RootView` reconnects when the scene becomes active again). Nothing sent through the relay reaches the phone until it is back on screen.
3. **Phone locked in the cart**, player thirty metres away. As 2, plus distance: even a push that rings may not be heard.

An Apple Watch changes case 2. When the iPhone is locked and the watch is worn and unlocked, iOS delivers the notification to the watch and not to the phone, so the wrist gets the haptic.

### 3.2 The paths

| Path | Target's phone | One-way delay | Sound | Vibration | Needs | Effort |
| --- | --- | --- | --- | --- | --- | --- |
| Live relay, deployed ([ADR-0014](../adr/0014-live-relay-before-auth.md)) | Wad on screen | 0.2 to 0.6 s warm; up to about 1.5 s after a Lambda cold start or on weak signal **(unverified)**; ADR-0014 says "usually well under a second" | Yes, through the speaker regardless of the ringer switch, at the user's volume | Yes, any CoreHaptics pattern | Nothing new on the server; new payload types in the app | S on the wire |
| APNs alert push | Locked, or Wad in the background | 1 to 3 s typical; a tail of 10 s or more; never guaranteed **(unverified)** | Only with the ringer on and no Focus in the way (Time Sensitive gets through Focus) | Yes, the system's alert vibration | Apple Developer Program, an APNs key, a device token registry, auth | M to L |
| Push forwarded to an Apple Watch | Phone locked, watch worn | The push delay plus about 1 s **(unverified)** | On the watch, only out of silent mode | Yes, in silent mode too; stronger with Prominent Haptic | The same as push; nothing more to build | none |
| watchOS app with a workout session | Any | 0.3 to 1 s **(unverified)** | Weak; the watch speaker | Yes, repeated haptics | A new watchOS target | L |
| Critical alert | Any | As push | Yes, overrides the switch at a volume the app sets | Yes | An entitlement Apple grants for health and safety; not for this | n/a |

### 3.3 Path notes

**Live relay (deployed).** `publish` fans the frame out to the room and the reply carries `delivered`, the number of connections it reached, so the sender knows at once whether the target's phone was listening: zero means asleep. The server stamps every delivered frame with `sentAt`, so the receiving phone can compute the one-way delay (phone clocks are NTP-synced to within tens of milliseconds **(unverified)**); a debug readout in the live feed would give real on-course numbers. Payloads are opaque to the server, so a `distraction` type needs no backend change. The room has no identities: the payload must carry the target's player id, and a following phone must know which player it is (today a follower only types a code).

**APNs alert push.** Prerequisites: Apple Developer Program membership (push is not a capability of a Personal Team, which is what the phone runs today **(unverified)**; enrollment already gates M1), an APNs authentication key (`.p8`) and a device token per phone stored against the user. The payload: an `alert`, a `sound` naming a file in the app bundle (aiff, wav or caf, at most 30 seconds), `interruption-level: time-sensitive` (the Time Sensitive Notifications capability is toggled in Xcode with no approval; it gets through a Focus unless the user has turned it off for the app), `apns-priority: 10`, `apns-push-type: alert`, and an `apns-expiration` a few seconds out so a late push is dropped instead of going off on the next hole. When Wad is on screen the push is handed to the app, which plays its own show; dedupe by distraction id so a target reached both ways plays once. Apple guarantees neither delivery nor timing. The ringer switch mutes the sound; the vibration follows the user's Vibrate on Silent setting, which is on by default.

**Critical Alerts.** The one interruption level that overrides the ringer switch and plays at a volume the app chooses. It needs an entitlement that Apple grants on application, to health, safety, security and similar apps; a prank between friends will not qualify. Not a path.

**Watch forwarding.** Comes with push for nothing. Phone locked and watch worn means the alert goes to the wrist; the haptic plays in silent mode too, Prominent Haptic makes it stronger, theater mode suppresses it. The user controls per-app mirroring in the Watch app.

**A watchOS app.** `WKInterfaceDevice.play(_:)` does nothing while the watch app is in the background unless the app is running an `HKWorkoutSession` (golf is an activity type). With one running the app runs for the whole session, can hold its own WebSocket (through the phone, or over Wi-Fi or cellular) and play repeated haptics on command. Sound in the background needs the audio background mode as well, and the watch speaker is weak. A watch runs one workout session at a time, so it would clash with a player's own Workout app round. Effort L for a new target, its UI and review scrutiny.

**Background location, a synergy and not a plan.** If hole detection ([geolocation research](geolocation.md), phases 2 and 3) ever keeps location updates running during a round, Wad is alive in the background and the relay socket survives, so Phase A would reach pocketed phones without push. The battery and review cost belong to that feature. Do not add background location for the distraction alone: guideline 2.5.4 says multitasking apps "may only use background services for their intended purposes".

**Rejected.** Silent audio to keep the app alive (the classic 2.5.4 rejection). VoIP pushes without CallKit (rejected at review). Background pushes (`content-available`): about 30 seconds of execution, throttled by the system, and no sound or haptic of their own. MultipeerConnectivity: tens of metres and foreground only, which ADR-0014 already passed on. Live Activities: an alerting update makes the same noise as an ordinary push, for more work.

### 3.4 What the device can do once the message is there

With Wad on screen (relay, or a push handed to the app):

- **Sound.** The existing `EventSoundPlayer` (`ios/Wad/Events/`) uses the `.ambient` category, which the ringer switch mutes and which mixes with other audio. A distraction wants `.playback`, which plays regardless of the switch, at the user's volume; an app cannot raise the system volume. Synthesised like the existing shows (`EventSynth`) or a bundled file. Five to eight seconds, escalating, because arrival time varies by a second or two.
- **Haptics.** `EventHaptics` already plays CoreHaptics patterns; the hole-in-one pattern runs six seconds. A distraction pattern can run as long as its sound.
- **Screen.** A full-screen `EventOverlay` show on the target ("Zach fired at you"), a toast on the other phones ("Zach fired at Pat"), and a receipt frame back through the relay so the sender sees "landed".
- **Settings.** `EventSettings.soundsEnabled` mutes the shows today. Whether joining the distraction game overrides that switch for distractions is a decision (section 8).

Locked or in the background (push): the notification's sound, at most 30 seconds and only what the file does; the system's vibration; the banner. No custom haptic and no overlay until the phone is unlocked.

### 3.5 Timing

A golf swing takes about 1 to 1.5 s from takeaway to impact, and a pre-shot routine 10 to 20 s **(unverified)**. Over the relay a sender who presses as the club starts back lands it during the swing. Over push it lands somewhere in the routine. So the design should not depend on timing:

- A long, escalating show, so that a second or two of jitter still hits something.
- An **armed** state on the sender's phone that says whether the target's phone is listening (the relay's `members` and `delivered`) or asleep (push only), so the sender knows what to expect.
- A **landed** receipt from the target's phone, and a "went to their pocket" message when only a push went out.
- A **staleness cutoff**: a distraction that reaches a phone more than a few seconds late is dropped, not played on the next hole. The relay's `sentAt` and the push's `apns-expiration` both allow it.

## 4. Credits, stakes and the pot

### 4.1 Why the pot cannot run on in-app purchase

Read from the App Store Review Guidelines on 2026-10-18:

- 3.1.1: unlocking features or functionality, "in-game currencies" among the examples, must use in-app purchase. Buying a distraction credit is a digital good, so if it is sold in the app it is sold through Apple, at Apple's 15 to 30 percent.
- 5.3.3: "Apps may not use in-app purchase to purchase credit or currency for use in conjunction with real money gaming of any kind."
- 5.3.4: real money gaming and lotteries "must have necessary licensing and permissions in the locations where the app is used, must be geo-restricted to those locations", and "Lottery apps must have consideration, chance, and a prize."
- 5.3.1 and 5.3.2: sweepstakes and contests must be sponsored by the developer, with official rules in the app that say Apple is not involved.

In-app purchase also has no way to pay a user: the money goes to the developer, so a pot funded by purchases could only be paid out by us, outside Apple, from revenue Apple has already taken a cut of. And Apple aside, a prize pot funded by the participants is regulated: with a winner picked by chance it is a lottery, and with a winner picked by skill it is still a contest with state-by-state rules once the house (us) touches the money. Developers on Apple's forums report free prediction apps with prizes being held to 5.3.4 at review **(unverified)**.

### 4.2 Recommended: the pot is a bet in the ledger

The same posture as every other game in Wad: the app computes who owes whom and the players settle by Venmo link (ADR-0007); nothing is sold and nothing is held. A bought distraction is a stake the sender owes the pot; the pot is paid to the winner; the per-player deltas sum to zero and net into the single settlement with Skins, Wad, Greenies and Wolf. The free credit carries no money, so the base feature works with the money switched off, and the game is "friends betting on golf" like the others rather than a product we sell.

### 4.3 If revenue is wanted

Sell extra credits as a consumable in-app purchase and keep the revenue, with no pot attached; or a paid tier of the app. Never route in-app purchase money into a pot, and do not offer both models in the same round: that is the 5.3.3 case.

### 4.4 Who wins the pot

Options, for the owner to choose from (section 8):

- **A. Low net for the round.** Simple, uses what the engines already compute. Ties need a rule (split in whole cents, or the pot is not paid, as with an unresolved Skins carryover, Open Question 1).
- **B. Most survivals.** A target who still makes par or better (gross or net, to decide) on a hole they were distracted on has survived it; most survivals takes the pot. Rewards the victim, which is the fun of it.
- **C. Bounty.** Each bought distraction is a side bet between sender and target at the stake. Target makes par or better: the target collects the stake from the sender. Worse: the stake goes to the pot, which is paid by rule A at the end. Every firing has money on it, both ways.
- **D. A draw by the app.** Avoid it: chance is exactly what turns a prize pool into a lottery, and it is less fun than A to C.

Rules A to C keep the game a skill bet like the other four.

### 4.5 Worked example (cents)

Four players, one free credit each, stake 500. Zach fires three times (two bought), Sam twice (one bought), Alex once, Pat never. Pot: 1500.

Rule A, Pat has the low net: Pat +1500, Zach -1000, Sam -500, Alex 0. Sum 0. Pairwise: Zach pays Pat 1000, Sam pays Pat 500, netted with the other games by `settle`.

Rule C, one of Zach's bought firings is at Pat on hole 7: Pat pars, so Zach -500 and Pat +500 on that firing and the pot shrinks to 1000; Pat bogeys, so the 500 stays in the pot.

### 4.6 Rules the engine needs whichever pot rule is picked

- A sender cannot target themself. Whether a sender may fire more than once on a hole, or a target be fired at more than once on a hole, is a decision.
- Whether a firing must come before the target's score for the hole is entered (otherwise a distraction "after" a double bogey is free money under rule C).
- Credits cannot go negative. Uses beyond the free credit are the bought ones, in firing order, so there is no separate purchase record to keep consistent: the stake is derived from the events, like everything else.
- A player who leaves mid-round (Open Question 2) applies to this game too.
- A guest without the app has no phone in the room and cannot be a target; whether they can be in the game at all is a decision.

## 5. Fit with the codebase

- **Engine.** `backend/src/engines/distractions.ts`, pure like the others: input is the players in the game, the free credits, the stake, the pot rule and the events (sender, target, hole, order); output is per-player deltas that sum to zero and a state (credits left per player, pot in cents, firings per hole, survivals). `LedgerGame` gains `"distractions"` so `pairwiseLedger` can say why ("Zach: 2 bought distractions, 1000"), and `settle` nets it. The bundle reaches the phone through [ADR-0011](../adr/0011-engines-on-device-javascriptcore.md) (`npm run build:ios-engines`).
- **Round config.** `games.distractions = { freeCredits: 1, stakeCents: 500, potRule: "lowNet" }` on the round item, beside the other games.
- **Events (data model).** `ROUND#<roundId>` / `DISTRACTION#<hole:02d>#<senderUserId>#<seq>` with `targetUserId`, `firedAt` and, for the record, `deliveredVia`. Owned by the sender (each player owns their own bet events, ADR-0004), written unconditionally, derived on read; access pattern 3 (query all SKs of a round) already covers it. On the phone, a `distractions` list on the round, alongside the hole events.
- **Device tokens (Phase B).** `USER#<userId>` / `DEVICE#<token>` with `updatedAt` and a `ttl` renewed on every launch (expire after about 60 days of silence). New access pattern: `PK=USER#id, SK begins_with DEVICE#`. Routes `PUT /me/devices` and `DELETE /me/devices/{token}`; they need auth (M1).
- **Relay payload (Phase A).** `{ "type": "distraction", "id": "...", "fromPlayerID": "p1", "fromName": "Zach", "targetPlayerID": "p3", "hole": 7, "firedAt": "...", "bought": true }` and `{ "type": "distractionLanded", "id": "...", "targetPlayerID": "p3" }`. `LivePayload` gains two cases; an older build already ignores a type it does not know.
- **Target WebSocket contract (M3.3).** `{ "action": "distract", "roundId": "r_abc", "targetUserId": "u_3", "hole": 7 }`: the server records the event, broadcasts `distractionFired` to the round, and pushes to the target's devices when the target has no live connection (or always, with the app deduping by id).
- **Sending the push.** From the Lambda that handles the action. Two ways: (a) APNs directly over HTTP/2 from Node 22 (`http2` is built in; an ES256 JWT signed with the `.p8`, cached up to an hour), with the key in an SSM SecureString like the client token and the key id and team id as SSM parameters (the team id must never be committed, repo rule); (b) an SNS platform application (`aws_sns_platform_application`), Terraform-native, but the key goes through a CI secret into Terraform state and it adds a service. (a) fits the existing SSM pattern and adds no AWS service. Both are free at this volume (APNs costs nothing; SNS mobile push is $0.50 per million). Either way it is an `infra/` PR with the owner's approval.
- **iOS (Phase B).** Ask for notification permission with sound in context, when the player joins a distraction game, not at launch; register for remote notifications and send the token; the Time Sensitive capability; a bundled sound of at most 30 seconds; `UNUserNotificationCenterDelegate` so a push that arrives on screen plays the show instead of a banner.
- **Cost.** API Gateway WebSocket messages are about $1 per million and connection minutes $0.25 per million; a round's distractions are a few dozen frames. Nothing near the $20 per month threshold for `infra/` changes.

## 6. App Store and the course

- **4.5.4.** Push "must not be required for the app to function" and must not be used for marketing. A game the players opt into is neither; the app works without it. Still, the game is a per-round toggle like Wad, so consent is explicit, and a player who leaves the game can neither fire nor be targeted.
- **Harassment (1.1, 1.2).** Mutual opt-in among the four people in a round, with the sender named on the target's screen. Keep the copy playful and let the reviewer see the opt-in.
- **Privacy manifest.** Declare push; a device token is an identifier used for app functionality.
- **On the course.** The noise reaches the next tee and some courses ban phone noise. Cap the sound at a few seconds and let the group pick a class at setup (haptic only, short, full). That is the whole etiquette story; the rest is the group's business.

## 7. Recommended plan

**First, measure.** Add a debug readout of `receivedAt - sentAt` to the live feed and carry two phones round the course for a round. Replace the estimates in 3.5 with numbers before designing the timing of the show.

**Phase A: over the relay (now).** Effort M. The engine with its ledger and settlement wiring and the worked example as a test; the setup toggle with free credits, stake and pot rule; a Distract button per player on the hole view, greyed with no credit and showing "listening" or "asleep" from the room state; the two payload types; the target's show (`.playback` sound, a long haptic pattern, the overlay) and the receipt; recording on the scoring phone (and in each sender's own round once every phone scores, M3.4). Acceptance: two phones in a room, both on screen; a firing plays the show on the target within a second; the sender sees "landed"; settlement shows the pot and its payout. Known gap, stated in the UI: a phone in a pocket gets nothing until it wakes, and a firing older than the cutoff is dropped rather than played late.

**Phase B: push (after Apple Developer Program enrollment, M1 auth and the rounds API).** Effort M to L, one `infra/` PR. The device registry, the send path, the sound file, permission in context. Acceptance: target locked in a pocket vibrates within about three seconds and rings if the ringer is on; a target wearing a watch feels it on the wrist. The relay path stays for phones on screen because it is faster and louder.

**Phase C: a watchOS app.** Effort L. Only if the group wears watches and the wrist buzz from B is not enough.

## 8. Decisions for the owner

1. Is the base game (one free credit, no money) wanted on its own, over the relay, before push exists? It only reaches phones that are on screen.
2. The default stake, and whether bought credits are capped per player per round.
3. The pot rule (A, B or C in 4.4) and the tie rule.
4. At most one firing per sender per hole, per target per hole, both, or neither.
5. Must a firing come before the target's score for the hole is entered?
6. Does joining the game override the player's sounds switch for distractions?
7. A sound class at setup (haptic only, short, full), or always full?
8. Guests with no phone in the room: out of the game, or in it as senders only?
9. Any appetite for in-app purchase revenue with no pot, instead of or beside the ledger pot?
10. Apple Developer Program enrollment timing; it gates Phase B as it already gates M1.
11. Is a watch app worth an L for this group?

## 9. Sources

Opened and read on 2026-10-18:

- App Store Review Guidelines, sections 2.5.4, 3.1.1, 4.5.4 and 5.3: https://developer.apple.com/app-store/review/guidelines/

Known through search-result summaries only, or pages that did not render for the fetch tool (**unverified** where they are the only support):

- `UNNotificationInterruptionLevel` (page did not render): https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel
- Interruption levels, Focus and the ringer switch, vendor documentation: https://documentation.onesignal.com/docs/en/ios-focus-modes-and-interruption-levels.md and https://docs.oracle.com/en/cloud/saas/marketing/responsys-develop-mobile/ios/advanced-notifications.htm
- Critical Alerts entitlement scope and process: https://newly.app/articles/critical-alerts-entitlement and https://developer.apple.com/forums/thread/794822
- Supported capabilities by membership (table did not render): https://developer.apple.com/help/account/reference/supported-capabilities-ios/
- APNs acceptance latency, provider side, not device arrival: https://knock.app/push-api-benchmarks/apns
- APNs device-side delays and tails, Apple forums: https://developer.apple.com/forums/thread/762088 and https://developer.apple.com/forums/thread/825224
- Guideline 5.3 as applied at review, Apple forums: https://developer.apple.com/forums/thread/825845 and https://developer.apple.com/forums/thread/747996
- Audio background mode rejections under 2.5.4, Apple forums: https://developer.apple.com/forums/thread/826849
- `WKInterfaceDevice.play(_:)`, background haptics only with a workout session: https://developer.apple.com/documentation/watchkit/wkinterfacedevice/play(_:)
- Running workout sessions and the audio background mode on watchOS: https://developer.apple.com/documentation/healthkit/running-workout-sessions and https://developer.apple.com/documentation/watchkit/taking-advantage-of-frontmost-app-state
- Apple Watch silent mode keeps haptics, per-app mirroring: https://www.howtogeek.com/222128/how-to-silence-manage-conceal-notifications-on-your-apple-watch/ and https://support.pushover.net/i72-not-hearing-notification-sounds-on-apple-watch

In this repository: [ADR-0004](../adr/0004-multi-device-sync.md), [ADR-0007](../adr/0007-payments-venmo-deeplinks.md), [ADR-0011](../adr/0011-engines-on-device-javascriptcore.md), [ADR-0014](../adr/0014-live-relay-before-auth.md), [api.md](../api.md) (live relay and target WebSocket contract), [data-model.md](../data-model.md), `ios/Wad/Live/`, `ios/Wad/Events/`, `backend/src/handlers/live.ts`, [geolocation.md](geolocation.md).
