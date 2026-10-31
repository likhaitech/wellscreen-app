/**
 * WellScreen parent-to-child app-limit notification Worker.
 *
 * Required Cloudflare Worker environment bindings:
 *   FIREBASE_PROJECT_ID            = wellscreen-58cb7
 *   FIREBASE_SERVICE_ACCOUNT_JSON  = ENTIRE service-account JSON (SECRET)
 *
 * This Worker is deliberately invoked by the parent Flutter app AFTER
 * Firestore successfully saves a time limit. It does not listen to Firestore.
 *
 * Request: POST /notify-limit
 *   Authorization: Bearer <Firebase Auth ID token of signed-in parent>
 *   Content-Type: application/json
 *   {"childProfileId":"...", "packageName":"com.example.app"}
 *
 * Do not put service account credentials in the Flutter application.
 */

const encoder = new TextEncoder();
let tokenCache = null;
let firebaseKeysCache = null;

function jsonResponse(status, payload) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
    },
  });
}

function getStringField(document, name) {
  const value = document?.fields?.[name]?.stringValue;
  return typeof value === 'string' ? value : '';
}

function base64Url(bytes) {
  const bin = Array.from(bytes, (byte) => String.fromCharCode(byte)).join('');
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

async function googleServiceToken(serviceAccountJson) {
  const now = Math.floor(Date.now() / 1000);
  if (tokenCache && tokenCache.expiresAt > now + 90) {
    return tokenCache.value;
  }

  const serviceAccount = JSON.parse(serviceAccountJson);
  if (!serviceAccount.client_email || !serviceAccount.private_key) {
    throw new Error('Service account JSON missing client_email or private_key');
  }
  const keyBytes = Uint8Array.from(
    atob(
      serviceAccount.private_key
        .replace(/-----BEGIN PRIVATE KEY-----/g, '')
        .replace(/-----END PRIVATE KEY-----/g, '')
        .replace(/\s/g, ''),
    ),
    (c) => c.charCodeAt(0),
  );
  const signingKey = await crypto.subtle.importKey(
    'pkcs8',
    keyBytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const header = base64Url(encoder.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claims = base64Url(
    encoder.encode(
      JSON.stringify({
        iss: serviceAccount.client_email,
        scope: [
          'https://www.googleapis.com/auth/datastore',
          'https://www.googleapis.com/auth/firebase.messaging',
        ].join(' '),
        aud: 'https://oauth2.googleapis.com/token',
        iat: now,
        exp: now + 3600,
      }),
    ),
  );
  const unsigned = `${header}.${claims}`;
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    signingKey,
    encoder.encode(unsigned),
  );
  const assertion = `${unsigned}.${base64Url(new Uint8Array(sig))}`;

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) {
    throw new Error(`Google OAuth token exchange failed (${response.status})`);
  }
  const result = await response.json();
  if (!result.access_token) throw new Error('No OAuth access token returned');
  tokenCache = {
    value: result.access_token,
    expiresAt: now + Math.min(Number(result.expires_in) || 3600, 3600),
  };
  return result.access_token;
}

// Verify the signed-in parent's Firebase ID token with Google's public keys.
// Checks the RS256 signature, issuer, audience, and expiration. This does NOT
// require a Firebase API key and does not rely on the untrusted caller's UID.
function decodeBase64Url(input) {
  const base64 = input.replace(/-/g, '+').replace(/_/g, '/')
    .padEnd(Math.ceil(input.length / 4) * 4, '=');
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
}

async function firebasePublicKeys() {
  const now = Date.now();
  if (firebaseKeysCache && firebaseKeysCache.expiresAt > now) {
    return firebaseKeysCache.keys;
  }
  const response = await fetch(
    'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
  );
  if (!response.ok) throw new Error(`Firebase signing keys unavailable (${response.status})`);
  const jwks = await response.json();
  if (!Array.isArray(jwks.keys)) throw new Error('Firebase signing keys are invalid');
  // Cache within this Worker isolate; public keys rotate periodically.
  const maxAge = Number(response.headers.get('cache-control')?.match(/max-age=(\d+)/)?.[1] || 300);
  firebaseKeysCache = {
    keys: jwks.keys,
    expiresAt: now + Math.min(Math.max(maxAge, 60), 3600) * 1000,
  };
  return jwks.keys;
}

async function authenticatedFirebaseUid(idToken, projectId) {
  try {
    const parts = idToken.split('.');
    if (parts.length !== 3) return null;
    const header = JSON.parse(new TextDecoder().decode(decodeBase64Url(parts[0])));
    const claims = JSON.parse(new TextDecoder().decode(decodeBase64Url(parts[1])));
    if (header.alg !== 'RS256' || typeof header.kid !== 'string') return null;
    const now = Math.floor(Date.now() / 1000);
    if (
      claims.aud !== projectId ||
      claims.iss !== `https://securetoken.google.com/${projectId}` ||
      typeof claims.sub !== 'string' ||
      claims.sub.length < 1 ||
      claims.sub.length > 128 ||
      !Number.isInteger(claims.exp) ||
      claims.exp <= now ||
      !Number.isInteger(claims.iat) ||
      claims.iat > now ||
      !Number.isInteger(claims.auth_time) ||
      claims.auth_time > now
    ) return null;
    const jwks = await firebasePublicKeys();
    const key = jwks.find((candidate) => candidate.kid === header.kid);
    if (!key) return null;
    const publicKey = await crypto.subtle.importKey(
      'jwk', key,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false, ['verify'],
    );
    const verified = await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      publicKey,
      decodeBase64Url(parts[2]),
      encoder.encode(`${parts[0]}.${parts[1]}`),
    );
    return verified ? claims.sub : null;
  } catch (error) {
    console.error('Firebase ID token verification failed:', String(error));
    return null;
  }
}

