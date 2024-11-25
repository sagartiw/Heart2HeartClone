import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

admin.initializeApp();

const invalidTokenCodes = [
    "messaging/invalid-registration-token",
    "messaging/registration-token-not-registered",
];

export const scheduleDailyTask = functions.pubsub
    .schedule("*/2 * * * *")
    .timeZone("America/New_York")
    .onRun(async () => {
        try {
            const usersSnapshot = await admin.firestore()
                .collection("users")
                .where("fcmToken", "!=", null)
                .get();

            const notifications = usersSnapshot.docs.map(async (userDoc) => {
                const userData = userDoc.data();
                const token = userData.fcmToken;

                if (!token) return;

                const message = {
                    token,
                    notification: {
                        title: "Daily Health Check",
                        body: "Time to process your daily health data",
                    },
                    data: {
                        type: "dailyTask",
                        timestamp: Date.now().toString(),
                    },
                    apns: {
                        payload: {
                            aps: {
                                "content-available": 1,
                                "mutable-content": 1,
                            },
                        },
                        headers: {
                            "apns-push-type": "background",
                            "apns-priority": "5",
                            "apns-topic": "com.Jackson.Heart2Heart",
                        },
                    },
                    android: {
                        priority: "high" as const,
                    },
                };

                try {
                    await admin.messaging().send(message);
                    console.log(`Success: sent noti to ${userDoc.id}`);
                } catch (error) {
                    console.error(
                        `Notification failed for user ${userDoc.id}:`,
                        error
                    );

                    if (error instanceof Error) {
                        if (
                            "code" in error &&
                            invalidTokenCodes.includes(error.code as string)
                        ) {
                            await userDoc.ref.update({
                                fcmToken: admin.firestore.FieldValue.delete(),
                            });
                        }
                    }
                }
            });

            await Promise.all(notifications);
            return null;
        } catch (error) {
            console.error("Error in scheduleDailyTask:", error);
            return null;
        }
    });

export const sendPartnerNotification = functions.https.onCall(
    async (data, context) => {
        // Ensure the request is authenticated
        if (!context.auth) {
            throw new functions.https.HttpsError(
                "unauthenticated",
                "The function must be called while authenticated."
            );
        }

        try {
            const message = {
                token: data.token,
                notification: {
                    title: data.notification.title,
                    body: data.notification.body,
                },
                data: data.data,
                apns: {
                    payload: {
                        aps: {
                            "content-available": 1,
                            "mutable-content": 1,
                            "sound": "default",
                        },
                    },
                    headers: {
                        "apns-priority": "10",
                        "apns-topic": "com.Jackson.Heart2Heart",
                    },
                },
                android: {
                    priority: "high" as const,
                },
            };

            try {
                await admin.messaging().send(message);
                console.log("Success: sent notification to recipient");
                return {success: true};
            } catch (error) {
                console.error("Notification failed:", error);

                if (error instanceof Error) {
                    if (
                        "code" in error &&
                        invalidTokenCodes.includes(error.code as string)
                    ) {
                        throw new functions.https.HttpsError(
                            "failed-precondition",
                            "The recipient's device token is invalid"
                        );
                    }
                }
                throw new functions.https.HttpsError(
                    "internal",
                    "Error sending notification"
                );
            }
        } catch (error) {
            console.error("Error in sendPartnerNotification:", error);
            if (error instanceof functions.https.HttpsError) {
                throw error;
            }
            throw new functions.https.HttpsError(
                "internal",
                "Error sending notification"
            );
        }
    }
);
