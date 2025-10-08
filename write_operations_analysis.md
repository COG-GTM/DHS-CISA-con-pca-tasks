# Write Operations Analysis for PostgreSQL Migration

**Ticket:** MBA-322 - Phase 1 Database Schema Design for PostgreSQL Migration  
**Repository:** COG-GTM/DHS-CISA-con-pca-tasks  
**Analysis Date:** October 8, 2025  
**Analyst:** Devin AI

---

## Executive Summary

This analysis documents all MongoDB operations found in the `COG-GTM/DHS-CISA-con-pca-tasks` repository and identifies critical gaps requiring investigation in the `COG-GTM/con-pca-api` repository.

**Critical Finding:** The con-pca-tasks repository contains **ONLY read operations**. All write operations (Insert, Update, Delete) must exist in the con-pca-api repository, which was not available for this analysis.

---

## MongoDB Operations in con-pca-tasks

### Read Operations Summary

| Collection | Operation | Query Pattern | Location |
|------------|-----------|---------------|----------|
| `cycle` | FindOne | By `_id` (ObjectID) | `database/collections/cycles.go:31-33` |
| `subscription` | FindOne | By `_id` (ObjectID) | `database/collections/subscriptions.go:75-77` |
| `notification` | FindOne | By `task_name` (string) | `database/collections/notifications.go:20-22` |
| `template` | FindOne | By `name` (string) AND `retired=false` | `database/collections/phishes.go:19-21` |

### Detailed Operation Analysis

#### 1. Cycle Collection - GetCycle()

**File:** `database/collections/cycles.go`

```go
func GetCycle(id string) (Cycle, error) {
    var c Cycle
    objectId, err := primitive.ObjectIDFromHex(id)
    if err != nil {
        return c, err
    }
    err = db.CyclesCollection.
        FindOne(db.Ctx, bson.D{{Key: "_id", Value: objectId}}).
        Decode(&c)
    return c, nil
}
```

**Query Pattern:**
- Input: String ID from HTTP endpoint
- Conversion: `primitive.ObjectIDFromHex(id)` converts hex string to ObjectID
- Query: Single document lookup by `_id`
- Usage: Called from `notifications/manager.go:43` to fetch cycle data

**PostgreSQL Compatibility:**
✅ Simple SELECT by primary key - fully compatible  
⚠️ Requires ObjectID-to-UUID conversion strategy

#### 2. Subscription Collection - GetSubscription()

**File:** `database/collections/subscriptions.go`

```go
func GetSubscription(id string) (Subscription, error) {
    var s Subscription
    objectId, err := primitive.ObjectIDFromHex(id)
    if err != nil {
        return s, err
    }
    err = db.SubscriptionsCollection.
        FindOne(db.Ctx, bson.D{{Key: "_id", Value: objectId}}).
        Decode(&s)
    return s, nil
}
```

**Query Pattern:**
- Input: Subscription ID from Cycle.SubscriptionId field
- Conversion: ObjectID from hex string
- Query: Single document lookup by `_id`
- Usage: Called from `notifications/manager.go:48` after fetching cycle

**PostgreSQL Compatibility:**
✅ Simple SELECT by primary key with foreign key traversal - fully compatible  
✅ Proposed schema includes `subscription_id UUID NOT NULL REFERENCES subscriptions(id)` in cycles table

#### 3. Notification Collection - GetNotification()

**File:** `database/collections/notifications.go`

```go
func GetNotification(TaskName string) (Notification, error) {
    var n Notification
    err := db.NotificationsCollection.
        FindOne(db.Ctx, bson.D{{Key: "task_name", Value: TaskName}}).
        Decode(&n)
    return n, nil
}
```

**Query Pattern:**
- Input: Task type + "_report" suffix (e.g., "cycle_report")
- Query: Lookup by `task_name` field (NOT by _id)
- No ObjectID conversion required
- Usage: Called from `notifications/manager.go:54`

