--


CREATE INDEX IF NOT EXISTS idx_subscriptions_legacy_objectid 
ON subscriptions(legacy_objectid) 
WHERE legacy_objectid IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_subscriptions_customer_id 
ON subscriptions(customer_id) 
WHERE customer_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_subscriptions_status 
ON subscriptions(status) 
WHERE status IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_subscriptions_archived 
ON subscriptions(archived);

CREATE INDEX IF NOT EXISTS idx_subscriptions_active 
ON subscriptions(id) 
WHERE archived = FALSE;

CREATE INDEX IF NOT EXISTS idx_subscriptions_primary_contact_email 
ON subscriptions(primary_contact_email) 
WHERE primary_contact_email IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_subscriptions_customer_active 
ON subscriptions(customer_id, archived, status) 
WHERE customer_id IS NOT NULL;

COMMENT ON INDEX idx_subscriptions_legacy_objectid IS 'Supports backward-compatible ObjectID lookups from HTTP endpoints';
COMMENT ON INDEX idx_subscriptions_customer_active IS 'Optimizes customer subscription queries filtering by active status';


CREATE INDEX IF NOT EXISTS idx_subscription_tasks_subscription_id 
ON subscription_tasks(subscription_id);

CREATE INDEX IF NOT EXISTS idx_subscription_tasks_task_uuid 
ON subscription_tasks(task_uuid);

CREATE INDEX IF NOT EXISTS idx_subscription_tasks_executed 
ON subscription_tasks(executed) 
WHERE executed = FALSE;

CREATE INDEX IF NOT EXISTS idx_subscription_tasks_scheduled_date 
ON subscription_tasks(scheduled_date);

CREATE INDEX IF NOT EXISTS idx_subscription_tasks_pending 
ON subscription_tasks(subscription_id, executed, scheduled_date) 
WHERE executed = FALSE;

CREATE INDEX IF NOT EXISTS idx_subscription_tasks_type 
ON subscription_tasks(task_type) 
WHERE task_type IS NOT NULL;

COMMENT ON INDEX idx_subscription_tasks_pending IS 'Optimizes queries for pending tasks per subscription ordered by schedule';


CREATE INDEX IF NOT EXISTS idx_cycles_legacy_objectid 
ON cycles(legacy_objectid) 
WHERE legacy_objectid IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_cycles_subscription_id 
ON cycles(subscription_id);

CREATE INDEX IF NOT EXISTS idx_cycles_active 
ON cycles(active) 
WHERE active = TRUE;

CREATE INDEX IF NOT EXISTS idx_cycles_start_date 
ON cycles(start_date);

CREATE INDEX IF NOT EXISTS idx_cycles_end_date 
ON cycles(end_date);

CREATE INDEX IF NOT EXISTS idx_cycles_send_by_date 
ON cycles(send_by_date);

CREATE INDEX IF NOT EXISTS idx_cycles_subscription_active 
ON cycles(subscription_id, active, start_date DESC) 
WHERE active = TRUE;

CREATE INDEX IF NOT EXISTS idx_cycles_active_dates 
ON cycles(active, start_date, end_date) 
WHERE active = TRUE;

COMMENT ON INDEX idx_cycles_legacy_objectid IS 'CRITICAL: HTTP endpoints pass ObjectID strings (24-char hex)';
COMMENT ON INDEX idx_cycles_subscription_id IS 'CRITICAL: FK traversal in notification workflow (GetCycle → GetSubscription)';


CREATE INDEX IF NOT EXISTS idx_notifications_legacy_objectid 
ON notifications(legacy_objectid) 
WHERE legacy_objectid IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_notifications_task_name 
ON notifications(task_name);

CREATE INDEX IF NOT EXISTS idx_notifications_name 
ON notifications(name) 
WHERE name IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_notifications_has_attachment 
ON notifications(has_attachment) 
WHERE has_attachment = TRUE;

COMMENT ON INDEX idx_notifications_task_name IS 'CRITICAL: Lookup by task_name in notification workflow (e.g., "cycle_report")';


CREATE INDEX IF NOT EXISTS idx_templates_legacy_objectid 
ON templates(legacy_objectid) 
WHERE legacy_objectid IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_templates_name 
ON templates(name);

CREATE INDEX IF NOT EXISTS idx_templates_retired 
ON templates(retired);

CREATE INDEX IF NOT EXISTS idx_templates_name_active 
ON templates(name, retired) 
WHERE retired = FALSE;

COMMENT ON INDEX idx_templates_name_active IS 'CRITICAL: Supports GetPhish(name) query filtering non-retired templates';



CREATE INDEX IF NOT EXISTS idx_subscriptions_target_emails_gin 
ON subscriptions USING GIN (target_email_list);

CREATE INDEX IF NOT EXISTS idx_subscriptions_templates_gin 
ON subscriptions USING GIN (templates_selected);

CREATE INDEX IF NOT EXISTS idx_subscriptions_next_templates_gin 
ON subscriptions USING GIN (next_templates);

CREATE INDEX IF NOT EXISTS idx_cycles_template_ids_gin 
ON cycles USING GIN (template_ids);

COMMENT ON INDEX idx_subscriptions_target_emails_gin IS 'Supports JSONB queries on target_email_list array (if needed by con-pca-api)';


CREATE INDEX IF NOT EXISTS idx_subscriptions_notification_workflow 
ON subscriptions(
    id, 
    primary_contact_first_name, 
    primary_contact_last_name, 
    primary_contact_email,
    admin_email
) WHERE archived = FALSE;

COMMENT ON INDEX idx_subscriptions_notification_workflow IS 'Covering index for notification workflow - includes all fields accessed in notifications/manager.go';








--
--
--


--
--
--
--
--


--
--
