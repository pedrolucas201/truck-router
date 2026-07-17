package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	fsclient "github.com/pedrolucas201/truck-router/backend/internal/firestore"
	"github.com/pedrolucas201/truck-router/backend/internal/handlers"
	apimw "github.com/pedrolucas201/truck-router/backend/internal/middleware"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	ctx := context.Background()
	fsClient, err := fsclient.NewClient(ctx)
	if err != nil {
		log.Fatalf("firestore client: %v", err)
	}
	defer fsClient.Close()

	if err := apimw.InitFirebaseAuth(ctx); err != nil {
		log.Fatalf("firebase auth: %v", err)
	}

	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	r.Get("/health", handlers.Health)

	r.Group(func(r chi.Router) {
		r.Use(apimw.FirebaseAuth)

		h := handlers.NewRestrictions(fsClient)
		r.Get("/restrictions", h.List)
		r.Post("/restrictions", h.Create)
		r.Post("/restrictions/{id}/confirm", h.Confirm)
		r.Post("/restrictions/{id}/report", h.Report)

		// HERE geocoding proxy
		r.Get("/here/autocomplete", handlers.HereAutocomplete)
		r.Get("/here/geocode", handlers.HereGeocode)
		r.Get("/here/discover", handlers.HereDiscover)
		r.Get("/here/lookup", handlers.HereLookup)
		r.Get("/here/revgeocode", handlers.HereRevgeocode)
		r.Get("/here/weather", handlers.HereWeather)

		// Clima na rota: digere o fan-out e devolve só células severas.
		r.Post("/weather/route", handlers.WeatherRoute)

		// TomTom geocoding proxy
		r.Get("/tomtom/geocode", handlers.TomTomGeocode)

		// Routing proxy
		r.Get("/route/here", handlers.HereRoute)
		r.Get("/route/tomtom/*", handlers.TomTomRoute)
	})

	log.Printf("server listening on :%s", port)
	if err := http.ListenAndServe(":"+port, r); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