**PostgreSQL Compatibility:**
✅ Simple SELECT by indexed string column - fully compatible  
✅ Proposed schema includes `task_name VARCHAR(255) UNIQUE NOT NULL` with index  
✅ No foreign key relationships - independent lookup

#### 4. Template Collection - GetPhish()

**File:** `database/collections/phishes.go`

```go
func GetPhish(Name string) (Phish, error) {
    var p Phish
    err := db.PhishesCollection.
        FindOne(db.Ctx, bson.D{{Key: "name", Value: Name}, {Key: "retired", Value: false}}).
        Decode(&p)
    return p, nil
}
```

**Query Pattern:**
- Input: Template name (string)
- Query: **Compound filter** - by `name` AND `retired=false`
- Critical: Only returns non-retired templates
- Usage: Not called in con-pca-tasks (likely used by con-pca-api)

**PostgreSQL Compatibility:**
✅ WHERE clause with compound condition - fully compatible  
✅ Proposed schema includes both fields with indexes:
   - `name VARCHAR(255) UNIQUE NOT NULL`
   - `retired BOOLEAN DEFAULT FALSE`
   - Index: `idx_templates_name` and `idx_templates_retired`

---

## Critical Query Pattern: Multi-Collection Dependency Chain

**Location:** `notifications/manager.go:41-54`

```go
func Manager(cycleId, tasktype string) {
    // Step 1: Get cycle by ID
    c, err := collections.GetCycle(cycleId)
    
    // Step 2: Get subscription using FK traversal
    s, err := collections.GetSubscription(c.SubscriptionId)
    
    // Step 3: Get notification by task name
    n, err := collections.GetNotification(tasktype + "_report")
    
    // Step 4: Access nested primary contact
    firstName := s.PrimaryContact.FirstName
    lastName := s.PrimaryContact.LastName
}
```

**PostgreSQL Requirements:**
1. ✅ Foreign key from `cycles.subscription_id` to `subscriptions.id`
2. ✅ Index on `cycles.subscription_id` for efficient FK traversal
3. ✅ Unique index on `notifications.task_name` for lookup performance
4. ⚠️ Decision needed: PrimaryContact as embedded JSONB or separate table
5. ⚠️ UUID compatibility required for cycle_id string parameter

---

## Write Operations - Critical Gap

### What We Know
- ❌ **NO write operations found in con-pca-tasks repository**
- ❌ No InsertOne, UpdateOne, DeleteOne, or Aggregate operations
- ❌ No transaction patterns visible
- ❌ No multi-collection update operations

### What We Need from con-pca-api

The following operations MUST exist in con-pca-api and need analysis:

#### 1. Cycle Write Operations
- **Create:** How are new cycles inserted?
- **Update:** Are cycle dates/status updated after creation?
- **Delete:** Are cycles soft-deleted or hard-deleted?
- **Batch:** Are cycles created in batches?

#### 2. Subscription Write Operations
- **Create:** New subscription creation with embedded documents
- **Update Tasks:** How is the `tasks` array updated? (SubscriptionTasks)
- **Update Templates:** How are `templates_selected` and `next_templates` modified?
- **Update Contact:** Is `primary_contact` updated separately or with subscription?
- **Target List:** How is `target_email_list` array modified?
- **Status Changes:** How does subscription status transition? (processing, archived)

#### 3. Notification Template Write Operations
- **Create:** Template creation process
- **Update:** Can templates be modified?
- **Delete:** Are templates deleted or marked inactive?

#### 4. Phishing Template Write Operations
- **Create:** Template creation with HTML/text content
- **Update:** Template modification process
- **Retire:** How does the `retired` flag get set?
- **Bulk Updates:** Are multiple templates updated together?

#### 5. Transaction Patterns
- **Multi-Collection Updates:** Are cycles and subscriptions updated together?
- **Atomicity Requirements:** Which operations need to be atomic?
- **Rollback Scenarios:** What failures require rollback?

---

## Schema Compatibility Assessment

### Based on Available Information

