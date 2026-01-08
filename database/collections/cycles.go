package collections

import (
	"context"
	"encoding/json"
	"time"

	db "github.com/cisagov/con-pca-tasks/database"
)

type Cycle struct {
	SubscriptionId string    `json:"subscription_id"`
	TemplateIds    []string  `json:"template_ids"`
	StartDate      time.Time `json:"start_date"`
	EndDate        time.Time `json:"end_date"`
	SendByDate     time.Time `json:"send_by_date"`
	Active         bool      `json:"active"`
	TargetCount    int       `json:"target_count"`
}

// GetCycle returns a cycle by id
func GetCycle(id string) (Cycle, error) {
	var c Cycle
	var templateIdsJSON []byte

	err := db.DB.QueryRow(
		context.Background(),
		`SELECT subscription_id, template_ids, start_date, end_date, send_by_date, active, target_count
		 FROM cycles WHERE id = $1`,
		id,
	).Scan(
		&c.SubscriptionId,
		&templateIdsJSON,
		&c.StartDate,
		&c.EndDate,
		&c.SendByDate,
		&c.Active,
		&c.TargetCount,
	)
	if err != nil {
		return c, err
	}

	if templateIdsJSON != nil {
		if err := json.Unmarshal(templateIdsJSON, &c.TemplateIds); err != nil {
			return c, err
		}
	}

	return c, nil
}
