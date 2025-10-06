package notifications

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestTemplate_Render_ValidTemplate(t *testing.T) {
	tmpl := Template{
		FirstName: "John",
		LastName:  "Doe",
	}

	data := "Hello {{.FirstName}} {{.LastName}}!"
	result := tmpl.Render(data)

	assert.Equal(t, "Hello John Doe!", result)
}

func TestTemplate_Render_EmptyTemplate(t *testing.T) {
	tmpl := Template{
		FirstName: "Jane",
		LastName:  "Smith",
	}

	data := ""
	result := tmpl.Render(data)

	assert.Equal(t, "", result)
}

func TestTemplate_Render_NoVariables(t *testing.T) {
	tmpl := Template{
		FirstName: "Alice",
		LastName:  "Johnson",
	}

	data := "This is a static message with no variables"
	result := tmpl.Render(data)

	assert.Equal(t, "This is a static message with no variables", result)
}

func TestTemplate_Render_OnlyFirstName(t *testing.T) {
	tmpl := Template{
		FirstName: "Bob",
		LastName:  "Williams",
	}

	data := "Dear {{.FirstName}},"
	result := tmpl.Render(data)

	assert.Equal(t, "Dear Bob,", result)
}

func TestTemplate_Render_OnlyLastName(t *testing.T) {
	tmpl := Template{
		FirstName: "Charlie",
		LastName:  "Brown",
	}

	data := "Mr. {{.LastName}}"
	result := tmpl.Render(data)

	assert.Equal(t, "Mr. Brown", result)
}

func TestTemplate_Render_MultipleVariables(t *testing.T) {
	tmpl := Template{
		FirstName: "David",
		LastName:  "Miller",
	}

	data := "{{.FirstName}} {{.LastName}} ({{.LastName}}, {{.FirstName}})"
	result := tmpl.Render(data)

	assert.Equal(t, "David Miller (Miller, David)", result)
}

func TestTemplate_Render_HTMLTemplate(t *testing.T) {
	tmpl := Template{
		FirstName: "Emma",
		LastName:  "Davis",
	}

	data := "<p>Hello <strong>{{.FirstName}} {{.LastName}}</strong>!</p>"
	result := tmpl.Render(data)

	assert.Equal(t, "<p>Hello <strong>Emma Davis</strong>!</p>", result)
}

func TestTemplate_Render_WithNewlines(t *testing.T) {
	tmpl := Template{
		FirstName: "Frank",
		LastName:  "Wilson",
	}

	data := "Dear {{.FirstName}},\n\nThis is a test message.\n\nSincerely,\nThe Team"
	result := tmpl.Render(data)

	expected := "Dear Frank,\n\nThis is a test message.\n\nSincerely,\nThe Team"
	assert.Equal(t, expected, result)
}

func TestTemplate_Render_EmptyFirstName(t *testing.T) {
	tmpl := Template{
		FirstName: "",
		LastName:  "Anderson",
	}

	data := "Hello {{.FirstName}} {{.LastName}}"
	result := tmpl.Render(data)

	assert.Equal(t, "Hello  Anderson", result)
}

func TestTemplate_Render_EmptyLastName(t *testing.T) {
	tmpl := Template{
		FirstName: "Grace",
		LastName:  "",
	}

	data := "Hello {{.FirstName}} {{.LastName}}"
	result := tmpl.Render(data)

	assert.Equal(t, "Hello Grace ", result)
}

func TestTemplate_Render_InvalidTemplate(t *testing.T) {
	tmpl := Template{
		FirstName: "Henry",
		LastName:  "Taylor",
	}

	data := "Hello {{.FirstName} {{.LastName}}"
	
	defer func() {
		if r := recover(); r != nil {
			t.Log("Template parsing panicked as expected for invalid template")
		}
	}()
	
	result := tmpl.Render(data)
	assert.Empty(t, result)
}