| Aspect | Status | Notes |
|--------|--------|-------|
| Read by Primary Key | ✅ COMPATIBLE | All _id lookups map to UUID primary key |
| Foreign Key Traversal | ✅ COMPATIBLE | Cycle → Subscription relationship preserved |
| String-based Lookups | ✅ COMPATIBLE | task_name and name fields have unique indexes |
| Compound Queries | ✅ COMPATIBLE | name + retired filter supported by indexes |
| Array Fields | ⚠️ NEEDS VALIDATION | JSONB proposed but write patterns unknown |
| Embedded Documents | ⚠️ NEEDS VALIDATION | PrimaryContact strategy unclear without writes |
| Transactions | ❌ CANNOT ASSESS | No visibility into multi-collection operations |

---

## Recommendations

### Immediate Actions Required

1. **Obtain Access to con-pca-api Repository**
   - Priority: CRITICAL
   - Reason: 100% of write operations are missing from current analysis
   - Impact: Cannot validate proposed schema without write patterns

2. **Document Write Operations from con-pca-api**
   - All Insert operations and their data structures
   - All Update operations and their target fields
   - All Delete operations and cascade requirements
   - Transaction boundaries and atomicity needs

3. **Validate Array Field Strategies**
   - Determine if `tasks` array is updated incrementally or replaced
   - Analyze `target_email_list` modification patterns
   - Assess `templates_selected` and `next_templates` update frequency

4. **Test Transaction Requirements**
   - Identify operations that span multiple collections
   - Document rollback scenarios
   - Determine isolation level requirements

### Schema Design Decisions Pending con-pca-api Analysis

1. **SubscriptionTasks Array**
   - Current: Proposed as JSONB in `subscriptions.tasks`
   - Question: Are individual tasks updated, or entire array replaced?
   - If individual updates needed: Separate `subscription_tasks` table recommended
   - If bulk replace only: JSONB acceptable

2. **TargetEmail Array**
   - Current: Proposed as JSONB in `subscriptions.target_email_list`
   - Question: Are targets added/removed individually?
   - If individual modifications: Separate `target_emails` table recommended
   - If static per cycle: JSONB acceptable

3. **PrimaryContact Embedded Document**
   - Current: Proposed as separate `primary_contacts` table
   - Question: Is contact updated separately from subscription?
   - If independent updates: Separate table correct
   - If always updated with subscription: Could be JSONB or columns in subscriptions

---

## PostgreSQL Migration Risks

### High Risk (Blockers)
1. ❌ **Unknown Write Patterns:** Cannot validate schema without con-pca-api access
2. ❌ **Transaction Requirements:** Unknown atomicity needs across collections
3. ❌ **Array Update Patterns:** JSONB vs normalized table decision incomplete

### Medium Risk (Need Validation)
1. ⚠️ **ObjectID to UUID Conversion:** Need to verify existing IDs can convert
2. ⚠️ **Performance Impact:** JSONB query performance vs normalized tables
3. ⚠️ **Concurrent Updates:** Locking strategy for array field modifications

### Low Risk (Manageable)
1. ✅ **Read Operations:** All current reads map cleanly to PostgreSQL
2. ✅ **Foreign Keys:** Relationship structure is clear
3. ✅ **Indexes:** Query patterns well-defined from read operations

---

## Conclusion

**Analysis Completeness: 40%**

This analysis successfully documents all read operations in con-pca-tasks, but represents only a fraction of the total operation patterns needed for migration planning. The absence of write operations from this repository is a critical limitation.

**Next Steps:**
1. Obtain access to `COG-GTM/con-pca-api` repository
2. Conduct comprehensive write operation analysis
3. Update this document with complete operation patterns
4. Finalize schema design decisions based on write patterns
5. Validate transaction requirements across both repositories

**Confidence Level:** Low 🔴 for overall schema design  
**Blocker:** con-pca-api repository access required to proceed with implementation phase

---

**Document Version:** 1.0  
**Status:** INCOMPLETE - Requires con-pca-api Analysis  
**Next Review:** After con-pca-api access granted
