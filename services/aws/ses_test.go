package aws

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNewSESEmail(t *testing.T) {
	email := NewSESEmail()

	assert.NotNil(t, email)
	assert.IsType(t, &SESEmail{}, email)
	assert.Empty(t, email.To)
	assert.Empty(t, email.Cc)
	assert.Empty(t, email.Bcc)
	assert.Empty(t, email.FileName)
}

func TestBuildMessage_Fields(t *testing.T) {
	email := NewSESEmail()

	to := "recipient@example.com"
	cc := "cc@example.com"
	bcc := "bcc@example.com"
	subject := "Test Subject"
	html := "<p>Test HTML content</p>"
	text := "Test plain text content"
	fileName := "test.pdf"

	email.BuildMessage(to, cc, bcc, subject, html, text, fileName)

	assert.Equal(t, to, email.To)
	assert.Equal(t, cc, email.Cc)
	assert.Equal(t, bcc, email.Bcc)
	assert.Equal(t, fileName, email.FileName)
	assert.NotNil(t, email.Data)
	assert.NotEmpty(t, email.Data.Data)
}

func TestBuildMessage_EmptyFields(t *testing.T) {
	email := NewSESEmail()

	email.BuildMessage("", "", "", "", "", "", "")

	assert.Empty(t, email.To)
	assert.Empty(t, email.Cc)
	assert.Empty(t, email.Bcc)
	assert.Empty(t, email.FileName)
}
