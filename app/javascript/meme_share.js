// Decide how saving a Meme should happen: "share" (open the share sheet with the
// PNG) when the device can share that file, otherwise "download".
export function saveMethod(nav, file) {
  if (!nav || typeof nav.share !== "function" || typeof nav.canShare !== "function") return "download"
  try {
    return nav.canShare({ files: [file] }) ? "share" : "download"
  } catch {
    return "download"
  }
}
