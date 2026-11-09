"""WellScreen chat request decisions and temporary access grants.

Backend-authored approvals only. Existing emergencyAccess and app_rules stay untouched.
Requires existing firebase_service.get_firestore_client().
"""
from __future__ import annotations

import datetime as dt
import logging
from typing import Any

from google.api_core.exceptions import AlreadyExists, Conflict

from firebase_admin import auth, firestore, messaging
from google.cloud.firestore_v1 import transactional

from .firebase_service import get_firestore_client

UTC = dt.timezone.utc
MAX_APPROVED_MINUTES = 180
LOGGER = logging.getLogger(__name__)


class ChatAccessError(ValueError):
    pass


def authenticated_uid(authorization: str | None) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise ChatAccessError("Firebase authentication required")
    try:
        claims = auth.verify_id_token(authorization[7:].strip(), check_revoked=True)
        return str(claims["uid"])
    except Exception as exc:
        raise ChatAccessError("Invalid or expired Firebase session") from exc


def _paired_profile(db: Any, profile_id: str) -> dict[str, Any]:
    if not profile_id or "/" in profile_id:
        raise ChatAccessError("Invalid child profile")
    snap = db.collection("child_profiles").document(profile_id).get()
    if not snap.exists:
        raise ChatAccessError("Child profile not found")
    data = snap.to_dict() or {}
    if not data.get("parentId") or not data.get("childAccountId"):
        raise ChatAccessError("Profile is not paired")
    return data


def _restricted_rule(db: Any, parent_uid: str, package: str) -> dict[str, Any] | None:
    snap = db.collection("app_rules").document(parent_uid).get()
    rules = (snap.to_dict() or {}).get("rules", [])
    for rule in rules:
        if (isinstance(rule, dict) and rule.get("packageName") == package and
                rule.get("restrictEnabled") is True):
            return rule
    return None


def respond_to_request(*, parent_uid: str, profile_id: str, request_id: str,
                       approve: bool, approved_minutes: int | None) -> dict[str, Any]:
    db = get_firestore_client()
    profile = _paired_profile(db, profile_id)
    if profile["parentId"] != parent_uid:
        raise ChatAccessError("Only the paired parent can decide")
    if approve and (not isinstance(approved_minutes, int) or
                    isinstance(approved_minutes, bool) or
                    not 1 <= approved_minutes <= MAX_APPROVED_MINUTES):
        raise ChatAccessError("Approved time must be 1–180 minutes")
    req_ref = db.collection("child_profiles").document(profile_id).collection(
        "access_requests").document(request_id)
    now = dt.datetime.now(UTC)

    @transactional
    def decide(tx: Any) -> dict[str, Any]:
        snap = req_ref.get(transaction=tx)
        if not snap.exists:
            raise ChatAccessError("Request does not exist")
        data = snap.to_dict() or {}
        if data.get("childUid") != profile["childAccountId"]:
            raise ChatAccessError("Request does not belong to this child")
        if data.get("status") != "pending":
            raise ChatAccessError("This request was already decided")
        pkg = data.get("packageName", "")
        if not isinstance(pkg, str) or not pkg or "/" in pkg:
            raise ChatAccessError("Invalid application package")
        grant_ref = db.collection("child_profiles").document(profile_id).collection(
            "temporary_access_grants").document(pkg)
        prior = grant_ref.get(transaction=tx) if approve else None
        if approve and prior is not None and prior.exists:
            earlier = prior.to_dict() or {}
            previous_expiry = earlier.get("expiresAt")
            if earlier.get("state") == "pending_activation" or (
                earlier.get("state") == "active" and previous_expiry and previous_expiry > now
            ):
                raise ChatAccessError("Another grant is already active or awaiting activation")
        authoritative_rule = _restricted_rule(db, parent_uid, pkg) if approve else None
        if approve and authoritative_rule is None:
            raise ChatAccessError("The application is no longer restricted")
        next_status = "approved_pending_activation" if approve else "declined"
        tx.update(req_ref, {
            "status": next_status,
            "approvedMinutes": approved_minutes if approve else None,
            "decidedAt": firestore.SERVER_TIMESTAMP,
            "decidedBy": parent_uid,
            "decisionNotificationState": "pending",
        })
        if approve:
            tx.set(grant_ref, {
                "packageName": pkg,
                "appName": (authoritative_rule or {}).get("appName") or pkg,
                "requestId": request_id,
                "parentId": parent_uid,
                "childUid": profile["childAccountId"],
                "approvedMinutes": approved_minutes,
                "state": "pending_activation",
                "approvedAt": firestore.SERVER_TIMESTAMP,
                "activatedAt": None,
                "expiresAt": None,
            })
        return {"status": next_status, "approvedMinutes": approved_minutes if approve else None}

    # A single transaction authorizes the transition; notifications are best effort.
    # The persistent decisionNotificationState is also swept by cron if this
    # immediate delivery cannot complete (e.g. no token / Render outage).
    decision = decide(db.transaction())
    try:
        dispatch_decision_notification(db, profile_id, request_id, profile)
    except Exception:
        LOGGER.exception("Chat decision notification deferred to cron")
    return decision


