# Reviewer instructions — complete access before submission

## Access gate (not complete)

The current app uses email OTP, not an app password. Codes expire after five minutes and one account on two devices cannot form a couple. Reviewer access must work throughout the review without contacting the developer for each login. No demo account, mailbox login, fixed OTP, authentication bypass, or production secret has been created by this document.

Before submission, the owner must provide two dedicated test identities and a safe, persistent method for reviewers to receive their OTPs, or implement and fully disclose a secure review/demo mode. Avoid the owner's real mailbox or customer data. Test access from a clean device before entering it in the store's private App Access/App Review fields. Do not put credentials in source control or public listing text. A pre-linked sample pair helps reviewers inspect content, but separate unpaired identities or a safe reset are also needed to exercise mutual consent.

Fill the private store form with the verified account access, backend environment, app build/commit, tested device models/OS versions, contact name and contact telephone. The public support address is gbuyandelger277@gmail.com; it is not itself a working review-login method.

[Apple complete review information](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/) requires working access to account-based features. Expiring OTPs copied at submission time do not satisfy ongoing access.

## Notes to reviewers (copy after access is supplied)

This is a Mongolian-language app for two people who already know each other. Both accounts use the same production service; no geographic restriction is applied to the couple features. Florist catalog coverage is Mongolia and depends on OpenStreetMap records. Purchases are disabled for this release. No payment or external checkout is required to inspect the free functionality.

1. Sign in using account A's email and its fresh six-digit OTP. On the second device, sign in using the separately supplied account B. Complete the same steps on either platform.
2. On the home screen, open **Хосоор холбогдох** (Connect as a couple). Set a recognizable test display name on each account if needed.
3. On A, choose **Урилгын код үүсгэх** (Create invitation code), then **Код хуулах** (Copy code).
4. On B, paste that code in **Урилга авсан уу?** (Received an invitation?), review A's displayed name, and choose **Зөвшөөрч хүсэлт илгээх** (Agree and request connection).
5. On A, review B's request and choose **Зөвшөөрч холбогдох** (Agree and connect). Both accounts must consent. If A was backgrounded, return to the app and refresh to retrieve the request. Do not expect a received code alone to complete pairing.
6. Return home and open **Бид хоёр** (The two of us). In the calendar, add a date with a future time. The partner reviews/accepts it. Open the same day on both accounts to verify the result.
7. Add a photo memory using a test image. It appears as a sticker on its calendar day. Open the sticker for its photo and text. Photos require an active pair and are not public links.
8. Open the daily-question tab. Submit an answer from A; B's answer remains hidden until B also submits. After both submit, each can see both answers. Submitted answers are not editable.
9. Open the wishes tab, add a test wish and like it on both accounts. Use its planning action to propose a date; verify it through the calendar.
10. Return home and open **Ойрхон цэцгийн дэлгүүр** (Nearby flower shops). Select manual map placement to test without location permission, or explicitly choose the location button. Test around central Ulaanbaatar for bundled catalog results. Directions open externally only when selected.
11. **Миний бүртгэл** (My account) contains **Мэдээллээ татах** (Export my information), policy links, **Гарах** (Sign out), and **Бүртгэл устгах** (Delete account).
12. Test unlink/deletion last on disposable review accounts. Unlink is in **Хосоор холбогдох → Холболтоо салгах**. It removes that pair's memories and wishes for both users. For account deletion, obtain a fresh email login and confirm within ten minutes by entering **УСТГАХ**. Deletion revokes all sessions and cannot be undone. Photos' storage cleanup is queued after access is revoked.

No full English UI, live shop availability, background partner tracking, remote push, or automatic subscription cancellation is promised. In-app reminders require explicit consent on each device and reconcile remote changes when the app is open.

## Before copying these notes

- Verify each translated label against the final build; this file was written from source, not a completed device run.
- Use only synthetic content and resettable test accounts.
- Attach the actual tested device/OS/build evidence and private access instructions.
- Ensure web deletion and all policy links work without needing the app installed.
