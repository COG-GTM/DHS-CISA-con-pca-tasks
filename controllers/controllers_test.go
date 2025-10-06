package controllers

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
)

func TestHealthCheckHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/tasks", nil)
	w := httptest.NewRecorder()
	healthCheckHandler(w, req)
	res := w.Result()
	defer res.Body.Close()
	data, err := io.ReadAll(res.Body)
	if err != nil {
		t.Errorf("expected error to be nil got %v", err)
	}
	if string(data) != "Up and running!" {
		t.Errorf("expected 'Up and running!', but got %v", string(data))
	}
}

func TestEmailReportHandler(t *testing.T) {
	t.Skip("Skipping integration test - requires MongoDB and AWS setup. Use E2E tests instead.")
}

func TestPdfReportHandler(t *testing.T) {
	tests := []struct {
		name       string
		cycleID    string
		reportType string
		wantStatus int
		wantBody   string
	}{
		{
			name:       "valid cycle PDF report",
			cycleID:    "test-cycle-id",
			reportType: "cycle",
			wantStatus: http.StatusOK,
			wantBody:   "cycle report pdf complete! Cycle id: test-cycle-id",
		},
		{
			name:       "valid monthly PDF report",
			cycleID:    "monthly-cycle-id",
			reportType: "monthly",
			wantStatus: http.StatusOK,
			wantBody:   "monthly report pdf complete! Cycle id: monthly-cycle-id",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/tasks/"+tt.cycleID+"/reports/"+tt.reportType+"/pdf", nil)
			w := httptest.NewRecorder()

			rctx := chi.NewRouteContext()
			rctx.URLParams.Add("cycle_id", tt.cycleID)
			rctx.URLParams.Add("report_type", tt.reportType)
			req = req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))

			pdfReportHandler(w, req)

			res := w.Result()
			defer res.Body.Close()

			assert.Equal(t, tt.wantStatus, res.StatusCode)
			assert.Equal(t, "application/json", res.Header.Get("Content-Type"))

			data, err := io.ReadAll(res.Body)
			assert.NoError(t, err)
			assert.Equal(t, tt.wantBody, string(data))
		})
	}
}

func TestTasksRouter(t *testing.T) {
	router := TasksRouter()

	tests := []struct {
		name       string
		method     string
		path       string
		wantStatus int
	}{
		{
			name:       "health check GET",
			method:     http.MethodGet,
			path:       "/",
			wantStatus: http.StatusOK,
		},
		{
			name:       "pdf report GET",
			method:     http.MethodGet,
			path:       "/test-id/reports/cycle/pdf",
			wantStatus: http.StatusOK,
		},
		{
			name:       "health check POST not allowed",
			method:     http.MethodPost,
			path:       "/",
			wantStatus: http.StatusMethodNotAllowed,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(tt.method, tt.path, nil)
			w := httptest.NewRecorder()

			router.ServeHTTP(w, req)

			res := w.Result()
			defer res.Body.Close()

			assert.Equal(t, tt.wantStatus, res.StatusCode)
		})
	}
}
