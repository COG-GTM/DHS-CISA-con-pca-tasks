# Nested Document Migration Strategy

**Ticket:** MBA-322 - Phase 1 Database Schema Design  
**Analysis Date:** October 8, 2025  
**Related Document:** write_operations_analysis.md

## Executive Summary

This document analyzes nested document structures in the MongoDB collections and provides specific recommendations for their PostgreSQL implementation. The analysis focuses on query patterns, update frequency, and performance implications to determine whether each nested structure should use JSONB, normalized tables, or a hybrid approach.

### Recommendation Summary

| Structure | MongoDB Location | Recommendation | Rationale |
|-----------|------------------|----------------|-----------|
| SubscriptionTasks | subscriptions.tasks[] | **Separate Table** | Frequent positional updates, query filtering needed |
| TargetEmail | subscriptions.target_email_list[] | **JSONB Array** | Read-heavy, simple structure, replaced wholesale |
| TargetTimeline | targets.timeline[] | **Separate Table** | Frequent appends, analytics queries, geo data |
| NotificationHistory | subscriptions.notification_history[] | **Separate Table** | Audit trail, frequent appends, potential analytics |
| PrimaryContact | subscriptions.primary_contact{} | **JSONB Object** | Single embedded object, simple structure |
| TemplateIndicators | templates.indicators{} | **JSONB Object** | Complex nested object, read-only after creation |
| CycleTasks | cycles.tasks[] | **JSONB Array** | Simple task list, read-heavy |
| ManualReports | cycles.manual_reports[] | **JSONB Array** | Simple structure, infrequent updates |
| TestResults | subscriptions.test_results[] | **Separate Table** | Complex structure, positional updates |

## 1. SubscriptionTasks Analysis

### 1.1 Current Structure

**Location:** `subscriptions.tasks` array  
**Schema:** (subscription_schema.py:39-62)

```python
class SubscriptionTasksSchema(Schema):
    task_uuid = fields.Str()
    task_type = fields.Str(validate=validate.OneOf([
        "start_subscription_email",
        "status_report",
        "cycle_report",
        "yearly_report",
        "thirty_day_reminder",
        "fifteen_day_reminder",
        "five_day_reminder",
        "safelisting_reminder",
        "end_cycle",
        "start_next_cycle",
    ]))
    scheduled_date = DateTimeField()
    executed = fields.Bool(load_default=False)
    executed_date = DateTimeField(required=False)
    error = fields.Str(required=False, allow_none=True)
```

### 1.2 Write Patterns

```python
# 1. Initial creation - entire array created at once
tasks = get_initial_tasks(subscription, cycle)
subscription_manager.update(
    document_id=subscription_id, 
    data={"tasks": tasks}
)

# 2. Positional updates - update specific task by task_uuid
subscription_manager.update_in_list(
    document_id=subscription_id,
    field="tasks.$",
    data=task,
    params={"tasks.task_uuid": task["task_uuid"]}
)

# 3. Adding new tasks
subscription_manager.add_to_list(
    document_id=subscription["_id"],
    field="tasks",
    data=task
)
```

**Update Frequency:** High - tasks are updated as they execute (every few minutes during active subscription)

### 1.3 Query Patterns

```python
# 1. Find pending tasks (tasks.py:23-48)
subscriptions = subscription_manager.all(
    params={
        "status": "running",
        "tasks": {
            "$elemMatch": {
                "executed": False,
                "scheduled_date": {"$lte": datetime.utcnow()}
            }
        }
    }
)

# 2. Access specific task within subscription
# MongoDB positional operator for updates
```

**Query Frequency:** Very High - checked every TASK_MINUTES (default: 1 minute)

### 1.4 Recommendation: **Separate Normalized Table**

**Rationale:**
1. **Frequent positional updates** - Each task execution requires finding and updating specific array element
2. **Complex queries** - Need to filter subscriptions by task properties ($elemMatch)
3. **Indexing** - Can't efficiently index into JSONB arrays for executed/scheduled_date
4. **Audit trail** - Individual task records enable better tracking
5. **Performance** - Updating single row vs rewriting entire JSONB array

**Proposed Schema:**

```sql
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

CREATE INDEX idx_subscription_tasks_subscription_id ON subscription_tasks(subscription_id);
CREATE INDEX idx_subscription_tasks_pending ON subscription_tasks(executed, scheduled_date) WHERE executed = FALSE;
CREATE INDEX idx_subscription_tasks_uuid ON subscription_tasks(task_uuid);
```

**Migration Complexity:** Medium  
**Performance Impact:** Significant improvement for task processing

