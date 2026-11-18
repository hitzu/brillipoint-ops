feat(video): boomerang and slow-motion clips end to end (PB, API, front)

### Problem

Guests can capture boomerang and slow-motion clips in the photobooth app (PB), but the clip never leaves the iPad: it is stored locally (`Documents/video-beta/<sessionToken>.mp4`) and only shareable via AirDrop/WhatsApp. Backend and gallery cannot handle video today:

- **API accepts JPEG only**: `src/photos/dto/presigned-upload.dto.ts:19` (`@IsIn(['image/jpeg'])`), `src/photos/photos.service.ts:224-225`, `src/photos/sessions.service.ts:45-47,461-463`.
- **Presign shape is photo-specific**: always returns `.jpg` original + minimized paths (`sessions.service.ts:452-509`); confirm requires `minimizedStoragePath` (`sessions.service.ts:511-550`).
- **No video in the model**: `Photo` / `Session` entities have no `type`, `mime`, `duration` or poster columns. Read endpoints only filter by extension (`isGifPath`, `sessions.service.ts:555`).
- **Front has no video rendering**: no `<video>` in the party feature (only `src/features/story/components/LoopVideo.tsx`); `SessionItem` only allows `type: "photo"` (`src/features/party/types/session.ts:1-2`); `SessionPhoto` has no media type (`src/interfaces/eventGallery.ts:17-21`).

### Decisions (2026-11-06)

1. **PB is the flag.** Video is enabled by the operator in PB (`VideoBetaSettings.enabled`, device-local, off by default, `Services/VideoBetaSettings.swift` on `feat/video-camera-functionality-mvp`). There is **no** video flag in the backend or the front. PB only requests video upload URLs when video is on.
2. **Video is fully independent from photos.** It does not count toward `photoCount` or the session photo quota. If PB never uploads a video, nothing changes for anyone: photo responses keep their exact current shape and the front shows no trace of video.
3. **A video is never a gallery cover.** Videos are ordered last among the session items, after all photos.
4. **Isolated and additive API** so video can be removed without photos noticing (no breaking changes until video proves it sells): own table, own endpoints, optional read field. `Photo` is not touched.
5. **Same storage bucket**, in a `videos` subfolder next to `minimized` (`photobooth/${eventId}/minimized/...`, `sessions.service.ts:484`): `photobooth/${eventId}/videos/${fileId}.mp4` plus its poster `.jpg`. For now a session has at most one video.
6. **Offline**: if there is no internet, PB puts the video upload in the event's deferred upload queue (same queue as photos, `feat/offline-total-event`) and uploads it when connectivity returns.
7. **The API does not validate whether video is "enabled"** for an event (PB is the gate). Accepted MVP risk; revisit if video becomes a paid feature.

### Proposal

**Phase 1 — PB (in progress, local only)**
- Branch `feat/video-camera-functionality-mvp` (2 wip commits): recipes, composer, quality presets, upsell flow and tests are done (`odd/tasks/boomerang-mvp.md` T1-T3, T7-T9).
- Pending: T4 (mode selector + video session path) and T5 (result screen + share) are implemented but not walked through in the simulator; T6 (on-device validation) not started.
- Consolidate with `feat/boomerang-mvp` (1 wip commit, diverged base) before Phase 2.

**Phase 2 — API**
- **Own storage**: a dedicated table (e.g. `session_videos`: session, storage path, poster path, mime, duration).
- **Own endpoints**: dedicated video presign/confirm (e.g. under `/sessions/:token/videos`) returning upload URLs for `photobooth/${eventId}/videos/${fileId}.mp4` and its poster `.jpg`. Photo presign/confirm stays untouched.
- **Optional read field**: session (and gallery session) responses gain an optional `videos` field, present only when the session has videos. Photo items keep their exact current shape.

**Phase 3 — Front**
- When the session response contains `videos`, append them after the photos as a `video` `SessionItem`; render `<video>` (poster, muted, loop, playsinline) in carousel (`ItemStage.tsx`), grid (`PhotoGrid.tsx`) and session card. Gallery cover (`Overview.tsx`) stays photo-only.
- Without the `videos` field the front behaves exactly as today.
- Share/download already maps `mp4` → `video/mp4` (`src/features/party/utils/mediaActions.ts:34-35`).

**Phase 4 — PB upload**: upload MP4 + poster with the new endpoints through the deferred upload queue, and restore the QR in video sessions. Do not reuse the dead `uploadGIF` (`Services/SessionPhotoUploader.swift:451`), which targets a retired response shape.

### Acceptance criteria

- With video off in PB (default), PB, API responses and the front behave exactly as today.
- PB: on-device validation done (fps, processing time, size ≤ 6 MB, playback), results recorded in `boomerang-mvp.md` T6.
- A boomerang / slow-motion clip captured in PB is uploaded to `photobooth/<eventId>/videos/` and shows in the guest's session page and the event gallery, after the photos, with its poster as thumbnail.
- A video captured without internet is queued and uploaded once connectivity returns.
- A video never becomes the gallery cover and never counts toward `photoCount`.
- Photo endpoints and the `Photo` table keep their exact current behavior (JPEG-only, same request/response shape); removing the video table and endpoints would not affect photos.

### Risks

- The Supabase bucket may restrict allowed MIME types or file size; verify that `video/mp4` uploads to the existing bucket succeed before building Phase 4 (the API signs URLs without content type or size limits, `photos.service.ts:68-79`).
- No backend enforcement of video (decision 7).
- This changes the PB ↔ API contract (a cross-repo port); update `system.yaml` and contracts when declared.

### Out of scope

- Sharing photos and video without internet (AirDrop / local network). Will be tracked in a separate issue after video ships.

### Engram context

Before implementing, recover the planning context (decisions, discarded alternatives, evidence) from Engram: project `brillipoint-ops`, `topic_key` `issue/brillipoint-ops#3` (`mem_search`, then `mem_get_observation`). If it contradicts this issue, the issue wins.

### Affected repositories (hint)

BrillipointPhotobook, bookandsign-api, bookandsign-front
