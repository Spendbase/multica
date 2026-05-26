-- name: GetUser :one
SELECT * FROM "user"
WHERE id = $1;

-- name: GetUserByEmail :one
SELECT * FROM "user"
WHERE email = $1;

-- name: CreateUser :one
INSERT INTO "user" (name, email, avatar_url, google_id, email_verified)
VALUES ($1, $2, $3, sqlc.narg('google_id'), sqlc.arg('email_verified'))
RETURNING *;

-- name: UpdateUser :one
-- Patches the user-controlled profile fields. Each parameter follows
-- COALESCE-on-NULL semantics so the handler can omit any field it
-- doesn't intend to write.
--
-- `timezone` (Viewing-tz preference) participates in
-- the same shape but uses sqlc.narg + a sentinel-string convention:
-- the handler passes the empty string "" to mean "clear back to NULL"
-- (browser-detected fallback), an IANA name like "Asia/Shanghai" to
-- pin a value, and `sqlc.narg('timezone') IS NULL` (no value at all)
-- to leave the existing column untouched. Folding it into UpdateUser
-- rather than carrying a dedicated UpdateUserTimezone keeps the
-- profile-patch shape uniform between Preferences fields.
UPDATE "user" SET
    name = COALESCE($2, name),
    avatar_url = COALESCE($3, avatar_url),
    language = COALESCE($4, language),
    profile_description = COALESCE(sqlc.narg('profile_description'), profile_description),
    timezone = CASE
        WHEN sqlc.narg('timezone')::text IS NULL THEN timezone
        WHEN sqlc.narg('timezone')::text = ''    THEN NULL
        ELSE sqlc.narg('timezone')::text
    END,
    updated_at = now()
WHERE id = $1
RETURNING *;

-- name: MarkUserOnboarded :one
UPDATE "user" SET
    onboarded_at = COALESCE(onboarded_at, now()),
    updated_at = now()
WHERE id = $1
RETURNING *;

-- name: PatchUserOnboarding :one
-- Partial update of the user's onboarding decision fields. Currently only the
-- questionnaire JSONB is patchable — the v2 attempt at persisting Step 3
-- runtime choice on the user row was reverted; that state now lives in a
-- frontend Zustand transient store.
UPDATE "user" SET
    onboarding_questionnaire = COALESCE(sqlc.narg('questionnaire'), onboarding_questionnaire),
    updated_at = now()
WHERE id = sqlc.arg('id')
RETURNING *;

-- name: JoinCloudWaitlist :one
-- Records interest in cloud runtimes. Does NOT mark onboarding
-- complete — the user still has to pick a real path (CLI / Skip)
-- in Step 3. Repeating the call overwrites email + reason.
UPDATE "user" SET
    cloud_waitlist_email = $2,
    cloud_waitlist_reason = $3,
    updated_at = now()
WHERE id = $1
RETURNING *;

-- name: GetUserByGoogleID :one
SELECT * FROM "user"
WHERE google_id = $1;

-- name: LinkGoogleIdentity :one
-- Sets google_id on first Google login. email_verified flips to TRUE because
-- the caller has already validated Google's email_verified claim against a
-- verified ID token before invoking this query.
UPDATE "user" SET
    google_id = $2,
    email_verified = TRUE,
    updated_at = now()
WHERE id = $1
RETURNING *;

-- name: SetStarterContentState :one
-- Atomically transition starter_content_state. The handler is
-- responsible for checking the current value first (to decide between
-- "transition NULL -> imported and run the seeding" vs "already
-- decided, short-circuit"). Using COALESCE here would swallow the
-- transition, so this is a straight assignment.
UPDATE "user" SET
    starter_content_state = $2,
    updated_at = now()
WHERE id = $1
RETURNING *;