## 2. TargetEmail Analysis

### 2.1 Current Structure

**Location:** `subscriptions.target_email_list` array  
**Schema:** (subscription_schema.py:22-28)

```python
class SubscriptionTargetSchema(Schema):
    email = fields.Email(required=True)
    first_name = fields.Str(required=False, allow_none=True)
    last_name = fields.Str(required=False, allow_none=True)
    position = fields.Str(required=False, allow_none=True)
```

### 2.2 Write Patterns

```python
# 1. Set entire list at once (most common)
subscription_manager.update(
    document_id=subscription_id,
    data={"target_email_list": new_list}
)

# 2. Remove failed email (rare)
subscription_manager.delete_from_list(
    document_id=subscription["_id"],
    field="target_email_list",
    data=target
)
```

**Update Frequency:** Low - typically set once during subscription creation, rarely modified

### 2.3 Query Patterns

```python
# 1. Read entire list
subscription = subscription_manager.get(document_id=subscription_id)
target_count = len(subscription["target_email_list"])

# 2. Iterate over list during cycle start
for target in subscription["target_email_list"]:
    # Create target records
```

**Query Frequency:** Low - read during subscription view and cycle creation

### 2.4 Recommendation: **JSONB Array**

**Rationale:**
1. **Simple structure** - Only 4 fields, all scalar types
2. **Read-heavy** - Rarely updated after initial creation
3. **Wholesale replacement** - When updated, entire list is replaced
4. **No complex queries** - Never queried independently, always accessed via subscription
5. **Storage efficiency** - Keeping with subscription reduces joins

**Proposed Schema:**

```sql
-- In subscriptions table
target_email_list JSONB DEFAULT '[]'::jsonb,

-- Example data structure:
-- [
--   {"email": "user@example.com", "first_name": "John", "last_name": "Doe", "position": "Manager"},
--   {"email": "user2@example.com", "first_name": "Jane", "last_name": "Smith", "position": null}
-- ]
```

**Alternative Consideration:** If needing to query by email or validate uniqueness, create a separate table. However, current usage patterns don't require this.

**Migration Complexity:** Low  
**Performance Impact:** Neutral to slight improvement (fewer joins)

## 3. TargetTimeline Analysis

### 3.1 Current Structure

**Location:** `targets.timeline` array  
**Schema:** (target_schema.py:20-25)

```python
class TargetTimelineSchema(Schema):
    time = DateTimeField()
    message = fields.Str(validate=validate.OneOf(["opened", "clicked"]))
    details = fields.Nested(TimelineDetailsSchema)

class TimelineDetailsSchema(Schema):
    user_agent = fields.Str(required=False, allow_none=True)
    ip = fields.Str(required=False, allow_none=True)
    asn_org = fields.Str(required=False, allow_none=True)
    city = fields.Str(required=False, allow_none=True)
    country = fields.Str(required=False, allow_none=True)
```

### 3.2 Write Patterns

```python
# Frequent appends - add timeline event
target_manager.add_to_list(
    document_id=target["_id"],
    field="timeline",
    data={
        "time": datetime.utcnow(),
        "message": "clicked",
        "details": {
            "user_agent": request.headers.get("User-Agent"),
            "ip": request.remote_addr,
            "asn_org": geo_data.get("asn_org"),
            "city": geo_data.get("city"),
            "country": geo_data.get("country"),
        }
    }
)

# Protection: Limit to 10 events
if len(click_events) < 10:
    target_manager.add_to_list(...)
```

**Update Frequency:** Very High - updated on every email open/click event

### 3.3 Query Patterns

```python
# 1. Read timeline for reporting (stats.py)
target = target_manager.get(document_id=target_id)
timeline_events = target.get("timeline", [])

# 2. Count specific event types
click_events = list(filter(lambda x: x["message"] == "clicked", target.get("timeline", [])))

# 3. Potential analytics on geo data
# - Which cities have highest click rates?
# - Which ASNs are most susceptible?
```

**Query Frequency:** High - accessed for every report generation and stats calculation

### 3.4 Recommendation: **Separate Normalized Table**

**Rationale:**
1. **Frequent appends** - Timeline grows continuously, each append with JSONB rewrites entire array
2. **Analytics potential** - Geo data (city, country, asn_org) useful for aggregate queries
3. **Nested structure** - Details object adds complexity to JSONB queries
4. **Indexing** - Can index on time, message, ip, geo fields for analytics
5. **Audit trail** - Timeline events are immutable audit records
6. **Size** - Up to 10 events per target, thousands of targets = tens of thousands of timeline events

**Proposed Schema:**