async function getFirestoreDocument(projectId, accessToken, segments) {
  const path = segments.map(encodeURIComponent).join('/');
  const url = `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/databases/(default)/documents/${path}`;
  const response = await fetch(url, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  if (response.status === 404) return null;
  if (!response.ok) {
    throw new Error(`Firestore read failed (${response.status})`);
  }
  return await response.json();
}

function durationLabel(minutes) {
  if (minutes % 60 === 0) return `${minutes / 60} hour${minutes === 60 ? '' : 's'}`;
  if (minutes < 60) return `${minutes} minute${minutes === 1 ? '' : 's'}`;
  return `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== '/notify-limit') {
      return jsonResponse(404, { ok: false, error: 'Not found' });
    }
    if (request.method !== 'POST') {
      return jsonResponse(405, { ok: false, error: 'Method not allowed' });
    }
    if (!env.FIREBASE_PROJECT_ID || !env.FIREBASE_SERVICE_ACCOUNT_JSON) {
      return jsonResponse(503, { ok: false, error: 'Worker configuration incomplete' });
    }

    const auth = request.headers.get('authorization') || '';
    if (!auth.startsWith('Bearer ') || auth.length > 10000) {
      return jsonResponse(401, { ok: false, error: 'Firebase sign-in required' });
    }

    let payload;
    try {
      const body = await request.text();
      if (body.length > 4096) {
        return jsonResponse(413, { ok: false, error: 'Request too large' });
      }
      payload = JSON.parse(body);
    } catch (_) {
      return jsonResponse(400, { ok: false, error: 'Invalid JSON' });
    }
    const childProfileId = payload?.childProfileId;
    const packageName = payload?.packageName;
    if (
      typeof childProfileId !== 'string' ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(childProfileId) ||
      typeof packageName !== 'string' ||
      !/^[A-Za-z0-9_.]{1,255}$/.test(packageName)
    ) {
      return jsonResponse(400, { ok: false, error: 'Invalid child profile or app package' });
    }

    try {
      const uid = await authenticatedFirebaseUid(auth.slice(7), env.FIREBASE_PROJECT_ID);
      if (!uid) return jsonResponse(401, { ok: false, error: 'Invalid Firebase session' });

      const accessToken = await googleServiceToken(env.FIREBASE_SERVICE_ACCOUNT_JSON);
      const childProfile = await getFirestoreDocument(
        env.FIREBASE_PROJECT_ID,
        accessToken,
        ['child_profiles', childProfileId],
      );
      // Never trust a parent ID provided by the caller. Confirm ownership in Firestore.
      if (!childProfile || getStringField(childProfile, 'parentId') !== uid) {
        return jsonResponse(403, { ok: false, error: 'Not authorized for this child' });
      }
      if (getStringField(childProfile, 'pairingStatus') !== 'connected') {
        return jsonResponse(409, { ok: false, error: 'Child device is not paired' });
      }
      const childUid = getStringField(childProfile, 'childAccountId');
      if (!childUid) {
        return jsonResponse(409, { ok: false, error: 'Paired child account is missing' });
      }

      const [appLimit, childUser] = await Promise.all([
        getFirestoreDocument(
          env.FIREBASE_PROJECT_ID,
          accessToken,
          ['child_profiles', childProfileId, 'app_time_limits', packageName],
        ),
        getFirestoreDocument(
          env.FIREBASE_PROJECT_ID,
          accessToken,
          ['users', childUid],
        ),
      ]);
      if (!appLimit) return jsonResponse(404, { ok: false, error: 'App limit not found' });
      if (getStringField(appLimit, 'packageName') !== packageName) {
        return jsonResponse(409, { ok: false, error: 'App limit data does not match' });
      }
      const rawMinutes = appLimit.fields?.limitMinutes?.integerValue;
      const limitMinutes = Number(rawMinutes);
      if (!Number.isInteger(limitMinutes) || limitMinutes < 1 || limitMinutes > 1440) {
        return jsonResponse(409, { ok: false, error: 'Invalid stored time limit' });
      }
      const childToken = getStringField(childUser, 'limitNotificationToken');
      if (!childToken) {
        return jsonResponse(409, { ok: false, error: 'Child notification token not registered' });
      }
      const appName = getStringField(appLimit, 'appName') || packageName;
      const sendResponse = await fetch(
        `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(env.FIREBASE_PROJECT_ID)}/messages:send`,
        {
          method: 'POST',
          headers: {
            authorization: `Bearer ${accessToken}`,
            'content-type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: childToken,
              data: {
                type: 'app_time_limit_changed',
                childProfileId,
                packageName,
                appName,
                limitMinutes: String(limitMinutes),
              },
              android: {
                priority: 'HIGH',
                ttl: '86400s',
                collapse_key: 'wellscreen-limit-sync',
              },
            },
          }),
        },
      );
      if (!sendResponse.ok) {
        console.error('FCM send failed', sendResponse.status);
        return jsonResponse(502, { ok: false, error: 'FCM rejected notification' });
      }
      return jsonResponse(200, { ok: true, sent: true });
    } catch (err) {
      console.error('WellScreen notification worker failed:', String(err));
      return jsonResponse(502, { ok: false, error: 'Notification service unavailable' });
    }
  },
};
