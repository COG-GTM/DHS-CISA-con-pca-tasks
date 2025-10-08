-- 
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


CREATE TABLE templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    name VARCHAR(255) UNIQUE NOT NULL,
    subject VARCHAR(500),
    html TEXT,
    text TEXT,
    retired BOOLEAN DEFAULT FALSE,
    
    landing_page_id VARCHAR(255),  -- References landing_page collection (not in migration scope)
    sending_profile_id VARCHAR(255),  -- References sending_profile collection (not in migration scope)
    
    deception_score INTEGER CHECK (deception_score BETWEEN 1 AND 6),
    from_address VARCHAR(255),
    retired_description TEXT,
    
    sophisticated TEXT[],  -- Array of recommendation IDs
    red_flag TEXT[],  -- Array of recommendation IDs
    
    indicators JSONB,  -- Structure: {appearance: {grammar, link_domain, logo_graphics}, sender: {...}, relevancy: {...}, behavior: {...}}
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by VARCHAR(100),
    updated_by VARCHAR(100)
);

COMMENT ON TABLE templates IS 'Phishing email templates (formerly "template" collection)';
COMMENT ON COLUMN templates.indicators IS 'Nested structure containing appearance, sender, relevancy, and behavior indicators';
COMMENT ON COLUMN templates.sophisticated IS 'Array of recommendation IDs for sophisticated indicators';
COMMENT ON COLUMN templates.red_flag IS 'Array of recommendation IDs for red flag indicators';


CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    name VARCHAR(255) NOT NULL,
    subject VARCHAR(500),
    html TEXT,
    task_name VARCHAR(255) UNIQUE NOT NULL,
    text TEXT,
    has_attachment BOOLEAN DEFAULT FALSE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by VARCHAR(100),
    updated_by VARCHAR(100)
);

COMMENT ON TABLE notifications IS 'System notification templates';
COMMENT ON COLUMN notifications.task_name IS 'Unique identifier for the notification type (e.g., "cycle_report", "status_report")';


CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    name VARCHAR(255) NOT NULL,
    customer_id VARCHAR(255),  -- FK to customer collection (not in migration scope)
    sending_profile_id VARCHAR(255),  -- FK to sending_profile collection (not in migration scope)
    target_domain VARCHAR(255),
    
    start_date TIMESTAMP WITH TIME ZONE,
    cycle_start_date TIMESTAMP WITH TIME ZONE,
    targets_updated_time TIMESTAMP WITH TIME ZONE,
    
    admin_email VARCHAR(255),
    operator_email VARCHAR(255),
    targets_updated_username VARCHAR(255),
    
    status VARCHAR(50) CHECK (status IN ('created', 'queued', 'running', 'stopped')),
    processing BOOLEAN DEFAULT FALSE,
    archived BOOLEAN DEFAULT FALSE,
    
    continuous_subscription BOOLEAN DEFAULT FALSE,
    buffer_time_minutes INTEGER,
    cycle_length_minutes INTEGER,
    cooldown_minutes INTEGER,
    report_frequency_minutes INTEGER,
    
    landing_page_id VARCHAR(255),  -- FK to landing_page collection (not in migration scope)
    landing_domain VARCHAR(255),  -- The landing domain for simulated phishing URLs
    landing_page_url VARCHAR(255),  -- The URL to redirect to after landing domain
    
    phish_header VARCHAR(255),
    reporting_password VARCHAR(255),
    
    target_email_list JSONB DEFAULT '[]'::jsonb,  -- Array of {email, first_name, last_name, position}
    templates_selected TEXT[],  -- Array of template IDs
    next_templates TEXT[],  -- Array of template IDs for next cycle
    
    tasks JSONB DEFAULT '[]'::jsonb,  -- TODO: Consider moving to subscription_tasks table
    notification_history JSONB DEFAULT '[]'::jsonb,  -- TODO: Consider moving to subscription_notification_history table
    test_results JSONB DEFAULT '[]'::jsonb,  -- TODO: Consider moving to subscription_test_results table
    next_test_results JSONB DEFAULT '[]'::jsonb,  -- TODO: Consider moving to subscription_test_results table
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by VARCHAR(100),
    updated_by VARCHAR(100)
);

