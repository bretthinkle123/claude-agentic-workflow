import { GoogleAuthProvider, GithubAuthProvider, signInWithPopup } from 'firebase/auth';
import { getAuth } from 'firebase/auth';
import { firebaseApp } from './firebase';

const auth = getAuth(firebaseApp);

// Google and GitHub are wired here per "Google and GitHub at minimum".
// Add Microsoft and Apple the same way — via OAuthProvider with their provider
// IDs — once enabled in the Firebase Console.
const providers = {
  google: new GoogleAuthProvider(),
  github: new GithubAuthProvider(),
} as const;

/** Sign in with a supported OAuth provider; opens popup. */
export async function signInWithProvider(providerName: keyof typeof providers) {
  return signInWithPopup(auth, providers[providerName]);
}
