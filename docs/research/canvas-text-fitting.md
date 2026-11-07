# Browser text-fitting and canvas export of Memes (MEME-4)

Scope: render a **Meme** (a **Template** image plus a **Player**'s caption text) in the browser, shrink each caption to fit its **Text Box**, and upload the baked PNG through Active Storage. Phone-first. Rails 8.1, importmap, Stimulus, no JS bundler.

Confidence labels: **[verified]** means read on the cited primary page. **[inferred]** means the page was silent and I'm reasoning from the spec or general knowledge. Check those before relying on them.

## 1. Text fitting on canvas

### Primitives

- `ctx.measureText(text)` returns `TextMetrics` with `width` (advance width) and `actualBoundingBoxLeft/Right/Ascent/Descent` (ink extents). It also returns `fontBoundingBoxAscent/Descent`, which depend on the font and not on the string. [verified: WHATWG HTML canvas spec, https://html.spec.whatwg.org/multipage/canvas.html]
- Measurements use the current `ctx.font`. The default is 10px sans-serif. [MDN measureText, https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/measureText]
- Per MDN, `width` is the advance width and is not the ink extent. Use `actualBoundingBoxLeft + actualBoundingBoxRight` for the visible extent. [MDN page was thin, so this is partly inferred]
- The spec text I read gave no measurement algorithm, so don't assume glyph metrics match across engines. Fit on the same engine that exports. See section 5.
- `fillText` and `strokeText` take an optional `maxWidth`. If the text is wider, the browser may condense or scale it. [verified: MDN strokeText, https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/strokeText] Don't use it for fitting: it only squeezes horizontally, so it distorts the glyphs and can't wrap.
- Text-drawing style properties exist on the context: `letterSpacing`, `wordSpacing`, `fontKerning` (`auto`|`normal`|`none`), `textRendering` (`auto`|`optimizeSpeed`|`optimizeLegibility`|`geometricPrecision`). [verified: WHATWG spec] Set them explicitly. Don't leave the defaults to differ between code paths.

### Algorithm

For each Text Box (a rect `w x h` in Template pixel coordinates):

1. Convert the caption to upper case if the meme style wants it. Memes conventionally do.
2. Binary search the integer font size between `minSize` (for example 12px) and `maxSize` (for example the box height). For each candidate size:
   - Set `ctx.font = \`${size}px Anton\``.
   - Greedy word wrap. Split on whitespace and accumulate words into a line until `measureText(line + " " + word).width > w`. Then start a new line.
   - Fit test: `lines.length * lineHeight <= h` AND every line's width `<= w`. Take `lineHeight = size * k` with k about 1.1. A fixed k is deterministic. `fontBoundingBox*` is string-independent but can differ per platform.
3. Pick the largest size that passes. The fit test is monotonic enough for binary search in practice. A bigger size never makes wrapped text fit better, aside from rounding.
4. If even `minSize` fails, either truncate with an ellipsis or accept overflow clipped by the box. Product decision. Prefer capping caption length in the input UI (`maxlength`) so this is rare.

### Long unbroken words

A word wider than `w` cannot be fixed by wrapping. The search handles it naturally. Because the fit test also checks per-line width, the size shrinks until the word fits. The word is only broken as a last resort at `minSize`, by splitting by characters with `measureText` per grapheme (use `Intl.Segmenter` for graphemes, so emoji and combining marks are not split). [inferred; `Intl.Segmenter` is ECMA-402. Not fetched.]

### Stroke width and the fit

The outline extends beyond the glyph by `lineWidth / 2` per side. Include it in the fit: fit against `w - lineWidth` and `h - lineWidth`. Make `lineWidth` proportional to font size (about `size / 8`) and recompute it per candidate size. [inferred]

### Render order

Draw the stroke first, then the fill on top. Otherwise the stroke eats the inside half of the glyph. MDN says only that canvas paints in call order. [inferred from MDN strokeText]

## 2. Meme font and outline

### Impact licensing

- Impact ships with Windows. Microsoft's redistribution FAQ says you may not self-host or convert Windows fonts to WOFF/WOFF2 for the web, and you may not redistribute the fonts. [verified: https://learn.microsoft.com/en-us/typography/fonts/font-faq]
- The same FAQ allows listing a Windows font in a CSS font stack, because the "use" happens on the viewer's device. So `font-family: Impact` is allowed but unreliable, since many Android and iOS devices lack it.
- The FAQ treats graphic files made with the fonts, including "a meme", as equivalent to printed output with no restriction, unless the app is licensed for non-commercial use only. [verified: same page] So a PNG baked with Impact on a user's Windows machine is fine, but you can't ship Impact to the phones.
- Conclusion: do not bundle Impact. Extended web rights come from Monotype or the original foundry (the FAQ points to Monotype and fonts.com). [verified]

### Free look-alikes (SIL OFL)

- **Anton**: Google Fonts, designed by Vernon Adams, category display, licence OFL 1.1. Copyright "2020 The Anton Project Authors". [verified: https://github.com/google/fonts/tree/main/ofl/anton (METADATA.pb and OFL.txt)]
- OFL 1.1 permits use, embedding and bundling, and redistribution with the copyright notice and licence included. It can't be sold standalone. Modified versions can't use the Reserved Font Name. [verified: OFL.txt]
- Other condensed bold Google Fonts under OFL, such as Oswald (700), Bebas Neue, and League Gothic, are candidates. I only verified Anton's licence page. Check the OFL.txt for any other font before adopting it.
- Recommendation: Anton. Closest to Impact's proportions, and self-hostable.
- Self-host the WOFF2 under `app/assets/fonts/` (or `public/`) with an `@font-face`, and keep the OFL.txt alongside. Self-hosting avoids a third-party request and avoids a canvas font race with a CDN. No cookie or Google request is needed. [inferred]

### Stroke rendering

- Use `ctx.lineJoin = "round"`. The default is `miter`, which makes spikes on sharp glyph corners (W, M, A, V). [verified: MDN lineJoin, https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/lineJoin; miter is the default and falls back to bevel above `miterLimit`, default 10 per general Canvas knowledge]
- `ctx.strokeStyle = "#000"; ctx.lineWidth = size / 8;` then `strokeText`, then `fillStyle = "#fff"` and `fillText`. [inferred]

### Ensuring the web font is loaded before drawing

- `document.fonts.load(fontSpec, text?)` starts loading the matching faces and returns a promise that fulfills with the loaded `FontFace` array, and rejects if any font fails. `text` defaults to a single space and only filters faces by unicode-range. Baseline widely available since January 2020. [verified: MDN, https://developer.mozilla.org/en-US/docs/Web/API/FontFaceSet/load]
- Canvas does not trigger or wait for font loading by itself. If the face isn't loaded, `ctx.font` silently falls back, and the **fit is computed with the wrong metrics**. [inferred from the spec's separation of canvas and font loading; verify in a browser]
- Pattern: `await document.fonts.load("1em Anton", captionText)` (pass the real text so unicode-range subsets are triggered) before the first measure or draw. Handle rejection by falling back to a system bold condensed stack. Also re-run the fit after load if the preview was drawn earlier.
- No-match behaviour is not stated on MDN. The spec's `load` likely resolves with an empty array. [inferred. Check the CSS Font Loading spec.] So also assert with `document.fonts.check("1em Anton")` after loading.

## 3. Canvas tainting, CORS and Active Storage images

- Drawing a cross-origin image taints the canvas unless the image was fetched with CORS approval. On a tainted canvas, `getImageData`, `toBlob`, `toDataURL` and `captureStream` throw `SecurityError`. Each canvas bitmap has an origin-clean flag, initially true. [verified: MDN CORS-enabled image, https://developer.mozilla.org/en-US/docs/Web/HTML/How_to/CORS_enabled_image; WHATWG canvas spec]
- To avoid tainting, set `img.crossOrigin = "anonymous"` **before** setting `src`, and have the server send `Access-Control-Allow-Origin`. [verified: MDN]
- `toBlob(callback, type, quality)` defaults to `image/png`. The callback may receive `null`, so check for it. `quality` only matters for lossy types. [verified: MDN toBlob, https://developer.mozilla.org/en-US/docs/Web/API/HTMLCanvasElement/toBlob]

### What this means for Active Storage

- `url_for(attachment)` gives a permanent signed route that redirects (expires after 5 minutes) to the storage service. Default representations also go through a redirect controller (302). Proxy mode, `config.active_storage.resolve_model_to_route = :rails_storage_proxy`, has the app stream the bytes instead. [verified: Rails guide, https://guides.rubyonrails.org/active_storage_overview.html]
- **Disk service** (dev, or a single-server deploy): the guide says it "shares your app's origin", so no CORS is needed for direct uploads. [verified] Images read via the redirect also stay same-origin, so the canvas stays clean. [inferred]
- **S3, GCS or other services**: the redirect lands on another origin, so the bucket needs a CORS rule for GET (image reads) *in addition to* the PUT rule that direct upload needs. The guide lists only the upload requirements: allowed origins, `PUT`, and the headers `Content-Type`, `Content-MD5`, `Content-Disposition` (GCS also `x-goog-content-length-range`). [verified] The GET rule is my inference from the MDN requirement.
- Redirect-following caveat: a CORS image request that is redirected must have every hop send acceptable CORS headers. Unverified for Rails' redirect hop, which is on the app origin and so is usually fine. [inferred]
- **Simplest robust option**: serve Template images through the Rails proxy route (`rails_storage_proxy_url`). Same origin as the page, no bucket CORS needed, no taint risk, and the response is cacheable (the guide mentions a cache header for CDNs). Cost: the app streams image bytes. Put a CDN in front later if needed. If the CDN lives on another origin, add `Access-Control-Allow-Origin` there and keep `crossOrigin="anonymous"` in the code anyway.
- Always set `crossOrigin = "anonymous"` in code even for same-origin, so switching storage backends doesn't silently break export. A same-origin request ignores it harmlessly. [inferred]
- Wrap export in try/catch for `SecurityError` and for `null` blob, and surface a clear error. [verified: MDN]

## 4. Mobile limits, DPR and export resolution

- iOS Safari caps a canvas at 16,777,216 pixels (width x height). A 4097x4096 canvas only logs "Canvas area exceeds the maximum limit" when used. 5120x3072 (15,728,640 px) works. [verified, but from a secondary write-up: https://pqina.nl/blog/canvas-area-exceeds-the-maximum-limit/ (Jan 2022). I found no WebKit primary page; the limit may have changed since. Test on a real device.]
- macOS Safari fails differently: an oversized `getImageData` throws `InvalidStateError`. [verified, same source]
- Other browsers have higher limits (no numbers in the source). Safari also has a *total canvas memory* limit across all canvases. That follow-up article was not read. Treat as real: use one canvas, and set `canvas.width = canvas.height = 0` on any scratch canvas when done. [inferred]
- **Preview vs export, DPR**: `devicePixelRatio` only matters for how big the on-screen canvas looks. Don't multiply the *export* by it. Recommended: keep one backing canvas at a fixed export size, and display it scaled down by CSS (`width: 100%; height: auto`). CSS scaling is free, so no DPR math is needed and the preview is pixel-identical to the export. [inferred]
- **Resolution choice**: draw at the Template's native pixel size, but cap the long side at about 2048px (a typical meme template is 500-1500px, so this rarely applies). If larger, scale down proportionally, keeping area well under 16.7 MP (2048x2048 is 4.2 MP). Scale all Text Box coordinates and the font sizes by the same factor. Store Text Box geometry as fractions (0-1) of the Template, or in native pixels with a scale factor, so one code path serves all sizes. [inferred]
- Format: PNG is the `toBlob` default and lossless, so caption edges stay crisp. A 2048px PNG could be a few MB. If upload size hurts on mobile data, consider `image/jpeg` at 0.9. For a meme with hard text edges, PNG is preferred. Decide after measuring real sizes.

## 5. Keeping preview identical to export

Use **the same canvas and the same function** for both. The Stimulus controller owns one `<canvas>` (at export resolution, CSS-scaled for display). A single pure `render(ctx, template, boxes, captions)` draws the preview on every input, and `toBlob` is called on that same canvas at submit time. No second render path exists, so they can't diverge. Font, size search, wrapping and stroke all run on the same engine, which matters because glyph metrics vary by platform and engine (MDN measureText note). Debounce redraws (about 100ms or `requestAnimationFrame`) because the binary search plus wrap runs per keystroke. It's cheap, but this keeps low-end phones smooth.

## 6. Direct upload from a Stimulus controller (importmap)

- Active Storage JS can come from an importmap pin of `@rails/activestorage`. The guide lists `javascript_include_tag`, importmap pin, asset pipeline, or npm. [verified: Rails guide] In a Rails 8 importmap app, the default `config/importmap.rb` already has `pin "@rails/activestorage", to: "activestorage.esm.js"`. Confirm in this repo's `config/importmap.rb`.
- The module exports `start`, `DirectUpload`, `DirectUploadController`, `DirectUploadsController`, `dispatchEvent`. It auto-starts only if `window.ActiveStorage` is defined. Importing the ESM and only using `DirectUpload` does not trigger form auto-upload. [verified: rails/rails `activestorage/app/javascript/activestorage/index.js`]
- `new DirectUpload(file, url, delegate, customHeaders = {}, checksum_algorithm = "md5")`. `create(callback)` computes the checksum, creates the blob record at `url`, uploads the file, and calls `callback(error, blob)` (error-first) with `blob.toJSON()`. Delegate hooks (optional): `directUploadWillCreateBlobWithXHR(xhr)` and `directUploadWillStoreFileWithXHR(xhr)`, which can be used to track progress via `xhr.upload` and to add headers. [verified: rails/rails `direct_upload.js`]
- `url` is `rails_direct_uploads_url` (the guide's `data-direct-upload-url`), which you can render into a Stimulus value. [verified: guide]
- The file in `blob` JSON should include `signed_id`. I could not confirm `signed_id` from `direct_upload.js` alone, since it's defined in `BlobRecord`. The Rails guide's custom-UI flow uses the `signed_id` to attach it to the model by posting it in a hidden field. Verify by logging the callback arg. [inferred]
- Convert the Blob to a File first: `new File([blob], "meme.png", { type: "image/png" })`. DirectUpload takes a `File` (it reads `.name`, `.type`, `.size`). [inferred]
- Flow:
  1. Stimulus `connect()`: load the image (`crossOrigin`), `await document.fonts.load(...)`, draw.
  2. On input: re-render.
  3. On submit: `canvas.toBlob(cb, "image/png")`, wrap in a `File`, `new DirectUpload(file, this.urlValue, this).create((err, blob) => ...)`.
  4. On success: put `blob.signed_id` into a hidden field (for example `meme[image]`), and submit the form (or POST via fetch). The model does `has_one_attached :image`.
- Server side: validate content type (`image/png`) and byte size. Direct upload makes the client assert the type, so verify after attach, for example with `content_type` checks in the model or an `ActiveStorage` analyzer. [inferred]

## Recommended approach

1. **Single canvas, single render function** shared by preview and export. Backing size equals the Template's native size, capped at about 2048px on the long side (and well under iOS's 16.7 MP). Display it with CSS scaling, with no DPR multiplication.
2. **Font**: self-host **Anton** (OFL 1.1) as WOFF2 with `@font-face`. Never ship Impact (Microsoft's FAQ forbids self-hosting and conversion). Before first draw, `await document.fonts.load("1em Anton", text)` and re-fit after load.
3. **Fit**: per Text Box, binary search integer font size with greedy word wrap, with the fit test on both total height and each line's width (this covers long unbroken words), minimum size floor, then character-break or clip as a last resort. Also cap caption length in the input.
4. **Style**: `lineJoin = "round"`, stroke width about size/8 counted inside the fit, draw stroke then fill, with explicit `letterSpacing`, `fontKerning` and `textRendering` settings.
5. **Images**: serve Template images via Active Storage's **proxy route** (same origin, no bucket CORS), and always set `img.crossOrigin = "anonymous"` before `src`. If using S3 or a CDN later, add GET CORS rules for the app origin there. Guard `toBlob` with try/catch for `SecurityError` and a null check.
6. **Upload**: Stimulus controller imports `DirectUpload` from `@rails/activestorage` (importmap), wraps the PNG blob in a `File`, calls `create`, then submits the returned `signed_id` in a hidden field. Validate type and size server side. Progress comes from the delegate's XHR hooks.
7. **Open items to test on real devices**: iOS Safari area and total-memory limits (the cited source is a 2022 blog, not WebKit docs), that `document.fonts.load` guarantees metrics before the first measure, PNG file size at 2048px on mobile data, and whether `blob.signed_id` is present in the DirectUpload callback.