```sql
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

CREATE INDEX idx_target_timeline_target_id ON target_timeline_events(target_id, event_time DESC);
CREATE INDEX idx_target_timeline_message ON target_timeline_events(message);
CREATE INDEX idx_target_timeline_geo ON target_timeline_events(country, city) WHERE country IS NOT NULL;
```

**Migration Complexity:** Low  
**Performance Impact:** Significant improvement for timeline appends and analytics

## 4. NotificationHistory Analysis

### 4.1 Current Structure

**Location:** `subscriptions.notification_history` array  
**Schema:** (subscription_schema.py:13-19)

```python
class SubscriptionNotificationSchema(Schema):
    message_type = fields.Str()
    sent = DateTimeField()
    email_to = fields.List(fields.Str())
    email_from = fields.Str()
```

### 4.2 Write Patterns

```python
# Append-only - add notification record
subscription_manager.add_to_list(
    document_id=self.subscription["_id"],
    field="notification_history",
    data={
        "message_type": "cycle_report",
        "sent": datetime.utcnow(),
        "email_to": ["admin@example.com", "operator@example.com"],
        "email_from": "noreply@example.com",
    }
)
```

**Update Frequency:** Medium - grows throughout subscription lifecycle (every report/notification)

### 4.3 Query Patterns

```python
# 1. View notification history
subscription = subscription_manager.get(document_id=subscription_id)
history = subscription.get("notification_history", [])

# 2. Potential analytics
# - How many notifications sent per subscription?
# - Which notification types most common?
```

**Query Frequency:** Low to Medium - viewed in subscription details, potential analytics

### 4.4 Recommendation: **Separate Normalized Table**

**Rationale:**
1. **Audit trail** - Important record of all communications
2. **Append-only** - Each notification adds to array, JSONB inefficient for frequent appends
3. **Array field** - email_to is array within array, complicates JSONB
4. **Analytics potential** - May want to query notification patterns
5. **Size** - Can grow large for long-running subscriptions
6. **Compliance** - Separate table enables easier audit queries

**Proposed Schema:**

```sql
CREATE TABLE subscription_notification_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    message_type VARCHAR(100) NOT NULL,
    sent_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    email_to TEXT[] NOT NULL,  -- PostgreSQL native array type
    email_from VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_notification_history_subscription_id ON subscription_notification_history(subscription_id, sent_at DESC);
CREATE INDEX idx_notification_history_message_type ON subscription_notification_history(message_type);
```

**Migration Complexity:** Low  
**Performance Impact:** Improvement for append operations

## 5. PrimaryContact Analysis

### 5.1 Current Structure

**Location:** `subscriptions.primary_contact` object (not array)  
**Schema:** (subscription_schema.py:90, customer_schema.py - CustomerContactSchema)

```python
# Embedded in subscription
primary_contact = fields.Nested(CustomerContactSchema)

class CustomerContactSchema(Schema):
    first_name = fields.Str()
    last_name = fields.Str()
    title = fields.Str()
    office_phone = fields.Str()
    mobile_phone = fields.Str()
    email = fields.Str()
    notes = fields.Str()
    active = fields.Bool()
```

### 5.2 Write Patterns

```python
# Set entire object during subscription creation/update
subscription_manager.update(
    document_id=subscription_id,
    data={"primary_contact": contact_data}
)
```

**Update Frequency:** Very Low - set once, rarely modified

### 5.3 Query Patterns

```python
# Simple read as part of subscription
subscription = subscription_manager.get(document_id=subscription_id)
contact = subscription.get("primary_contact", {})
```

**Query Frequency:** Low - read with subscription details

### 5.4 Recommendation: **JSONB Object OR Separate Table**

**Note:** The proposed schema already has a separate `primary_contacts` table, which is reasonable.

**Arguments for Separate Table:**
- Enables querying contacts independently
- Can have multiple contacts per subscription in future
- Better data normalization

**Arguments for JSONB:**
- Simple 1:1 relationship
- Always accessed with subscription
- Never queried independently

**Final Recommendation:** **Keep Separate Table** as proposed in MBA-322, with modification:

```sql
-- Modify proposed schema to support 1:1 relationship
CREATE TABLE primary_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID UNIQUE NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,  -- UNIQUE ensures 1:1
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

CREATE INDEX idx_primary_contacts_subscription_id ON primary_contacts(subscription_id);
CREATE INDEX idx_primary_contacts_email ON primary_contacts(email);
```

**Migration Complexity:** Low  
**Performance Impact:** Neutral (requires JOIN but infrequent)

## 6. TemplateIndicators Analysis

