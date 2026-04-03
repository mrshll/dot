---
name: podcast-release
description: "Publish a new episode of the Weathering podcast. Handles the full release pipeline: MP3 metadata & chapters via ffmpeg, upload to Cloudflare R2, generate episode markdown for the dynamical.org 11ty site, validate the podcast RSS feed, and draft social posts. Use this skill whenever the user says 'release an episode', 'publish a podcast', 'new episode', 'podcast release', or anything about shipping/publishing a Weathering episode. Also trigger when user mentions podcast metadata, chapter markers, or podcast feed validation in the context of Weathering."
---

# Podcast Release Skill

Publishes a new episode of the **Weathering** podcast through a multi-step pipeline. Each step pauses for user confirmation before proceeding to the next.

## Prerequisites

The user needs to provide (or you need to locate):
- The edited MP3 file (final audio)
- A Google Doc URL with shownotes (title, chapters with timestamps, description, links, recommended reading)
- Episode cover art image (or use the default `weathering_logo.png`)

Tools that should be available on the system:
- `ffmpeg` (for MP3 metadata/chapters)
- `aws` CLI (for R2 upload)
- `git` (for committing to the dynamical.org repo)
- `op` (1Password CLI — R2 credentials are stored in the "Cloudflare R2 Weathering" item)

## Pipeline Steps

Work through these steps in order. Use a TodoList to track progress. Pause after each step to confirm with the user before proceeding.

### Step 1: Gather Episode Info

Ask the user for:
- MP3 file path
- Google Doc URL for shownotes
- Episode number (auto-detect by looking at existing episodes in `content/podcast/` and incrementing)
- Publish date (default: today)
- Cover art path (default: download `https://weathering.dynamical.org/weathering_logo.png`)

Fetch the Google Doc by appending `/export?format=txt` to the doc URL (follow redirects). Parse out:
- **Title**: Usually the first line or clearly labeled
- **Description/summary**: The introductory paragraph(s)
- **Chapters**: Lines with timestamps in `HH:MM:SS` or `MM:SS` format
- **Papers/links**: URLs and paper titles
- **Recommended reading**: Book/article recommendations

Show the parsed content to the user for confirmation before proceeding.

### Step 2: MP3 Metadata & Chapters

Use ffmpeg to embed ID3v2 metadata into the MP3:

```bash
# Write chapter metadata file (ffmetadata format)
# See scripts/write_chapters.py for generating the ffmetadata file from parsed chapters

ffmpeg -i input.mp3 -i chapters.ffmetadata \
  -map 0:a -map_metadata 1 \
  -metadata title="EPISODE_TITLE" \
  -metadata artist="Marshall, Marta, and Alden" \
  -metadata album="Weathering" \
  -metadata track="EPISODE_NUMBER" \
  -metadata genre="Podcast" \
  -metadata date="PUBLISH_DATE" \
  -c copy \
  output.mp3
```

If cover art is provided, also embed it:
```bash
ffmpeg -i output.mp3 -i cover.png \
  -map 0:a -map 1:v \
  -c:a copy -c:v png \
  -metadata:s:v title="Album cover" \
  -metadata:s:v comment="Cover (front)" \
  -disposition:v attached_pic \
  final.mp3
```

Use `scripts/write_chapters.py` to generate the ffmetadata file from the parsed chapter list.

After tagging, verify with:
```bash
ffprobe -v quiet -print_format json -show_chapters -show_format output.mp3
```

Show the metadata summary to the user for confirmation.

### Step 3: Upload to R2

Upload the final MP3 to the Cloudflare R2 bucket. Use `op run` to inject credentials from the "Cloudflare R2 Weathering" 1Password item:

```bash
op run --env-file=<(cat <<'EOF'
AWS_ACCESS_KEY_ID=op://Private/Cloudflare R2 Weathering/access key id
AWS_SECRET_ACCESS_KEY=op://Private/Cloudflare R2 Weathering/secret access key
EOF
) -- aws s3 cp final.mp3 s3://weathering/EPISODE_NUMBER.mp3 \
  --endpoint-url https://a037e2d3d5f9c6ecfc95350360f2ab8d.r2.cloudflarestorage.com \
  --content-type audio/mpeg
```

The public URL will be: `https://weathering.dynamical.org/EPISODE_NUMBER.mp3`

Verify the upload by checking the URL is accessible (curl -I).

### Step 4: Create Episode Markdown

