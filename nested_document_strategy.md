# Nested Document Migration Strategy

**Ticket:** MBA-322 - Phase 1 Database Schema Design for PostgreSQL Migration  
**Repository:** COG-GTM/DHS-CISA-con-pca-tasks  
**Analysis Date:** October 8, 2025  
**Analyst:** Devin AI

---

## Executive Summary

This document analyzes MongoDB's nested document structures and provides recommendations for their migration to PostgreSQL, evaluating the tradeoffs between JSONB storage and normalized relational tables.

---

## Nested Structures in con-pca-tasks

### Overview

Three nested document structures exist in the MongoDB schema:

1. **SubscriptionTasks** - Array of task execution records
2. **TargetEmail** - Array of email recipients with contact details
3. **PrimaryContact** - Single embedded contact document

---

## 1. SubscriptionTasks Structure

### Current MongoDB Structure

**Location:** `database/collections/subscriptions.go:30-37`

```go
type SubscriptionTasks struct {
    TaskUUID      string    `bson:"task_uuid"`
    TaskType      string    `bson:"task_type"`
    ScheduledDate time.Time `bson:"scheduled_date"`
    Executed      bool      `bson:"executed"`
    ExecutedDate  time.Time `bson:"executed_date"`
    Error         string    `bson:"error"`
}

// Embedded in Subscription as:
Tasks []SubscriptionTasks `bson:"tasks"`
```

### Usage Analysis

**Current Usage in con-pca-tasks:**
- ❌ No read operations on tasks array
- ❌ No filtering or querying individual tasks
- ❌ No updates to task status visible in this repository

**Likely Usage in con-pca-api (requires verification):**
- ⚠️ Probable: Add new tasks to array when scheduled
- ⚠️ Probable: Update task status when executed
- ⚠️ Probable: Record execution errors
- ⚠️ Unknown: Query tasks by status or date
- ⚠️ Unknown: Individual task updates vs full array replacement

### Migration Options

#### Option A: JSONB Array (Current MBA-322 Proposal)

**Schema:**
```sql
CREATE TABLE subscriptions (
    ...
    tasks JSONB,
    ...
);
```

**Example Data:**
```json
[
  {
    "task_uuid": "123e4567-e89b-12d3-a456-426614174000",
    "task_type": "cycle_report",
    "scheduled_date": "2025-10-08T10:00:00Z",
    "executed": true,
    "executed_date": "2025-10-08T10:05:00Z",
    "error": ""
  }
]
```

**Advantages:**
- ✅ Schema matches existing MongoDB structure exactly
- ✅ No JOIN operations needed when fetching subscription with tasks
- ✅ Atomic updates - replace entire array in single UPDATE
- ✅ Simple migration - direct JSON export/import
- ✅ Good for read-heavy operations

**Disadvantages:**
- ❌ Cannot efficiently query individual tasks (no indexes on JSONB array elements)
- ❌ Cannot use foreign keys to reference tasks
- ❌ Difficult to update single task status without reading entire array
- ❌ Cannot enforce constraints on individual tasks (e.g., task_uuid uniqueness)
- ❌ Poor performance for queries like "find all executed tasks"

**Query Examples:**
```sql
-- Find subscriptions with pending tasks (complex and slow)
SELECT * FROM subscriptions 
WHERE EXISTS (
    SELECT 1 FROM jsonb_array_elements(tasks) AS task
    WHERE (task->>'executed')::boolean = false
);

-- Update single task status (requires reading entire array)
UPDATE subscriptions 
SET tasks = jsonb_set(
    tasks, 
    '{0,executed}', 
    'true'
) 
WHERE id = '...';
```

#### Option B: Normalized Table (Recommended)

