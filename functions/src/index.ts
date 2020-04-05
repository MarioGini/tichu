import * as functions from 'firebase-functions';


export const countNameChanges = functions.firestore
    .document('users/{userId}')
    .onUpdate((change, context) => {
        // Retrieve the current and previous value
        const data = change.after.data();
        const previousData = change.before.data();

        if (data.isReady == previousData.isReady) return null;

        var newCards = { cards: Math.floor(Math.random() * 20) + 1 };

        // Then return a promise of a set operation to update the count
        return change.after.ref.collection('cards').add(newCards);
    });

