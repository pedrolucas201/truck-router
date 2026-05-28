package handlers

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"

	"cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
	fs "github.com/pedrolucas201/truck-router/backend/internal/firestore"
)

type Restrictions struct {
	client *firestore.Client
}

func NewRestrictions(client *firestore.Client) *Restrictions {
	return &Restrictions{client: client}
}

func (h *Restrictions) List(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	minLat, err1 := strconv.ParseFloat(q.Get("minLat"), 64)
	maxLat, err2 := strconv.ParseFloat(q.Get("maxLat"), 64)
	minLng, err3 := strconv.ParseFloat(q.Get("minLng"), 64)
	maxLng, err4 := strconv.ParseFloat(q.Get("maxLng"), 64)
	if err1 != nil || err2 != nil || err3 != nil || err4 != nil {
		http.Error(w, "invalid bbox params", http.StatusBadRequest)
		return
	}

	restrictions, err := fs.ListInBounds(r.Context(), h.client, minLat, maxLat, minLng, maxLng)
	if err != nil {
		log.Printf("List: %v", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	if restrictions == nil {
		restrictions = []fs.Restriction{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(restrictions)
}

func (h *Restrictions) Create(w http.ResponseWriter, r *http.Request) {
	var in fs.CreateInput
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		http.Error(w, "invalid body", http.StatusBadRequest)
		return
	}
	if in.Type == "" || in.UID == "" {
		http.Error(w, "type and uid required", http.StatusBadRequest)
		return
	}

	id, err := fs.Create(r.Context(), h.client, in)
	if err != nil {
		log.Printf("Create: %v", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{"id": id})
}

func (h *Restrictions) Confirm(w http.ResponseWriter, r *http.Request) {
	h.incrementField(w, r, "confirmedBy")
}

func (h *Restrictions) Report(w http.ResponseWriter, r *http.Request) {
	h.incrementField(w, r, "reportedBy")
}

func (h *Restrictions) incrementField(w http.ResponseWriter, r *http.Request, field string) {
	id := chi.URLParam(r, "id")
	if id == "" {
		http.Error(w, "missing id", http.StatusBadRequest)
		return
	}
	if err := fs.Increment(r.Context(), h.client, id, field); err != nil {
		log.Printf("Increment %s %s: %v", id, field, err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte("{}"))
}
