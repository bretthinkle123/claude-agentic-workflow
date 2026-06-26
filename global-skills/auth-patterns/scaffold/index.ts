// Public frontend auth surface — browser sign-in / MFA only. The server guards
// (require_auth / require_mfa / require_role) live in the Python backend module.
export { signInWithProvider } from './oauth';
export { enrollTotp, confirmTotpEnrollment, resolveTotpChallenge } from './mfa';
