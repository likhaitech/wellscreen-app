from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Allow `python scripts/grant_admin.py` from inside backend/.
BACKEND_DIR = Path(__file__).resolve().parents[1]

if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from firebase_admin import auth, firestore

from app.services.firebase_service import (
    get_firestore_client,
    initialize_firebase,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Grant the WellScreen administrator role to a Firebase user."
    )

    group = parser.add_mutually_exclusive_group(required=True)

    group.add_argument(
        "--uid",
        help="Firebase Auth UID",
    )

    group.add_argument(
        "--email",
        help="Firebase Auth email address",
    )

    return parser.parse_args()


def main() -> None:
    args = parse_args()

    initialize_firebase()

    if args.uid:
        user = auth.get_user(args.uid)
    else:
        user = auth.get_user_by_email(args.email)

    claims = dict(user.custom_claims or {})

    claims["role"] = "admin"
    claims["admin"] = True

    auth.set_custom_user_claims(
        user.uid,
        claims,
    )

    db = get_firestore_client()

    db.collection("users").document(user.uid).set(
        {
            "uid": user.uid,
            "email": user.email,
            "fullName": user.display_name,
            "role": "admin",
            "updatedAt": firestore.SERVER_TIMESTAMP,
        },
        merge=True,
    )

    print(
        f"Admin role granted to "
        f"{user.email or user.uid} ({user.uid})."
    )

    print(
        "Sign out and sign back in so Firebase "
        "issues a token with the new claim."
    )


if __name__ == "__main__":
    main()