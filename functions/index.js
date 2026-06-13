// functions/index.js
const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// =========================
// Helper: ดึง fcmToken จาก uid (กัน uid ว่าง)
// =========================
async function getUserToken(uid) {
  if (!uid) {
    console.log("getUserToken called with invalid uid:", uid);
    return null;
  }

  try {
    const snap = await db.collection("users").doc(uid).get();
    if (!snap.exists) {
      console.log("getUserToken: user doc not found for uid", uid);
      return null;
    }

    const data = snap.data() || {};
    if (!data.fcmToken) {
      console.log("getUserToken: no fcmToken field for uid", uid);
      return null;
    }

    return data.fcmToken;
  } catch (err) {
    console.error("getUserToken: error loading user", uid, err);
    return null;
  }
}

// หา receiver จาก room.uids (array ยาว 2 ตัว [uid1, uid2])
function findReceiverUid(roomData, senderUid) {
  if (!roomData || !Array.isArray(roomData.uids)) {
    console.log("findReceiverUid: invalid roomData.uids", roomData);
    return null;
  }
  return roomData.uids.find((u) => u && u !== senderUid) || null;
}

// หาคนที่เป็นเจ้าของแมว จาก cats/{catId}
async function getOwnerUidFromCat(catId) {
  if (!catId) {
    console.log("getOwnerUidFromCat called with invalid catId:", catId);
    return null;
  }

  try {
    const snap = await db.collection("cats").doc(catId).get();
    if (!snap.exists) {
      console.log("getOwnerUidFromCat: cat doc not found", catId);
      return null;
    }

    const cat = snap.data() || {};
    const ownerUid = cat.ownerId || cat.userId || cat.uid || null;

    if (!ownerUid) {
      console.log("getOwnerUidFromCat: no owner field in cat", catId, cat);
    }

    return ownerUid;
  } catch (err) {
    console.error("getOwnerUidFromCat: error loading cat", catId, err);
    return null;
  }
}

// =========================
// 1) แจ้งเตือนเมื่อมี "ข้อความใหม่"
// rooms/{roomId}/messages/{msgId}
// =========================
exports.onNewMessage = functions.firestore
  .document("rooms/{roomId}/messages/{msgId}")
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const roomId = context.params.roomId;

    const senderUid = data.senderUid;
    if (!senderUid) {
      console.log("onNewMessage: missing senderUid", { roomId, data });
      return null;
    }

    // โหลด room เพื่อหาอีกฝั่ง
    let roomSnap;
    try {
      roomSnap = await db.collection("rooms").doc(roomId).get();
    } catch (err) {
      console.error("onNewMessage: error fetching room", roomId, err);
      return null;
    }

    if (!roomSnap.exists) {
      console.log("onNewMessage: room not found", roomId);
      return null;
    }

    const roomData = roomSnap.data() || {};
    const receiverUid = findReceiverUid(roomData, senderUid);

    if (!receiverUid) {
      console.log("onNewMessage: cannot determine receiverUid", {
        roomId,
        senderUid,
        roomData,
      });
      return null;
    }

    const text =
      (typeof data.text === "string" && data.text.trim()) ||
      "คุณมีข้อความใหม่";

    // ดึง token ของผู้รับ
    const token = await getUserToken(receiverUid);
    if (!token) {
      console.log("onNewMessage: No FCM token for receiver:", receiverUid);
      return null;
    }

    // ดึงชื่อฝั่งผู้ส่งไว้เป็น title
    let senderName = "ผู้ใช้ที่คุณแชทด้วย";
    try {
      const senderSnap = await db.collection("users").doc(senderUid).get();
      if (senderSnap.exists) {
        const senderData = senderSnap.data() || {};
        senderName =
          senderData.username ||
          senderData.firstName ||
          senderData.displayName ||
          senderName;
      }
    } catch (err) {
      console.error(
        "onNewMessage: error fetching sender user",
        senderUid,
        err
      );
    }

    const message = {
      token,
      notification: {
        title: senderName,
        body: text,
      },
      data: {
        type: "message",
        roomId,
        senderUid,
        receiverUid,
      },
    };

    try {
      const res = await messaging.send(message);
      console.log("onNewMessage: sent notification", {
        to: receiverUid,
        roomId,
        res,
      });
    } catch (err) {
      console.error("onNewMessage: error sending FCM", err);
    }

    return null;
  });

// =========================
// 2) แจ้งเตือนเมื่อมี "แมตช์ใหม่"
// matches/{matchId}
// fields: catA, catB, ...
// =========================
exports.onNewMatch = functions.firestore
  .document("matches/{matchId}")
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const matchId = context.params.matchId;

    const catA = data.catA;
    const catB = data.catB;

    if (!catA || !catB) {
      console.log("onNewMatch: missing catA/catB", { matchId, data });
      return null;
    }

    // หา owner ของแมวแต่ละตัว
    const [userA, userB] = await Promise.all([
      getOwnerUidFromCat(catA),
      getOwnerUidFromCat(catB),
    ]);

    if (!userA && !userB) {
      console.log("onNewMatch: cannot find owners for cats", {
        matchId,
        catA,
        catB,
      });
      return null;
    }

    const [tokenA, tokenB] = await Promise.all([
      getUserToken(userA),
      getUserToken(userB),
    ]);

    const baseNotification = {
      title: "คุณมีแมชใหม่!",
      body: "มีคนถูกใจแมวของคุณกลับมา ❤️",
    };

    const sendPromises = [];

    // ส่งให้ฝั่ง A
    if (tokenA && userB) {
      sendPromises.push(
        messaging.send({
          token: tokenA,
          notification: baseNotification,
          data: {
            type: "match",
            otherUid: userB,
            matchId,
          },
        })
      );
    } else {
      console.log("onNewMatch: skip sending to userA", { userA, tokenA });
    }

    // ส่งให้ฝั่ง B
    if (tokenB && userA) {
      sendPromises.push(
        messaging.send({
          token: tokenB,
          notification: baseNotification,
          data: {
            type: "match",
            otherUid: userA,
            matchId,
          },
        })
      );
    } else {
      console.log("onNewMatch: skip sending to userB", { userB, tokenB });
    }

    try {
      const results = await Promise.allSettled(sendPromises);
      console.log("onNewMatch: send results", { matchId, results });
    } catch (err) {
      console.error("onNewMatch: error sending FCM", err);
    }

    return null;
  });
