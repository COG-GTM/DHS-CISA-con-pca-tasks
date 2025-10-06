
package e2e

import (
	"io"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestE2E_HealthCheck(t *testing.T) {
	srv, cleanup := setupTestServer(t)
	defer cleanup()

	resp, err := http.Get(srv.URL + "/tasks/")
	require.NoError(t, err)
	defer resp.Body.Close()

	assert.Equal(t, http.StatusOK, resp.StatusCode)
	
	body, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	assert.Equal(t, "Up and running!", string(body))
}

func TestE2E_PDFReport(t *testing.T) {
	srv, cleanup := setupTestServer(t)
	defer cleanup()

	cycleID := "test-cycle-id"
	reportType := "cycle"

	resp, err := http.Get(srv.URL + "/tasks/" + cycleID + "/reports/" + reportType + "/pdf")
	require.NoError(t, err)
	defer resp.Body.Close()

	assert.Equal(t, http.StatusOK, resp.StatusCode)
	assert.Equal(t, "application/json", resp.Header.Get("Content-Type"))

	body, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	assert.Contains(t, string(body), "report pdf complete")
	assert.Contains(t, string(body), cycleID)
}

func TestE2E_PDFReport_DifferentReportTypes(t *testing.T) {
	srv, cleanup := setupTestServer(t)
	defer cleanup()

	tests := []struct {
		name       string
		cycleID    string
		reportType string
		wantStatus int
	}{
		{
			name:       "cycle report",
			cycleID:    "cycle-001",
			reportType: "cycle",
			wantStatus: http.StatusOK,
		},
		{
			name:       "monthly report",
			cycleID:    "cycle-002",
			reportType: "monthly",
			wantStatus: http.StatusOK,
		},
		{
			name:       "yearly report",
			cycleID:    "cycle-003",
			reportType: "yearly",
			wantStatus: http.StatusOK,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			resp, err := http.Get(srv.URL + "/tasks/" + tt.cycleID + "/reports/" + tt.reportType + "/pdf")
			require.NoError(t, err)
			defer resp.Body.Close()

			assert.Equal(t, tt.wantStatus, resp.StatusCode)
		})
	}
}

func TestE2E_InvalidRoute(t *testing.T) {
	srv, cleanup := setupTestServer(t)
	defer cleanup()

	resp, err := http.Get(srv.URL + "/tasks/invalid/route")
	require.NoError(t, err)
	defer resp.Body.Close()

	assert.Equal(t, http.StatusNotFound, resp.StatusCode)
}

func TestE2E_MethodNotAllowed(t *testing.T) {
	srv, cleanup := setupTestServer(t)
	defer cleanup()

	resp, err := http.Post(srv.URL+"/tasks/", "application/json", nil)
	require.NoError(t, err)
	defer resp.Body.Close()

	assert.Equal(t, http.StatusMethodNotAllowed, resp.StatusCode)
}

func TestE2E_ConcurrentRequests(t *testing.T) {
	srv, cleanup := setupTestServer(t)
	defer cleanup()

	concurrency := 10
	done := make(chan bool, concurrency)

	for i := 0; i < concurrency; i++ {
		go func(id int) {
			resp, err := http.Get(srv.URL + "/tasks/")
			if err != nil {
				t.Errorf("Request %d failed: %v", id, err)
				done <- false
				return
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusOK {
				t.Errorf("Request %d got status %d", id, resp.StatusCode)
				done <- false
				return
			}

			done <- true
		}(i)
	}

	for i := 0; i < concurrency; i++ {
		success := <-done
		assert.True(t, success, "Request should succeed")
	}
}
