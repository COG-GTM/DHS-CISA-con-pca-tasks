# Write Operations Analysis for PostgreSQL Migration

**Ticket:** MBA-322 - Phase 1 Database Schema Design  
**Analysis Date:** October 8, 2025  
**Repositories Analyzed:** COG-GTM/DHS-CISA-con-pca-tasks, COG-GTM/con-pca-api

## Executive Summary

This document analyzes all MongoDB write operations in the `con-pca-api` repository to validate compatibility with the proposed PostgreSQL schema design. The analysis reveals significant gaps in the original proposal that must be addressed before implementation.

### Critical Findings

1. **Missing Collection:** The proposed schema only addresses 4 collections (cycle, subscription, notification, template) but the system uses a 5th critical collection: **target**
2. **Array Operations:** Extensive use of MongoDB array operators ($push, $pull, positional updates) that require careful translation to PostgreSQL
3. **Missing Fields:** Numerous fields in actual schemas are absent from the proposed PostgreSQL schema
4. **Transaction Patterns:** Multi-collection operations that may require PostgreSQL transaction management

## 1. Base Manager Class Write Operations

Location: `con-pca-api/src/api/manager.py`

All collection managers inherit from the base `Manager` class, which provides the following write operations:

### 1.1 Insert Operations

```python
def save(self, data):
    """Save new item to collection."""
    # Uses: db.insert_one()
    # Adds: created, created_by, updated, updated_by timestamps
    result = self.db.insert_one(self.load_data(data))
    return {"_id": str(result.inserted_id)}

def save_many(self, data):
    """Save list to collection."""
    # Uses: db.insert_many()
    # Adds: created, created_by timestamps
    result = self.db.insert_many(self.load_data(data, many=True))
    return result.inserted_ids
```

**PostgreSQL Compatibility:**
- ✅ Direct equivalent: INSERT INTO ... RETURNING id
- ✅ Batch inserts supported with COPY or multi-row INSERT
- ⚠️ Need to handle created_by/updated_by fields (currently uses Flask g.username or "bot")

### 1.2 Update Operations

```python
def update(self, document_id, data, update=True):
    """Update item by id."""
    # Uses: db.update_one() with $set operator
    # Adds: updated, updated_by timestamps if update=True
    self.db.update_one(
        self.document_query(document_id),
        {"$set": self.load_data(data, partial=True)},
    )

def update_many(self, params, data):
    """Update many items with params."""
    # Uses: db.update_many() with $set operator
    self.db.update_many(
        params,
        {"$set": self.load_data(data, partial=True)},
    )
```

**PostgreSQL Compatibility:**
- ✅ Direct equivalent: UPDATE ... WHERE id = $1
- ✅ Bulk updates supported with UPDATE ... WHERE id IN (...)
- ✅ Trigger functions can handle updated_at timestamp automatically

### 1.3 Delete Operations

```python
def delete(self, document_id=None, params=None):
    """Delete item by object id."""
    if document_id:
        self.db.delete_one(self.document_query(document_id))
    if params or params == {}:
        self.db.delete_many(params)
```

**PostgreSQL Compatibility:**
- ✅ Direct equivalent: DELETE FROM ... WHERE id = $1
- ✅ Bulk deletes supported with DELETE FROM ... WHERE id IN (...)
- ✅ CASCADE behavior on foreign keys handles related record cleanup

### 1.4 Array Manipulation Operations (CRITICAL)

```python
def add_to_list(self, document_id, field, data):
    """Add item to list in document."""
    return self.db.update_one(
        self.document_query(document_id), {"$push": {field: data}}
    )

def delete_from_list(self, document_id, field, data):
    """Delete item from list in document."""
    return self.db.update_one(
        self.document_query(document_id), {"$pull": {field: data}}
    )

def update_in_list(self, document_id, field, data, params):
    """Update item in list from document."""
    # Uses positional $ operator to update specific array element
    query = self.document_query(document_id)
    query.update(params)
    self.db.update_one(query, {"$set": {field: data}})
```

**PostgreSQL Compatibility:**
- ⚠️ **COMPLEX** - These operations are heavily used throughout the codebase
- Option 1 (JSONB): Use jsonb_insert(), jsonb_set(), jsonb array operators
  - Pro: Maintains document-like structure
  - Con: Complex queries, limited indexing, potential performance issues
- Option 2 (Normalized Tables): Create separate tables with foreign keys
  - Pro: Relational integrity, efficient queries, proper indexing
  - Con: More complex schema, joins required
- **Recommendation:** Hybrid approach (see nested_document_strategy.md)

### 1.5 Upsert Operations

```python
def upsert(self, query, data):
    """Upsert documents into the database."""
    self.db.update_one(
        query,
        {"$set": self.load_data(data)},
        upsert=True,
    )
```