COMMENT ON TABLE subscriptions IS 'Phishing campaign subscriptions';
COMMENT ON COLUMN subscriptions.target_email_list IS 'JSONB array of target email objects: [{email, first_name, last_name, position}, ...]';
COMMENT ON COLUMN subscriptions.templates_selected IS 'Array of template IDs selected for current cycle';
COMMENT ON COLUMN subscriptions.next_templates IS 'Array of template IDs for next cycle';
COMMENT ON COLUMN subscriptions.tasks IS 'JSONB array of scheduled tasks - consider migrating to subscription_tasks table';
COMMENT ON COLUMN subscriptions.notification_history IS 'JSONB array of notification records - consider migrating to separate table';
COMMENT ON COLUMN subscriptions.test_results IS 'JSONB array of test results - consider migrating to separate table';


CREATE TABLE primary_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    subscription_id UUID UNIQUE NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    title VARCHAR(100),
    office_phone VARCHAR(50),
    mobile_phone VARCHAR(50),
    email VARCHAR(255),
    notes TEXT,
    active BOOLEAN DEFAULT TRUE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE primary_contacts IS 'Primary contact information for subscriptions (1:1 relationship)';


CREATE TABLE cycles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    
    start_date TIMESTAMP WITH TIME ZONE NOT NULL,
    end_date TIMESTAMP WITH TIME ZONE NOT NULL,
    send_by_date TIMESTAMP WITH TIME ZONE NOT NULL,
    
    active BOOLEAN DEFAULT TRUE,
    target_count INTEGER DEFAULT 0,
    dirty_stats BOOLEAN DEFAULT FALSE,
    
    phish_header VARCHAR(255),
    
    template_ids TEXT[],  -- Array of template IDs used in this cycle
    tasks JSONB DEFAULT '[]'::jsonb,  -- Array of task objects (simpler than subscription tasks, read-only)
    manual_reports JSONB DEFAULT '[]'::jsonb,  -- Array of {email, report_date}
    
    stats JSONB,  -- Cycle statistics
    nonhuman_stats JSONB,  -- Non-human interaction statistics
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by VARCHAR(100),
    updated_by VARCHAR(100)
);

COMMENT ON TABLE cycles IS 'Phishing campaign cycles - each represents one execution of a subscription';
COMMENT ON COLUMN cycles.template_ids IS 'Array of template IDs used in this cycle';
COMMENT ON COLUMN cycles.tasks IS 'JSONB array of task objects (copied from subscription at cycle creation, read-only)';
COMMENT ON COLUMN cycles.manual_reports IS 'JSONB array of manual report records: [{email, report_date}, ...]';
COMMENT ON COLUMN cycles.dirty_stats IS 'Flag indicating statistics need recalculation';
COMMENT ON COLUMN cycles.stats IS 'JSONB object containing cycle statistics';
COMMENT ON COLUMN cycles.nonhuman_stats IS 'JSONB object containing non-human interaction statistics';


CREATE TABLE targets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    cycle_id UUID NOT NULL REFERENCES cycles(id) ON DELETE CASCADE,
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    template_id UUID NOT NULL REFERENCES templates(id) ON DELETE RESTRICT,
    
    email VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    position VARCHAR(100),
    
    deception_level VARCHAR(20) CHECK (deception_level IN ('low', 'moderate', 'high')),
    deception_level_int INTEGER CHECK (deception_level_int BETWEEN 1 AND 6),
    
    send_date TIMESTAMP WITH TIME ZONE NOT NULL,
    sent BOOLEAN DEFAULT FALSE,
    sent_date TIMESTAMP WITH TIME ZONE,
    error TEXT,
    
    timeline JSONB DEFAULT '[]'::jsonb,  -- Array of {time, message, details: {user_agent, ip, asn_org, city, country}}
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE targets IS 'Individual target recipients in a cycle';
COMMENT ON COLUMN targets.timeline IS 'JSONB array of interaction events - consider migrating to target_timeline_events table for analytics';
COMMENT ON COLUMN targets.deception_level IS 'Human-readable deception level (low/moderate/high)';
COMMENT ON COLUMN targets.deception_level_int IS 'Numeric deception score (1-6)';