def activate_grant(*, child_uid: str, profile_id: str,
                   package_name: str) -> dict[str, Any]:
    db = get_firestore_client()
    profile = _paired_profile(db, profile_id)
    if profile["childAccountId"] != child_uid:
        raise ChatAccessError("Only the paired child can activate this grant")
    if not package_name or "/" in package_name:
        raise ChatAccessError("Invalid package")
    ref = db.collection("child_profiles").document(profile_id).collection(
        "temporary_access_grants").document(package_name)
    now = dt.datetime.now(UTC)

    @transactional
    def activate(tx: Any) -> dict[str, Any]:
        snap = ref.get(transaction=tx)
        if not snap.exists:
            raise ChatAccessError("Grant not found")
        grant = snap.to_dict() or {}
        if grant.get("childUid") != child_uid:
            raise ChatAccessError("Grant owner mismatch")
        if grant.get("state") == "active":
            return {"status": "active", "expiresAt": grant.get("expiresAt")}
        if grant.get("state") != "pending_activation":
            raise ChatAccessError("Grant is not awaiting activation")
        minutes = grant.get("approvedMinutes")
        if not isinstance(minutes, int) or not 1 <= minutes <= MAX_APPROVED_MINUTES:
            raise ChatAccessError("Invalid approved duration")
        expiry = now + dt.timedelta(minutes=minutes)
        tx.update(ref, {"state": "active", "activatedAt": now, "expiresAt": expiry})
        request_id = grant.get("requestId")
        if isinstance(request_id, str) and request_id:
            request_ref = db.collection("child_profiles").document(profile_id).collection(
                "access_requests").document(request_id)
            tx.update(request_ref, {"status": "active", "activatedAt": now,
                                    "expiresAt": expiry})
        return {"status": "active", "expiresAt": expiry}

    return activate(db.transaction())



def _display_name(db: Any, uid: str, fallback: str) -> str:
    if not uid:
        return fallback
    try:
        account = db.collection("users").document(uid).get().to_dict() or {}
        for field in ("fullName", "displayName", "name"):
            name = account.get(field)
            if isinstance(name, str) and name.strip():
                return name.strip()[:90]
    except Exception:
        LOGGER.exception("Could not load chat sender display name")
    return fallback


def _ensure_inbox(db: Any, recipient_uid: str, *, notification_id: str,
                  title: str, body: str, profile_id: str,
                  kind: str, sender_uid: str, request_id: str = "") -> bool:
    """Create one durable recipient notification; never reset a read message."""
    ref = db.collection("users").document(recipient_uid).collection(
        "notifications").document(notification_id)
    try:
        ref.create({
            "type": kind,
            "title": title[:150],
            "body": body[:2000],
            "childProfileId": profile_id,
            "senderUid": sender_uid,
            "requestId": request_id,
            "createdAt": firestore.SERVER_TIMESTAMP,
            "readAt": None,
        })
    except (AlreadyExists, Conflict):
        pass
    except Exception:
        LOGGER.exception("Cannot persist chat notification %s", notification_id)
        return False
    return True


