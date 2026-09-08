-- 0018 The owner exists before the owner logs in
--
-- FOUND BY WRITING THE PROVISIONING FUNCTION.
--
-- 0017 added `users.auth_user_id` on the theory that a salon owner is created
-- by the console days before they first open the app. That was right, but
-- incomplete: `users.id` still carried
--
--     FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE
--
-- from 0003, which encodes the opposite assumption - that a user row cannot
-- exist until an Auth account does. So app_admin.provision_salon could not
-- create the owner at all, and PRD 6.2 requires exactly that ("creates the
-- owner user ... the owner then logs into the same Android app with that
-- mobile number").
--
-- The fix is the shape `customers` has used since 0004: an internal uuid
-- primary key, plus a nullable auth_user_id attached at first login. Nothing
-- depended on users.id being the Auth uid - every `users` policy keys off
-- salon_id, and app_role comes from the JWT claim, not from this table. The
-- rows that reference users(id) - staff, notifications, notification_tokens -
-- are unaffected, because users(id) is still the primary key.

alter table public.users drop constraint users_id_fkey;

comment on column public.users.id is
  'Internal identity, generated at provisioning. NOT the Auth uid - see auth_user_id. An owner has a row here from the moment the console creates the salon, which is before they have ever logged in.';

-- ---------------------------------------------------------------------------
-- Detaching a login must not destroy the salon's record of a person
-- ---------------------------------------------------------------------------
--
-- 0017 created this FK with the default NO ACTION, which would make deleting
-- an Auth account fail whenever a users row pointed at it. SET NULL matches
-- customers.auth_user_id and is the behaviour we actually want: the login goes,
-- the staff record and everything attached to it stays. Hard-deleting a
-- person's operational history is not something an auth-side deletion should
-- be able to cause (RULES 14).

alter table public.users drop constraint users_auth_user_id_fkey;

alter table public.users
  add constraint users_auth_user_id_fkey
  foreign key (auth_user_id) references auth.users(id) on delete set null;