### 6.1 Current Structure

**Location:** `templates.indicators` nested object  
**Schema:** (template_schema.py:41-47)

```python
class TemplateIndicatorSchema(Schema):
    appearance = fields.Nested(TemplateAppearanceSchema)  # {grammar, link_domain, logo_graphics}
    sender = fields.Nested(TemplateSenderSchema)  # {external, internal, authoritative}
    relevancy = fields.Nested(TemplateRelevancySchema)  # {organization, public_news}
    behavior = fields.Nested(TemplateBehaviorSchema)  # {fear, duty_obligation, curiosity, greed}
```

### 6.2 Write Patterns

```python
# Set entire indicators object during template creation
template_manager.save({
    "name": "Template Name",
    "indicators": {
        "appearance": {"grammar": 1, "link_domain": 2, "logo_graphics": 3},
        "sender": {"external": 1, "internal": 2, "authoritative": 3},
        "relevancy": {"organization": 1, "public_news": 2},
        "behavior": {"fear": 1, "duty_obligation": 2, "curiosity": 3, "greed": 4}
    }
})
```

**Update Frequency:** Very Low - set during template creation, rarely changed

### 6.3 Query Patterns

```python
# Simple read as part of template
template = template_manager.get(document_id=template_id)
indicators = template.get("indicators", {})
```

**Query Frequency:** Low - read with template details

### 6.4 Recommendation: **JSONB Object**

**Rationale:**
1. **Complex nested structure** - 3 levels deep (indicators → category → values)
2. **Read-only after creation** - Set once, rarely modified
3. **No independent queries** - Always accessed with template
4. **Schema flexibility** - Indicators structure may evolve
5. **Simplicity** - Flattening to separate tables overly complex

**Proposed Schema:**

```sql
-- In templates table
indicators JSONB,

-- Example structure:
-- {
--   "appearance": {"grammar": 1, "link_domain": 2, "logo_graphics": 3},
--   "sender": {"external": 1, "internal": 2, "authoritative": 3},
--   "relevancy": {"organization": 1, "public_news": 2},
--   "behavior": {"fear": 1, "duty_obligation": 2, "curiosity": 3, "greed": 4}
-- }
```

**Migration Complexity:** Low  
**Performance Impact:** Neutral

## 7. CycleTasks and ManualReports Analysis

### 7.1 CycleTasks Structure

**Location:** `cycles.tasks` array  
**Schema:** Similar to SubscriptionTasks but stored on cycle

### 7.2 Recommendation: **JSONB Array**

**Rationale:**
- Unlike subscription tasks, cycle tasks are copied at cycle creation
- No positional updates needed (tasks reference subscription tasks)
- Read-only after cycle creation
- Simpler than subscription tasks pattern

```sql
-- In cycles table
tasks JSONB DEFAULT '[]'::jsonb,
```

### 7.3 ManualReports Structure

**Location:** `cycles.manual_reports` array  
**Schema:** (cycle_schema.py:11-15)

```python
class CycleManualReportsSchema(BaseSchema):
    email = fields.Str()
    report_date = DateTimeField()
```

### 7.4 Recommendation: **JSONB Array**

**Rationale:**
- Simple structure (2 fields)
- Infrequent updates
- Small arrays
- No complex queries

```sql
-- In cycles table
manual_reports JSONB DEFAULT '[]'::jsonb,
```

## 8. TestResults Analysis

### 8.1 Current Structure

**Location:** `subscriptions.test_results` and `subscriptions.next_test_results` arrays  
**Schema:** (subscription_schema.py:65-78)

```python
class SubscriptionTestSchema(Schema):
    test_uuid = fields.Str()
    email = fields.Str()
    template = fields.Nested(TemplateSchema)  # Nested template object!
    first_name = fields.Str()
    last_name = fields.Str()
    sent = fields.Bool()
    sent_date = DateTimeField()
    opened = fields.Bool()
    clicked = fields.Bool()
    timeline = fields.List(fields.Nested(TargetTimelineSchema))  # Nested array!
    error = fields.Str(required=False, allow_none=True)
```

### 8.2 Write Patterns

```python
# Positional updates - update specific test result
subscription_manager.update_in_list(
    document_id=subscription_id,
    field="test_results.$",
    data=contact,
    params={"test_results.test_uuid": contact["test_uuid"]}
)
```

### 8.3 Recommendation: **Separate Normalized Table**

**Rationale:**
1. **Complex nested structure** - Contains nested template object AND timeline array
2. **Positional updates** - Requires finding and updating specific array element
3. **Similar to targets** - Test results are essentially test targets
4. **Timeline** - Same timeline pattern as targets (should use same approach)