def chat_push_status(*, caller_uid: str) -> dict[str, Any]:
    """Authenticated diagnosis without disclosing an FCM registration token."""
    db = get_firestore_client()
    account = db.collection("users").document(caller_uid).get().to_dict() or {}
    source = next((key for key in ("chatFcmToken", "fcmToken", "limitNotificationToken")
                   if account.get(key)), None)
    return {
        "registered": bool(source),
        "tokenSource": source,
        "notificationPermission": account.get("chatNotificationPermission", "unknown"),
        "note": "FCM token registration is not proof of Android notification permission or display.",
    }


def _unread_count(db: Any, uid: str) -> int:
    try:
        unread = db.collection("users").document(uid).collection("notifications").where(
            "readAt", "==", None).limit(99).stream()
        return max(1, sum(1 for _ in unread))
    except Exception:
        LOGGER.exception("Could not count chat unread notifications")
        return 1


def _deliver(db: Any, uid: str, *, title: str, body: str,
             notification_id: str, profile_id: str,
             kind: str) -> str:
    account = db.collection("users").document(uid).get().to_dict() or {}
    token = (account.get("chatFcmToken") or account.get("fcmToken")
             or account.get("limitNotificationToken"))
    if not token:
        LOGGER.warning("Chat push skipped: no token for account %s", uid[-6:])
        return "no_token"
    try:
        messaging.send(messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            token=token,
            data={
                "type": "parent_child_chat",
                "kind": kind,
                "notificationId": notification_id,
                "eventId": notification_id,
                "childProfileId": profile_id,
            },
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    channel_id="wellscreen_chat",
                    notification_count=_unread_count(db, uid),
                ),
            ),
        ))
        LOGGER.info("FCM accepted chat push kind=%s recipient=%s id=%s",
                    kind, uid[-6:], notification_id)
        return "sent"  # FCM accepted, not proof of handset display.
    except messaging.UnregisteredError:
        # Clear only the token that was actually rejected.
        token_field = next((field for field in
                            ("chatFcmToken", "fcmToken", "limitNotificationToken")
                            if account.get(field) == token), "chatFcmToken")
        db.collection("users").document(uid).update({token_field: None})
        LOGGER.warning("Chat FCM token unregistered recipient=%s field=%s",
                       uid[-6:], token_field)
        return "unregistered"
    except Exception:
        LOGGER.exception("FCM chat dispatch failed")
        return "failed"


def _claim(db: Any, ref: Any, field: str) -> bool:
    @transactional
    def claim_one(tx: Any) -> bool:
        snap = ref.get(transaction=tx)
        if not snap.exists or (snap.to_dict() or {}).get(field) != "pending":
            return False
        tx.update(ref, {
            field: "claimed",
            field + "ClaimedAt": firestore.SERVER_TIMESTAMP,
        })
        return True
    return claim_one(db.transaction())


def _dispatch_notification(db: Any, *, event_ref: Any, field: str,
                           recipient_uid: str, title: str, body: str,
                           notification_id: str, profile_id: str,
                           kind: str, sender_uid: str,
                           request_id: str = "") -> bool:
    if not _ensure_inbox(db, recipient_uid, notification_id=notification_id,
                         title=title, body=body, profile_id=profile_id,
                         kind=kind, sender_uid=sender_uid,
                         request_id=request_id):
        return False
    if not _claim(db, event_ref, field):
        return False
    status = _deliver(db, recipient_uid, title=title, body=body,
                      notification_id=notification_id,
                      profile_id=profile_id, kind=kind)
    # Once FCM was attempted, intentionally do not retry blindly: an ambiguous
    # timeout might already have delivered it, causing duplicates. The inbox
    # record persists regardless of push outcome. No-token is safe to retry.
    # No registered token and invalidated token are retried by the scheduled
    # sweep after the phone registers a fresh token. Ambiguous send failures
    # are not blindly retried to avoid duplicate visible notifications.
    event_ref.update({field: "pending" if status in ("no_token", "unregistered") else status})
    return status == "sent"


