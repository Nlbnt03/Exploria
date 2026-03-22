import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// Not calling admin.initializeApp() here to avoid duplicate initialization 
// in case there is already a main index file, but if this is the entrypoint 
// make sure admin is initialized in your main export.
// admin.initializeApp();

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

export const verifyAndCheckIn = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Token yok');
  }

  const userId = context.auth.uid;
  const { venueId, mapId, userLat, userLng, accuracy, isMocked, distance } = data;
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
