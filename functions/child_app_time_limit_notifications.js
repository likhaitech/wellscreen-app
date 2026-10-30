// Merge this export into your existing Firebase Cloud Functions project.
// Requires firebase-functions v2 and firebase-admin. Use a trusted server;
// NEVER send FCM requests with service-account credentials from Flutter.
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

if (!getApps().length) initializeApp();

exports.notifyChildAppTimeLimit = onDocumentWritten(
  'child_profiles/{childProfileId}/app_time_limits/{appPackage}',
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) return; // Removed limit: no new-assignment notice.
    if (before && before.limitMinutes === after.limitMinutes &&
        before.appName === after.appName) return; // Avoid edit-no-op spam.

    const { childProfileId, appPackage } = event.params;
    const minutes = after.limitMinutes;
    if (!Number.isInteger(minutes) || minutes < 1 || minutes > 1440 ||
        after.packageName !== appPackage) return;

    const firestore = getFirestore();
    const childProfile = await firestore.collection('child_profiles')
      .doc(childProfileId).get();
    if (!childProfile.exists) return;
    const profile = childProfile.data();
    if (profile.pairingStatus !== 'connected' || !profile.childAccountId) return;

    const childDoc = await firestore.collection('users')
      .doc(profile.childAccountId).get();
    if (!childDoc.exists) return;
    const child = childDoc.data();
    if (child.role !== 'child' || child.pairedChildProfileId !== childProfileId ||
        child.pairedParentId !== profile.parentId) return;

    const token = child.limitNotificationToken;
    if (typeof token !== 'string' || !token) return;

    const appName = (typeof after.appName === 'string' && after.appName.trim())
      ? after.appName.trim().slice(0, 150) : appPackage;
    const duration = minutes % 60 === 0
      ? `${minutes / 60} hour${minutes === 60 ? '' : 's'}`
      : minutes < 60
        ? `${minutes} minute${minutes === 1 ? '' : 's'}`
        : `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
    const title = 'New App Time Limit';
    const body = `Your parent set a daily limit of ${duration} for ${appName}.`;

    try {
      await getMessaging().send({
        token,
        notification: { title, body },
        data: {
          type: 'app_time_limit_changed',
          childProfileId,
          packageName: appPackage,
          appName,
          limitMinutes: String(minutes),
        },
        android: {
          priority: 'normal',
          notification: {
            channelId: 'wellscreen_limit_updates',
            tag: `limit_${childProfileId}_${appPackage}`,
          },
        },
      });
    } catch (error) {
      console.error('Could not deliver child app limit notification:', error);
      // Do not delete tokens blindly: other notification producers may use them.
    }
  },
);
