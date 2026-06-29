"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onAdminNotificationWritten = exports.doubleQuestReward = exports.claimDailyAdReward = exports.resetWeeklyXP = exports.onRoomInviteWritten = exports.onFriendRequestWritten = exports.sendWeeklyTaskReminders = exports.verifyAndCheckIn = void 0;
const functions = require("firebase-functions");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const firestore_1 = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
admin.initializeApp();
// Haversine formula (km)
function getDistanceFromLatLonInKm(lat1, lon1, lat2, lon2) {
    const R = 6371;
    const dLat = deg2rad(lat2 - lat1);
    const dLon = deg2rad(lon2 - lon1);
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
}
function deg2rad(deg) {
    return deg * (Math.PI / 180);
}
exports.verifyAndCheckIn = functions.https.onCall(async (request) => {
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
    }
    catch (error) {
        console.error("Gezdim Transaction Hatası:", error);
        throw new functions.https.HttpsError('internal', 'Server error during check-in');
    }
});
// ────────────────────────────────────────────────────────────
// YARDIMCI: Geçersiz FCM token'ını Firestore'dan sil
// ────────────────────────────────────────────────────────────
async function deleteStaleToken(uid) {
    try {
        await admin.firestore().collection("users").doc(uid).update({ fcmToken: admin.firestore.FieldValue.delete() });
        console.log(`[FCM] Stale token silindi: ${uid}`);
    }
    catch (err) {
        console.error(`[FCM] Token silinirken hata (${uid}):`, err);
    }
}
// ────────────────────────────────────────────────────────────
// YARDIMCI: FCM bildirimi gönder, stale token'ı temizle
// ────────────────────────────────────────────────────────────
async function sendNotification(uid, token, title, body, data) {
    try {
        await admin.messaging().send({
            token,
            notification: { title, body },
            data,
            android: { priority: "high" },
            apns: { payload: { aps: { sound: "default" } } },
        });
    }
    catch (err) {
        const fcmError = err;
        if (fcmError?.errorInfo?.code === "messaging/registration-token-not-registered") {
            await deleteStaleToken(uid);
        }
        else {
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
exports.sendWeeklyTaskReminders = (0, scheduler_1.onSchedule)({ schedule: "0 6 * * *", timeZone: "Europe/Istanbul" }, async () => {
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
        const tasksByUid = new Map();
        for (const doc of tasksSnap.docs) {
            const { assignedTo, title } = doc.data();
            if (!tasksByUid.has(assignedTo))
                tasksByUid.set(assignedTo, []);
            tasksByUid.get(assignedTo).push(title);
        }
        // Kullanıcıları batch olarak çek (getAll — tek round trip)
        const uids = Array.from(tasksByUid.keys());
        const userRefs = uids.map((uid) => db.collection("users").doc(uid));
        const userDocs = await db.getAll(...userRefs);
        const sendPromises = [];
        for (const userDoc of userDocs) {
            if (!userDoc.exists)
                continue;
            const uid = userDoc.id;
            const userData = userDoc.data();
            const token = userData.fcmToken;
            if (!token)
                continue;
            if (userData.notificationPrefs?.weeklyTask === false)
                continue;
            const titles = tasksByUid.get(uid) ?? [];
            const bodyText = titles.length === 1
                ? titles[0]
                : `${titles[0]} ve ${titles.length - 1} görev daha seni bekliyor`;
            sendPromises.push(sendNotification(uid, token, "📋 Görevin seni bekliyor!", bodyText, {
                route: "/tasks",
            }));
        }
        await Promise.all(sendPromises);
        console.log(`[WeeklyTask] ${sendPromises.length} bildirim gönderildi.`);
    }
    catch (error) {
        console.error("[WeeklyTask] Hata:", error);
    }
});
// ────────────────────────────────────────────────────────────
// 2. ARKADAŞLIK İSTEĞİ BİLDİRİMİ
// ────────────────────────────────────────────────────────────
exports.onFriendRequestWritten = (0, firestore_1.onDocumentWritten)("friendRequests/{requestId}", async (event) => {
    const snap = event.data;
    if (!snap)
        return;
    const afterData = snap.after.data();
    const beforeData = snap.before.data();
    if (!afterData)
        return; // deleted
    if (afterData.status !== "pending")
        return;
    if (beforeData && beforeData.status === "pending")
        return; // didn't change
    const requestId = event.params.requestId;
    const { fromUid, toUid } = afterData;
    const db = admin.firestore();
    try {
        // fromUid (username) ve toUid (token + prefs) verisini tek seferde çek
        const [fromDoc, toDoc] = await db.getAll(db.collection("users").doc(fromUid), db.collection("users").doc(toUid));
        if (!toDoc.exists)
            return;
        const toData = toDoc.data();
        const token = toData.fcmToken;
        if (!token)
            return;
        if (toData.notificationPrefs?.friendRequest === false)
            return;
        const fromData = fromDoc.data();
        const username = fromData?.username ?? "Biri";
        await sendNotification(toUid, token, "👤 Yeni arkadaşlık isteği", `${username} sana arkadaşlık isteği gönderdi`, { route: "/friend-requests", requestId });
        console.log(`[FriendRequest] ${fromUid} → ${toUid} bildirimi gönderildi.`);
    }
    catch (error) {
        console.error("[FriendRequest] Hata:", error);
    }
});
// ────────────────────────────────────────────────────────────
// 3. ODA DAVETİ BİLDİRİMİ
// ────────────────────────────────────────────────────────────
exports.onRoomInviteWritten = (0, firestore_1.onDocumentWritten)("invites/{inviteId}", async (event) => {
    const snap = event.data;
    if (!snap)
        return;
    const afterData = snap.after.data();
    const beforeData = snap.before.data();
    if (!afterData)
        return; // deleted
    if (afterData.status !== "pending")
        return;
    if (beforeData && beforeData.status === "pending")
        return; // didn't change
    const inviteId = event.params.inviteId;
    const { fromUserId: fromUid, toUserId: toUid, roomId, roomName } = afterData;
    const db = admin.firestore();
    try {
        const [fromDoc, toDoc] = await db.getAll(db.collection("users").doc(fromUid), db.collection("users").doc(toUid));
        if (!toDoc.exists)
            return;
        const toData = toDoc.data();
        const token = toData.fcmToken;
        if (!token)
            return;
        if (toData.notificationPrefs?.roomInvite === false)
            return;
        const fromData = fromDoc.data();
        const username = fromData?.username ?? "Biri";
        await sendNotification(toUid, token, "✉️ Oda daveti!", `${username} seni '${roomName}' odasına davet etti`, { route: "/pending-invites", inviteId, roomId });
        console.log(`[RoomInvite] ${fromUid} → ${toUid} bildirimi gönderildi.`);
    }
    catch (error) {
        console.error("[RoomInvite] Hata:", error);
    }
});
// ────────────────────────────────────────────────────────────
// 4. HAFTALIK XP SIFIRLAMA
//    Her Pazartesi 00:00 İstanbul saatinde tüm kullanıcıları sıfırlar.
// ────────────────────────────────────────────────────────────
exports.resetWeeklyXP = (0, scheduler_1.onSchedule)({ schedule: "0 0 * * 1", timeZone: "Europe/Istanbul" }, async () => {
    const db = admin.firestore();
    const [leaderboardSnap, usersSnap] = await Promise.all([
        db.collection("leaderboard").get(),
        db.collection("users").get(),
    ]);
    const allWrites = [];
    const chunk = (arr, size) => Array.from({ length: Math.ceil(arr.length / size) }, (_, i) => arr.slice(i * size, i * size + size));
    // Leaderboard sıfırla
    for (const docs of chunk(leaderboardSnap.docs, 499)) {
        const batch = db.batch();
        docs.forEach((doc) => batch.update(doc.ref, {
            weeklyXP: 0,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }));
        allWrites.push(batch);
    }
    // Users weeklyXP sıfırla
    for (const docs of chunk(usersSnap.docs, 499)) {
        const batch = db.batch();
        docs.forEach((doc) => batch.update(doc.ref, {
            weeklyXP: 0,
            weeklyXPUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }));
        allWrites.push(batch);
    }
    await Promise.all(allWrites.map((b) => b.commit()));
    console.log(`[WeeklyReset] ${leaderboardSnap.size} leaderboard + ${usersSnap.size} users sıfırlandı.`);
});
// ────────────────────────────────────────────────────────────
// 5. ADMIN PANEL GENEL BİLDİRİMİ (TOPIC)
// ────────────────────────────────────────────────────────────
// ────────────────────────────────────────────────────────────
// YARDIMCI: XP değerine göre unvan ve renk döndür
// ────────────────────────────────────────────────────────────
function getUserTitleAndColor(xp) {
    if (xp >= 20000)
        return { title: "Efsane", colorHex: "ffff1744" };
    if (xp >= 9000)
        return { title: "Usta Kaşif", colorHex: "fff5a623" };
    if (xp >= 4000)
        return { title: "Seyyah", colorHex: "ffec4899" };
    if (xp >= 1500)
        return { title: "Kaşif", colorHex: "ff2196f3" };
    if (xp >= 500)
        return { title: "Gezgin", colorHex: "ff10b981" };
    return { title: "Yolcu", colorHex: "ff94a3b8" };
}
// ────────────────────────────────────────────────────────────
// 6. GÜNLÜK ÖDÜLLÜ REKLAM — XP EKLE
//    Client: rewarded reklamı göster → bu fonksiyonu çağır.
//    Günlük limit: 3 izleme / gün. XP sunucu tarafında eklenir.
// ────────────────────────────────────────────────────────────
exports.claimDailyAdReward = functions.https.onCall(async (request) => {
    if (!request.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Token yok");
    }
    const userId = request.auth.uid;
    const db = admin.firestore();
    const userRef = db.collection("users").doc(userId);
    const now = new Date();
    const today = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
    const dailyXP = 25;
    const maxDaily = 3;
    let watchedToday = 0;
    try {
        await db.runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new functions.https.HttpsError("not-found", "Kullanıcı bulunamadı");
            }
            const data = userDoc.data();
            const storedDate = data.dailyAdsResetDate ?? "";
            let watched = storedDate === today ? (data.dailyAdsWatched ?? 0) : 0;
            if (watched >= maxDaily) {
                throw new functions.https.HttpsError("resource-exhausted", "Günlük limit doldu");
            }
            const currentXP = data.xp ?? 0;
            const currentWeeklyXP = data.weeklyXP ?? 0;
            const username = data.username ?? "";
            const newXP = currentXP + dailyXP;
            const newWeeklyXP = currentWeeklyXP + dailyXP;
            watchedToday = watched + 1;
            transaction.set(userRef, {
                xp: newXP,
                weeklyXP: newWeeklyXP,
                weeklyXPUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
                dailyAdsWatched: watchedToday,
                dailyAdsResetDate: today,
            }, { merge: true });
            // Leaderboard sync
            const { title, colorHex } = getUserTitleAndColor(newXP);
            const leaderboardRef = db.collection("leaderboard").doc(userId);
            transaction.set(leaderboardRef, {
                weeklyXP: newWeeklyXP,
                totalXP: newXP,
                title,
                titleColorHex: colorHex,
                username,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        });
        console.log(`[DailyAdReward] ${userId} → +${dailyXP} XP (${watchedToday}/${maxDaily} today)`);
        return { success: true, xpAdded: dailyXP, watchedToday, maxDaily };
    }
    catch (error) {
        if (error instanceof functions.https.HttpsError)
            throw error;
        console.error("[DailyAdReward] Hata:", error);
        throw new functions.https.HttpsError("internal", "Sunucu hatası");
    }
});
// ────────────────────────────────────────────────────────────
// 7. GÖREV XP'SİNİ 2'YE KATLA
//    Client: rewarded reklamı göster → bu fonksiyonu çağır.
//    Her görev haftada yalnızca bir kez katlanabilir.
//    Takip: weeklyQuests.doubledKeys (dizi) — hafta sıfırlandığında temizlenir.
// ────────────────────────────────────────────────────────────
exports.doubleQuestReward = functions.https.onCall(async (request) => {
    if (!request.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Token yok");
    }
    const userId = request.auth.uid;
    const questKey = request.data?.questKey;
    // Server-authoritative quest XP map
    const questXpMap = {
        ilkAdim: 50,
        kasifRuhu: 100,
        cesitliKasif: 75,
        duzenliGezgin: 75,
        takimOyuncusu: 100,
        takimKasifi: 100,
        tamHafta: 300,
    };
    if (!questKey || !(questKey in questXpMap)) {
        throw new functions.https.HttpsError("invalid-argument", "Geçersiz görev anahtarı");
    }
    const bonusXP = questXpMap[questKey];
    const db = admin.firestore();
    const userRef = db.collection("users").doc(userId);
    try {
        await db.runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new functions.https.HttpsError("not-found", "Kullanıcı bulunamadı");
            }
            const data = userDoc.data();
            const weeklyQuests = data.weeklyQuests ?? {};
            // Quest tamamlanmış mı?
            const questData = weeklyQuests[questKey] ?? {};
            if (questData.done !== true) {
                throw new functions.https.HttpsError("failed-precondition", "Görev henüz tamamlanmadı");
            }
            // Bu hafta zaten katlandı mı?
            const doubledKeys = weeklyQuests.doubledKeys ?? [];
            if (doubledKeys.includes(questKey)) {
                throw new functions.https.HttpsError("already-exists", "Bu görev zaten çift XP aldı");
            }
            const currentXP = data.xp ?? 0;
            const currentWeeklyXP = data.weeklyXP ?? 0;
            const username = data.username ?? "";
            const newXP = currentXP + bonusXP;
            const newWeeklyXP = currentWeeklyXP + bonusXP;
            transaction.set(userRef, {
                xp: newXP,
                weeklyXP: newWeeklyXP,
                weeklyXPUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
                // doubledKeys'i weeklyQuests haritasına ekle (hafta sıfırında temizlenir)
                "weeklyQuests.doubledKeys": admin.firestore.FieldValue.arrayUnion(questKey),
            }, { merge: true });
            // Leaderboard sync
            const { title, colorHex } = getUserTitleAndColor(newXP);
            const leaderboardRef = db.collection("leaderboard").doc(userId);
            transaction.set(leaderboardRef, {
                weeklyXP: newWeeklyXP,
                totalXP: newXP,
                title,
                titleColorHex: colorHex,
                username,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        });
        console.log(`[DoubleQuestReward] ${userId} → ${questKey} +${bonusXP} XP bonus`);
        return { success: true, xpAdded: bonusXP };
    }
    catch (error) {
        if (error instanceof functions.https.HttpsError)
            throw error;
        console.error("[DoubleQuestReward] Hata:", error);
        throw new functions.https.HttpsError("internal", "Sunucu hatası");
    }
});
exports.onAdminNotificationWritten = (0, firestore_1.onDocumentWritten)("adminNotifications/{notificationId}", async (event) => {
    const snap = event.data;
    if (!snap)
        return;
    const afterData = snap.after.data();
    const beforeData = snap.before.data();
    if (!afterData)
        return; // deleted
    if (afterData.status !== "pending")
        return;
    if (beforeData && beforeData.status === "pending")
        return; // didn't change
    try {
        const message = {
            topic: "announcements",
            notification: {
                title: afterData.title ?? "Yeni Duyuru",
                body: afterData.body ?? "Exploria'dan yeni bir haber var!",
            },
            android: { priority: "high" },
            apns: { payload: { aps: { sound: "default" } } },
        };
        await admin.messaging().send(message);
        // Gönderildi olarak işaretle
        await snap.after.ref.update({
            status: "sent",
            sentAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log(`[AdminNotification] Genel bildirim başarıyla gönderildi: ${afterData.title}`);
    }
    catch (error) {
        await snap.after.ref.update({ status: "error", error: String(error) });
        console.error("[AdminNotification] Hata:", error);
    }
});
//# sourceMappingURL=index.js.map