**Schema:**
```sql
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- ... other fields ...
);

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

CREATE INDEX idx_subscription_tasks_subscription_id ON subscription_tasks(subscription_id);
CREATE INDEX idx_subscription_tasks_executed ON subscription_tasks(executed);
CREATE INDEX idx_subscription_tasks_scheduled_date ON subscription_tasks(scheduled_date);
CREATE INDEX idx_subscription_tasks_task_uuid ON subscription_tasks(task_uuid);
```

**Advantages:**
- ✅ Efficient queries on individual tasks
- ✅ Indexed lookups by task_uuid, status, or date
- ✅ Update single task without touching subscription
- ✅ Foreign key integrity
- ✅ Unique constraint on task_uuid
- ✅ Easy to query "all tasks" across subscriptions
- ✅ Standard SQL JOIN patterns

**Disadvantages:**
- ❌ Requires JOIN to fetch subscription with tasks
- ❌ More complex migration (array → rows)
- ❌ Additional table to manage

**Query Examples:**
```sql
-- Find subscriptions with pending tasks (fast with index)
SELECT DISTINCT s.* 
FROM subscriptions s
JOIN subscription_tasks st ON st.subscription_id = s.id
WHERE st.executed = false;

-- Update single task status (direct update)
UPDATE subscription_tasks 
SET executed = true, 
    executed_date = NOW() 
WHERE task_uuid = '...';

-- Get subscription with tasks (standard JOIN)
SELECT s.*, 
       json_agg(st.*) as tasks
FROM subscriptions s
LEFT JOIN subscription_tasks st ON st.subscription_id = s.id
WHERE s.id = '...'
GROUP BY s.id;
```

### Recommendation: **Option B - Normalized Table**

**Reasoning:**
1. **Task Execution Pattern:** Tasks are likely updated individually as they execute
2. **Query Requirements:** Need to query pending/executed tasks efficiently
3. **Data Integrity:** task_uuid should be unique and enforceable
4. **Scalability:** As task count grows, normalized approach scales better
5. **Relational Nature:** Tasks have clear relationship to subscriptions

**Confidence:** Medium 🟡 (High confidence in technical benefits, but requires con-pca-api validation)

---

## 2. TargetEmail Structure

### Current MongoDB Structure

**Location:** `database/collections/subscriptions.go:12-17`

```go
type TargetEmail struct {
    Email     string `bson:"email"`
    FirstName string `bson:"first_name"`
    LastName  string `bson:"last_name"`
    Position  string `bson:"position"`
}

// Embedded in Subscription as:
TargetEmailList []TargetEmail `bson:"target_email_list"`
```

### Usage Analysis

**Current Usage in con-pca-tasks:**
- ❌ No direct read operations on target_email_list
- ❌ No filtering or querying individual targets
- ✅ Implicitly used: Email sent to targets via subscription

**Likely Usage in con-pca-api (requires verification):**
- ⚠️ Probable: Set target list when creating subscription
- ⚠️ Probable: Update target list when subscription modified
- ⚠️ Unknown: Add/remove individual targets
- ⚠️ Unknown: Query targets across subscriptions
- ⚠️ Unknown: Track target-specific metrics

### Migration Options

#### Option A: JSONB Array (Current MBA-322 Proposal)

**Schema:**
```sql
CREATE TABLE subscriptions (
    ...
    target_email_list JSONB,
    ...
);
```

**Advantages:**
- ✅ Simple structure for static lists
- ✅ No JOIN needed when fetching subscription
- ✅ Matches current MongoDB structure
- ✅ Good if targets rarely change independently

**Disadvantages:**
- ❌ Cannot query targets across subscriptions
- ❌ Cannot enforce email format validation
- ❌ Difficult to update single target
- ❌ No referential integrity

#### Option B: Normalized Table

**Schema:**
```sql
CREATE TABLE target_emails (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    position VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_target_emails_subscription_id ON target_emails(subscription_id);
CREATE INDEX idx_target_emails_email ON target_emails(email);
```

**Advantages:**
- ✅ Query targets across subscriptions
- ✅ Email validation at database level
- ✅ Individual target updates
- ✅ Track target history

