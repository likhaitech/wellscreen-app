# Deploying the WellScreen backend

The mobile app's push notifications (and the admin settings/logs screens) only work once this backend is running somewhere the phone can reach it over the internet - not just on your laptop. This guide deploys it to [Render](https://render.com), which has a genuinely free tier for small services like this one (confirmed current as of 2026: no credit card required, 750 free instance-hours/month).

**The one real tradeoff:** a free Render web service "spins down" after 15 minutes with no traffic, and takes about a minute to wake back up on the next request. For day-to-day testing that's fine. **Before your oral defense**, open `https://<your-service>.onrender.com/health` in a browser a few minutes ahead of time to wake it up, so the first live demo request isn't slow.

## 1. Get a Firebase service account key

This is a private credential file - keep it out of git entirely (the repo's `.gitignore` already blocks `backend/firebase-service-account.json` from being committed, so this only needs to go into Render's dashboard, never into a commit).

1. Go to the [Firebase Console](https://console.firebase.google.com) → your `wellscreen-58cb7` project → **Project Settings** (gear icon) → **Service Accounts** tab.
2. Click **Generate new private key**. This downloads a `.json` file to your computer.
3. Keep that file somewhere safe on your machine for step 3 below - do not upload it anywhere except Render's dashboard.

## 2. Create the Render web service

1. Sign up / log in at [render.com](https://render.com) (no card needed for the free tier).
2. **New +** → **Web Service** → connect your GitHub account → select the `wellscreen-app` repository.
3. Configure these fields:
   - **Root Directory:** `backend`
   - **Runtime:** `Python 3`
   - **Build Command:** `pip install -r requirements.txt`
   - **Start Command:** `uvicorn app.main:app --host 0.0.0.0 --port $PORT`
   - **Instance Type:** Free
4. Click **Create Web Service**. It'll try to deploy immediately - that's fine, it'll fail until step 3 is done (no Firebase credentials yet), then redeploy successfully afterward.

## 3. Add the Firebase credentials as a Secret File

1. In your new service's dashboard, go to **Environment** in the left sidebar.
2. Under **Secret Files**, click **+ Add Secret File**.
3. Filename: `firebase-service-account.json`. Contents: open the JSON file from step 1 in a text editor, copy everything, paste it into the Contents box.
4. Save. Render mounts this at `/etc/secrets/firebase-service-account.json` inside the running service.
5. Still in **Environment**, add a regular environment variable:
   - Key: `FIREBASE_SERVICE_ACCOUNT_PATH`
   - Value: `/etc/secrets/firebase-service-account.json`

   (`backend/app/services/firebase_service.py` already reads this exact environment variable - no code change needed.)

6. Save - this triggers a fresh deploy.

## 4. Verify it's live

Once the deploy finishes (Render's dashboard shows "Live"), open `https://<your-service-name>.onrender.com/health` in a browser. You should see `{"status":"ok"}`. If you get an error instead, check the **Logs** tab in Render's dashboard - the most common cause is the secret file path being typed wrong in step 3.

## 5. Point the app at the real backend

Open `mobile_app/lib/config/app_config.dart` and change the `defaultValue` from `'https://your-backend-url.example.com'` to your actual Render URL (`https://<your-service-name>.onrender.com`, no trailing slash). Then push and rebuild the app - see the main chat for the exact git commands.

## What this unlocks

Once this is live and the app is rebuilt: real push notifications when a child's usage becomes unhealthy or shares a new GPS location (`POST /alerts/notify`), plus the admin settings/logs screens your teammate built, which were previously only reachable from an Android emulator on the same machine running the backend.
