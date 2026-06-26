import { TotpMultiFactorGenerator, getMultiFactorResolver, getAuth } from 'firebase/auth';

// Path A — Firebase TOTP MFA (recommended). Duo Mobile acts as the authenticator
// app (TOTP is RFC 6238). Path B (Duo Universal Prompt) is a backend integration;
// see the auth-patterns SKILL.md and pipeline-alternatives.md.

/** Generate TOTP secret and return QR code URI for Duo Mobile enrollment. */
export async function enrollTotp(user) {
  const session = await user.multiFactor.getSession();
  const totpSecret = await TotpMultiFactorGenerator.generateSecret(session);
  return totpSecret.generateQrCodeUrl(user.email, 'YourAppName');
}

/** Confirm TOTP enrollment with the code the user entered from Duo Mobile. */
export async function confirmTotpEnrollment(user, secret, verificationCode: string) {
  const assertion = TotpMultiFactorGenerator.assertionForEnrollment(secret, verificationCode);
  return user.multiFactor.enroll(assertion, 'Duo Mobile');
}

/** Complete sign-in after Firebase issues a MultiFactorResolver challenge. */
export async function resolveTotpChallenge(error, verificationCode: string) {
  const resolver = getMultiFactorResolver(getAuth(), error);
  const hint = resolver.hints.find((h) => h.factorId === TotpMultiFactorGenerator.FACTOR_ID);
  const assertion = TotpMultiFactorGenerator.assertionForSignIn(hint!.uid, verificationCode);
  return resolver.resolveSignIn(assertion);
}
