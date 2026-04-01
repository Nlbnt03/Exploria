import * as functions from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

admin.initializeApp();

// Haversine formula (km)
function getDistanceFromLatLonInKm(lat1: number, lon1: number, lat2: number, lon2: number) {
  const R = 6371;
  const dLat = deg2rad(lat2 - lat1);
  const dLon = deg2rad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function deg2rad(deg: number) {
  return deg * (Math.PI / 180);
}

export const verifyAndCheckIn = functions.https.onCall(async (request) => {
  if (!request.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Token yok');
  }

  const userId = request.auth.uid;
  const { venueId, mapId, userLat, userLng, accuracy, isMocked, distance } = request.data;
  const db = admin.firestore();

  // 1. HIZ KONTROLÜ (Işınlanma/Teleport Tespiti)
  const limit30Kmh = 30;

  const lastCheckInSnapshot = await db.collection("venue_checkins")
    .where("userId", "==", userId)
    .orderBy("markedAt", "desc")
    .limit(1)
    .get();

  if (!lastCheckInSnapshot.empty) {
    const lastDoc = lastCheckInSnapshot.docs[0].data();

    if (lastDoc.markedAt && lastDoc.userLat && lastDoc.userLng) {
      const lastTime = lastDoc.markedAt.toDate().getTime();
      const currentTime = Date.now();

      const hoursPassed = (currentTime - lastTime) / (1000 * 60 * 60);

      const distanceKm = getDistanceFromLatLonInKm(lastDoc.userLat, lastDoc.userLng, userLat, userLng);

      if (hoursPassed > 0) {
        const speedKmH = distanceKm / hoursPassed;
        if (speedKmH > limit30Kmh) {
          console.warn(`[Speed Error] User: ${userId}, Speed: ${speedKmH} km/h`);
          return { status: 'speed_error' };
        }
      }
    }
  }

  // 2. HAFTALIK GÖREV İŞLEME DİĞER TARAFA ALINDI: BURADA SADECE DOĞRULAMA (SPOOF / SPEED) YAPILIYOR
  try {
    const compositeId = `${userId}_${venueId}`;
    const checkInRef = db.collection("venue_checkins").doc(compositeId);

    // Idempotent constraint & Log saving
    await db.runTransaction(async (transaction) => {
      const checkInDoc = await transaction.get(checkInRef);
      if (checkInDoc.exists) {
        return;
      }

      transaction.set(checkInRef, {
        venueId,
        mapId,
        userId,
        markedAt: admin.firestore.FieldValue.serverTimestamp(),
        userLat,
        userLng,
        accuracy,
        isMocked,
        distance
      });
    });

    return { status: 'success' };
  } catch (error) {
    console.error("Gezdim Transaction Hatası:", error);
    throw new functions.https.HttpsError('internal', 'Server error during check-in');
  }
});

// ────────────────────────────────────────────────────────────
// YARDIMCI: Geçersiz FCM token'ını Firestore'dan sil
// ────────────────────────────────────────────────────────────
async function deleteStaleToken(uid: string): Promise<void> {
  try {
    await admin.firestore().collection("users").doc(uid).update({ fcmToken: admin.firestore.FieldValue.delete() });
    console.log(`[FCM] Stale token silindi: ${uid}`);
  } catch (err) {
    console.error(`[FCM] Token silinirken hata (${uid}):`, err);
  }
}

// ────────────────────────────────────────────────────────────
// YARDIMCI: FCM bildirimi gönder, stale token'ı temizle
// ────────────────────────────────────────────────────────────
async function sendNotification(
  uid: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<void> {
  try {
    await admin.messaging().send({
      token,
      notification: { title, body },
      data,
      android: { priority: "high" },
      apns: { payload: { aps: { sound: "default" } } },
    });
  } catch (err: unknown) {
    const fcmError = err as { errorInfo?: { code?: string } };
    if (fcmError?.errorInfo?.code === "messaging/registration-token-not-registered") {
      await deleteStaleToken(uid);
    } else {
      console.error(`[FCM] Bildirim gönderilemedi (${uid}):`, err);
    }
  }
}

// ────────────────────────────────────────────────────────────
// 1. HAFTALIK GÖREV HATIRLATICI
//    Her gün 09:00 İstanbul (UTC 06:00) saatinde çalışır.
//
//    Gerekli Firestore Composite Index:
//      Collection : weeklyTasks
//      Fields     : completed (ASC), dueAt (ASC)
// ────────────────────────────────────────────────────────────
export const sendWeeklyTaskReminders = onSchedule(
  { schedule: "0 6 * * *", timeZone: "Europe/Istanbul" },
  async () => {
    const db = admin.firestore();

    // Haftanın sonunu hesapla (Pazar 23:59:59)
    const now = new Date();
    const endOfWeek = new Date(now);
    const dayOfWeek = now.getDay(); // 0=Pazar
    const daysUntilSunday = dayOfWeek === 0 ? 0 : 7 - dayOfWeek;
    endOfWeek.setDate(now.getDate() + daysUntilSunday);
    endOfWeek.setHours(23, 59, 59, 999);

    try {
      // Tamamlanmamış ve bu haftaya ait görevleri çek
      const tasksSnap = await db
        .collection("weeklyTasks")
        .where("completed", "==", false)
        .where("dueAt", "<=", admin.firestore.Timestamp.fromDate(endOfWeek))
        .get();

      if (tasksSnap.empty) {
        console.log("[WeeklyTask] Bekleyen görev yok.");
        return;
      }

      // uid → görev başlıkları eşlemesi oluştur (bir kullanıcının N görevi olabilir)
      const tasksByUid = new Map<string, string[]>();
      for (const doc of tasksSnap.docs) {
        const { assignedTo, title } = doc.data() as { assignedTo: string; title: string };
        if (!tasksByUid.has(assignedTo)) tasksByUid.set(assignedTo, []);
        tasksByUid.get(assignedTo)!.push(title);
      }

      // Kullanıcıları batch olarak çek (getAll — tek round trip)
      const uids = Array.from(tasksByUid.keys());
      const userRefs = uids.map((uid) => db.collection("users").doc(uid));
      const userDocs = await db.getAll(...userRefs);

      const sendPromises: Promise<void>[] = [];

      for (const userDoc of userDocs) {
        if (!userDoc.exists) continue;

        const uid = userDoc.id;
        const userData = userDoc.data() as {
          fcmToken?: string;
          notificationPrefs?: { weeklyTask?: boolean };
        };

        const token = userData.fcmToken;
        if (!token) continue;

        if (userData.notificationPrefs?.weeklyTask === false) continue;

        const titles = tasksByUid.get(uid) ?? [];
        const bodyText =
          titles.length === 1
            ? titles[0]
            : `${titles[0]} ve ${titles.length - 1} görev daha seni bekliyor`;

        sendPromises.push(
          sendNotification(uid, token, "📋 Görevin seni bekliyor!", bodyText, {
            route: "/tasks",
          })
        );
      }

      await Promise.all(sendPromises);
      console.log(`[WeeklyTask] ${sendPromises.length} bildirim gönderildi.`);
    } catch (error) {
      console.error("[WeeklyTask] Hata:", error);
    }
  }
);

// ────────────────────────────────────────────────────────────
// 2. ARKADAŞLIK İSTEĞİ BİLDİRİMİ
// ────────────────────────────────────────────────────────────
export const onFriendRequestWritten = onDocumentWritten(
  "friendRequests/{requestId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const afterData = snap.after.data() as {
      fromUid: string;
      toUid: string;
      status: string;
    } | undefined;
    const beforeData = snap.before.data() as { status?: string } | undefined;

    if (!afterData) return; // deleted
    if (afterData.status !== "pending") return;
    if (beforeData && beforeData.status === "pending") return; // didn't change

    const requestId = event.params.requestId;
    const { fromUid, toUid } = afterData;
    const db = admin.firestore();

    try {
      // fromUid (username) ve toUid (token + prefs) verisini tek seferde çek
      const [fromDoc, toDoc] = await db.getAll(
        db.collection("users").doc(fromUid),
        db.collection("users").doc(toUid)
      );

      if (!toDoc.exists) return;

      const toData = toDoc.data() as {
        fcmToken?: string;
        notificationPrefs?: { friendRequest?: boolean };
      };

      const token = toData.fcmToken;
      if (!token) return;

      if (toData.notificationPrefs?.friendRequest === false) return;

      const fromData = fromDoc.data() as { username?: string };
      const username = fromData?.username ?? "Biri";

      await sendNotification(
        toUid,
        token,
        "👤 Yeni arkadaşlık isteği",
        `${username} sana arkadaşlık isteği gönderdi`,
        { route: "/friend-requests", requestId }
      );

      console.log(`[FriendRequest] ${fromUid} → ${toUid} bildirimi gönderildi.`);
    } catch (error) {
      console.error("[FriendRequest] Hata:", error);
    }
  }
);

