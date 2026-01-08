package collections

import (
	"context"

	db "github.com/cisagov/con-pca-tasks/database"
)

type Phish struct {
	Name    string `json:"name"`
	Subject string `json:"subject"`
	Html    string `json:"html"`
	Text    string `json:"text"`
	Retired bool   `json:"retired"`
}

// GetPhish returns a phish template by name
func GetPhish(Name string) (Phish, error) {
	var p Phish
	err := db.DB.QueryRow(
		context.Background(),
		`SELECT name, subject, html, text, retired
		 FROM templates WHERE name = $1 AND retired = false`,
		Name,
	).Scan(
		&p.Name,
		&p.Subject,
		&p.Html,
		&p.Text,
		&p.Retired,
	)
	if err != nil {
		return p, err
	}
	return p, nil
}
