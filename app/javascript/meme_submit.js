// Pure helpers for submitting a Meme (no DOM), so node can test them.

// Milliseconds until the Captioning deadline on this device's clock. `serverNow` is the server's time when the
// page was built and `deviceAtConnect` what this device's clock read then, which gives the clock offset.
// Null when there is no deadline.
export function msUntilZero(deadline, serverNow, deviceAtConnect, deviceNow) {
  const deadlineMs = Date.parse(deadline)
  if (Number.isNaN(deadlineMs)) return null
  const offset = Date.parse(serverNow) - deviceAtConnect
  return Math.max(0, deadlineMs - (deviceNow + offset))
}

// The JSON the submit Meme operation takes: one caption per Text Box, blanks allowed.
export function memeBody(signedId, templateId, captions, boxCount) {
  return {
    signed_id: signedId,
    template_id: templateId,
    captions: Array.from({ length: boxCount }, (_, n) => captions[n] || ''),
  }
}

// A visible, actionable message for whatever went wrong while baking, uploading or submitting.
export function failureMessage(error) {
  if (error?.serverErrors?.length) return error.serverErrors.join(', ')
  if (error?.name === 'SecurityError') return "Couldn't export the image from this browser. Try again."
  if (error?.message && /upload/i.test(error.message)) return 'The upload failed. Check your connection and try again.'
  if (error?.message) return `Something went wrong: ${error.message}. Try again.`
  return 'Could not make your Meme image. Try again.'
}
