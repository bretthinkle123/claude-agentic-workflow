import { initializeApp, getApps } from 'firebase/app';

const firebaseConfig = {
  apiKey: process.env.FIREBASE_API_KEY,
  authDomain: process.env.FIREBASE_AUTH_DOMAIN,
  projectId: process.env.FIREBASE_PROJECT_ID,
};

/** Singleton Firebase client app — safe to call multiple times. */
export const firebaseApp = getApps().length
  ? getApps()[0]
  : initializeApp(firebaseConfig);