**Proposed Schema:**

```sql
CREATE TABLE subscription_test_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    test_uuid UUID NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL,
    template_id UUID REFERENCES templates(id),  -- FK instead of nested object
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

-- Test timeline uses same target_timeline_events pattern
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

CREATE INDEX idx_test_results_subscription_id ON subscription_test_results(subscription_id);
CREATE INDEX idx_test_results_uuid ON subscription_test_results(test_uuid);
```

## 9. Summary Matrix

| Nested Structure | Current Pattern | Recommended Approach | Primary Reason |
|------------------|-----------------|---------------------|----------------|
| subscriptions.tasks[] | Complex array | **Separate Table** | Frequent positional updates, complex queries |
| subscriptions.target_email_list[] | Simple array | **JSONB Array** | Read-heavy, wholesale replacement |
| subscriptions.notification_history[] | Append-only array | **Separate Table** | Audit trail, frequent appends |
| subscriptions.primary_contact{} | Single object | **Separate Table** (as proposed) | Normalization, already proposed |
| subscriptions.test_results[] | Complex array | **Separate Table** | Positional updates, nested complexity |
| subscriptions.next_test_results[] | Complex array | **Separate Table** | Same as test_results |
| targets.timeline[] | Append-only array | **Separate Table** | Analytics, frequent appends, geo indexing |
| templates.indicators{} | Nested object | **JSONB Object** | Read-only, complex nesting |
| cycles.tasks[] | Simple array | **JSONB Array** | Read-only, simple structure |
| cycles.manual_reports[] | Simple array | **JSONB Array** | Infrequent updates, simple structure |

## 10. Implementation Guidelines

### 10.1 JSONB Operations in Application Code

For JSONB arrays, the application will need to:

```python
# MongoDB: $push operation
db.update_one({"_id": id}, {"$push": {"array": item}})

# PostgreSQL equivalent:
# UPDATE table SET array = array || '[item]'::jsonb WHERE id = $1
# Or use jsonb_insert(), jsonb_set()

# MongoDB: $pull operation
db.update_one({"_id": id}, {"$pull": {"array": item}})

# PostgreSQL equivalent:
# UPDATE table SET array = array - 'item' WHERE id = $1
```

### 10.2 Normalized Table Benefits

- Proper foreign key constraints
- Individual row updates (no array rewrite)
- Efficient indexing
- Standard SQL queries
- Better for analytics

### 10.3 JSONB Benefits

- Document-like flexibility
- Fewer tables and joins
- Atomic updates of entire structure
- Schema evolution without ALTER TABLE

## 11. Performance Considerations

### 11.1 Measured Impact

Based on usage patterns:

**High-Frequency Operations (optimized with separate tables):**
- Task execution checks: Every 1 minute → subscription_tasks table
- Timeline appends: Every email open/click → target_timeline_events table
- Test result updates: During testing → test_results table

**Low-Frequency Operations (acceptable with JSONB):**
- Target email list updates: Rarely → JSONB array
- Template indicators: Set once → JSONB object

### 11.2 Index Strategy

**Separate Tables:**
- Full indexing capabilities
- Covering indexes for common queries
- Partial indexes for filtered queries

**JSONB:**
- GIN indexes for containment queries
- Expression indexes for specific paths
- Limited compared to normalized tables

## 12. Migration Path

### 12.1 Phase 1: Schema Creation
1. Create normalized tables for: subscription_tasks, target_timeline_events, notification_history, test_results
2. Add JSONB columns for: target_email_list, indicators, cycle tasks, manual_reports

### 12.2 Phase 2: Dual-Write
1. Write to both MongoDB and PostgreSQL
2. Normalize arrays for separate tables
3. Keep JSONB as-is for simple structures

### 12.3 Phase 3: Data Migration
1. Iterate through MongoDB documents
2. Extract array elements to separate table rows
3. Copy simple arrays to JSONB

### 12.4 Phase 4: Validation
1. Compare row counts between MongoDB arrays and PostgreSQL tables
2. Validate JSONB structure matches MongoDB

## Conclusion

The hybrid approach balances performance, maintainability, and migration complexity:

- **Separate tables** for frequently updated, complex, or queryable nested structures
- **JSONB** for simple, read-heavy, or rarely updated nested structures

This strategy leverages PostgreSQL's strengths while minimizing migration complexity and maintaining query performance.

---

**Prepared by:** Devin AI  
**Session:** https://app.devin.ai/sessions/df7340be39754e4088080fa2b29c0e41  
**Date:** October 8, 2025