// ────────────────────────────────────────────────────────────
// 3. ODA DAVETİ BİLDİRİMİ
// ────────────────────────────────────────────────────────────
export const onRoomInviteWritten = onDocumentWritten(
  "invites/{inviteId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const afterData = snap.after.data() as {
      fromUserId: string;
      toUserId: string;
      roomId: string;
      roomName: string;
      status: string;
    } | undefined;
    const beforeData = snap.before.data() as { status?: string } | undefined;

    if (!afterData) return; // deleted
    if (afterData.status !== "pending") return;
    if (beforeData && beforeData.status === "pending") return; // didn't change

    const inviteId = event.params.inviteId;
    const { fromUserId: fromUid, toUserId: toUid, roomId, roomName } = afterData;
    const db = admin.firestore();

    try {
      const [fromDoc, toDoc] = await db.getAll(
        db.collection("users").doc(fromUid),
        db.collection("users").doc(toUid)
      );

      if (!toDoc.exists) return;

      const toData = toDoc.data() as {
        fcmToken?: string;
        notificationPrefs?: { roomInvite?: boolean };
      };

      const token = toData.fcmToken;
      if (!token) return;

      if (toData.notificationPrefs?.roomInvite === false) return;

      const fromData = fromDoc.data() as { username?: string };
      const username = fromData?.username ?? "Biri";

      await sendNotification(
        toUid,
        token,
        "✉️ Oda daveti!",
        `${username} seni '${roomName}' odasına davet etti`,
        { route: "/pending-invites", inviteId, roomId }
      );

      console.log(`[RoomInvite] ${fromUid} → ${toUid} bildirimi gönderildi.`);
    } catch (error) {
      console.error("[RoomInvite] Hata:", error);
    }
  }
);
