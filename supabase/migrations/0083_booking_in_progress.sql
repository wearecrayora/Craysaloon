-- 0083 A booking can be IN PROGRESS
--
-- The start-code feature (0084) puts a step between "confirmed" and
-- "completed": the customer is in the chair and the service has begun.
--
-- Alone in its own migration because PostgreSQL will not let a new enum value
-- be USED in the transaction that adds it, and every migration here runs in
-- one transaction. 0084 is where it is used - including in the double-booking
-- constraint, which covers pending and confirmed only and would otherwise
-- treat an occupied chair as free.

alter type public.booking_status add value if not exists 'in_progress' after 'confirmed';
