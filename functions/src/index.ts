/* functions/src/index.ts */
import * as functions from "firebase-functions/v2";
import * as admin from "firebase-admin";

admin.initializeApp();

exports.createDailyTask = functions.scheduler.onSchedule(
    {
        schedule: "30 * * * *",
        timeZone: "UTC",
    },
    async () => {
        try {
            const db = admin.firestore();

            // Delete existing tasks
            const tasksSnapshot = await db.collection("dailyTasks").get();
            const deletePromises = tasksSnapshot.docs.map((doc) => (
                doc.ref.delete()
            ));
            await Promise.all(deletePromises);

            // Get all users
            const usersSnapshot = await db.collection("users").get();

            // Create a task for each user
            const taskPromises = usersSnapshot.docs.map((userDoc) => (
                db.collection("dailyTasks").add({
                    userId: userDoc.id,
                    timestamp: admin.firestore.Timestamp.now(),
                    status: "pending",
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                })
            ));

            await Promise.all(taskPromises);

            console.log(
                `Tasks updated for ${usersSnapshot.size} users`
            );
        } catch (error) {
            console.error("Error managing tasks:", error);
            throw error;
        }
    }
);