**PostgreSQL Compatibility:**
- ✅ Direct equivalent: INSERT ... ON CONFLICT DO UPDATE

### 1.6 Specialized Operations

```python
def delete_fields(self, field_names=[]):
    """Delete all fields in the list entirely from a collection."""
    for field_name in field_names:
        self.db.update_many({}, {"$unset": {field_name: 1}})
```

**PostgreSQL Compatibility:**
- ✅ Equivalent: ALTER TABLE ... DROP COLUMN ...
- ⚠️ Less common operation, typically done via migrations

## 2. Collection-Specific Write Operations

### 2.1 Cycle Collection

**Manager:** `CycleManager` (lines 344-352)

**Write Operations Found:**
- `cycle_manager.save(cycle)` - Create new cycle (subscriptions.py:49)
- `cycle_manager.update(document_id, data)` - Update cycle fields (subscriptions.py:107, :122)
- `cycle_manager.update_many(params, data)` - Bulk update dirty_stats flag (template_views.py:114-116)

**Usage Patterns:**
```python
# Creating cycle in start_subscription()
cycle = {
    "subscription_id": subscription_id,
    "start_date": start_date,
    "send_by_date": send_by_date,
    "end_date": end_date,
    "phish_header": subscription["phish_header"],
    "active": True,
    "target_count": total_targets,
    "template_ids": set(),  # Converted to list later
    "tasks": tasks
}
resp = cycle_manager.save(cycle)
cycle_id = resp["_id"]

# Updating cycle
cycle_manager.update(document_id=cycle_id, data=cycle)

# Bulk update for dirty stats
cycle_manager.update_many(
    params={"template_ids": template_id}, 
    data={"dirty_stats": True}
)
```

**PostgreSQL Schema Requirements:**
- ✅ Proposed schema includes: id, subscription_id, template_ids (JSONB), start_date, end_date, send_by_date, active, target_count
- ❌ **MISSING:** tasks (JSONB array), dirty_stats (BOOLEAN), stats (JSONB), nonhuman_stats (JSONB), manual_reports (JSONB array), phish_header (VARCHAR)

### 2.2 Subscription Collection

**Manager:** `SubscriptionManager` (lines 411-420)

**Write Operations Found:**
- `subscription_manager.save(data)` - Create subscription
- `subscription_manager.update(document_id, data)` - Update subscription (subscriptions.py:106, :123-124)
- `subscription_manager.add_to_list(document_id, field, data)` - Add to arrays (notifications.py:163-166, tasks.py:162-165)
- `subscription_manager.delete_from_list(document_id, field, data)` - Remove from target_email_list (failed_email_views.py:59-62)
- `subscription_manager.update_in_list(document_id, field, data, params)` - Update array elements (safelist_testing.py:218-221, :255-258)

**Critical Array Operations:**

```python
# Adding to notification_history array
subscription_manager.add_to_list(
    document_id=self.subscription["_id"],
    field="notification_history",
    data={
        "message_type": "...",
        "sent": datetime,
        "email_to": addresses,
        "email_from": from_address,
    }
)

# Adding tasks to array
subscription_manager.add_to_list(
    document_id=subscription["_id"],
    field="tasks",
    data=task
)

# Removing failed targets
subscription_manager.delete_from_list(
    document_id=subscription["_id"],
    field="target_email_list",
    data=target
)

# Updating specific test result in array
subscription_manager.update_in_list(
    document_id=subscription_id,
    field="test_results.$",  # Positional operator
    data=contact,
    params={"test_results.test_uuid": contact["test_uuid"]}
)
```

**PostgreSQL Schema Requirements:**
- ✅ Proposed schema includes: Most basic fields, next_templates (JSONB)
- ❌ **MISSING:** notification_history (JSONB array), test_results (JSONB array), next_test_results (JSONB array), landing_page_id (UUID FK), landing_domain (VARCHAR), landing_page_url (VARCHAR), targets_updated_username (VARCHAR), targets_updated_time (TIMESTAMP), phish_header (VARCHAR), reporting_password (VARCHAR)
- ⚠️ **CRITICAL:** tasks array and target_email_list arrays have complex nested structures and frequent array manipulation

### 2.3 Template Collection

**Manager:** `TemplateManager` (lines 435-444)

**Write Operations Found:**
- `template_manager.save(data)` - Create template (template_views.py:72)
- `template_manager.update(document_id, data)` - Update template (template_views.py:113)
- `template_manager.delete(document_id)` - Delete template (template_views.py:159)

