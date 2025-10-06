package mailgun

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestMailgunEmail_BuildMessage(t *testing.T) {
	email := &MailgunEmail{}

	to := "test@example.com"
	cc := "cc@example.com"
	bcc := "bcc@example.com"
	subject := "Test Subject"
	html := "<p>Test HTML</p>"
	text := "Test Text"

	email.BuildMessage(to, cc, bcc, subject, html, text)

	assert.Equal(t, to, email.To)
	assert.Equal(t, cc, email.Cc)
	assert.Equal(t, bcc, email.Bcc)
	assert.Equal(t, subject, email.Subject)
	assert.Equal(t, html, email.Html)
	assert.Equal(t, text, email.Text)
}

func TestMailgunEmail_BuildMessage_EmptyFields(t *testing.T) {
	email := &MailgunEmail{}

	email.BuildMessage("", "", "", "", "", "")

	assert.Empty(t, email.To)
	assert.Empty(t, email.Cc)
	assert.Empty(t, email.Bcc)
	assert.Empty(t, email.Subject)
	assert.Empty(t, email.Html)
	assert.Empty(t, email.Text)
}

func TestMailgunEmail_Send(t *testing.T) {
	email := &MailgunEmail{
		To:      "test@example.com",
		Subject: "Test",
		Text:    "Test message",
	}

	err := email.Send()

	assert.NoError(t, err)
}
