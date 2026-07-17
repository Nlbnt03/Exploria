"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onAdminNotificationWritten = exports.doubleQuestReward = exports.claimDailyAdReward = exports.resetWeeklyXP = exports.onRoomInviteWritten = exports.onPlaceSuggestionWritten = exports.onFriendRequestWritten = exports.sendWeeklyTaskReminders = exports.verifyAndCheckIn = exports.onMapPoiWritten = exports.reconcileActiveMapCounts = exports.retryPendingAccountDeletions = exports.cleanupExpiredRoomsAndInvites = exports.onUserMapStateWritten = exports.deleteMap = exports.createMap = exports.deleteAccount = exports.unblockUser = exports.blockUser = exports.sendFriendRequest = void 0;
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
const MAX_ACTIVE_MAPS = 5;
const ROOM_RETENTION_DAYS = 30;
const CLOSED_INVITE_RETENTION_DAYS = 30;
const PENDING_INVITE_RETENTION_DAYS = 7;
const MILLIS_PER_DAY = 24 * 60 * 60 * 1000;
const CLEANUP_BATCH_LIMIT = 200;
function assertVerifiedEmail(auth) {
    if (auth.token.email_verified !== true) {
        throw new functions.https.HttpsError("failed-precondition", "Bu işlem için e-posta adresini doğrulamalısın.");
    }
}
function assertString(value, field, maxLength) {
    if (typeof value !== "string") {
        throw new functions.https.HttpsError("invalid-argument", `${field} metin olmalı.`);
    }
    const trimmed = value.trim();
    if (!trimmed || trimmed.length > maxLength) {
        throw new functions.https.HttpsError("invalid-argument", `${field} boş olamaz ve ${maxLength} karakteri geçemez.`);
    }
    return trimmed;
}
function validateBoundsGeometry(raw) {
    if (!Array.isArray(raw) || raw.length < 3 || raw.length > 200) {
        throw new functions.https.HttpsError("invalid-argument", "bounds en az 3 koordinattan oluşmalı.");
    }
    const points = raw.map((item) => {
        if (!item || typeof item !== "object") {
            throw new functions.https.HttpsError("invalid-argument", "bounds koordinatları geçersiz.");
        }
        const record = item;
        const lat = record.lat;
        const lng = record.lng;
        if (typeof lat !== "number" || typeof lng !== "number") {
            throw new functions.https.HttpsError("invalid-argument", "bounds lat/lng sayısal olmalı.");
        }
        if (!Number.isFinite(lat) || !Number.isFinite(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
            throw new functions.https.HttpsError("invalid-argument", "bounds koordinat aralığı geçersiz.");
        }
        return { lat, lng };
    });
    const unique = new Set(points.map((point) => `${point.lat.toFixed(7)},${point.lng.toFixed(7)}`));
    if (unique.size < 3) {
        throw new functions.https.HttpsError("invalid-argument", "bounds en az 3 farklı nokta içermeli.");
    }
    return points;
}
function parseTotalPois(raw) {
    if (typeof raw !== "number" || !Number.isInteger(raw) || raw < 0 || raw > 10000) {
        throw new functions.https.HttpsError("invalid-argument", "totalPois geçerli bir tam sayı olmalı.");
    }
    return raw;
}
function parseOptionalInt(raw, field, min, max) {
    if (raw === undefined || raw === null)
        return 0;
    if (typeof raw !== "number" || !Number.isInteger(raw) || raw < min || raw > max) {
        throw new functions.https.HttpsError("invalid-argument", `${field} geçerli bir tam sayı olmalı.`);
    }
    return raw;
}
function parseCoordinate(raw, field, min, max) {
    if (typeof raw !== "number" || !Number.isFinite(raw) || raw < min || raw > max) {
        throw new functions.https.HttpsError("invalid-argument", `${field} koordinatı geçersiz.`);
    }
    return raw;
}
function parseNumber(raw, field, min, max) {
    if (typeof raw !== "number" || !Number.isFinite(raw) || raw < min || raw > max) {
        throw new functions.https.HttpsError("invalid-argument", `${field} değeri geçersiz.`);
    }
    return raw;
}
function parseStringArray(raw) {
    if (!Array.isArray(raw))
        return [];
    return raw
        .filter((value) => typeof value === "string")
        .map((value) => value.trim())
        .filter((value) => value.length > 0);
}
function parseProgress(raw) {
    if (!raw || typeof raw !== "object") {
        return { totalPois: 0, visitedPois: 0, earnedXp: 0 };
    }
    const progress = raw;
    const totalPois = typeof progress.totalPois === "number" ? Math.max(0, Math.floor(progress.totalPois)) : 0;
    const visitedPois = typeof progress.visitedPois === "number" ? Math.max(0, Math.floor(progress.visitedPois)) : 0;
    const earnedXp = typeof progress.earnedXp === "number" ? Math.max(0, Math.floor(progress.earnedXp)) : 0;
    return { totalPois, visitedPois, earnedXp };
}
function isActivePoi(data) {
    if (!data)
        return false;
    const raw = data.isActive;
    if (typeof raw === "boolean")
        return raw;
    if (typeof raw === "number")
        return raw === 1;
    if (typeof raw === "string")
        return raw.toLowerCase() === "true";
    return true;
}
function mapStateRef(uid, mapId) {
    return admin.firestore()
        .collection("userMapStates")
        .doc(uid)
        .collection("states")
        .doc(mapId);
}
async function deleteQueryDocuments(db, query) {
    const snapshot = await query.get();
    if (snapshot.empty)
        return 0;
    const writer = db.bulkWriter();
    for (const doc of snapshot.docs) {
        writer.delete(doc.ref);
    }
    await writer.close();
    return snapshot.size;
}
async function removeDeletedUserFromFriendEdges(db, uid) {
    const edges = await db.collectionGroup("friends")
        .where("friendUid", "==", uid)
        .get();
    for (const edge of edges.docs) {
        const ownerRef = edge.ref.parent.parent;
        if (!ownerRef || ownerRef.id === uid)
            continue;
        await db.runTransaction(async (transaction) => {
            const [edgeSnap, ownerSnap] = await Promise.all([
                transaction.get(edge.ref),
                transaction.get(ownerRef),
            ]);
            if (!edgeSnap.exists)
                return;
            transaction.delete(edge.ref);
            if (!ownerSnap.exists)
                return;
            const currentCount = ownerSnap.data()?.friendsCount ?? 0;
            transaction.set(ownerRef, {
                friends: admin.firestore.FieldValue.arrayRemove(uid),
                friendsCount: Math.max(0, currentCount - 1),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        });
    }
    // Eski veya yarım kalmış kayıtlarda alt koleksiyon kenarı bulunmasa bile
    // users.friends dizisinde silinen kullanıcı kalmasın.
    const danglingUsers = await db.collection("users")
        .where("friends", "array-contains", uid)
        .get();
    for (const user of danglingUsers.docs) {
        if (user.id === uid)
            continue;
        await db.runTransaction(async (transaction) => {
            const snapshot = await transaction.get(user.ref);
            if (!snapshot.exists)
                return;
            const friends = snapshot.data()?.friends;
            if (!Array.isArray(friends) || !friends.includes(uid))
                return;
            const currentCount = snapshot.data()?.friendsCount ?? 0;
            transaction.set(user.ref, {
                friends: admin.firestore.FieldValue.arrayRemove(uid),
                friendsCount: Math.max(0, currentCount - 1),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        });
    }
}
async function detachDeletedUserFromRooms(db, uid) {
    const memberships = await db.collectionGroup("members")
        .where("uid", "==", uid)
        .get();
    for (const membership of memberships.docs) {
        const roomRef = membership.ref.parent.parent;
        if (!roomRef)
            continue;
        await db.runTransaction(async (transaction) => {
            const roomSnap = await transaction.get(roomRef);
            if (!roomSnap.exists) {
                transaction.delete(membership.ref);
                transaction.delete(roomRef.collection("locations").doc(uid));
                transaction.delete(roomRef.collection("presence").doc(uid));
                return;
            }
            const room = roomSnap.data() ?? {};
            const status = room.status ?? "waiting";
            const isHost = room.hostId === uid;
            if (isHost && status !== "finished") {
                const members = await transaction.get(roomRef.collection("members"));
                const nextHost = members.docs.find((doc) => doc.id !== uid);
                if (nextHost) {
                    transaction.set(roomRef, {
                        hostId: nextHost.id,
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    }, { merge: true });
                }
                else {
                    transaction.set(roomRef, {
                        status: "finished",
                        finishedAt: admin.firestore.FieldValue.serverTimestamp(),
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    }, { merge: true });
                }
            }
            else if (isHost) {
                transaction.set(roomRef, { hostId: "deleted-user" }, { merge: true });
            }
            transaction.delete(membership.ref);
            transaction.delete(roomRef.collection("locations").doc(uid));
            transaction.delete(roomRef.collection("presence").doc(uid));
        });
    }
    // Eski veya tutarsız odalarda üyelik belgesi kayıp olsa bile silinen
    // kullanıcı host olarak kalıp odayı kilitlemesin.
    const hostedRooms = await db.collection("rooms")
        .where("hostId", "==", uid)
        .get();
    for (const hostedRoom of hostedRooms.docs) {
        await db.runTransaction(async (transaction) => {
            const [roomSnap, members] = await Promise.all([
                transaction.get(hostedRoom.ref),
                transaction.get(hostedRoom.ref.collection("members")),
            ]);
            if (!roomSnap.exists || roomSnap.data()?.hostId !== uid)
                return;
            const status = roomSnap.data()?.status ?? "waiting";
            const nextHost = members.docs.find((doc) => doc.id !== uid);
            if (status !== "finished" && nextHost) {
                transaction.set(hostedRoom.ref, {
                    hostId: nextHost.id,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });
            }
            else if (status !== "finished") {
                transaction.set(hostedRoom.ref, {
                    status: "finished",
                    finishedAt: admin.firestore.FieldValue.serverTimestamp(),
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });
            }
            else {
                transaction.set(hostedRoom.ref, { hostId: "deleted-user" }, { merge: true });
            }
        });
    }
    const visits = await db.collectionGroup("visits")
        .where("visitedBy", "==", uid)
        .get();
    if (!visits.empty) {
        const writer = db.bulkWriter();
        for (const visit of visits.docs) {
            writer.update(visit.ref, { visitedBy: "deleted-user" });
        }
        await writer.close();
    }
}
async function deleteUserOwnedData(db, uid) {
    const userRef = db.collection("users").doc(uid);
    const userMapStateRef = db.collection("userMapStates").doc(uid);
    await removeDeletedUserFromFriendEdges(db, uid);
    await detachDeletedUserFromRooms(db, uid);
    const queries = [
        db.collection("usernames").where("uid", "==", uid),
        db.collection("friendRequests").where("fromUid", "==", uid),
        db.collection("friendRequests").where("toUid", "==", uid),
        db.collection("invites").where("fromUserId", "==", uid),
        db.collection("invites").where("toUserId", "==", uid),
        db.collection("multiInvites").where("fromUid", "==", uid),
        db.collection("multiInvites").where("toUid", "==", uid),
        db.collection("venue_checkins").where("userId", "==", uid),
        db.collection("placeSuggestions").where("userId", "==", uid),
        db.collection("userReports").where("reporterUid", "==", uid),
        db.collection("userReports").where("reportedUid", "==", uid),
        db.collectionGroup("blockedUsers").where("blockedUid", "==", uid),
    ];
    for (const query of queries) {
        await deleteQueryDocuments(db, query);
    }
    await db.recursiveDelete(userMapStateRef);
    await db.recursiveDelete(userRef);
    await db.collection("leaderboard").doc(uid).delete();
}
async function processAccountDeletion(db, uid) {
    const jobRef = db.collection("accountDeletionJobs").doc(uid);
    try {
        await deleteUserOwnedData(db, uid);
        try {
            await admin.auth().deleteUser(uid);
        }
        catch (error) {
            const code = error.code;
            if (code !== "auth/user-not-found")
                throw error;
        }
        await jobRef.delete();
    }
    catch (error) {
        await jobRef.set({
            uid,
            status: "pending",
            attempts: admin.firestore.FieldValue.increment(1),
            lastError: error instanceof Error ? error.message.slice(0, 500) : "unknown",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        throw error;
    }
}
function pairKey(uidA, uidB) {
    return [uidA, uidB].sort().join("_");
}
exports.sendFriendRequest = functions.https.onCall(async (request) => {
    if (!request.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Oturum yok.");
    }
    assertVerifiedEmail(request.auth);
    const fromUid = request.auth.uid;
    const data = request.data;
    const toUid = assertString(data.toUid, "toUid", 160);
    if (fromUid === toUid) {
        throw new functions.https.HttpsError("invalid-argument", "Kendine arkadaşlık isteği gönderemezsin.");
    }
    const db = admin.firestore();
    const fromUserRef = db.collection("users").doc(fromUid);
    const toUserRef = db.collection("users").doc(toUid);
    const requestRef = db.collection("friendRequests").doc(`${fromUid}_${toUid}`);
    const reverseRef = db.collection("friendRequests").doc(`${toUid}_${fromUid}`);
    const fromFriendRef = fromUserRef.collection("friends").doc(toUid);
    const toFriendRef = toUserRef.collection("friends").doc(fromUid);
    const fromBlockedToRef = fromUserRef.collection("blockedUsers").doc(toUid);
    const toBlockedFromRef = toUserRef.collection("blockedUsers").doc(fromUid);
    await db.runTransaction(async (transaction) => {
        const [fromUser, toUser, requestSnap, reverseSnap, fromFriend, toFriend, fromBlockedTo, toBlockedFrom,] = await Promise.all([
            transaction.get(fromUserRef),
            transaction.get(toUserRef),
            transaction.get(requestRef),
            transaction.get(reverseRef),
            transaction.get(fromFriendRef),
            transaction.get(toFriendRef),
            transaction.get(fromBlockedToRef),
            transaction.get(toBlockedFromRef),
        ]);
        if (!fromUser.exists || !toUser.exists) {
            throw new functions.https.HttpsError("not-found", "Kullanıcı bulunamadı.");
        }
        if (fromFriend.exists || toFriend.exists) {
            throw new functions.https.HttpsError("already-exists", "Bu kullanıcı zaten arkadaş listende.");
        }
        if (fromBlockedTo.exists || toBlockedFrom.exists) {
            throw new functions.https.HttpsError("failed-precondition", "Bu kullanıcıya arkadaşlık isteği gönderilemez.");
        }
        const requestStatus = requestSnap.data()?.status;
        if (requestStatus === "pending") {
            throw new functions.https.HttpsError("already-exists", "Bu kullanıcıya zaten istek gönderdin.");
        }
        const reverseStatus = reverseSnap.data()?.status;
        if (reverseStatus === "pending") {
            throw new functions.https.HttpsError("already-exists", "Bu kullanıcıdan bekleyen bir istek var.");
        }
        const fromData = fromUser.data() ?? {};
        const toData = toUser.data() ?? {};
        transaction.set(requestRef, {
            fromUid,
            toUid,
            fromUsername: fromData.username ?? "",
            toUsername: toData.username ?? "",
            pairKey: pairKey(fromUid, toUid),
            status: "pending",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
    return { status: "pending" };
});
exports.blockUser = functions.https.onCall(async (request) => {
    if (!request.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Oturum yok.");
    }
    assertVerifiedEmail(request.auth);
    const currentUid = request.auth.uid;
    const data = request.data;
    const blockedUid = assertString(data.blockedUid, "blockedUid", 160);
    if (currentUid === blockedUid) {
        throw new functions.https.HttpsError("invalid-argument", "Kendini engelleyemezsin.");
    }
    const db = admin.firestore();
    const currentUserRef = db.collection("users").doc(currentUid);
    const blockedUserRef = db.collection("users").doc(blockedUid);
    const myFriendRef = currentUserRef.collection("friends").doc(blockedUid);
    const blockedSideRef = blockedUserRef.collection("friends").doc(currentUid);
    const myBlockRef = currentUserRef.collection("blockedUsers").doc(blockedUid);
    const requestRefA = db.collection("friendRequests").doc(`${currentUid}_${blockedUid}`);
    const requestRefB = db.collection("friendRequests").doc(`${blockedUid}_${currentUid}`);
    await db.runTransaction(async (transaction) => {
        const [currentUserSnap, blockedUserSnap, myFriendSnap, blockedSideSnap, requestSnapA, requestSnapB,] = await Promise.all([
            transaction.get(currentUserRef),
            transaction.get(blockedUserRef),
            transaction.get(myFriendRef),
            transaction.get(blockedSideRef),
            transaction.get(requestRefA),
            transaction.get(requestRefB),
        ]);
        if (!currentUserSnap.exists || !blockedUserSnap.exists) {
            throw new functions.https.HttpsError("not-found", "Kullanıcı bulunamadı.");
        }
        const blockedUserData = blockedUserSnap.data() ?? {};
        transaction.set(myBlockRef, {
            blockedUid,
            username: blockedUserData.username ?? "",
            name: blockedUserData.name ?? "",
            surname: blockedUserData.surname ?? "",
            photoUrl: blockedUserData.photoUrl ?? "",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        if (myFriendSnap.exists)
            transaction.delete(myFriendRef);
        if (blockedSideSnap.exists)
            transaction.delete(blockedSideRef);
        const currentCount = currentUserSnap.data()?.friendsCount ?? 0;
        const blockedCount = blockedUserData.friendsCount ?? 0;
        transaction.set(currentUserRef, {
            friends: admin.firestore.FieldValue.arrayRemove(blockedUid),
            friendsCount: myFriendSnap.exists && currentCount > 0 ? currentCount - 1 : currentCount,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        transaction.set(blockedUserRef, {
            friends: admin.firestore.FieldValue.arrayRemove(currentUid),
            friendsCount: blockedSideSnap.exists && blockedCount > 0 ? blockedCount - 1 : blockedCount,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        for (const requestSnap of [requestSnapA, requestSnapB]) {
            const status = requestSnap.data()?.status;
            if (requestSnap.exists && (status === "pending" || status === "accepted")) {
                transaction.set(requestSnap.ref, {
                    status: "cancelled",
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });
            }
        }
    });
    return { status: "blocked" };
});
exports.unblockUser = functions.https.onCall(async (request) => {
    if (!request.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Oturum yok.");
    }
    assertVerifiedEmail(request.auth);
    const currentUid = request.auth.uid;
    const data = request.data;
    const blockedUid = assertString(data.blockedUid, "blockedUid", 160);
    if (currentUid === blockedUid) {
        throw new functions.https.HttpsError("invalid-argument", "Kendin için engel kaydı kaldıramazsın.");
    }
    await admin.firestore()
        .collection("users")
        .doc(currentUid)
        .collection("blockedUsers")
        .doc(blockedUid)
        .delete();
    return { status: "unblocked" };
});
exports.deleteAccount = functions.https.onCall({ timeoutSeconds: 540, memory: "512MiB" }, async (request) => {
    if (!request.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Oturum yok.");
    }
    const authTime = Number(request.auth.token.auth_time ?? 0);
    const signedInSeconds = Math.floor(Date.now() / 1000) - authTime;
    if (!authTime || signedInSeconds > 10 * 60) {
        throw new functions.https.HttpsError("failed-precondition", "Hesabı silmek için yeniden giriş yapmalısın.");
    }
    const uid = request.auth.uid;
    const db = admin.firestore();
    await db.collection("accountDeletionJobs").doc(uid).set({
        uid,
        status: "processing",
        requestedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await processAccountDeletion(db, uid);
    return { status: "deleted" };
});
exports.createMap = functions.https.onCall(async (request) => {
    if (!request.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Oturum yok.");
    }
    assertVerifiedEmail(request.auth);
    const uid = request.auth.uid;
    const data = request.data;
    const title = assertString(data.title, "title", 60);
    const areaId = assertString(data.areaId, "areaId", 120);
    const bounds = validateBoundsGeometry(data.bounds);
    const totalPois = parseTotalPois(data.totalPois);
    const db = admin.firestore();
    const userRef = db.collection("users").doc(uid);
    const parentRef = db.collection("userMapStates").doc(uid);
    const mapRef = parentRef.collection("states").doc();
    await db.runTransaction(async (transaction) => {
        const userSnap = await transaction.get(userRef);
        const activeMapCount = userSnap.data()?.activeMapCount ?? 0;
        if (activeMapCount >= MAX_ACTIVE_MAPS) {
            throw new functions.https.HttpsError("resource-exhausted", "5/5 aktif harita — bir haritayı bitir veya sil.");
        }
        const now = admin.firestore.FieldValue.serverTimestamp();
        transaction.set(parentRef, {
            lastOpenedMapId: mapRef.id,
            lastOpenedAt: now,
            updatedAt: now,
        }, { merge: true });
        transaction.set(mapRef, {
            ownerUid: uid,
            areaId,
            mapName: title,
            bounds,
            status: "active",
            progress: {
                totalPois,
                visitedPois: 0,
                percent: 0,
                earnedXp: 0,
            },
            revealedCellIds: [],
            visitedPoiIds: [],
            lastInsidePosition: null,
            cameraCenter: null,
            zoom: null,
            completedAt: null,
            completionCountApplied: false,
            createdAt: now,
            updatedAt: now,
        });
        transaction.set(userRef, {
            activeMapCount: admin.firestore.FieldValue.increment(1),
            updatedAt: now,
        }, { merge: true });
    });
    return { mapId: mapRef.id };
});
exports.deleteMap = functions.https.onCall(async (request) => {
    if (!request.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Oturum yok.");
    }
    assertVerifiedEmail(request.auth);
    const uid = request.auth.uid;
    const data = request.data;
    const mapId = assertString(data.mapId, "mapId", 160);
    const db = admin.firestore();
    const userRef = db.collection("users").doc(uid);
    const parentRef = db.collection("userMapStates").doc(uid);
    const ref = mapStateRef(uid, mapId);
    await db.runTransaction(async (transaction) => {
        const snap = await transaction.get(ref);
        const parentSnap = await transaction.get(parentRef);
        if (!snap.exists) {
            throw new functions.https.HttpsError("not-found", "Harita bulunamadı.");
        }
        const map = snap.data() ?? {};
        const ownerUid = map.ownerUid ?? uid;
        if (ownerUid !== uid) {
            throw new functions.https.HttpsError("permission-denied", "Bu haritayı silme yetkin yok.");
        }
        const status = map.status ?? "active";
        if (status === "deleted") {
            return;
        }
        const now = admin.firestore.FieldValue.serverTimestamp();
        if (status === "active") {
            transaction.set(userRef, {
                activeMapCount: admin.firestore.FieldValue.increment(-1),
                updatedAt: now,
            }, { merge: true });
        }
        if (parentSnap.data()?.lastOpenedMapId === mapId) {
            transaction.set(parentRef, {
                lastOpenedMapId: admin.firestore.FieldValue.delete(),
                lastOpenedAt: now,
                updatedAt: now,
            }, { merge: true });
        }
        // Aktif harita listesinden kaldır, fakat Pasaport için kazanılmış
        // pulları ve check-in tarihlerini kalıcı olarak koru.
        transaction.set(ref, {
            status: "deleted",
            statusBeforeDelete: status,
            deletedAt: now,
            updatedAt: now,
        }, { merge: true });
    });
    return { status: "deleted", passportDataPreserved: true };
});
exports.onUserMapStateWritten = (0, firestore_1.onDocumentWritten)("userMapStates/{uid}/states/{mapId}", async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after)
        return;
    const beforeStatus = before.status ?? "active";
    const afterStatus = after.status ?? "active";
    if (beforeStatus === "active" && afterStatus === "completed") {
        if (after.completionCountApplied === true)
            return;
        const db = admin.firestore();
        const batch = db.batch();
        batch.set(db.collection("users").doc(event.params.uid), {
            activeMapCount: admin.firestore.FieldValue.increment(-1),
            completedMapCount: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        batch.set(mapStateRef(event.params.uid, event.params.mapId), {
            completedAt: after.completedAt ?? admin.firestore.FieldValue.serverTimestamp(),
            completionCountApplied: true,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        await batch.commit();
    }
    else if (beforeStatus === "completed" && afterStatus === "active") {
        await admin.firestore().collection("users").doc(event.params.uid).set({
            activeMapCount: admin.firestore.FieldValue.increment(1),
            completedMapCount: admin.firestore.FieldValue.increment(-1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    }
});
exports.cleanupExpiredRoomsAndInvites = (0, scheduler_1.onSchedule)({
    schedule: "30 3 * * *",
    timeZone: "Europe/Istanbul",
    timeoutSeconds: 540,
    memory: "512MiB",
}, async () => {
    const db = admin.firestore();
    const now = Date.now();
    const roomCutoff = admin.firestore.Timestamp.fromMillis(now - ROOM_RETENTION_DAYS * MILLIS_PER_DAY);
    const closedInviteCutoff = admin.firestore.Timestamp.fromMillis(now - CLOSED_INVITE_RETENTION_DAYS * MILLIS_PER_DAY);
    const pendingInviteCutoff = admin.firestore.Timestamp.fromMillis(now - PENDING_INVITE_RETENTION_DAYS * MILLIS_PER_DAY);
    const expiredRooms = await db.collection("rooms")
        .where("status", "==", "finished")
        .where("updatedAt", "<=", roomCutoff)
        .orderBy("updatedAt", "asc")
        .limit(CLEANUP_BATCH_LIMIT)
        .get();
    let deletedRooms = 0;
    let deletedRoomInvites = 0;
    for (const room of expiredRooms.docs) {
        try {
            deletedRoomInvites += await deleteQueryDocuments(db, db.collection("invites").where("roomId", "==", room.id));
            await db.recursiveDelete(room.ref);
            deletedRooms++;
        }
        catch (error) {
            console.error(`[Cleanup] Oda silinemedi: ${room.id}`, error);
        }
    }
    const closedInvites = db.collection("invites")
        .where("status", "in", ["accepted", "rejected"])
        .where("updatedAt", "<=", closedInviteCutoff)
        .orderBy("updatedAt", "asc")
        .limit(CLEANUP_BATCH_LIMIT);
    const deletedClosedInvites = await deleteQueryDocuments(db, closedInvites);
    const pendingInvites = db.collection("invites")
        .where("status", "==", "pending")
        .where("createdAt", "<=", pendingInviteCutoff)
        .orderBy("createdAt", "asc")
        .limit(CLEANUP_BATCH_LIMIT);
    const deletedPendingInvites = await deleteQueryDocuments(db, pendingInvites);
    console.log("[Cleanup] Tamamlandı", {
        deletedRooms,
        deletedRoomInvites,
        deletedClosedInvites,
        deletedPendingInvites,
    });
});
exports.retryPendingAccountDeletions = (0, scheduler_1.onSchedule)({
    schedule: "15 4 * * *",
    timeZone: "Europe/Istanbul",
    timeoutSeconds: 540,
    memory: "512MiB",
}, async () => {
    const db = admin.firestore();
    const jobs = await db.collection("accountDeletionJobs").limit(20).get();
    let completed = 0;
    for (const job of jobs.docs) {
        try {
            await processAccountDeletion(db, job.id);
            completed++;
        }
        catch (error) {
            console.error(`[AccountDeletion] Tekrar denenecek: ${job.id}`, error);
        }
    }
    console.log(`[AccountDeletion] ${completed}/${jobs.size} iş tamamlandı.`);
});
exports.reconcileActiveMapCounts = (0, scheduler_1.onSchedule)({ schedule: "0 4 * * *", timeZone: "Europe/Istanbul" }, async () => {
    const db = admin.firestore();
    const activeSnap = await db.collectionGroup("states")
        .where("status", "==", "active")
        .get();
    const counts = new Map();
    for (const doc of activeSnap.docs) {
        const parent = doc.ref.parent.parent;
        if (!parent)
            continue;
        const uid = parent.id;
        counts.set(uid, (counts.get(uid) ?? 0) + 1);
    }
    const usersWithCounts = await db.collection("users")
        .where("activeMapCount", ">", 0)
        .get();
    for (const userDoc of usersWithCounts.docs) {
        if (!counts.has(userDoc.id))
            counts.set(userDoc.id, 0);
    }
    let batch = db.batch();
    let writes = 0;
    for (const [uid, count] of counts.entries()) {
        batch.set(db.collection("users").doc(uid), {
            activeMapCount: count,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        writes++;
        if (writes % 450 === 0) {
            await batch.commit();
            batch = db.batch();
        }
    }
    if (writes % 450 !== 0) {
        await batch.commit();
    }
});
async function reconcileAreaMapProgress(areaId) {
    const db = admin.firestore();
    const poiSnap = await db.collection("maps").doc(areaId).collection("pois").get();
    const activePoiIds = new Set();
    let activePoiCount = 0;
    for (const doc of poiSnap.docs) {
        const data = doc.data();
        if (!isActivePoi(data))
            continue;
        activePoiCount++;
        activePoiIds.add(doc.id);
        const dataId = data.id;
        if (typeof dataId === "string" && dataId.trim()) {
            activePoiIds.add(dataId.trim());
        }
    }
    const totalPois = activePoiCount;
    const stateSnap = await db.collectionGroup("states")
        .where("areaId", "==", areaId)
        .get();
    let batch = db.batch();
    let writes = 0;
    const commitIfNeeded = async () => {
        if (writes > 0 && writes % 400 === 0) {
            await batch.commit();
            batch = db.batch();
        }
    };
    for (const doc of stateSnap.docs) {
        const data = doc.data();
        const uid = doc.ref.parent.parent?.id;
        if (!uid)
            continue;
        const beforeStatus = data.status ?? "active";
        if (beforeStatus === "deleted")
            continue;
        const visitedIds = parseStringArray(data.visitedPoiIds);
        const progress = parseProgress(data.progress);
        const visitedPois = activePoiIds.size > 0
            ? visitedIds.filter((id) => activePoiIds.has(id)).length
            : 0;
        const visitedFallback = Math.min(progress.visitedPois, totalPois);
        const normalizedVisited = visitedIds.length > 0 ? visitedPois : visitedFallback;
        const percent = totalPois > 0 ? Math.round((normalizedVisited / totalPois) * 10000) / 100 : 0;
        const nextStatus = totalPois > 0 && normalizedVisited >= totalPois ? "completed" : "active";
        const now = admin.firestore.FieldValue.serverTimestamp();
        const update = {
            progress: {
                totalPois,
                visitedPois: normalizedVisited,
                percent,
                earnedXp: progress.earnedXp,
            },
            status: nextStatus,
            updatedAt: now,
        };
        if (beforeStatus === "active" && nextStatus === "completed") {
            update.completedAt = data.completedAt ?? now;
            update.completionCountApplied = true;
            batch.set(db.collection("users").doc(uid), {
                activeMapCount: admin.firestore.FieldValue.increment(-1),
                completedMapCount: admin.firestore.FieldValue.increment(1),
                updatedAt: now,
            }, { merge: true });
            writes++;
        }
        else if (beforeStatus === "completed" && nextStatus === "active") {
            update.completedAt = admin.firestore.FieldValue.delete();
            update.completionCountApplied = false;
            batch.set(db.collection("users").doc(uid), {
                activeMapCount: admin.firestore.FieldValue.increment(1),
                completedMapCount: admin.firestore.FieldValue.increment(-1),
                updatedAt: now,
            }, { merge: true });
            writes++;
        }
        batch.set(doc.ref, update, { merge: true });
        writes++;
        await commitIfNeeded();
    }
    if (writes % 400 !== 0) {
        await batch.commit();
    }
}
exports.onMapPoiWritten = (0, firestore_1.onDocumentWritten)("maps/{areaId}/pois/{poiId}", async (event) => {
    const beforeActive = event.data?.before.exists
        ? isActivePoi(event.data.before.data())
        : false;
    const afterActive = event.data?.after.exists
        ? isActivePoi(event.data.after.data())
        : false;
    if (beforeActive === afterActive)
        return;
    await reconcileAreaMapProgress(event.params.areaId);
});
exports.verifyAndCheckIn = functions.https.onCall(async (request) => {
    if (!request.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Token yok');
    }
    assertVerifiedEmail(request.auth);
    const userId = request.auth.uid;
    const data = request.data;
    const venueId = assertString(data.venueId, "venueId", 180);
    const mapId = assertString(data.mapId, "mapId", 180);
    const userLat = parseCoordinate(data.userLat, "userLat", -90, 90);
    const userLng = parseCoordinate(data.userLng, "userLng", -180, 180);
    const accuracy = parseNumber(data.accuracy, "accuracy", 0, 10000);
    const distance = parseNumber(data.distance, "distance", 0, 1000000);
    const xpValue = parseOptionalInt(data.xpValue, "xpValue", 0, 10000);
    const isMocked = data.isMocked === true;
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
                    return {
                        status: 'speed_error',
                        xpEligible: false,
                        mapCompleted: false,
                    };
                }
            }
        }
    }
    // 2. Doğrulanan check-in'i, harita ilerlemesini ve completion sayaçlarını
    // tek transaction'da yaz. XP hâlâ client quest akışında veriliyor; burada
    // xpEligible=false dönerek tamamlanmış/tekrar check-in'lerde XP üretimi engellenir.
    try {
        const compositeId = `${userId}_${mapId}_${venueId}`;
        const legacyCompositeId = `${userId}_${venueId}`;
        const checkInRef = db.collection("venue_checkins").doc(compositeId);
        const legacyCheckInRef = db.collection("venue_checkins").doc(legacyCompositeId);
        const userRef = db.collection("users").doc(userId);
        const stateRef = mapStateRef(userId, mapId);
        let result = {
            status: "success",
            alreadyVisited: false,
            xpEligible: false,
            mapCompleted: false,
        };
        await db.runTransaction(async (transaction) => {
            const [checkInDoc, legacyCheckInDoc, mapDoc] = await Promise.all([
                transaction.get(checkInRef),
                legacyCompositeId === compositeId ? transaction.get(checkInRef) : transaction.get(legacyCheckInRef),
                transaction.get(stateRef),
            ]);
            if (!mapDoc.exists) {
                throw new functions.https.HttpsError("not-found", "Harita bulunamadı.");
            }
            const map = mapDoc.data() ?? {};
            const ownerUid = map.ownerUid ?? userId;
            if (ownerUid !== userId) {
                throw new functions.https.HttpsError("permission-denied", "Bu haritaya check-in yetkin yok.");
            }
            const status = map.status ?? "active";
            if (status === "deleted") {
                throw new functions.https.HttpsError("failed-precondition", "Silinmiş haritada check-in yapılamaz.");
            }
            if (status === "completed") {
                result = {
                    status: "success",
                    alreadyVisited: true,
                    xpEligible: false,
                    mapCompleted: false,
                };
                return;
            }
            const visitedIds = parseStringArray(map.visitedPoiIds);
            const alreadyVisited = checkInDoc.exists || legacyCheckInDoc.exists || visitedIds.includes(venueId);
            if (alreadyVisited) {
                result = {
                    status: "success",
                    alreadyVisited: true,
                    xpEligible: false,
                    mapCompleted: false,
                };
                return;
            }
            const progress = parseProgress(map.progress);
            const totalPois = progress.totalPois;
            const visitedBefore = Math.max(progress.visitedPois, visitedIds.length);
            const visitedAfter = totalPois > 0
                ? Math.min(totalPois, visitedBefore + 1)
                : visitedBefore + 1;
            const percent = totalPois > 0 ? Math.round((visitedAfter / totalPois) * 10000) / 100 : 0;
            const mapCompleted = totalPois > 0 && visitedAfter >= totalPois;
            const now = admin.firestore.FieldValue.serverTimestamp();
            transaction.set(userRef, { lastActiveAt: now }, { merge: true });
            transaction.set(checkInRef, {
                venueId,
                mapId,
                userId,
                markedAt: now,
                userLat,
                userLng,
                accuracy,
                isMocked,
                distance,
                xpValue,
            });
            const mapUpdate = {
                visitedPoiIds: admin.firestore.FieldValue.arrayUnion(venueId),
                progress: {
                    totalPois,
                    visitedPois: visitedAfter,
                    percent,
                    earnedXp: progress.earnedXp + xpValue,
                },
                updatedAt: now,
            };
            if (mapCompleted) {
                mapUpdate.status = "completed";
                mapUpdate.completedAt = now;
                mapUpdate.completionCountApplied = true;
                transaction.set(userRef, {
                    activeMapCount: admin.firestore.FieldValue.increment(-1),
                    completedMapCount: admin.firestore.FieldValue.increment(1),
                    updatedAt: now,
                }, { merge: true });
            }
            transaction.set(stateRef, mapUpdate, { merge: true });
            result = {
                status: "success",
                alreadyVisited: false,
                xpEligible: true,
                mapCompleted,
            };
        });
        return result;
    }
    catch (error) {
        console.error("Gezdim Transaction Hatası:", error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
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
// 1. GÜNLÜK ETKİLEŞİM BİLDİRİMLERİ (segmentli)
//    Her gün 09:00 İstanbul (UTC 06:00) saatinde çalışır. Tek geçişte iki
//    segmenti değerlendirir:
//      a) Haftanın ikinci yarısında hâlâ bitmemiş görevi olan aktif kullanıcılar
//      b) 3+ gündür `lastActiveAt` güncellenmemiş (uygulamayı açmamış/check-in
//         yapmamış) kullanıcılar → re-engagement bildirimi
//    Not: users/{uid}.weeklyQuests gerçek görev verisidir (bkz. game_provider.dart).
//    Eski sürüm hiç yazılmayan "weeklyTasks" koleksiyonunu sorguladığı için
//    sessizce hiçbir bildirim göndermiyordu.
// ────────────────────────────────────────────────────────────
const WEEKLY_QUEST_KEYS = [
    "ilkAdim",
    "kasifRuhu",
    "cesitliKasif",
    "duzenliGezgin",
    "takimOyuncusu",
    "takimKasifi",
    "tamHafta",
];
function currentWeekStart() {
    const now = new Date();
    const jsDay = now.getDay(); // 0=Pazar..6=Cumartesi
    const isoWeekday = jsDay === 0 ? 7 : jsDay; // 1=Pazartesi..7=Pazar
    const monday = new Date(now);
    monday.setDate(now.getDate() - (isoWeekday - 1));
    const y = monday.getFullYear();
    const m = (monday.getMonth() + 1).toString().padStart(2, "0");
    const d = monday.getDate().toString().padStart(2, "0");
    return `${y}-${m}-${d}`;
}
exports.sendWeeklyTaskReminders = (0, scheduler_1.onSchedule)({ schedule: "0 6 * * *", timeZone: "Europe/Istanbul" }, async () => {
    const db = admin.firestore();
    const weekStart = currentWeekStart();
    const now = new Date();
    const jsDay = now.getDay();
    const isoWeekday = jsDay === 0 ? 7 : jsDay;
    const isLaterHalfOfWeek = isoWeekday >= 4; // Perşembe'den itibaren hatırlat
    const inactivityCutoffMs = Date.now() - 3 * 24 * 60 * 60 * 1000;
    try {
        const usersSnap = await db.collection("users").get();
        const sendPromises = [];
        for (const userDoc of usersSnap.docs) {
            const uid = userDoc.id;
            const userData = userDoc.data();
            const token = userData.fcmToken;
            if (!token)
                continue;
            // Segment A: bu hafta hâlâ bitmemiş görevi olan aktif kullanıcı
            const quests = userData.weeklyQuests;
            if (isLaterHalfOfWeek &&
                quests?.weekStart === weekStart &&
                userData.notificationPrefs?.weeklyTask !== false) {
                const hasIncomplete = WEEKLY_QUEST_KEYS.some((key) => {
                    const quest = quests[key];
                    return quest !== undefined && quest.done !== true;
                });
                if (hasIncomplete) {
                    sendPromises.push(sendNotification(uid, token, "📋 Görevin seni bekliyor!", "Bu haftaki görevlerini tamamlamana az kaldı, hafta bitmeden keşfe çık!", { route: "/tasks" }));
                    continue; // aynı gün iki bildirimle boğmayalım
                }
            }
            // Segment B: 3+ gündür aktif değil → re-engagement
            const lastActiveMs = userData.lastActiveAt?.toMillis();
            if (lastActiveMs !== undefined &&
                lastActiveMs <= inactivityCutoffMs &&
                userData.notificationPrefs?.reengagement !== false) {
                sendPromises.push(sendNotification(uid, token, "🌫️ Sisin geri gelmene az kaldı!", "Şehrinde hâlâ keşfedilmeyi bekleyen yerler var, hadi devam et!", { route: "/" }));
            }
        }
        await Promise.all(sendPromises);
        console.log(`[DailyEngagement] ${sendPromises.length} bildirim gönderildi.`);
    }
    catch (error) {
        console.error("[DailyEngagement] Hata:", error);
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
// 2.5 MEKAN ÖNERİSİ ONAYLANDI — XP + Bildirim
//    Admin panel placeSuggestions/{id}.status'u "approved" yaptığında
//    tetiklenir. Kullanıcıya XP verir, pendingSuggestionRewards'a ekler
//    (client bir sonraki açılışta tebrik dialoğu gösterip temizler) ve
//    push bildirimi yollar.
// ────────────────────────────────────────────────────────────
exports.onPlaceSuggestionWritten = (0, firestore_1.onDocumentWritten)("placeSuggestions/{suggestionId}", async (event) => {
    const snap = event.data;
    if (!snap)
        return;
    const afterData = snap.after.data();
    const beforeData = snap.before.data();
    if (!afterData)
        return; // deleted
    if (afterData.status !== "approved")
        return;
    if (beforeData && beforeData.status === "approved")
        return; // didn't change
    const { userId, name } = afterData;
    if (!userId)
        return;
    const suggestionId = event.params.suggestionId;
    const db = admin.firestore();
    const userRef = db.collection("users").doc(userId);
    try {
        const xpAwarded = await getRemoteConfigInt("place_suggestion_xp", 100);
        let token;
        let notifyPref;
        await db.runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists)
                return;
            const data = userDoc.data();
            const currentXP = data.xp ?? 0;
            const currentWeeklyXP = data.weeklyXP ?? 0;
            const username = data.username ?? "";
            const newXP = currentXP + xpAwarded;
            const newWeeklyXP = currentWeeklyXP + xpAwarded;
            token = data.fcmToken;
            notifyPref = data.notificationPrefs
                ?.placeSuggestion;
            transaction.set(userRef, {
                xp: newXP,
                weeklyXP: newWeeklyXP,
                weeklyXPUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
                pendingSuggestionRewards: admin.firestore.FieldValue.arrayUnion({
                    suggestionId,
                    name: name ?? "",
                    xp: xpAwarded,
                }),
            }, { merge: true });
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
        if (token && notifyPref !== false) {
            await sendNotification(userId, token, "🎉 Mekan önerin onaylandı!", `"${name ?? "Önerin"}" haritaya eklendi, +${xpAwarded} XP kazandın!`, { route: "/" });
        }
        console.log(`[PlaceSuggestion] ${userId} → +${xpAwarded} XP (${suggestionId})`);
    }
    catch (error) {
        console.error("[PlaceSuggestion] Hata:", error);
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
// Rozet kategorisine göre gösterilecek ikon adı (bkz. badge_award_service.dart _getIconNameForCategory)
function iconNameForCategory(category) {
    switch (category) {
        case "social":
            return "people";
        case "streak":
            return "local_fire_department";
        case "secret":
            return "visibility_off";
        case "exploration":
        default:
            return "explore";
    }
}
// Haftanın kapanışında, kullanıcının kendisi + arkadaşlarından oluşan grupta
// haftalık XP'de 1. sırada olanlara "weekly_leader" ("Lider") rozetini verir.
// En az 1 arkadaşı olmayan kullanıcılar (tek kişilik grup) değerlendirmeye alınmaz.
async function awardWeeklyLeaderBadges(db, leaderboardSnap, usersSnap) {
    const badgeId = "weekly_leader";
    const badgeDoc = await db.collection("badges").doc(badgeId).get();
    if (!badgeDoc.exists) {
        console.warn(`[WeeklyLeaderBadge] '${badgeId}' rozet tanımı bulunamadı, atlanıyor.`);
        return;
    }
    const badgeDef = badgeDoc.data();
    const xpByUid = new Map();
    leaderboardSnap.docs.forEach((doc) => {
        const data = doc.data();
        xpByUid.set(doc.id, {
            weeklyXP: data.weeklyXP ?? 0,
            totalXP: data.totalXP ?? 0,
        });
    });
    const friendsByUid = new Map();
    usersSnap.docs.forEach((doc) => {
        const friends = doc.data().friends;
        friendsByUid.set(doc.id, Array.isArray(friends) ? friends : []);
    });
    const winners = [];
    for (const uid of xpByUid.keys()) {
        const friends = friendsByUid.get(uid) ?? [];
        if (friends.length === 0)
            continue;
        const group = [uid, ...friends].filter((id) => xpByUid.has(id));
        if (group.length < 2)
            continue;
        const [topUid] = [...group].sort((a, b) => {
            const xa = xpByUid.get(a);
            const xb = xpByUid.get(b);
            return xb.weeklyXP - xa.weeklyXP || xb.totalXP - xa.totalXP;
        });
        if (topUid === uid)
            winners.push(uid);
    }
    if (winners.length === 0)
        return;
    const outcomes = await Promise.allSettled(winners.map(async (uid) => {
        const badgeRef = db.collection("users").doc(uid).collection("badges").doc(badgeId);
        if ((await badgeRef.get()).exists)
            return; // Zaten kazanılmış, tekrar verilmez
        const batch = db.batch();
        batch.set(badgeRef, {
            id: badgeId,
            name: badgeDef.name ?? "Lider",
            description: badgeDef.description ?? "",
            iconName: iconNameForCategory(badgeDef.category),
            images: badgeDef.images ?? {},
            earnedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        const xpReward = badgeDef.xpReward ?? 0;
        if (xpReward > 0) {
            batch.set(db.collection("users").doc(uid), { xp: admin.firestore.FieldValue.increment(xpReward) }, { merge: true });
        }
        await batch.commit();
    }));
    const failed = outcomes.filter((o) => o.status === "rejected").length;
    console.log(`[WeeklyLeaderBadge] ${winners.length - failed}/${winners.length} kullanıcıya 'Lider' rozeti verildi.`);
}
// ────────────────────────────────────────────────────────────
// 4. HAFTALIK XP SIFIRLAMA
//    Her Pazartesi 00:00 İstanbul saatinde tüm kullanıcıları sıfırlar.
//    Sıfırlamadan önce, o haftayı 1. sırada bitirenlere "Lider" rozeti verilir.
// ────────────────────────────────────────────────────────────
exports.resetWeeklyXP = (0, scheduler_1.onSchedule)({ schedule: "0 0 * * 1", timeZone: "Europe/Istanbul" }, async () => {
    const db = admin.firestore();
    const [leaderboardSnap, usersSnap] = await Promise.all([
        db.collection("leaderboard").get(),
        db.collection("users").get(),
    ]);
    await awardWeeklyLeaderBadges(db, leaderboardSnap, usersSnap);
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
    // Haftalık ritmi vurgulamak için tüm kullanıcılara tek bir topic bildirimi
    // gönder (herkes bootstrap'ta "announcements" topic'ine abone olur).
    // Reset işleminin kendisini etkilememesi için ayrı try/catch içinde.
    try {
        await admin.messaging().send({
            topic: "announcements",
            notification: {
                title: "🎉 Yeni hafta başladı!",
                body: "Liderlik tablosu sıfırlandı. İlk adımını at ve zirveye tırman!",
            },
            android: { priority: "high" },
            apns: { payload: { aps: { sound: "default" } } },
        });
        console.log("[WeeklyReset] Yeni hafta bildirimi gönderildi.");
    }
    catch (error) {
        console.error("[WeeklyReset] Yeni hafta bildirimi gönderilemedi:", error);
    }
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
// YARDIMCI: Remote Config parametrelerini oku (client'ın kullandığı aynı
// parametre adları). Şablonu tekrar tekrar çekmemek için 5 dk modül-içi
// cache kullanılır; okuma başarısız olursa (henüz konsolda parametre
// yoksa vs.) çağıran taraftan verilen fallback'e düşülür.
// ────────────────────────────────────────────────────────────
let rcCache = null;
const RC_CACHE_TTL_MS = 5 * 60 * 1000;
async function getRemoteConfigInt(key, fallback) {
    const now = Date.now();
    if (!rcCache || now - rcCache.fetchedAt > RC_CACHE_TTL_MS) {
        try {
            const template = await admin.remoteConfig().getTemplate();
            const params = {};
            for (const [k, param] of Object.entries(template.parameters)) {
                const dv = param.defaultValue;
                if (dv && "value" in dv)
                    params[k] = dv.value;
            }
            rcCache = { params, fetchedAt: now };
        }
        catch (error) {
            console.error("[RemoteConfig] Şablon okunamadı, fallback kullanılacak:", error);
            return fallback;
        }
    }
    const parsed = parseInt(rcCache.params[key] ?? "", 10);
    return Number.isFinite(parsed) ? parsed : fallback;
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
    assertVerifiedEmail(request.auth);
    const userId = request.auth.uid;
    const db = admin.firestore();
    const userRef = db.collection("users").doc(userId);
    const now = new Date();
    const today = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
    const dailyXP = await getRemoteConfigInt("daily_ad_reward_xp", 25);
    const maxDaily = await getRemoteConfigInt("daily_ad_reward_max", 3);
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
    assertVerifiedEmail(request.auth);
    const userId = request.auth.uid;
    const questKey = request.data?.questKey;
    // Fallback XP değerleri — Remote Config'te "quest_xp_<key>" parametresi
    // yoksa veya okunamazsa bunlar kullanılır. Asıl değer client'ın da
    // okuduğu Remote Config şablonundan gelir (getRemoteConfigInt).
    const questXpDefaults = {
        ilkAdim: 50,
        kasifRuhu: 100,
        cesitliKasif: 75,
        duzenliGezgin: 75,
        takimOyuncusu: 100,
        takimKasifi: 100,
        tamHafta: 300,
    };
    if (!questKey || !(questKey in questXpDefaults)) {
        throw new functions.https.HttpsError("invalid-argument", "Geçersiz görev anahtarı");
    }
    const bonusXP = await getRemoteConfigInt(`quest_xp_${questKey}`, questXpDefaults[questKey]);
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