**Usage Patterns:**
```python
# Creating template
return jsonify(template_manager.save(request.json))

# Updating template with related cycle updates
template = template_manager.get(document_id=template_id)
template.update(data)
template_manager.update(document_id=template_id, data=template)
# Also triggers cycle dirty_stats update
cycle_manager.update_many(
    params={"template_ids": template_id}, 
    data={"dirty_stats": True}
)

# Deleting template (with extensive validation)
# - Check if template is retired
# - Check if used in active cycles
# - Check if referenced in subscription templates_selected
template_manager.delete(document_id=template_id)
```

**PostgreSQL Schema Requirements:**
- ✅ Proposed schema includes: id, name, subject, html, text, retired
- ❌ **MISSING:** landing_page_id (UUID FK), sending_profile_id (UUID FK), deception_score (INTEGER), from_address (VARCHAR), retired_description (TEXT), sophisticated (JSONB array of recommendation IDs), red_flag (JSONB array of recommendation IDs), indicators (JSONB nested structure)

### 2.4 Notification Collection

**Manager:** `NotificationManager` (lines 447-456)

**Write Operations Found:**
- `notification_manager.save(data)` - Create notification
- `notification_manager.update(document_id, data)` - Update notification
- No array operations found

**PostgreSQL Schema Requirements:**
- ✅ Proposed schema matches actual schema: id, name, subject, html, task_name, text, has_attachment

### 2.5 Target Collection (MISSING FROM PROPOSED SCHEMA)

**Manager:** `TargetManager` (lines 423-432)

**Write Operations Found:**
- `target_manager.save_many(targets)` - Bulk insert targets (subscriptions.py:108)
- `target_manager.add_to_list(document_id, field, data)` - Add timeline events (landing/views.py:52-55, :101-104)

**Critical Usage:**

```python
# Creating targets in bulk during subscription start
targets = []
for target_email in subscription["target_email_list"]:
    target = {
        "cycle_id": cycle_id,
        "subscription_id": subscription_id,
        "template_id": selected_template_id,
        "email": target_email["email"],
        "first_name": target_email.get("first_name"),
        "last_name": target_email.get("last_name"),
        "position": target_email.get("position"),
        "send_date": calculated_send_date,
        "deception_level": "low|moderate|high",
        "deception_level_int": 1-6,
        "sent": False,
        "timeline": []
    }
    targets.append(target)
target_manager.save_many(targets)

# Adding to timeline array
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
```

**PostgreSQL Schema Requirements:**
- ❌ **COMPLETELY MISSING:** The target collection is not in the proposed schema at all!
- Required fields: id, cycle_id (UUID FK), subscription_id (UUID FK), template_id (UUID FK), email (VARCHAR), first_name (VARCHAR), last_name (VARCHAR), position (VARCHAR), deception_level (ENUM), deception_level_int (INTEGER), send_date (TIMESTAMP), sent (BOOLEAN), sent_date (TIMESTAMP), error (TEXT), timeline (JSONB array or separate table)

## 3. Other Collections Write Operations

Additional collections found in con-pca-api that are NOT in scope for this migration but exist in the system:

- `customer` collection - CustomerManager
- `landing_page` collection - LandingPageManager
- `sending_profile` collection - SendingProfileManager
- `recommendation` collection - RecommendationManager
- `nonhuman` collection - NonHumanManager
- `user` collection - UserManager
- `logging` collection - LoggingManager (with TTL index)
- `failed_emails` collection - FailedEmailManager
- `config` collection - ConfigManager

These are referenced but not included in MBA-322 Phase 1 scope.

## 4. Transaction Patterns

Several operations span multiple collections that may benefit from PostgreSQL transactions:

### 4.1 Start Subscription Transaction
```python
# subscriptions.py:30-109
cycle = cycle_manager.save(cycle)  # 1. Create cycle
subscription_manager.update(subscription_id, update_data)  # 2. Update subscription
target_manager.save_many(targets)  # 3. Create all targets
```

**Recommendation:** Wrap in PostgreSQL transaction to ensure atomicity.

### 4.2 Template Deletion Transaction
```python
# template_views.py:119-160
# 1. Validate template is retired
# 2. Check for usage in cycles
# 3. Check for usage in subscriptions
# 4. Delete template
template_manager.delete(document_id=template_id)
```

**Recommendation:** Read-only validation, then single delete. May not need explicit transaction.

### 4.3 Stop Subscription Transaction
```python
# subscriptions.py:112-126
cycle_manager.update(cycle["_id"], {"active": False})  # 1. Deactivate cycle
subscription_manager.update(subscription_id, {"status": "stopped", "tasks": []})  # 2. Stop subscription
```

**Recommendation:** Wrap in PostgreSQL transaction to ensure consistency.

## 5. Schema Compatibility Assessment