CREATE TABLE subscription_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    task_uuid UUID NOT NULL UNIQUE,
    task_type VARCHAR(50) NOT NULL CHECK (task_type IN (
        'start_subscription_email',
        'status_report',
        'cycle_report',
        'yearly_report',
        'thirty_day_reminder',
        'fifteen_day_reminder',
        'five_day_reminder',
        'safelisting_reminder',
        'end_cycle',
        'start_next_cycle'
    )),
    scheduled_date TIMESTAMP WITH TIME ZONE NOT NULL,
    executed BOOLEAN DEFAULT FALSE,
    executed_date TIMESTAMP WITH TIME ZONE,
    error TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE subscription_tasks IS 'Scheduled tasks for subscriptions (normalized alternative to subscriptions.tasks JSONB)';

CREATE TABLE target_timeline_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_id UUID NOT NULL REFERENCES targets(id) ON DELETE CASCADE,
    event_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    message VARCHAR(20) NOT NULL CHECK (message IN ('opened', 'clicked')),
    user_agent TEXT,
    ip INET,
    asn_org VARCHAR(255),
    city VARCHAR(100),
    country VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE target_timeline_events IS 'Timeline of target interactions (normalized alternative to targets.timeline JSONB)';

CREATE TABLE subscription_notification_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    message_type VARCHAR(100) NOT NULL,
    sent_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    email_to TEXT[] NOT NULL,
    email_from VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE subscription_notification_history IS 'History of notifications sent (normalized alternative to subscriptions.notification_history JSONB)';

CREATE TABLE subscription_test_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    test_uuid UUID NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL,
    template_id UUID REFERENCES templates(id),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    sent BOOLEAN DEFAULT FALSE,
    sent_date TIMESTAMP WITH TIME ZONE,
    opened BOOLEAN DEFAULT FALSE,
    clicked BOOLEAN DEFAULT FALSE,
    error TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE subscription_test_results IS 'Test email results (normalized alternative to subscriptions.test_results JSONB)';

CREATE TABLE test_timeline_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    test_result_id UUID NOT NULL REFERENCES subscription_test_results(id) ON DELETE CASCADE,
    event_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    message VARCHAR(20) NOT NULL CHECK (message IN ('opened', 'clicked')),
    user_agent TEXT,
    ip INET,
    asn_org VARCHAR(255),
    city VARCHAR(100),
    country VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE test_timeline_events IS 'Timeline of test email interactions';


CREATE TABLE id_migration_mapping (
    collection_name VARCHAR(50) NOT NULL,
    mongodb_id VARCHAR(24) NOT NULL,
    postgres_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (collection_name, mongodb_id)
);

CREATE INDEX idx_id_migration_postgres ON id_migration_mapping(collection_name, postgres_id);

COMMENT ON TABLE id_migration_mapping IS 'Temporary table for mapping MongoDB ObjectIDs to PostgreSQL UUIDs during migration';


CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_templates_updated_at BEFORE UPDATE ON templates
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_notifications_updated_at BEFORE UPDATE ON notifications
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_subscriptions_updated_at BEFORE UPDATE ON subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_primary_contacts_updated_at BEFORE UPDATE ON primary_contacts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_cycles_updated_at BEFORE UPDATE ON cycles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_targets_updated_at BEFORE UPDATE ON targets
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_subscription_tasks_updated_at BEFORE UPDATE ON subscription_tasks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_subscription_test_results_updated_at BEFORE UPDATE ON subscription_test_results
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


--
--
--
--
--
