# Starter Template Library: sourcing images we can ship (MEME-3)

Researched 2026-11-06. Terms follow `GLOSSARY.md` (Template, Text Box, Template Library, Hand, Admin).

## Bottom line

No source gives us classic meme Templates under a clean licence. The images are almost all third-party copyrighted stills or photos, and the sites that host them disclaim or ignore rights. The practical risk for ~10 Players in a private, non-commercial Room is low but not zero. The best structured data (Text Box counts and positions) comes from memegen. See "Recommended approach" at the end.

## Sources assessed

### Imgflip

- API `GET https://api.imgflip.com/get_memes` needs no auth and is on the Free tier. It returns the top 100 user-uploaded memes by 30-day caption count. Each entry has `id`, `name`, `url`, `width`, `height` and `box_count`. Docs warn the size and order "may change at any time" and that properties may be added without warning. [imgflip.com/api]
- I fetched it live: 100 memes, with `box_count` of 2 (67), 3 (22), 4 (9) and 5 (2). The images are hosted at `i.imgflip.com`.
- The docs say the database is user-generated and not curated, and that memes "will come and go". The docs state no licence for the template images or the data. [imgflip.com/api]
- ToS: users keep ownership of uploads and grant Imgflip a worldwide licence. Other users "can also use the content with the Service". There is no API-specific term and no scraping clause. The closest is a ban on access "using a method other than the interface and the instructions that we provide". Imgflip responds to copyright notices. It mentions hotlinking and says it does not currently charge for bandwidth. [imgflip.com/terms]
- So Imgflip grants no right to redistribute the images. Fetching them at seed time through the documented endpoint is the intended use. Bundling them in our repo is not licensed.
- `box_count` is a count only. There are no coordinates. Imgflip's caption endpoint (`caption_image`) needs a login and renders captions server-side. We would not use it.

### Know Your Meme

- It is an encyclopedia, not an image-licensing source. The site footer reads "© Literally Media Ltd." with all rights reserved, and "Know Your Meme" is a registered trademark. [knowyourmeme.com/about]
- I found no public API. The `/terms` URL returned 404, and the About page does not link to terms. Its robots.txt disallows some paths (comments, edits, search and others) but not meme pages. [knowyourmeme.com/robots.txt]
- Use KYM only to identify a Template's origin and name. Do not scrape its images. Memegen already stores a KYM `source` link for each Template.

### Wikimedia Commons