### 5.1 Cycles Collection
| Operation | MongoDB | PostgreSQL Proposed | Compatible | Notes |
|-----------|---------|---------------------|------------|-------|
| Insert | insert_one | INSERT INTO | ✅ | Direct mapping |
| Update | update_one | UPDATE WHERE id = | ✅ | Direct mapping |
| Bulk Update | update_many | UPDATE WHERE id IN | ✅ | Direct mapping |
| Template IDs Array | document field | JSONB | ⚠️ | Proposed as JSONB, but simple string array might suffice |
| Tasks Array | document field | **MISSING** | ❌ | Not in proposed schema |
| Dirty Stats Flag | document field | **MISSING** | ❌ | Not in proposed schema |

### 5.2 Subscriptions Collection
| Operation | MongoDB | PostgreSQL Proposed | Compatible | Notes |
|-----------|---------|---------------------|------------|-------|
| Insert | insert_one | INSERT INTO | ✅ | Direct mapping |
| Update | update_one | UPDATE WHERE id = | ✅ | Direct mapping |
| Add to notification_history | $push | **MISSING FIELD** | ❌ | Field not in schema |
| Add to tasks | $push | JSONB append | ⚠️ | Proposed as JSONB, complex |
| Delete from target_email_list | $pull | JSONB remove | ⚠️ | Proposed as JSONB, complex |
| Update in test_results | positional $ | JSONB update | ⚠️ | Field not in schema |

### 5.3 Templates Collection
| Operation | MongoDB | PostgreSQL Proposed | Compatible | Notes |
|-----------|---------|---------------------|------------|-------|
| Insert | insert_one | INSERT INTO | ✅ | Direct mapping |
| Update | update_one | UPDATE WHERE id = | ✅ | Direct mapping |
| Delete | delete_one | DELETE FROM WHERE id = | ✅ | Direct mapping |
| Sophisticated/Red Flag arrays | document fields | **MISSING** | ❌ | Not in proposed schema |
| Indicators nested object | document field | **MISSING** | ❌ | Not in proposed schema |

### 5.4 Notifications Collection
| Operation | MongoDB | PostgreSQL Proposed | Compatible | Notes |
|-----------|---------|---------------------|------------|-------|
| All operations | Standard CRUD | Standard SQL | ✅ | Full compatibility |

### 5.5 Targets Collection
| Operation | MongoDB | PostgreSQL Proposed | Compatible | Notes |
|-----------|---------|---------------------|------------|-------|
| **ALL OPERATIONS** | Standard CRUD + arrays | **MISSING** | ❌ | **Collection not in proposed schema** |

## 6. Recommendations

### 6.1 Immediate Actions Required

1. **Add Target Collection:** The target table MUST be added to the schema. This is a critical collection with thousands of records per cycle.

2. **Add Missing Fields:** All missing fields identified above must be added to ensure no data loss.

3. **Array Operation Strategy:** Implement hybrid approach (see nested_document_strategy.md) for:
   - Simple arrays (template_ids, templates_selected, next_templates) → PostgreSQL array type or JSONB
   - Complex nested arrays with frequent manipulation (tasks, timeline, notification_history) → Separate normalized tables

4. **Transaction Boundaries:** Define explicit transaction boundaries for multi-collection operations.

### 6.2 Migration Strategy

1. **Phase 1:** Schema design (current) - Add all missing elements
2. **Phase 2:** Create parallel write operations to both MongoDB and PostgreSQL
3. **Phase 3:** Data migration with validation
4. **Phase 4:** Switch reads to PostgreSQL
5. **Phase 5:** Deprecate MongoDB

### 6.3 Performance Considerations

- **Indexes:** The proposed indexes are a good start, but additional indexes needed for:
  - targets(cycle_id, subscription_id, template_id, email, sent, send_date)
  - cycles(active, dirty_stats)
  - subscriptions(status, archived, customer_id)

- **JSONB vs Normalized:** See nested_document_strategy.md for detailed analysis

## 7. Conclusion

The proposed PostgreSQL schema in MBA-322 provides a foundation but has critical gaps:

1. ❌ Missing entire target collection (thousands of records)
2. ❌ Missing ~20 fields across existing collections
3. ⚠️ Unclear strategy for array manipulation operations
4. ⚠️ No transaction boundary definitions
5. ✅ Core CRUD operations are compatible

**Next Steps:**
1. Review and update schema/postgresql/001_initial_schema.sql with all missing elements
2. Define array operation strategy in nested_document_strategy.md
3. Create comprehensive index strategy in schema/postgresql/002_indexes.sql

---

**Prepared by:** Devin AI  
**Session:** https://app.devin.ai/sessions/df7340be39754e4088080fa2b29c0e41  
**Date:** October 8, 2025