def dispatch_message_notification(db: Any, profile_id: str, event_id: str,
                                  profile: dict[str, Any]) -> bool:
    ref = db.collection("child_profiles").document(profile_id).collection(
        "chat_messages").document(event_id)
    snapshot = ref.get()
    if not snapshot.exists:
        raise ChatAccessError("Message not found")
    msg = snapshot.to_dict() or {}
    parent, child = profile["parentId"], profile["childAccountId"]
    sender = msg.get("senderId")
    if sender not in (parent, child):
        raise ChatAccessError("Invalid message sender")
    recipient = child if sender == parent else parent
    fallback = (profile.get("parentDisplayName") or "Parent") if sender == parent \
        else (profile.get("name") or "Child")
    name = _display_name(db, sender, str(fallback))
    preview = str(msg.get("body", ""))[:110]
    return _dispatch_notification(
        db, event_ref=ref, field="notificationState",
        recipient_uid=recipient, title=f"Message from {name}",
        body=preview, notification_id=f"msg_{profile_id}_{event_id}",
        profile_id=profile_id, kind="chat_message", sender_uid=sender,
    )


def dispatch_request_notification(db: Any, profile_id: str, event_id: str,
                                  profile: dict[str, Any]) -> bool:
    ref = db.collection("child_profiles").document(profile_id).collection(
        "access_requests").document(event_id)
    snap = ref.get()
    if not snap.exists:
        raise ChatAccessError("Request not found")
    data = snap.to_dict() or {}
    child_uid = profile["childAccountId"]
    if data.get("childUid") != child_uid:
        raise ChatAccessError("Invalid request sender")
    name = _display_name(db, child_uid, str(profile.get("name") or "Child"))
    app = str(data.get("appName") or data.get("packageName") or "App")
    duration = data.get("requestedMinutes", "?")
    return _dispatch_notification(
        db, event_ref=ref, field="notificationState",
        recipient_uid=profile["parentId"],
        title=f"App request from {name}",
        body=f"{app}: {duration} minutes requested",
        notification_id=f"request_{profile_id}_{event_id}",
        profile_id=profile_id, kind="access_request",
        sender_uid=child_uid, request_id=event_id,
    )


def dispatch_decision_notification(db: Any, profile_id: str, event_id: str,
                                   profile: dict[str, Any]) -> bool:
    ref = db.collection("child_profiles").document(profile_id).collection(
        "access_requests").document(event_id)
    snap = ref.get()
    if not snap.exists:
        raise ChatAccessError("Request not found")
    data = snap.to_dict() or {}
    status = data.get("status")
    if status not in ("declined", "approved_pending_activation", "active", "expired"):
        return False
    approved = status in ("approved_pending_activation", "active", "expired") \
        and data.get("approvedMinutes") is not None
    app = str(data.get("appName") or data.get("packageName") or "App")
    parent_uid = profile["parentId"]
    name = _display_name(db, parent_uid,
                         str(profile.get("parentDisplayName") or "Parent"))
    return _dispatch_notification(
        db, event_ref=ref, field="decisionNotificationState",
        recipient_uid=profile["childAccountId"],
        title=f"{name} approved access" if approved else f"{name} declined access",
        body=(f"{app}: {data.get('approvedMinutes')} minutes approved" if approved
              else f"Access to {app} was declined"),
        notification_id=f"decision_{profile_id}_{event_id}",
        profile_id=profile_id, kind="access_decision", sender_uid=parent_uid,
        request_id=event_id,
    )


