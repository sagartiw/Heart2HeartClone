//functions/src/index.ts
import * as functions from "firebase-functions/v2";
import * as admin from "firebase-admin";

admin.initializeApp();

exports.createDailyTask = functions.scheduler.onSchedule(
    {
        schedule: "0 0 * * *",
        timeZone: "UTC",
    },
    async (event) => {
        try {
            const db = admin.firestore();

            await db.collection("dailyTasks").add({
                timestamp: admin.firestore.Timestamp.now(),
                status: "pending",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log("Daily task created successfully");
        } catch (error) {
            console.error("Error creating daily task:", error);
            throw error;
        }
    }
);
