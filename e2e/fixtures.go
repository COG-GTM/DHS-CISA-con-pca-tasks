
package e2e

const TestCycleID = "507f1f77bcf86cd799439011"

const TestSubscriptionID = "507f1f77bcf86cd799439012"

const TestNotificationTaskName = "cycle_report"

type SampleCycle struct {
	ID             string
	SubscriptionID string
	TemplateIDs    []string
	Active         bool
	TargetCount    int
}

func GetSampleCycle() SampleCycle {
	return SampleCycle{
		ID:             TestCycleID,
		SubscriptionID: TestSubscriptionID,
		TemplateIDs:    []string{"template1", "template2"},
		Active:         true,
		TargetCount:    100,
	}
}

type SampleSubscription struct {
	ID         string
	Name       string
	AdminEmail string
	Contact    SampleContact
}

type SampleContact struct {
	FirstName string
	LastName  string
	Email     string
}

func GetSampleSubscription() SampleSubscription {
	return SampleSubscription{
		ID:         TestSubscriptionID,
		Name:       "Test Organization",
		AdminEmail: "admin@example.com",
		Contact: SampleContact{
			FirstName: "John",
			LastName:  "Doe",
			Email:     "john.doe@example.com",
		},
	}
}

type SampleNotification struct {
	TaskName string
	Subject  string
	HTML     string
	Text     string
}

func GetSampleNotification() SampleNotification {
	return SampleNotification{
		TaskName: TestNotificationTaskName,
		Subject:  "PCA Cycle Report",
		HTML:     "<p>Dear {{.FirstName}} {{.LastName}},</p><p>Your cycle report is ready.</p>",
		Text:     "Dear {{.FirstName}} {{.LastName}},\n\nYour cycle report is ready.",
	}
}