**Disadvantages:**
- ❌ JOIN required for subscription + targets
- ❌ More complex queries

#### Option C: Hybrid - Normalized with Email Lookup Table

**Schema:**
```sql
-- Separate email contacts (reusable across subscriptions)
CREATE TABLE email_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    position VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Junction table
CREATE TABLE subscription_targets (
    subscription_id UUID REFERENCES subscriptions(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES email_contacts(id) ON DELETE CASCADE,
    added_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (subscription_id, contact_id)
);
```

**Advantages:**
- ✅ Reusable contact information
- ✅ No duplicate email records
- ✅ Many-to-many relationship support

**Disadvantages:**
- ❌ Additional complexity
- ❌ May be over-engineered for current needs

### Recommendation: **Option A - JSONB Array**

**Reasoning:**
1. **Static Nature:** Target lists likely set once per subscription and rarely modified
2. **Read Pattern:** Always fetched with subscription data (no independent queries)
3. **Simple Structure:** Only 4 fields, minimal complexity
4. **No Relationships:** Targets don't need to reference other entities
5. **Performance:** Avoiding JOIN for frequently-accessed data

**Confidence:** Medium 🟡 (Reasonable assumption but needs con-pca-api validation)

**Caveat:** If con-pca-api shows targets are frequently updated individually or queried across subscriptions, switch to Option B.

---

## 3. PrimaryContact Structure

### Current MongoDB Structure

**Location:** `database/collections/subscriptions.go:19-28`

```go
type PrimaryContact struct {
    FirstName   string `bson:"first_name"`
    LastName    string `bson:"last_name"`
    Title       string `bson:"title"`
    OfficePhone string `bson:"office_phone"`
    MobilePhone string `bson:"mobile_phone"`
    Email       string `bson:"email"`
    Notes       string `bson:"notes"`
    Active      bool   `bson:"active"`
}

// Embedded in Subscription as:
PrimaryContact PrimaryContact `bson:"primary_contact"`
```

### Usage Analysis

**Current Usage in con-pca-tasks:**
- ✅ `notifications/manager.go:63` - Reads FirstName and LastName for email template
- ✅ `notifications/manager.go:76` - Reads Email for email recipient

**Critical Access Pattern:**
```go
s, err := collections.GetSubscription(c.SubscriptionId)
firstName := s.PrimaryContact.FirstName
lastName := s.PrimaryContact.LastName
email := s.PrimaryContact.Email
```

**Likely Usage in con-pca-api (requires verification):**
- ⚠️ Probable: Set contact when creating subscription
- ⚠️ Probable: Update contact independently of subscription
- ⚠️ Unknown: Query by contact email or name
- ⚠️ Unknown: One contact per subscription always, or historical tracking?

### Migration Options

#### Option A: Separate Table (Current MBA-322 Proposal)

