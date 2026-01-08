package collections

import (
	"context"
	"encoding/json"
	"time"

	db "github.com/cisagov/con-pca-tasks/database"
)

type (
	TargetEmail struct {
		Email     string `json:"email"`
		FirstName string `json:"first_name"`
		LastName  string `json:"last_name"`
		Position  string `json:"position"`
	}

	PrimaryContact struct {
		FirstName   string `json:"first_name"`
		LastName    string `json:"last_name"`
		Title       string `json:"title"`
		OfficePhone string `json:"office_phone"`
		MobilePhone string `json:"mobile_phone"`
		Email       string `json:"email"`
		Notes       string `json:"notes"`
		Active      bool   `json:"active"`
	}

	SubscriptionTasks struct {
		TaskUUID      string    `json:"task_uuid"`
		TaskType      string    `json:"task_type"`
		ScheduledDate time.Time `json:"scheduled_date"`
		Executed      bool      `json:"executed"`
		ExecutedDate  time.Time `json:"executed_date"`
		Error         string    `json:"error"`
	}

	Subscription struct {
		Name                   string              `json:"name"`
		CustomerID             string              `json:"customer_id"`
		SendingProfileID       string              `json:"sending_profile_id"`
		TargetDomain           string              `json:"target_domain"`
		Customer               string              `json:"customer"`
		StartDate              time.Time           `json:"start_date"`
		PrimaryContact         PrimaryContact      `json:"primary_contact"`
		AdminEmail             string              `json:"admin_email"`
		OperatorEmail          string              `json:"operator_email"`
		Status                 string              `json:"status"`
		CycleStartDate         string              `json:"cycle_start_date"`
		TargetEmailList        []TargetEmail       `json:"target_email_list"`
		TemplatesSelected      []string            `json:"templates_selected"`
		NextTemplates          []string            `json:"next_templates"`
		ContinuousSubscription bool                `json:"continuous_subscription"`
		BufferTimeMinutes      int                 `json:"buffer_time_minutes"`
		CycleLengthMinutes     int                 `json:"cycle_length_minutes"`
		CooldownMinutes        int                 `json:"cooldown_minutes"`
		ReportFrequencyMinutes int                 `json:"report_frequency_minutes"`
		Tasks                  []SubscriptionTasks `json:"tasks"`
		Processing             bool                `json:"processing"`
		Archived               bool                `json:"archived"`
	}
)

// GetSubscription returns a subscription by id
func GetSubscription(id string) (Subscription, error) {
	var s Subscription
	var primaryContactJSON, targetEmailListJSON, templatesSelectedJSON, nextTemplatesJSON, tasksJSON []byte

	err := db.DB.QueryRow(
		context.Background(),
		`SELECT name, customer_id, sending_profile_id, target_domain, customer, start_date,
		        primary_contact, admin_email, operator_email, status, cycle_start_date,
		        target_email_list, templates_selected, next_templates, continuous_subscription,
		        buffer_time_minutes, cycle_length_minutes, cooldown_minutes, report_frequency_minutes,
		        tasks, processing, archived
		 FROM subscriptions WHERE id = $1`,
		id,
	).Scan(
		&s.Name,
		&s.CustomerID,
		&s.SendingProfileID,
		&s.TargetDomain,
		&s.Customer,
		&s.StartDate,
		&primaryContactJSON,
		&s.AdminEmail,
		&s.OperatorEmail,
		&s.Status,
		&s.CycleStartDate,
		&targetEmailListJSON,
		&templatesSelectedJSON,
		&nextTemplatesJSON,
		&s.ContinuousSubscription,
		&s.BufferTimeMinutes,
		&s.CycleLengthMinutes,
		&s.CooldownMinutes,
		&s.ReportFrequencyMinutes,
		&tasksJSON,
		&s.Processing,
		&s.Archived,
	)
	if err != nil {
		return s, err
	}

	if primaryContactJSON != nil {
		if err := json.Unmarshal(primaryContactJSON, &s.PrimaryContact); err != nil {
			return s, err
		}
	}
	if targetEmailListJSON != nil {
		if err := json.Unmarshal(targetEmailListJSON, &s.TargetEmailList); err != nil {
			return s, err
		}
	}
	if templatesSelectedJSON != nil {
		if err := json.Unmarshal(templatesSelectedJSON, &s.TemplatesSelected); err != nil {
			return s, err
		}
	}
	if nextTemplatesJSON != nil {
		if err := json.Unmarshal(nextTemplatesJSON, &s.NextTemplates); err != nil {
			return s, err
		}
	}
	if tasksJSON != nil {
		if err := json.Unmarshal(tasksJSON, &s.Tasks); err != nil {
			return s, err
		}
	}

	return s, nil
}
