--


CREATE INDEX idx_templates_name ON templates(name);
CREATE INDEX idx_templates_retired ON templates(retired);

CREATE INDEX idx_templates_name_not_retired ON templates(name) WHERE retired = FALSE;

CREATE INDEX idx_templates_deception_score ON templates(deception_score) WHERE retired = FALSE;

CREATE INDEX idx_templates_indicators ON templates USING GIN (indicators);




CREATE INDEX idx_subscriptions_customer_id ON subscriptions(customer_id);
CREATE INDEX idx_subscriptions_status ON subscriptions(status);
CREATE INDEX idx_subscriptions_archived ON subscriptions(archived);

CREATE INDEX idx_subscriptions_active ON subscriptions(status, archived) 
    WHERE status IN ('queued', 'running') AND archived = FALSE;

CREATE INDEX idx_subscriptions_name ON subscriptions(name);

CREATE INDEX idx_subscriptions_processing ON subscriptions(processing, status)
    WHERE processing = TRUE;

CREATE INDEX idx_subscriptions_templates_selected ON subscriptions USING GIN (templates_selected);

CREATE INDEX idx_subscriptions_landing_page_id ON subscriptions(landing_page_id)
    WHERE landing_page_id IS NOT NULL;


CREATE INDEX idx_primary_contacts_email ON primary_contacts(email);

CREATE INDEX idx_primary_contacts_active ON primary_contacts(active) WHERE active = TRUE;


CREATE INDEX idx_cycles_subscription_id ON cycles(subscription_id);
CREATE INDEX idx_cycles_active ON cycles(active);

CREATE INDEX idx_cycles_subscription_active ON cycles(subscription_id, active, created_at DESC)
    WHERE active = TRUE;

CREATE INDEX idx_cycles_start_date ON cycles(start_date);
CREATE INDEX idx_cycles_end_date ON cycles(end_date);

CREATE INDEX idx_cycles_dirty_stats ON cycles(dirty_stats) WHERE dirty_stats = TRUE;

CREATE INDEX idx_cycles_template_ids ON cycles USING GIN (template_ids);


CREATE INDEX idx_targets_cycle_id ON targets(cycle_id);
CREATE INDEX idx_targets_subscription_id ON targets(subscription_id);
CREATE INDEX idx_targets_template_id ON targets(template_id);
CREATE INDEX idx_targets_email ON targets(email);

CREATE INDEX idx_targets_pending_send ON targets(cycle_id, send_date, sent)
    WHERE sent = FALSE;

CREATE INDEX idx_targets_timeline ON targets USING GIN (timeline);

CREATE INDEX idx_targets_deception_level ON targets(deception_level);

CREATE INDEX idx_targets_with_errors ON targets(cycle_id, error)
    WHERE error IS NOT NULL;


CREATE INDEX idx_subscription_tasks_subscription_id ON subscription_tasks(subscription_id);
CREATE INDEX idx_subscription_tasks_uuid ON subscription_tasks(task_uuid);

CREATE INDEX idx_subscription_tasks_pending ON subscription_tasks(executed, scheduled_date)
    WHERE executed = FALSE;

CREATE INDEX idx_subscription_tasks_ready ON subscription_tasks(subscription_id, executed, scheduled_date)
    WHERE executed = FALSE;

CREATE INDEX idx_subscription_tasks_type ON subscription_tasks(task_type);


CREATE INDEX idx_target_timeline_target_id ON target_timeline_events(target_id, event_time DESC);

CREATE INDEX idx_target_timeline_message ON target_timeline_events(message);

CREATE INDEX idx_target_timeline_geo ON target_timeline_events(country, city)
    WHERE country IS NOT NULL;

CREATE INDEX idx_target_timeline_ip ON target_timeline_events(ip)
    WHERE ip IS NOT NULL;

CREATE INDEX idx_target_timeline_asn ON target_timeline_events(asn_org)
    WHERE asn_org IS NOT NULL;

CREATE INDEX idx_target_timeline_time ON target_timeline_events(event_time DESC);


CREATE INDEX idx_notification_history_subscription_id ON subscription_notification_history(subscription_id, sent_at DESC);

CREATE INDEX idx_notification_history_message_type ON subscription_notification_history(message_type);

CREATE INDEX idx_notification_history_email_to ON subscription_notification_history USING GIN (email_to);


CREATE INDEX idx_test_results_subscription_id ON subscription_test_results(subscription_id);
CREATE INDEX idx_test_results_uuid ON subscription_test_results(test_uuid);

CREATE INDEX idx_test_results_email ON subscription_test_results(email);

CREATE INDEX idx_test_results_template_id ON subscription_test_results(template_id);

CREATE INDEX idx_test_results_sent ON subscription_test_results(sent);
CREATE INDEX idx_test_results_opened ON subscription_test_results(opened);
CREATE INDEX idx_test_results_clicked ON subscription_test_results(clicked);

CREATE INDEX idx_test_results_stats ON subscription_test_results(subscription_id, sent, opened, clicked);


CREATE INDEX idx_test_timeline_test_result_id ON test_timeline_events(test_result_id, event_time DESC);

CREATE INDEX idx_test_timeline_message ON test_timeline_events(message);




CREATE INDEX idx_subscriptions_recent ON subscriptions(created_at DESC)
    WHERE created_at > NOW() - INTERVAL '30 days';

CREATE INDEX idx_targets_upcoming ON targets(send_date)
    WHERE sent = FALSE AND send_date > NOW();

CREATE INDEX idx_targets_recent_sent ON targets(sent_date DESC)
    WHERE sent = TRUE AND sent_date > NOW() - INTERVAL '7 days';


CREATE INDEX idx_subscriptions_list ON subscriptions(status, archived, name, created_at DESC)
    INCLUDE (customer_id, admin_email, operator_email);

CREATE INDEX idx_cycles_list ON cycles(subscription_id, active, created_at DESC)
    INCLUDE (start_date, end_date, target_count);

CREATE INDEX idx_targets_stats ON targets(cycle_id, sent, deception_level)
    INCLUDE (sent_date);


--
--
--
--
--
--
--
--
--