**Schema:**
```sql
CREATE TABLE primary_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
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

**Advantages:**
- ✅ Independent updates without touching subscription
- ✅ Can query by contact email
- ✅ Foreign key integrity
- ✅ Supports multiple contacts per subscription (if needed later)
- ✅ Clean separation of concerns

**Disadvantages:**
- ❌ Requires JOIN for every subscription read
- ❌ Extra table to manage
- ❌ Critical path adds JOIN overhead

#### Option B: Inline Columns in Subscriptions Table

**Schema:**
```sql
CREATE TABLE subscriptions (
    ...
    primary_contact_first_name VARCHAR(100),
    primary_contact_last_name VARCHAR(100),
    primary_contact_title VARCHAR(100),
    primary_contact_office_phone VARCHAR(50),
    primary_contact_mobile_phone VARCHAR(50),
    primary_contact_email VARCHAR(255),
    primary_contact_notes TEXT,
    primary_contact_active BOOLEAN DEFAULT TRUE,
    ...
);
```

**Advantages:**
- ✅ No JOIN required
- ✅ Atomic updates with subscription
- ✅ Simpler queries
- ✅ Matches read pattern (always fetched together)

**Disadvantages:**
- ❌ Cannot enforce email uniqueness across contacts
- ❌ Prefix naming convention clutters table
- ❌ Cannot extend to multiple contacts
- ❌ Updates entire subscription row for contact changes

#### Option C: JSONB Object

**Schema:**
```sql
CREATE TABLE subscriptions (
    ...
    primary_contact JSONB,
    ...
);
```

**Advantages:**
- ✅ Matches MongoDB structure exactly
- ✅ No JOIN required
- ✅ Easy migration

**Disadvantages:**
- ❌ Cannot index contact fields efficiently
- ❌ No validation on email format
- ❌ Difficult to query by contact attributes

### Recommendation: **Option B - Inline Columns**

**Reasoning:**
1. **Critical Read Path:** Contact is ALWAYS read with subscription in notifications workflow
2. **One-to-One Relationship:** Each subscription has exactly one primary contact
3. **Atomic Updates:** Contact and subscription likely updated together
4. **Performance:** No JOIN overhead on critical path
5. **Simple Structure:** Only 8 fields, manageable inline

**Alternative:** If con-pca-api shows independent contact updates are common, use Option A.

**Confidence:** Medium-High 🟡 (Strong technical reasoning but needs usage validation)

---

## Performance Analysis

### JSONB Performance Characteristics

**Strengths:**
- Fast for reading entire documents (no JOINs)
- Good for semi-structured or variable data
- Supports GIN indexes for specific queries
- Atomic updates of entire structure

**Weaknesses:**
- Cannot index array elements efficiently
- Poor for queries filtering on nested attributes
- JSONB operations slower than native SQL
- Larger storage overhead

### Normalized Table Performance Characteristics

**Strengths:**
- Fast indexed lookups on any column
- Efficient for queries across related entities
- Better for write-heavy workloads
- Standard SQL optimization techniques apply

**Weaknesses:**
- JOIN overhead on reads
- More complex queries
- Additional I/O for related tables

---

## Migration Complexity Assessment

| Structure | JSONB Complexity | Normalized Complexity | Recommended |
|-----------|------------------|----------------------|-------------|
| SubscriptionTasks | Low | Medium | **Normalized** |
| TargetEmail | Low | Medium | **JSONB** |
| PrimaryContact | Low | Low | **Inline Columns** |

---

## Final Recommendations Summary

### 1. SubscriptionTasks → subscription_tasks table (Normalized)
- **Reason:** Individual task updates, query requirements, data integrity
- **Confidence:** Medium 🟡
- **Validation Needed:** con-pca-api write patterns

### 2. TargetEmail → target_email_list JSONB
- **Reason:** Static lists, always fetched with subscription, simple structure
- **Confidence:** Medium 🟡
- **Validation Needed:** con-pca-api update frequency

### 3. PrimaryContact → Inline columns in subscriptions table
- **Reason:** Always fetched together, one-to-one, critical read path
- **Confidence:** Medium-High 🟡
- **Validation Needed:** Independent update patterns

---

## Next Steps

1. **Obtain con-pca-api repository access**
2. **Analyze write patterns** for each nested structure
3. **Validate update frequencies** (individual vs bulk)
4. **Test performance** with realistic data volumes
5. **Update recommendations** based on actual usage patterns

---

## Schema Updates Required

The MBA-322 proposed schema requires the following modifications:

### Remove from Proposal:
- `primary_contacts` table (move to inline columns)

### Add to Proposal:
- `subscription_tasks` table with proper indexes

### Keep as Proposed:
- `target_email_list` as JSONB in subscriptions table

---

**Document Version:** 1.0  
**Status:** PRELIMINARY - Requires con-pca-api Validation  
**Next Review:** After write pattern analysis
