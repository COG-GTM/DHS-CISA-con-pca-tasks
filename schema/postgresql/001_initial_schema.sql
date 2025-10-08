
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    legacy_objectid VARCHAR(24) UNIQUE,
    
    name VARCHAR(255) NOT NULL,
    customer_id VARCHAR(255),
    sending_profile_id VARCHAR(255),
    target_domain VARCHAR(255),
    customer VARCHAR(255),
    start_date TIMESTAMP WITH TIME ZONE,
    
    admin_email VARCHAR(255),
    operator_email VARCHAR(255),
    
    primary_contact_first_name VARCHAR(100),
    primary_contact_last_name VARCHAR(100),
    primary_contact_title VARCHAR(100),
    primary_contact_office_phone VARCHAR(50),
    primary_contact_mobile_phone VARCHAR(50),
    primary_contact_email VARCHAR(255),
    primary_contact_notes TEXT,
    primary_contact_active BOOLEAN DEFAULT TRUE,
    
    status VARCHAR(50),
    cycle_start_date VARCHAR(50),
    continuous_subscription BOOLEAN DEFAULT FALSE,
    
    buffer_time_minutes INTEGER,
    cycle_length_minutes INTEGER,
    cooldown_minutes INTEGER,
    report_frequency_minutes INTEGER,
    
    target_email_list JSONB,      -- Array of TargetEmail objects
    templates_selected JSONB,     -- Array of template IDs/names
    next_templates JSONB,          -- Array of upcoming template IDs (was missing from original proposal)
    
    processing BOOLEAN DEFAULT FALSE,
    archived BOOLEAN DEFAULT FALSE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE subscriptions IS 'Phishing campaign subscriptions - migrated from MongoDB subscription collection';
COMMENT ON COLUMN subscriptions.legacy_objectid IS 'Original MongoDB ObjectID for backward compatibility';
COMMENT ON COLUMN subscriptions.target_email_list IS 'JSONB array of target email objects: {email, first_name, last_name, position}';
COMMENT ON COLUMN subscriptions.templates_selected IS 'JSONB array of selected template identifiers';
COMMENT ON COLUMN subscriptions.next_templates IS 'JSONB array of next scheduled template identifiers';


CREATE TABLE subscription_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    
    task_uuid VARCHAR(255) UNIQUE NOT NULL,
    task_type VARCHAR(100) NOT NULL,
    
    scheduled_date TIMESTAMP WITH TIME ZONE NOT NULL,
    executed BOOLEAN DEFAULT FALSE,
    executed_date TIMESTAMP WITH TIME ZONE,
    
    error TEXT,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE subscription_tasks IS 'Individual scheduled tasks for subscriptions - normalized from MongoDB embedded array';
COMMENT ON COLUMN subscription_tasks.task_uuid IS 'Unique identifier for task execution tracking';


CREATE TABLE cycles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    legacy_objectid VARCHAR(24) UNIQUE,
    
    subscription_id UUID NOT NULL REFERENCES subscriptions(id),
    
    template_ids JSONB,
    
    start_date TIMESTAMP WITH TIME ZONE NOT NULL,
    end_date TIMESTAMP WITH TIME ZONE NOT NULL,
    send_by_date TIMESTAMP WITH TIME ZONE NOT NULL,
    
    active BOOLEAN DEFAULT TRUE,
    target_count INTEGER DEFAULT 0,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE cycles IS 'Phishing campaign cycles - migrated from MongoDB cycle collection';
COMMENT ON COLUMN cycles.legacy_objectid IS 'Original MongoDB ObjectID for backward compatibility';
COMMENT ON COLUMN cycles.template_ids IS 'JSONB array of template UUIDs used in this cycle';


CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    legacy_objectid VARCHAR(24) UNIQUE,
    
    name VARCHAR(255) NOT NULL,
    task_name VARCHAR(255) UNIQUE NOT NULL,
    
    subject VARCHAR(500),
    html TEXT,
    text TEXT,
    
    has_attachment BOOLEAN DEFAULT FALSE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE notifications IS 'Email notification templates - migrated from MongoDB notification collection';
COMMENT ON COLUMN notifications.task_name IS 'Unique task type identifier (e.g., "cycle_report", "monthly_report")';


CREATE TABLE templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    legacy_objectid VARCHAR(24) UNIQUE,
    
    name VARCHAR(255) UNIQUE NOT NULL,
    
    subject VARCHAR(500),
    html TEXT,
    text TEXT,
    
    retired BOOLEAN DEFAULT FALSE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE templates IS 'Phishing email templates - migrated from MongoDB template collection';
COMMENT ON COLUMN templates.retired IS 'Templates marked as retired are excluded from active use';


CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_subscriptions_updated_at BEFORE UPDATE ON subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_subscription_tasks_updated_at BEFORE UPDATE ON subscription_tasks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_cycles_updated_at BEFORE UPDATE ON cycles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_notifications_updated_at BEFORE UPDATE ON notifications
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_templates_updated_at BEFORE UPDATE ON templates
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


ALTER TABLE cycles ADD CONSTRAINT cycles_has_id CHECK (
    id IS NOT NULL OR legacy_objectid IS NOT NULL
);

ALTER TABLE subscriptions ADD CONSTRAINT subscriptions_has_id CHECK (
    id IS NOT NULL OR legacy_objectid IS NOT NULL
);

ALTER TABLE notifications ADD CONSTRAINT notifications_has_id CHECK (
    id IS NOT NULL OR legacy_objectid IS NOT NULL
);

ALTER TABLE templates ADD CONSTRAINT templates_has_id CHECK (
    id IS NOT NULL OR legacy_objectid IS NOT NULL
);

ALTER TABLE cycles ADD CONSTRAINT cycles_valid_legacy_id CHECK (
    legacy_objectid IS NULL OR 
    (length(legacy_objectid) = 24 AND legacy_objectid ~ '^[0-9a-fA-F]{24}$')
);

ALTER TABLE subscriptions ADD CONSTRAINT subscriptions_valid_legacy_id CHECK (
    legacy_objectid IS NULL OR 
    (length(legacy_objectid) = 24 AND legacy_objectid ~ '^[0-9a-fA-F]{24}$')
);

ALTER TABLE notifications ADD CONSTRAINT notifications_valid_legacy_id CHECK (
    legacy_objectid IS NULL OR 
    (length(legacy_objectid) = 24 AND legacy_objectid ~ '^[0-9a-fA-F]{24}$')
);

ALTER TABLE templates ADD CONSTRAINT templates_valid_legacy_id CHECK (
    legacy_objectid IS NULL OR 
    (length(legacy_objectid) = 24 AND legacy_objectid ~ '^[0-9a-fA-F]{24}$')
);

ALTER TABLE cycles ADD CONSTRAINT cycles_valid_dates CHECK (
    start_date <= end_date AND start_date <= send_by_date
);


--
--
--
--
--
--


--
--
