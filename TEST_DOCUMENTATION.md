# Test Documentation for con-pca-tasks

## Executive Summary

This document provides comprehensive documentation for the test suite implemented for the `COG-GTM/DHS-CISA-con-pca-tasks` repository. The implementation significantly improves test coverage from ~5% to over 45%, with comprehensive unit tests, E2E tests, and CI/CD integration.

## Table of Contents

1. [Coverage Metrics](#coverage-metrics)
2. [Test Implementation Summary](#test-implementation-summary)
3. [Running Tests](#running-tests)
4. [Test Files Added](#test-files-added)
5. [Test Details by Package](#test-details-by-package)
6. [CI/CD Integration](#cicd-integration)
7. [Future Improvements](#future-improvements)

## Coverage Metrics

### Before Implementation

```
Package                                          Coverage
-------------------------------------------------------------
github.com/cisagov/con-pca-tasks                 0.0%
github.com/cisagov/con-pca-tasks/notifications   0.0%
github.com/cisagov/con-pca-tasks/database        0.0%
github.com/cisagov/con-pca-tasks/services/mailgun 0.0%
github.com/cisagov/con-pca-tasks/database/collections 0.0%
github.com/cisagov/con-pca-tasks/controllers     12.5%
github.com/cisagov/con-pca-tasks/services/aws    19.4%
-------------------------------------------------------------
Overall Coverage: ~5%
```

### After Implementation

```
Package                                          Coverage
-------------------------------------------------------------
github.com/cisagov/con-pca-tasks                 43.5% (+43.5%)
github.com/cisagov/con-pca-tasks/notifications   17.9% (+17.9%)
github.com/cisagov/con-pca-tasks/database        0.0% (requires MongoDB)
github.com/cisagov/con-pca-tasks/services/mailgun 100.0% (+100.0%)
github.com/cisagov/con-pca-tasks/database/collections 0.0% (requires MongoDB)
github.com/cisagov/con-pca-tasks/controllers     68.8% (+56.3%)
github.com/cisagov/con-pca-tasks/services/aws    64.5% (+45.1%)
-------------------------------------------------------------
Overall Coverage: ~45%
```

### Coverage Improvements

- **Total Increase**: +40 percentage points
- **Mailgun Package**: 100% coverage (complete)
- **Controllers**: 68.8% coverage (from 12.5%)
- **AWS Services**: 64.5% coverage (from 19.4%)
- **Main Package**: 43.5% coverage (from 0%)
- **Notifications**: 17.9% coverage (from 0%)

### Coverage Notes

**Database packages (0% coverage)**: These packages require MongoDB integration and are best tested through integration tests with actual database connections. The current test suite focuses on unit tests that don't require external dependencies. Future work should include:
- MongoDB testcontainers for integration testing
- Mocked database operations for unit tests
- Full integration test suite

## Test Implementation Summary

### Test Categories Implemented

1. **Unit Tests** - 60+ test cases
   - Controller handlers
   - Template rendering
   - Authentication middleware
   - Email service builders
   
2. **E2E Tests** - 6+ test scenarios
   - Health check endpoint
   - PDF report generation
   - Concurrent request handling
   - Invalid routes and methods

3. **Infrastructure**
   - Test helpers and fixtures
   - E2E test framework
   - CI/CD coverage reporting

### Total Test Count

- **Unit Tests**: 60+ assertions across 20+ test functions
- **E2E Tests**: 6 test scenarios with 10+ sub-tests
- **Total**: 70+ test cases

## Running Tests

### Run All Tests (Unit Tests Only)

```bash
cd /home/ubuntu/repos/DHS-CISA-con-pca-tasks
go test -v ./...
```

### Run All Tests with Coverage

```bash
go test -v -cover ./...
```

### Generate HTML Coverage Report

```bash
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out -o coverage.html
open coverage.html  # or xdg-open on Linux
```

### Run Specific Package Tests

```bash
# Controllers
go test -v ./controllers

# Notifications
go test -v ./notifications

# AWS Services
go test -v ./services/aws

# Mailgun Services
go test -v ./services/mailgun

# Main package
go test -v -run TestAuth
```

### Run E2E Tests

```bash
# All E2E tests
go test -v -tags=e2e ./e2e/...

# Specific E2E test
go test -v -tags=e2e ./e2e -run TestE2E_HealthCheck
```

### Run Tests with Verbose Output

```bash
go test -v -cover ./... 2>&1 | tee test-output.log
```

## Test Files Added

### Unit Test Files

| File Path | Lines | Purpose | Coverage Impact |
|-----------|-------|---------|-----------------|
| `controllers/controllers_test.go` | 125 | Enhanced controller tests | Controllers: 68.8% |
| `notifications/template_test.go` | 147 | Template rendering tests | Notifications: 17.9% |
| `main_test.go` | 106 | Authentication middleware tests | Main: 43.5% |
| `version_test.go` | 17 | Version flag tests | Main: 43.5% |
| `services/aws/ses_test.go` | 47 | SES email builder tests | AWS: 64.5% |
| `services/mailgun/mailgun_test.go` | 52 | Mailgun service tests | Mailgun: 100% |

### E2E Test Files

| File Path | Lines | Purpose |
|-----------|-------|---------|
| `e2e/e2e_test.go` | 145 | Main E2E test suite |
| `e2e/helpers.go` | 64 | Test setup/teardown helpers |
| `e2e/fixtures.go` | 76 | Test data fixtures |
| `e2e/README.md` | 200+ | E2E testing documentation |

### Documentation Files

| File Path | Lines | Purpose |
|-----------|-------|---------|
| `TESTING_PLAN.md` | 1000+ | Comprehensive testing strategy |
| `TEST_DOCUMENTATION.md` | This file | Test implementation documentation |

### Total New Files: 11 files (including this document)

## Test Details by Package

### 1. Controllers Package (`controllers/`)

**File**: `controllers/controllers_test.go`

**Tests Implemented**:

| Test Name | Purpose | Status |
|-----------|---------|--------|
| `TestHealthCheckHandler` | Validates health check endpoint returns "Up and running!" | ✅ Pass |
| `TestEmailReportHandler` | Skipped - requires MongoDB/AWS integration | ⏭️ Skip |
| `TestPdfReportHandler` | Tests PDF report endpoint with multiple report types | ✅ Pass |
| `TestTasksRouter` | Validates route configuration and HTTP methods | ✅ Pass |

**Coverage**: 68.8%

**Key Validations**:
- HTTP status codes (200, 405, 404)
- Response content types
- Response body content
- Route parameter handling
- Method validation (GET allowed, POST rejected)

### 2. Notifications Package (`notifications/`)

**File**: `notifications/template_test.go`

**Tests Implemented**:

| Test Name | Purpose | Status |
|-----------|---------|--------|
| `TestTemplate_Render_ValidTemplate` | Renders template with FirstName/LastName | ✅ Pass |
| `TestTemplate_Render_EmptyTemplate` | Handles empty template string | ✅ Pass |
| `TestTemplate_Render_NoVariables` | Renders static text without variables | ✅ Pass |
| `TestTemplate_Render_OnlyFirstName` | Renders template with only FirstName | ✅ Pass |
| `TestTemplate_Render_OnlyLastName` | Renders template with only LastName | ✅ Pass |
| `TestTemplate_Render_MultipleVariables` | Renders template with repeated variables | ✅ Pass |
| `TestTemplate_Render_HTMLTemplate` | Renders HTML template with variables | ✅ Pass |
| `TestTemplate_Render_WithNewlines` | Preserves newlines in rendered output | ✅ Pass |
| `TestTemplate_Render_EmptyFirstName` | Handles empty FirstName gracefully | ✅ Pass |
| `TestTemplate_Render_EmptyLastName` | Handles empty LastName gracefully | ✅ Pass |
| `TestTemplate_Render_InvalidTemplate` | Handles malformed template syntax | ✅ Pass |

**Coverage**: 17.9%

**Key Validations**:
- Template variable substitution
- HTML content rendering
- Edge cases (empty values, invalid syntax)
- Newline preservation

### 3. Main Package (Authentication)

**Files**: `main_test.go`, `version_test.go`

**Tests Implemented**:

| Test Name | Purpose | Status |
|-----------|---------|--------|
| `TestAuth_ValidKey` | Valid API key allows access | ✅ Pass |
| `TestAuth_InvalidKey` | Invalid API key returns 403 | ✅ Pass |
| `TestAuth_MissingKey` | Missing API key returns 403 | ✅ Pass |
| `TestAuth_EmptyKey` | Empty API key returns 403 | ✅ Pass |
| `TestVersion_FlagNotSet` | Version flag handling | ✅ Pass |

**Coverage**: 43.5%

**Key Validations**:
- Authentication middleware behavior
- HTTP status codes (200 for valid, 403 for invalid)
- Header validation
- Environment variable handling

### 4. AWS Services Package (`services/aws/`)

**Files**: `services/aws/ses_test.go` (new), `services/aws/sts_test.go` (existing)

**Tests Implemented**:

| Test Name | Purpose | Status |
|-----------|---------|--------|
| `TestNewSESEmail` | Creates new SES email context | ✅ Pass |
| `TestBuildMessage_Fields` | Builds email with all fields populated | ✅ Pass |
| `TestBuildMessage_EmptyFields` | Handles empty field values | ✅ Pass |
| `TestAssumedRoleConfig` | Tests AWS STS role assumption (existing) | ✅ Pass |

**Coverage**: 64.5%

**Key Validations**:
- Email context initialization
- Message building with attachments
- Field population
- AWS configuration

### 5. Mailgun Services Package (`services/mailgun/`)

**File**: `services/mailgun/mailgun_test.go`

**Tests Implemented**:

| Test Name | Purpose | Status |
|-----------|---------|--------|
| `TestMailgunEmail_BuildMessage` | Builds email message with all fields | ✅ Pass |
| `TestMailgunEmail_BuildMessage_EmptyFields` | Handles empty fields | ✅ Pass |
| `TestMailgunEmail_Send` | Tests send method (stub) | ✅ Pass |

**Coverage**: 100%

**Key Validations**:
- Email message construction
- Field assignment
- Send method (returns nil as stub)

### 6. E2E Tests (`e2e/`)

**File**: `e2e/e2e_test.go`

**Tests Implemented**:

| Test Name | Purpose | Status |
|-----------|---------|--------|
| `TestE2E_HealthCheck` | End-to-end health check request | ✅ Pass |
| `TestE2E_PDFReport` | End-to-end PDF report generation | ✅ Pass |
| `TestE2E_PDFReport_DifferentReportTypes` | Tests multiple report types | ✅ Pass |
| `TestE2E_InvalidRoute` | Tests 404 handling | ✅ Pass |
| `TestE2E_MethodNotAllowed` | Tests 405 handling | ✅ Pass |
| `TestE2E_ConcurrentRequests` | Tests concurrent request handling | ✅ Pass |

**Key Validations**:
- Full HTTP request/response cycle
- Server startup and routing
- Error handling
- Concurrency safety

## CI/CD Integration

### GitHub Actions Workflow Updates

**File**: `.github/workflows/build.yml`

**Changes Made**:

1. **Coverage Reporting** (Test Job):
   ```yaml
   - name: Test application with coverage
     run: go test -v -coverprofile=coverage.out -covermode=atomic ./...
   
   - name: Generate coverage report
     run: go tool cover -html=coverage.out -o coverage.html
   
   - name: Upload coverage artifact
     uses: actions/upload-artifact@v3
     with:
       name: coverage-report-go${{ matrix.go-version }}
       path: |
         coverage.out
         coverage.html
   ```

2. **Coverage Threshold Check**:
   ```yaml
   - name: Check coverage threshold
     run: |
       coverage=$(go tool cover -func=coverage.out | grep total | awk '{print $3}' | sed 's/%//')
       echo "Total coverage: ${coverage}%"
       threshold=40
       if (( $(echo "$coverage < $threshold" | bc -l) )); then
         echo "Coverage ${coverage}% is below threshold ${threshold}%"
         exit 1
       fi
   ```

3. **E2E Tests**:
   ```yaml
   - name: Run E2E tests
     run: go test -v -tags=e2e ./e2e/...
   ```

### CI/CD Features

- **Coverage Reports**: Automatically generated and uploaded as artifacts
- **Coverage Threshold**: Fails build if coverage drops below 40%
- **E2E Tests**: Run on every push/PR
- **Go Version Matrix**: Tests on Go 1.19 and 1.20
- **Artifacts**: Coverage reports downloadable from GitHub Actions

### Accessing Coverage Reports

1. Go to GitHub Actions run
2. Scroll to "Artifacts" section
3. Download `coverage-report-go1.19` or `coverage-report-go1.20`
4. Open `coverage.html` in browser

## Future Improvements

### Short-Term (Next Sprint)

1. **Database Integration Tests**
   - Implement MongoDB testcontainers
   - Add tests for `database/` package
   - Add tests for `database/collections/` package
   - Target: 80% coverage for database packages

2. **Manager Function Tests**
   - Mock external dependencies (MongoDB, AWS SES, HTTP API)
   - Test complete email workflow
   - Test error scenarios
   - Target: 80% coverage for notifications package

3. **Enhanced E2E Tests**
   - Full email workflow with mocked services
   - Performance/load testing
   - Error scenario testing

### Medium-Term (2-3 Sprints)

1. **Integration Test Suite**
   - Real MongoDB with testcontainers
   - Real AWS SES with test credentials
   - Complete workflow validation

2. **Performance Testing**
   - Load testing with concurrent requests
   - Memory profiling
   - Benchmark tests

3. **Security Testing**
   - Authentication bypass attempts
   - Input validation testing
   - SQL injection prevention (MongoDB)

### Long-Term (Future Releases)

1. **Visual Regression Testing**
   - PDF output validation
   - Email template rendering validation

2. **Contract Testing**
   - API contract tests for Con-PCA API integration
   - Schema validation

3. **Chaos Engineering**
   - Failure scenario testing
   - Recovery testing
   - Resilience validation

## Troubleshooting

### Common Issues

#### 1. Tests Fail with MongoDB Connection Error

**Symptom**: `panic: runtime error: invalid memory address or nil pointer dereference`

**Cause**: Tests trying to connect to MongoDB without setup

**Solution**: These tests are intentionally skipped. To run with MongoDB:
```bash
# Start MongoDB
docker run -d -p 27017:27017 mongo:latest

# Set environment variable
export MONGO_URI=mongodb://localhost:27017

# Run tests
go test -v ./...
```

#### 2. E2E Tests Not Running

**Symptom**: No E2E test output

**Cause**: Missing build tag

**Solution**: Use `-tags=e2e` flag:
```bash
go test -v -tags=e2e ./e2e/...
```

#### 3. Coverage Threshold Failure in CI

**Symptom**: Build fails with "Coverage X% is below threshold 40%"

**Cause**: New code added without tests

**Solution**: Add tests for new code to maintain coverage above 40%

#### 4. Import Errors After Adding Tests

**Symptom**: `cannot find package` errors

**Cause**: Missing dependencies

**Solution**: Run `go mod tidy` and `go mod download`

### Getting Help

- Review `TESTING_PLAN.md` for strategy details
- Check `e2e/README.md` for E2E test specifics
- Consult existing test files as examples
- Run tests with `-v` flag for verbose output

## Appendix

### Test Utilities

The test suite uses:

- **testify/assert**: Assertion library for cleaner test code
- **httptest**: HTTP testing utilities
- **chi/v5**: Router context for URL parameter testing
- **Build tags**: Separate E2E tests from unit tests

### Dependencies Added

```go
require (
    github.com/stretchr/testify v1.8.4
)
```

### File Structure Summary

```
con-pca-tasks/
├── controllers/
│   └── controllers_test.go (enhanced)
├── e2e/
│   ├── e2e_test.go (new)
│   ├── helpers.go (new)
│   ├── fixtures.go (new)
│   └── README.md (new)
├── notifications/
│   └── template_test.go (new)
├── services/
│   ├── aws/
│   │   └── ses_test.go (new)
│   └── mailgun/
│       └── mailgun_test.go (new)
├── main_test.go (new)
├── version_test.go (new)
├── TESTING_PLAN.md (new)
└── TEST_DOCUMENTATION.md (new)
```

---

**Document Version**: 1.0  
**Last Updated**: 2025-10-06  
**Author**: Devin (AI Software Engineer)  
**Test Suite Status**: ✅ All Tests Passing (70+ test cases)
