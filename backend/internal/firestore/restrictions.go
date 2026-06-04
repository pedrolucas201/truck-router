package firestore

import (
	"context"
	"fmt"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const collection = "restrictions"

type Restriction struct {
	ID          string  `json:"id"`
	Lat         float64 `json:"lat"`
	Lng         float64 `json:"lng"`
	Type        string  `json:"type"`
	Value       float64 `json:"value"`
	RoadName    string  `json:"roadName,omitempty"`
	ConfirmedBy int     `json:"confirmedBy"`
}

type CreateInput struct {
	Lat      float64 `json:"lat"`
	Lng      float64 `json:"lng"`
	Type     string  `json:"type"`
	Value    float64 `json:"value"`
	RoadName string  `json:"roadName,omitempty"`
	UID      string  `json:"uid"`
}

func ListInBounds(ctx context.Context, client *firestore.Client, minLat, maxLat, minLng, maxLng float64) ([]Restriction, error) {
	iter := client.Collection(collection).
		Where("lat", ">=", minLat).
		Where("lat", "<=", maxLat).
		Documents(ctx)
	defer iter.Stop()

	var results []Restriction
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("iterate: %w", err)
		}
		r := fromDoc(doc)
		if r.Lng >= minLng && r.Lng <= maxLng {
			results = append(results, r)
		}
	}
	return results, nil
}

func Create(ctx context.Context, client *firestore.Client, in CreateInput) (string, error) {
	ref, _, err := client.Collection(collection).Add(ctx, map[string]any{
		"lat":         in.Lat,
		"lng":         in.Lng,
		"type":        in.Type,
		"value":       in.Value,
		"roadName":    in.RoadName,
		"createdByUid": in.UID,
		"confirmedBy": 0,
		"reportedBy":  0,
		"source":      "user",
	})
	if err != nil {
		return "", fmt.Errorf("add: %w", err)
	}
	return ref.ID, nil
}

// Vote registers a "confirm" or "report" vote for a restriction, deduplicating by uid.
// Switching actions (confirm → report or vice-versa) is allowed and adjusts both counters.
func Vote(ctx context.Context, client *firestore.Client, id, uid, action string) error {
	restrictionRef := client.Collection(collection).Doc(id)
	voteRef := restrictionRef.Collection("votes").Doc(uid)

	return client.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		voteDoc, err := tx.Get(voteRef)

		if err != nil && !isNotFound(err) {
			return fmt.Errorf("get vote: %w", err)
		}

		// No previous vote — increment target counter and create vote doc.
		if isNotFound(err) {
			if err := tx.Set(voteRef, map[string]any{"action": action}); err != nil {
				return err
			}
			return tx.Update(restrictionRef, []firestore.Update{
				{Path: counterField(action), Value: firestore.Increment(1)},
			})
		}

		// Same action — idempotent, nothing to do.
		prev, _ := voteDoc.Data()["action"].(string)
		if prev == action {
			return nil
		}

		// Changed action — swap counters and update vote doc.
		if err := tx.Set(voteRef, map[string]any{"action": action}); err != nil {
			return err
		}
		return tx.Update(restrictionRef, []firestore.Update{
			{Path: counterField(prev), Value: firestore.Increment(-1)},
			{Path: counterField(action), Value: firestore.Increment(1)},
		})
	})
}

func counterField(action string) string {
	if action == "confirm" {
		return "confirmedBy"
	}
	return "reportedBy"
}

func isNotFound(err error) bool {
	return status.Code(err) == codes.NotFound
}

func fromDoc(doc *firestore.DocumentSnapshot) Restriction {
	d := doc.Data()
	r := Restriction{ID: doc.Ref.ID}
	if v, ok := d["lat"].(float64); ok {
		r.Lat = v
	}
	if v, ok := d["lng"].(float64); ok {
		r.Lng = v
	}
	if v, ok := d["type"].(string); ok {
		r.Type = v
	}
	if v, ok := d["value"].(float64); ok {
		r.Value = v
	}
	if v, ok := d["roadName"].(string); ok {
		r.RoadName = v
	}
	if v, ok := d["confirmedBy"].(int64); ok {
		r.ConfirmedBy = int(v)
	}
	return r
}
