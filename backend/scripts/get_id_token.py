import getpass
import json
import urllib.error
import urllib.request


API_KEY = input("Firebase API key: ").strip()
EMAIL = input("Admin email: ").strip()
PASSWORD = getpass.getpass("Password: ")

url = (
    "https://identitytoolkit.googleapis.com/v1/"
    f"accounts:signInWithPassword?key={API_KEY}"
)

payload = json.dumps(
    {
        "email": EMAIL,
        "password": PASSWORD,
        "returnSecureToken": True,
    }
).encode("utf-8")

request = urllib.request.Request(
    url,
    data=payload,
    headers={"Content-Type": "application/json"},
    method="POST",
)

try:
    with urllib.request.urlopen(request) as response:
        result = json.loads(response.read().decode())

        print("\nLogin successful.\n")
        print("ID TOKEN:")
        print(result["idToken"])

except urllib.error.HTTPError as error:
    body = error.read().decode()
    print("\nLogin failed:")
    print(body)