Create the episode markdown file at `content/podcast/EPISODE_NUMBER.md` in the dynamical.org repo. Follow the exact frontmatter format of existing episodes:

```markdown
---
title: "EPISODE_TITLE"
date: YYYY-MM-DD
episode_number: "NNN"
audio_url: "https://weathering.dynamical.org/NNN.mp3"
spotify_url: ""
apple_url: ""
---

DESCRIPTION_FROM_SHOWNOTES

---

## Papers

- **[Paper Title](URL)**, Authors

---

## Chapters

- **HH:MM:SS** - Chapter title
- **HH:MM:SS** - Chapter title

---

## Recommended reading

- _Book Title_ by Author
- [Article Title](URL)
```

Notes:
- `spotify_url` and `apple_url` are left empty initially — they get filled in after the episode appears on those platforms.
- Match the style of existing episodes (look at 005.md, 006.md for reference).
- The description should be adapted from the Google Doc but written in the voice of the existing episodes.

Show the draft markdown to the user. After approval, commit and push:

```bash
cd /path/to/dynamical.org
git add content/podcast/NNN.md
git commit -m "Add episode NNN: EPISODE_TITLE"
git push origin main
```

This triggers a Cloudflare Pages deploy.

### Step 5: Validate Podcast Feed

After the deploy completes (wait ~1-2 minutes), validate the podcast RSS feed:

1. Fetch `https://dynamical.org/feed/podcast.xml`
2. Check that the new episode appears as the first `<item>`
3. Validate required fields: `<title>`, `<enclosure>`, `<pubDate>`, `<itunes:episode>`
4. Verify the enclosure URL is reachable
5. Optionally run through an RSS validator (fetch `https://podba.se/validate?url=https://dynamical.org/feed/podcast.xml` or use `xmllint`)

Report the validation results.

### Step 6: Platform Distribution

These steps require manual interaction. Guide the user through each:

**Apple Podcasts:**
- Open https://podcastsconnect.apple.com
- The feed should auto-update, but you can manually refresh
- Once the episode appears, grab the Apple Podcasts URL

**Spotify (creators.spotify.com):**
- Open https://creators.spotify.com
- Create a new episode manually (Spotify doesn't have a public upload API for podcasts)
- Upload the same MP3 or let it pull from the RSS feed
- Once published, grab the Spotify URL

After getting both URLs, update the episode markdown:
```bash
# Edit content/podcast/NNN.md to add spotify_url and apple_url
git add content/podcast/NNN.md
git commit -m "Add platform URLs for episode NNN"
git push origin main
```

### Step 7: Social Media Posts

Draft posts for each platform. The tone should match the podcast's voice: absurdist, surreal, self-deprecating. Undercut your own hype. Trust the audience. No generic enthusiasm, no press-release language.

**Draft format for each platform:**

- **LinkedIn** (~200-300 words): Slightly more context about the paper/topic. Include the dynamical.org episode URL.
- **Mastodon** (~400 chars): Pithy, weird, maybe a quote from the episode. Include URL.
- **Bluesky** (~250 chars): Similar to Mastodon. Include URL.

Present all three drafts to the user. After approval:
- **LinkedIn**: If the user has the LinkedIn MCP connected, post via API. Otherwise, copy to clipboard / provide for manual posting.
- **Mastodon**: If the user has API access configured, post via `curl` to their instance. Otherwise, manual.
- **Bluesky**: If the user has API access, post via AT Protocol. Otherwise, manual.

### Step 8: Wrap-up Checklist

Confirm everything is done:
- [ ] MP3 tagged with metadata and chapters
- [ ] MP3 uploaded to R2
- [ ] Episode markdown committed and deployed
- [ ] Podcast feed validates with new episode
- [ ] Episode live on Apple Podcasts (or pending)
- [ ] Episode live on Spotify (or pending)
- [ ] Social posts sent (or ready to send)
- [ ] Platform URLs updated in episode markdown

## File Locations

- **dynamical.org repo**: The mounted workspace folder
- **Episode markdown**: `content/podcast/NNN.md`
- **Podcast feed template**: `content/feed/podcast.njk`
- **Episode template**: `_includes/podcast-episode.njk`
- **Episode data config**: `content/podcast/podcast.11tydata.js`
- **R2 bucket**: `s3://weathering/` via endpoint `https://a037e2d3d5f9c6ecfc95350360f2ab8d.r2.cloudflarestorage.com`
- **Public audio URL pattern**: `https://weathering.dynamical.org/NNN.mp3`
