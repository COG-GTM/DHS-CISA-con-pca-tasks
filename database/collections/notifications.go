package collections

import (
	"context"

	db "github.com/cisagov/con-pca-tasks/database"
)

type Notification struct {
	Name          string `json:"name"`
	Subject       string `json:"subject"`
	Html          string `json:"html"`
	TaskName      string `json:"task_name"`
	Text          string `json:"text"`
	HasAttachment bool   `json:"has_attachment"`
}

// GetNotification returns a notification template by task name
func GetNotification(TaskName string) (Notification, error) {
	var n Notification
	err := db.DB.QueryRow(
		context.Background(),
		`SELECT name, subject, html, task_name, text, has_attachment
		 FROM notifications WHERE task_name = $1`,
		TaskName,
	).Scan(
		&n.Name,
		&n.Subject,
		&n.Html,
		&n.TaskName,
		&n.Text,
		&n.HasAttachment,
	)
	if err != nil {
		return n, err
	}
	return n, nil
}
