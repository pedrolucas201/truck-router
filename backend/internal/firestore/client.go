package firestore

import (
	"context"
	"fmt"
	"os"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	"google.golang.org/api/option"
)

func NewClient(ctx context.Context) (*firestore.Client, error) {
	projectID := os.Getenv("FIREBASE_PROJECT_ID")
	if projectID == "" {
		return nil, fmt.Errorf("FIREBASE_PROJECT_ID not set")
	}

	var app *firebase.App
	var err error

	if credFile := os.Getenv("GOOGLE_APPLICATION_CREDENTIALS"); credFile != "" {
		app, err = firebase.NewApp(ctx, &firebase.Config{ProjectID: projectID}, option.WithCredentialsFile(credFile))
	} else {
		// Cloud Run usa ADC (service account da instância)
		app, err = firebase.NewApp(ctx, &firebase.Config{ProjectID: projectID})
	}
	if err != nil {
		return nil, fmt.Errorf("firebase.NewApp: %w", err)
	}

	client, err := app.Firestore(ctx)
	if err != nil {
		return nil, fmt.Errorf("app.Firestore: %w", err)
	}
	return client, nil
}