def dispatch_chat_event(*, caller_uid: str, profile_id: str,
                        event_id: str, kind: str) -> dict[str, str]:
    """Prompt dispatch after server-committed Firestore write, never client-push."""
    db = get_firestore_client()
    profile = _paired_profile(db, profile_id)
    if kind == "message":
        ref = db.collection("child_profiles").document(profile_id).collection(
            "chat_messages").document(event_id)
        snap = ref.get()
        if not snap.exists or (snap.to_dict() or {}).get("senderId") != caller_uid:
            raise ChatAccessError("Only the original sender can dispatch this message")
        if caller_uid not in (profile["parentId"], profile["childAccountId"]):
            raise ChatAccessError("Sender is not paired")
        delivered = dispatch_message_notification(db, profile_id, event_id, profile)
    elif kind == "request":
        if caller_uid != profile["childAccountId"]:
            raise ChatAccessError("Only the paired child can submit requests")
        ref = db.collection("child_profiles").document(profile_id).collection(
            "access_requests").document(event_id)
        snap = ref.get()
        if not snap.exists or (snap.to_dict() or {}).get("childUid") != caller_uid:
            raise ChatAccessError("Only the request owner can dispatch it")
        delivered = dispatch_request_notification(db, profile_id, event_id, profile)
    else:
        raise ChatAccessError("Unsupported event kind")
    return {"status": "submitted" if delivered else "queued_or_already_dispatched"}


def sweep_chat_notifications(*, max_profiles: int = 200) -> dict[str, int]:
    """Scheduled fallback for offline writes or when the app process is gone.

    For production scale use a collection-group queue or pagination; only
    the first max_profiles profiles are scanned in this pilot implementation.
    """
    db = get_firestore_client()
    totals = {"scannedProfiles": 0, "sent": 0, "failed": 0}
    for profile_doc in db.collection("child_profiles").limit(max_profiles).stream():
        profile = profile_doc.to_dict() or {}
        if not profile.get("parentId") or not profile.get("childAccountId"):
            continue
        totals["scannedProfiles"] += 1
        profile_id = profile_doc.id
        messages = profile_doc.reference.collection("chat_messages").where(
            "notificationState", "==", "pending").limit(50).stream()
        for snapshot in messages:
            try:
                if dispatch_message_notification(db, profile_id, snapshot.id, profile):
                    totals["sent"] += 1
            except Exception:
                totals["failed"] += 1
                LOGGER.exception("Message notification sweep failed")
        requests_ref = profile_doc.reference.collection("access_requests")
        for snapshot in requests_ref.where(
                "notificationState", "==", "pending").limit(50).stream():
            try:
                if dispatch_request_notification(db, profile_id, snapshot.id, profile):
                    totals["sent"] += 1
            except Exception:
                totals["failed"] += 1
                LOGGER.exception("Request notification sweep failed")
        for snapshot in requests_ref.where(
                "decisionNotificationState", "==", "pending").limit(50).stream():
            try:
                if dispatch_decision_notification(db, profile_id, snapshot.id, profile):
                    totals["sent"] += 1
            except Exception:
                totals["failed"] += 1
                LOGGER.exception("Decision notification sweep failed")
        for snapshot in requests_ref.where(
                "status", "==", "active").limit(50).stream():
            data = snapshot.to_dict() or {}
            try:
                expires_at = data.get("expiresAt")
                if isinstance(expires_at, dt.datetime) and expires_at <= dt.datetime.now(UTC):
                    snapshot.reference.update({"status": "expired"})
                    pkg = str(data.get("packageName", ""))
                    if not pkg or "/" in pkg:
                        continue
                    grant_ref = profile_doc.reference.collection(
                        "temporary_access_grants").document(pkg)
                    grant_snap = grant_ref.get()
                    if grant_snap.exists and (grant_snap.to_dict() or {}).get("requestId") == snapshot.id:
                        grant_ref.update({"state": "expired"})
            except Exception:
                totals["failed"] += 1
                LOGGER.exception("Grant expiry sweep failed")
    return totals
