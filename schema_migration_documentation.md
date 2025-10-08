# Schema Migration Documentation - MongoDB to PostgreSQL

**Ticket:** MBA-322 - Phase 1 Database Schema Design for PostgreSQL Migration  
**Repository:** COG-GTM/DHS-CISA-con-pca-tasks  
**Analysis Date:** October 8, 2025  
**Analyst:** Devin AI

---

## Executive Summary

This document provides a comprehensive field-by-field mapping from MongoDB collections to PostgreSQL tables, documenting data type conversions, rationale for design decisions, and notes on structural changes from the original MBA-322 proposal.

---

## Table of Contents

1. [Subscriptions Collection → subscriptions Table](#1-subscriptions-collection--subscriptions-table)
2. [Subscription Tasks (Embedded Array) → subscription_tasks Table](#2-subscription-tasks-embedded-array--subscription_tasks-table)
3. [Cycles Collection → cycles Table](#3-cycles-collection--cycles-table)
4. [Notifications Collection → notifications Table](#4-notifications-collection--notifications-table)
5. [Templates Collection → templates Table](#5-templates-collection--templates-table)
6. [Data Type Mapping Reference](#6-data-type-mapping-reference)
7. [Migration Considerations](#7-migration-considerations)

---

## 1. Subscriptions Collection → subscriptions Table

### MongoDB Collection Structure

**Collection Name:** `subscription`  
**Go Struct Location:** `database/collections/subscriptions.go`

### Field-by-Field Mapping

| MongoDB Field (Go Struct) | MongoDB Type | PostgreSQL Column | PostgreSQL Type | Notes |
|---------------------------|--------------|-------------------|-----------------|-------|
| `_id` | ObjectID | `legacy_objectid` | VARCHAR(24) | Stored for backward compatibility |
| (new) | - | `id` | UUID | New primary key, auto-generated |
| `name` | string | `name` | VARCHAR(255) NOT NULL | Subscription name |
| `customer_id` | string | `customer_id` | VARCHAR(255) | Customer identifier |
| `sending_profile_id` | string | `sending_profile_id` | VARCHAR(255) | Email sending profile |
| `target_domain` | string | `target_domain` | VARCHAR(255) | Target domain for campaign |
| `customer` | string | `customer` | VARCHAR(255) | Customer name/reference |
| `start_date` | time.Time | `start_date` | TIMESTAMP WITH TIME ZONE | Campaign start date |
| `admin_email` | string | `admin_email` | VARCHAR(255) | Admin notification email |
| `operator_email` | string | `operator_email` | VARCHAR(255) | Operator contact email |
| `status` | string | `status` | VARCHAR(50) | Subscription status |
| `cycle_start_date` | string | `cycle_start_date` | VARCHAR(50) | Cycle start date pattern |
| `primary_contact` | PrimaryContact | (multiple columns) | (see below) | **Embedded document inlined as columns** |
| `primary_contact.first_name` | string | `primary_contact_first_name` | VARCHAR(100) | Contact first name |
| `primary_contact.last_name` | string | `primary_contact_last_name` | VARCHAR(100) | Contact last name |
| `primary_contact.title` | string | `primary_contact_title` | VARCHAR(100) | Contact job title |
| `primary_contact.office_phone` | string | `primary_contact_office_phone` | VARCHAR(50) | Office phone number |
| `primary_contact.mobile_phone` | string | `primary_contact_mobile_phone` | VARCHAR(50) | Mobile phone number |
| `primary_contact.email` | string | `primary_contact_email` | VARCHAR(255) | Contact email address |
| `primary_contact.notes` | string | `primary_contact_notes` | TEXT | Notes about contact |
| `primary_contact.active` | bool | `primary_contact_active` | BOOLEAN DEFAULT TRUE | Contact active status |
| `target_email_list` | []TargetEmail | `target_email_list` | JSONB | **Array stored as JSONB** |
| `templates_selected` | []string | `templates_selected` | JSONB | Array of template identifiers |
| `next_templates` | []string | `next_templates` | JSONB | **Missing from MBA-322, now added** |
| `continuous_subscription` | bool | `continuous_subscription` | BOOLEAN DEFAULT FALSE | Continuous campaign flag |
| `buffer_time_minutes` | int | `buffer_time_minutes` | INTEGER | Buffer time configuration |
| `cycle_length_minutes` | int | `cycle_length_minutes` | INTEGER | Cycle duration |
| `cooldown_minutes` | int | `cooldown_minutes` | INTEGER | Cooldown period |
| `report_frequency_minutes` | int | `report_frequency_minutes` | INTEGER | Report generation frequency |
| `tasks` | []SubscriptionTasks | (separate table) | - | **Normalized to subscription_tasks table** |
| `processing` | bool | `processing` | BOOLEAN DEFAULT FALSE | Processing flag |
| `archived` | bool | `archived` | BOOLEAN DEFAULT FALSE | Archive status |
| (new) | - | `created_at` | TIMESTAMP WITH TIME ZONE DEFAULT NOW() | Audit timestamp |
| (new) | - | `updated_at` | TIMESTAMP WITH TIME ZONE DEFAULT NOW() | Auto-updated via trigger |

### Design Decisions

**1. PrimaryContact: Embedded Document → Inline Columns**

**Original MBA-322 Proposal:** Separate `primary_contacts` table with foreign key

**Decision:** Inline as columns in `subscriptions` table

**Rationale:**
- **Read Pattern:** PrimaryContact is ALWAYS read with subscription in notifications workflow
- **One-to-One Relationship:** Each subscription has exactly one primary contact
- **Performance:** Eliminates JOIN on critical path (`notifications/manager.go:63-76`)
- **Simplicity:** Atomic updates of subscription and contact together

**Impact on Queries:**
```sql
-- Original proposal (with JOIN)
SELECT s.*, pc.* 
FROM subscriptions s 
LEFT JOIN primary_contacts pc ON pc.subscription_id = s.id;

-- Updated schema (no JOIN needed)
SELECT * FROM subscriptions;
```

**2. Tasks Array: Embedded Document → Normalized Table**

**Original MBA-322 Proposal:** JSONB array in `subscriptions.tasks`

**Decision:** Separate `subscription_tasks` table

**Rationale:**
- **Individual Updates:** Tasks are updated as they execute
- **Queryability:** Need to find pending tasks, filter by status
- **Data Integrity:** Enforce unique constraint on task_uuid
- **Indexing:** Cannot efficiently index JSONB array elements

**3. next_templates Field: Added**

**Issue:** Field exists in Go struct but missing from MBA-322 proposal

**Resolution:** Added as JSONB column in subscriptions table

**Location in Code:** `database/collections/subscriptions.go:53`

---

## 2. Subscription Tasks (Embedded Array) → subscription_tasks Table

### MongoDB Embedded Structure

**Parent Collection:** `subscription`  
**Go Struct Location:** `database/collections/subscriptions.go:30-37`  
**Embedded As:** `[]SubscriptionTasks` in `tasks` field

### Field-by-Field Mapping

| MongoDB Field (Go Struct) | MongoDB Type | PostgreSQL Column | PostgreSQL Type | Notes |
|---------------------------|--------------|-------------------|-----------------|-------|
| (new) | - | `id` | UUID PRIMARY KEY | New primary key for each task |
| (parent subscription `_id`) | ObjectID | `subscription_id` | UUID FOREIGN KEY | References subscriptions(id) |
| `task_uuid` | string | `task_uuid` | VARCHAR(255) UNIQUE NOT NULL | Unique task identifier |
| `task_type` | string | `task_type` | VARCHAR(100) NOT NULL | Task type (e.g., "cycle_report") |
| `scheduled_date` | time.Time | `scheduled_date` | TIMESTAMP WITH TIME ZONE NOT NULL | When task should run |
| `executed` | bool | `executed` | BOOLEAN DEFAULT FALSE | Execution status |
| `executed_date` | time.Time | `executed_date` | TIMESTAMP WITH TIME ZONE | When task actually executed |
| `error` | string | `error` | TEXT | Error message if execution failed |
| (new) | - | `created_at` | TIMESTAMP WITH TIME ZONE DEFAULT NOW() | Audit timestamp |
| (new) | - | `updated_at` | TIMESTAMP WITH TIME ZONE DEFAULT NOW() | Auto-updated via trigger |

### Migration Process

**MongoDB Structure:**
```json
{
  "_id": ObjectId("..."),
  "tasks": [
    {
      "task_uuid": "abc123",
      "task_type": "cycle_report",
      "scheduled_date": ISODate("2025-10-08T10:00:00Z"),
      "executed": false,
      "executed_date": null,
      "error": ""
    }
  ]
}
```

**PostgreSQL Structure:**
```sql
-- Parent record
INSERT INTO subscriptions (id, name, ...) VALUES (...);

-- Child records (one row per task)
INSERT INTO subscription_tasks (subscription_id, task_uuid, task_type, ...)
VALUES (parent_subscription_id, 'abc123', 'cycle_report', ...);
```

**Indexes Required:**
- `idx_subscription_tasks_subscription_id` - Foreign key lookups
- `idx_subscription_tasks_executed` - Find pending tasks
- `idx_subscription_tasks_scheduled_date` - Scheduling queries

---

## 3. Cycles Collection → cycles Table

### MongoDB Collection Structure

**Collection Name:** `cycle`  
**Go Struct Location:** `database/collections/cycles.go`

### Field-by-Field Mapping

| MongoDB Field (Go Struct) | MongoDB Type | PostgreSQL Column | PostgreSQL Type | Notes |
|---------------------------|--------------|-------------------|-----------------|-------|
| `_id` | ObjectID | `legacy_objectid` | VARCHAR(24) | Original MongoDB ID |
| (new) | - | `id` | UUID PRIMARY KEY | New UUID primary key |
| `subscription_id` | string | `subscription_id` | UUID NOT NULL REFERENCES subscriptions(id) | **Foreign key relationship** |
| `template_ids` | []string | `template_ids` | JSONB | Array of template UUIDs |
| `start_date` | time.Time | `start_date` | TIMESTAMP WITH TIME ZONE NOT NULL | Cycle start |
| `end_date` | time.Time | `end_date` | TIMESTAMP WITH TIME ZONE NOT NULL | Cycle end |
| `send_by_date` | time.Time | `send_by_date` | TIMESTAMP WITH TIME ZONE NOT NULL | Send deadline |
| `active` | bool | `active` | BOOLEAN DEFAULT TRUE | Active status |
| `target_count` | int | `target_count` | INTEGER DEFAULT 0 | Number of targets |
| (new) | - | `created_at` | TIMESTAMP WITH TIME ZONE DEFAULT NOW() | Audit timestamp |
| (new) | - | `updated_at` | TIMESTAMP WITH TIME ZONE DEFAULT NOW() | Auto-updated via trigger |

### Critical Query Pattern

**Location:** `notifications/manager.go:43-48`

```go
c, err := collections.GetCycle(cycleId)              // Step 1: Get cycle
s, err := collections.GetSubscription(c.SubscriptionId)  // Step 2: FK traversal
```

**PostgreSQL Equivalent:**
```sql
-- Step 1: Get cycle (supports both UUID and legacy ObjectID)
SELECT * FROM cycles WHERE id = $1 OR legacy_objectid = $1;

-- Step 2: Foreign key traversal
SELECT * FROM subscriptions WHERE id = cycle.subscription_id;

-- Or as single JOIN:
SELECT c.*, s.* 
FROM cycles c
JOIN subscriptions s ON s.id = c.subscription_id
WHERE c.id = $1 OR c.legacy_objectid = $1;
```

**Required Indexes:**
- `idx_cycles_legacy_objectid` - HTTP endpoint compatibility
- `idx_cycles_subscription_id` - FK traversal performance

---

## 4. Notifications Collection → notifications Table

### MongoDB Collection Structure

**Collection Name:** `notification`  
**Go Struct Location:** `database/collections/notifications.go`

### Field-by-Field Mapping

| MongoDB Field (Go Struct) | MongoDB Type | PostgreSQL Column | PostgreSQL Type | Notes |
|---------------------------|--------------|-------------------|-----------------|-------|
| `_id` | ObjectID | `legacy_objectid` | VARCHAR(24) | Original MongoDB ID |
| (new) | - | `id` | UUID PRIMARY KEY | New UUID primary key |
| `name` | string | `name` | VARCHAR(255) NOT NULL | Notification name |
| `task_name` | string | `task_name` | VARCHAR(255) UNIQUE NOT NULL | **Primary lookup field** |
| `subject` | string | `subject` | VARCHAR(500) | Email subject line |
| `html` | string | `html` | TEXT | HTML email body |
| `text` | string | `text` | TEXT | Plain text email body |
| `has_attachment` | bool | `has_attachment` | BOOLEAN DEFAULT FALSE | Attachment flag |
| (new) | - | `created_at` | TIMESTAMP WITH TIME ZONE DEFAULT NOW() | Audit timestamp |
| (new) | - | `updated_at` | TIMESTAMP WITH TIME ZONE DEFAULT NOW() | Auto-updated via trigger |

### Critical Query Pattern

**Location:** `notifications/manager.go:54`

```go
n, err := collections.GetNotification(tasktype + "_report")
```

**MongoDB Query:**
```javascript
db.notification.findOne({ task_name: "cycle_report" })
```

**PostgreSQL Query:**
```sql
SELECT * FROM notifications WHERE task_name = $1;
```

**Key Design Point:** Lookup is by `task_name` field, NOT by `_id`. This is why task_name has UNIQUE constraint and dedicated index.

**Required Index:** `idx_notifications_task_name`

---

## 5. Templates Collection → templates Table

### MongoDB Collection Structure

**Collection Name:** `template` (Note: accessed via `PhishesCollection` variable)  
**Go Struct Location:** `database/collections/phishes.go`

### Field-by-Field Mapping

| MongoDB Field (Go Struct) | MongoDB Type | PostgreSQL Column | PostgreSQL Type | Notes |
|---------------------------|--------------|-------------------|-----------------|-------|
| `_id` | ObjectID | `legacy_objectid` | VARCHAR(24) | Original MongoDB ID |
| (new) | - | `id` | UUID PRIMARY KEY | New UUID primary key |
| `name` | string | `name` | VARCHAR(255) UNIQUE NOT NULL | Template name (**lookup field**) |
| `subject` | string | `subject` | VARCHAR(500) | Email subject template |
| `html` | string | `html` | TEXT | HTML email template |
| `text` | string | `text` | TEXT | Plain text email template |
| `retired` | bool | `retired` | BOOLEAN DEFAULT FALSE | **Retirement status** |
| (new) | - | `created_at` | TIMESTAMP WITH TIME ZONE DEFAULT NOW() | Audit timestamp |
| (new) | - | `updated_at` | TIMESTAMP WITH TIME ZONE DEFAULT NOW() | Auto-updated via trigger |

### Naming Inconsistency Resolution

**Issue:** Collection naming inconsistency across codebase
- MongoDB collection name: `"template"`
- Go variable name: `PhishesCollection`
- Go struct name: `Phish`
- MBA-322 proposal: `templates` table

**Resolution:** PostgreSQL table named `templates` (plural) for consistency with other tables.

### Critical Query Pattern

**Location:** `database/collections/phishes.go:17-23`

```go
func GetPhish(Name string) (Phish, error) {
    err := db.PhishesCollection.
        FindOne(db.Ctx, bson.D{
            {Key: "name", Value: Name}, 
            {Key: "retired", Value: false}
        }).Decode(&p)
}
```

**MongoDB Query:**
```javascript
db.template.findOne({ name: "template_name", retired: false })
```

**PostgreSQL Query:**
```sql
SELECT * FROM templates 
WHERE name = $1 AND retired = FALSE;
```

**Key Design Point:** Compound filter on BOTH `name` AND `retired` status. Only active (non-retired) templates are returned.

**Required Index:** `idx_templates_name_active` (composite index on both fields)

---

## 6. Data Type Mapping Reference

### Comprehensive Type Conversion Table

| Go Type | MongoDB BSON Type | PostgreSQL Type | Size | Notes |
|---------|-------------------|-----------------|------|-------|
| `primitive.ObjectID` | ObjectID (12 bytes) | VARCHAR(24) | 24 chars | Stored as hex string in legacy_objectid |
| `uuid.UUID` (new) | - | UUID | 16 bytes | Native PostgreSQL UUID type |
| `string` | string | VARCHAR(n) or TEXT | Variable | VARCHAR for bounded, TEXT for unbounded |
| `int` | int32 | INTEGER | 4 bytes | Standard integer |
| `int64` | int64 | BIGINT | 8 bytes | Large integers |
| `bool` | boolean | BOOLEAN | 1 byte | Native boolean |
| `time.Time` | ISODate | TIMESTAMP WITH TIME ZONE | 8 bytes | **Always use WITH TIME ZONE** |
| `[]string` | array | JSONB | Variable | Arrays stored as JSONB |
| `[]TargetEmail` | array of documents | JSONB | Variable | Complex arrays as JSONB |
| `PrimaryContact` (embedded) | embedded document | (inline columns) | - | Flattened into parent table |
| `[]SubscriptionTasks` (embedded array) | array of documents | (separate table) | - | Normalized to subscription_tasks table |

### Special Considerations

**1. ObjectID → UUID Conversion**

**Challenge:** MongoDB ObjectID is 24-character hex string, PostgreSQL UUID is 36-character with hyphens.

**Solution:** Dual-ID strategy
```sql
id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
legacy_objectid VARCHAR(24) UNIQUE
```

**Migration:**
- Existing records: Generate new UUID, store original ObjectID in legacy_objectid
- New records: Generate UUID only, legacy_objectid can be NULL
- Queries: Support both formats via application layer

**2. BSON Array → JSONB vs Normalized Table**

**Decision Matrix:**

| If Array Contains... | Use JSONB | Use Normalized Table |
|---------------------|-----------|----------------------|
| Primitive values (strings, numbers) | ✅ Yes | ❌ No |
| Simple objects, rarely queried independently | ✅ Yes | ❌ No |
| Complex objects with relationships | ❌ No | ✅ Yes |
| Frequently updated individual elements | ❌ No | ✅ Yes |
| Need to query/filter array elements | ❌ No | ✅ Yes |

**Applied Decisions:**
- `target_email_list`: JSONB (simple objects, fetched with subscription)
- `templates_selected`: JSONB (array of IDs, no complex queries)
- `template_ids`: JSONB (array of IDs, no complex queries)
- `tasks` array: Normalized table (complex objects, individual updates, queries needed)

**3. Timestamp Handling**

**Rule:** ALL timestamps must use `TIMESTAMP WITH TIME ZONE`

**Rationale:**
- MongoDB ISODate includes timezone information
- PostgreSQL `TIMESTAMP` (without timezone) loses timezone data
- System may handle dates across multiple timezones

**Conversion Example:**
```go
// MongoDB
startDate: ISODate("2025-10-08T10:00:00.000Z")

// PostgreSQL
start_date: '2025-10-08 10:00:00+00' :: TIMESTAMP WITH TIME ZONE
```

---

## 7. Migration Considerations

### 7.1 Foreign Key Relationships

**Established Relationships:**

```
subscriptions (parent)
    ↓ (subscription_id FK)
cycles (child)

subscriptions (parent)
    ↓ (subscription_id FK)
subscription_tasks (child)
```

**No Foreign Keys:**
- notifications (independent lookup table)
- templates (independent lookup table)

**Referential Integrity:**
- `ON DELETE CASCADE` for subscription_tasks (tasks belong to subscription)
- No cascade for cycles (may want to preserve historical cycle data)

### 7.2 Index Strategy

**Performance-Critical Indexes:**

1. **Legacy ObjectID Lookups** (backward compatibility)
   - `idx_cycles_legacy_objectid`
   - `idx_subscriptions_legacy_objectid`
   - All others similarly

2. **Foreign Key Indexes** (critical for JOIN performance)
   - `idx_cycles_subscription_id`
   - `idx_subscription_tasks_subscription_id`

3. **Lookup Field Indexes** (primary query patterns)
   - `idx_notifications_task_name` (UNIQUE index)
   - `idx_templates_name_active` (compound index)

4. **Status Filtering Indexes** (common queries)
   - `idx_cycles_active`
   - `idx_subscriptions_archived`
   - `idx_subscription_tasks_executed`

**Index Types:**
- B-tree: Default, used for most indexes
- GIN: Used for JSONB columns if array element queries needed

### 7.3 Data Migration Script Structure

**High-Level Process:**

```python
# 1. Export from MongoDB
for doc in mongodb.subscriptions.find():
    subscription = {
        'id': generate_uuid(),
        'legacy_objectid': str(doc['_id']),
        # ... map all fields
    }
    
    # Extract and normalize tasks
    for task in doc.get('tasks', []):
        task_record = {
            'id': generate_uuid(),
            'subscription_id': subscription['id'],
            # ... map task fields
        }
        postgres_tasks.insert(task_record)
    
    # Flatten primary_contact
    if 'primary_contact' in doc:
        subscription.update({
            'primary_contact_first_name': doc['primary_contact']['first_name'],
            # ... flatten all contact fields
        })
    
    # Convert arrays to JSONB
    subscription['target_email_list'] = json.dumps(doc.get('target_email_list', []))
    
    postgres_subscriptions.insert(subscription)

# 2. Build foreign key mapping
objectid_to_uuid_map = {}
for subscription in subscriptions:
    objectid_to_uuid_map[subscription['legacy_objectid']] = subscription['id']

# 3. Update foreign key references in cycles
for doc in mongodb.cycles.find():
    cycle = {
        'id': generate_uuid(),
        'legacy_objectid': str(doc['_id']),
        'subscription_id': objectid_to_uuid_map[doc['subscription_id']],  # Convert!
        # ... map other fields
    }
    postgres_cycles.insert(cycle)
```

### 7.4 Data Validation Queries

**Post-Migration Verification:**

```sql
-- 1. Verify all foreign keys resolved
SELECT COUNT(*) 
FROM cycles c
LEFT JOIN subscriptions s ON c.subscription_id = s.id
WHERE s.id IS NULL;
-- Should return 0

-- 2. Verify legacy ObjectIDs are unique and valid format
SELECT COUNT(*) 
FROM subscriptions 
WHERE legacy_objectid IS NULL 
   OR legacy_objectid !~ '^[0-9a-fA-F]{24}$';
-- Should return 0 for migrated data

-- 3. Verify no orphaned subscription_tasks
SELECT COUNT(*) 
FROM subscription_tasks st
LEFT JOIN subscriptions s ON st.subscription_id = s.id
WHERE s.id IS NULL;
-- Should return 0

-- 4. Count comparison
-- MongoDB: db.subscription.count()
-- PostgreSQL:
SELECT COUNT(*) FROM subscriptions;
-- Should match

-- 5. Sample data validation
SELECT 
    s.legacy_objectid,
    s.name,
    s.primary_contact_email,
    COUNT(st.id) as task_count
FROM subscriptions s
LEFT JOIN subscription_tasks st ON st.subscription_id = s.id
GROUP BY s.id, s.legacy_objectid, s.name, s.primary_contact_email
LIMIT 10;
```

### 7.5 Application Code Changes Required

**Query Pattern Changes:**

```go
// Before (MongoDB)
err := db.CyclesCollection.
    FindOne(db.Ctx, bson.D{{Key: "_id", Value: objectId}}).
    Decode(&c)

// After (PostgreSQL)
query := "SELECT * FROM cycles WHERE id = $1 OR legacy_objectid = $1"
err := db.DB.GetContext(db.Ctx, &c, query, id)
```

**Struct Tag Changes:**

```go
// Before (MongoDB)
type Cycle struct {
    SubscriptionId string `bson:"subscription_id"`
}

// After (PostgreSQL)
type Cycle struct {
    ID             uuid.UUID  `db:"id" json:"id"`
    LegacyObjectID *string    `db:"legacy_objectid" json:"legacy_objectid,omitempty"`
    SubscriptionID uuid.UUID  `db:"subscription_id" json:"subscription_id"`
}
```

---

## 8. Summary of Changes from MBA-322 Proposal

### Added to Proposal

1. **✅ subscription_tasks Table**
   - **Why:** Normalized from embedded tasks array for better queryability
   - **Impact:** Enables individual task updates, status queries, unique constraints

2. **✅ legacy_objectid Columns**
   - **Why:** Backward compatibility with existing HTTP endpoints and ObjectID references
   - **Impact:** No breaking changes required for API clients

3. **✅ next_templates Field**
   - **Why:** Field exists in Go struct but was missing from proposal
   - **Impact:** Prevents data loss during migration

4. **✅ Primary Contact Inline Columns**
   - **Why:** One-to-one relationship, always fetched together, critical path optimization
   - **Impact:** Eliminates JOIN on notification workflow

### Removed from Proposal

1. **❌ primary_contacts Separate Table**
   - **Why:** Inlined into subscriptions table (see above)
   - **Impact:** Simpler schema, better performance for critical path

### Modified from Proposal

1. **📝 Timestamps**
   - **Change:** All timestamps use `TIMESTAMP WITH TIME ZONE` (not just TIMESTAMP)
   - **Why:** Preserve timezone information from MongoDB ISODate
   - **Impact:** Proper timezone handling across system

2. **📝 Index Strategy**
   - **Change:** Added indexes based on actual query patterns from con-pca-tasks
   - **Why:** Original proposal had generic indexes, not optimized for actual usage
   - **Impact:** Better query performance for critical paths

---

## 9. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Foreign key mismatches during migration | Medium | High | Comprehensive validation queries, dry-run migration |
| Legacy ObjectID queries fail | Low | High | Dual-ID strategy with indexed legacy_objectid column |
| JSONB query performance issues | Medium | Medium | GIN indexes on JSONB columns, monitoring |
| Missing write operations in analysis | High | High | **Obtain con-pca-api access for complete analysis** |
| Nested document strategy incorrect | Medium | Medium | Validate assumptions with con-pca-api write patterns |
| Data type conversion errors | Low | High | Extensive testing with sample data |

---

## 10. Next Steps

### Immediate (Before Implementation)

1. **✅ CRITICAL: Obtain access to con-pca-api repository**
   - Analyze all write operations (Insert, Update, Delete)
   - Validate nested document strategy decisions
   - Confirm transaction patterns

2. **Validate Schema with Sample Data**
   - Export small dataset from MongoDB
   - Test migration script
   - Verify foreign key relationships

3. **Review with Stakeholders**
   - Present schema design decisions
   - Confirm nested document strategies
   - Approve migration approach

### Implementation Phase

1. **Database Setup**
   - Create PostgreSQL instance
   - Run schema creation scripts
   - Verify constraints and indexes

2. **Migration Script Development**
   - Write data export from MongoDB
   - Implement ObjectID→UUID mapping
   - Handle nested document transformations

3. **Application Code Updates**
   - Implement PostgreSQL connection layer
   - Update repository functions
   - Add dual-ID query support

4. **Testing**
   - Unit tests for database layer
   - Integration tests for query patterns
   - Performance testing with realistic data volumes

5. **Deployment**
   - Staging environment migration
   - Validation and performance monitoring
   - Production migration with rollback plan

---

## Appendix A: Complete Data Type Conversion Matrix

| Source (MongoDB) | Target (PostgreSQL) | Conversion Notes |
|------------------|---------------------|------------------|
| ObjectId("507f...") | '507f1f77bcf86cd799439011' :: VARCHAR(24) | Hex string representation |
| "string value" | 'string value' :: VARCHAR or TEXT | Use VARCHAR for bounded lengths |
| 123 | 123 :: INTEGER | 32-bit integers |
| true / false | true / false :: BOOLEAN | Direct mapping |
| ISODate("2025-10-08T10:00:00Z") | '2025-10-08 10:00:00+00' :: TIMESTAMPTZ | Include timezone |
| ["item1", "item2"] | '["item1", "item2"]' :: JSONB | JSON array |
| {email: "x", name: "y"} | '{"email":"x","name":"y"}' :: JSONB | JSON object |
| null | NULL | Direct mapping |
| undefined | NULL | Treat as NULL |

---

## Appendix B: Query Performance Comparison

### Scenario 1: Get Cycle with Subscription and Notification

**MongoDB (Current):**
```javascript
// 3 separate queries
cycle = db.cycle.findOne({_id: ObjectId(...)})
subscription = db.subscription.findOne({_id: cycle.subscription_id})
notification = db.notification.findOne({task_name: "cycle_report"})
```

**PostgreSQL (New):**
```sql
-- Single query with JOINs
SELECT c.*, s.*, n.*
FROM cycles c
JOIN subscriptions s ON s.id = c.subscription_id
JOIN notifications n ON n.task_name = 'cycle_report'
WHERE c.id = $1 OR c.legacy_objectid = $1;
```

**Performance:** PostgreSQL should be faster due to single query + JOINs vs 3 round trips.

### Scenario 2: Find Pending Tasks

**MongoDB (Current - Complex):**
```javascript
// Would require $unwind if implemented
db.subscription.aggregate([
  {$unwind: "$tasks"},
  {$match: {"tasks.executed": false}},
  {$sort: {"tasks.scheduled_date": 1}}
])
```

**PostgreSQL (New - Simple):**
```sql
-- Direct query on normalized table
SELECT * FROM subscription_tasks
WHERE executed = FALSE
ORDER BY scheduled_date ASC;
```

**Performance:** PostgreSQL significantly faster with indexed queries on normalized table.

---

**Document Version:** 1.0  
**Status:** COMPLETE (Pending con-pca-api Validation)  
**Confidence:** High 🟢 for documented patterns, Medium 🟡 for assumptions requiring validation

---

**Analysis completed by:** Devin AI  
**Review Date:** October 8, 2025  
**Next Review:** After con-pca-api repository analysis