- Commons accepts only free content. Commercial use and derivatives must be allowed. Fair use is not accepted. CC BY, CC BY-SA, CC0 and public domain are the usual licences. [commons.wikimedia.org/wiki/Commons:Licensing]
- That makes it the one source that is safe to bundle, provided each file's author, source and licence are recorded (attribution is the usual requirement).
- The catch is that most classic meme images (movie stills, stock photos) are not on Commons because they are not free. What does exist is the free-photo subset (for example Commons' own "Category:Memes", plus self-published photos that became memes). That is a small, hit-or-miss set.
- There are no Text Box data. Each file's licence must be checked individually.

### CC0 / public-domain sets

- Pixabay, Unsplash and Pexels have their own site licences, not CC0. Openverse, the Wikimedia Commons PD categories and Smithsonian Open Access (CC0) are true CC0/PD sources.
- None of them contain "classic memes". They would give us original, safe stock images that we would have to pair with our own Text Box definitions.
- I did not verify these licence pages individually in this pass. That is a follow-up if we go this way.

### memegen (jacebrowning/memegen) and `api.memegen.link`

- The code is MIT licensed (copyright 2020 Jace Browning). The README and CONTRIBUTING files make no copyright or takedown statement about the template images, and they do not say the MIT licence covers them. [github.com/jacebrowning/memegen, LICENSE.txt]
- Each Template is a directory `templates/<id>/` with `config.yml` plus `default.png/jpg` background(s). CONTRIBUTING says to add the background image and update `config.yml`. [CONTRIBUTING.md] The repo has about 211 entries under `templates/`.
- The live API `GET https://api.memegen.link/templates/` returned 209 Templates. Each has `id`, `name`, `lines` (the Text Box count), `overlays`, `styles`, `blank` (the image URL), `example.text`, `source` (a KYM link) and `keywords`. Distribution of `lines`: 1 (6), 2 (166), 3 (22), 4 (6), 5 (4), 6 (3), 8 (2).
- `config.yml` has per-line Text Box geometry. Example from `templates/drake/config.yml`, a 2-line Template:
  - Line 1: `anchor_x: 0.0`, `anchor_y: 0.0`, `scale_x: 1.0`, `scale_y: 0.2`, `angle`, `align`, `style`, `color`, `font`.
  - Line 2: `anchor_y: 0.8`, other values the same.
  - The coordinates are fractions (0 to 1) of the image, so they are resolution independent.
  - It also holds `overlay` entries (centre, scale), `example` text, `source` and `keywords`.
- This is the only source I found with importable Text Box coordinates. It maps well to our Text Box (a region where text shrinks to fit). The default memegen boxes are often the classic top and bottom strip, so some manual tuning will be needed.
- The licensing gap: the images are the same third-party stills as everywhere else. MIT on the code does not give us rights to them.
- The public API sends `access-control-allow-origin: *` and long cache headers. I found no stated rate limit or ToS on the pages I could read. The Swagger docs page did not render for me, so I did not verify them.

## Copyright and practical risk

Not legal advice. This is the repo owner's judgment call.

- Classic meme images are usually copyrighted (film and TV stills, photographers' photos). No source above grants us a licence, apart from the free-licensed Commons subset.
- Private, non-commercial use among ~10 coworkers that is not publicly reachable has low practical risk. Fair-use arguments (transformative caption, no market harm) are plausible but are not guaranteed. Memes with identifiable private individuals add privacy concerns, which matter more than copyright here.
- The risk goes up if the repo is public, if the site is reachable by anyone, or if it is monetised. A public GitHub repo containing the images is the worst case, because a takedown (DMCA) lands on the repo.
- Safest to ship: images with a licence we can show (Commons free files, CC0, or our own originals).
- Fetch at seed time (not in the repo): Imgflip `get_memes` URLs, memegen `blank` URLs.

## Bundle vs fetch

| Option | In repo | Licence situation | Notes |
|---|---|---|---|
| Bundle Commons/CC0 images + attribution manifest | Yes | Clear | Small set, needs per-file licence records |
| Bundle memegen/Imgflip images | No | Not licensed | Public-repo DMCA exposure |
| Fetch from memegen `blank` URLs at seed time | Data only (id, name, Text Box geometry) | Same as above, but nothing is redistributed by us | Seed copies images into Active Storage on the private server, not git |
| Hotlink at runtime | Data only | Same | Fragile: third-party uptime, order and removals |

## Recommended approach

1. Seed the Template Library from memegen's `GET /templates/` plus each Template's `config.yml`. It has about 209 Templates, which comfortably covers a 10-Player, 3-Round game (30 Hands of 10 gives heavy repeats well below ~100). Import `lines` as the Text Box count and the `config.yml` `anchor_*`/`scale_*`/`angle` values as the Text Box regions, stored as 0 to 1 fractions.
2. Do this through a seed or rake task that runs at deploy or setup time. It downloads the `blank` image into the app's own storage (Active Storage or the server disk), which is gitignored. Commit only a JSON manifest of ids, names, Text Box geometry and `source` links, and no images. This keeps third-party images out of git history and any public repo.
3. Let the Admin curate: add a flag or ability to disable a Template. This lets us drop anything unsuitable (for example identifiable private individuals) and handle any takedown quickly.
4. Optionally add a small bundled set of Commons/CC0 images with an attribution manifest, so a fresh clone works with zero network access.
5. Use Imgflip only as a fallback or supplement. The `get_memes` list has 100 Templates with `box_count` only and no coordinates, so Text Boxes would have to be hand-defined.

Open items to verify before building: memegen's own ToS and rate limits (the docs page did not render), and the actual licence of any CC0 set we choose.

## Sources

- https://imgflip.com/api
- https://imgflip.com/terms
- https://api.imgflip.com/get_memes (live response)
- https://github.com/jacebrowning/memegen (README, LICENSE.txt, CONTRIBUTING.md, `templates/drake/config.yml`)
- https://api.memegen.link/templates/ (live response)
- https://commons.wikimedia.org/wiki/Commons:Licensing
- https://knowyourmeme.com/about and https://knowyourmeme.com/robots.txt (`/terms` returned 404)
