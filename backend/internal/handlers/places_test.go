package handlers

import (
	"encoding/json"
	"strings"
	"testing"
)

func decode(t *testing.T, b []byte) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatalf("json inválido: %v", err)
	}
	return m
}

func TestAutocompleteBodyComAt(t *testing.T) {
	b, err := autocompleteBody("Ceasa SJC", "-23.1896,-45.8841", "tok")
	if err != nil {
		t.Fatal(err)
	}
	m := decode(t, b)
	if m["input"] != "Ceasa SJC" || m["sessionToken"] != "tok" || m["languageCode"] != "pt-BR" {
		t.Errorf("campos básicos: %v", m)
	}
	// origin é o que faz a Google devolver distanceMeters (medido 2026-09-09).
	origin, _ := m["origin"].(map[string]any)
	if origin == nil || origin["latitude"] != -23.1896 || origin["longitude"] != -45.8841 {
		t.Errorf("origin: %v", m["origin"])
	}
	circle := m["locationBias"].(map[string]any)["circle"].(map[string]any)
	if circle["radius"] != 50000.0 {
		t.Errorf("raio do bias: %v", circle["radius"])
	}
	if rc := m["includedRegionCodes"].([]any); len(rc) != 1 || rc[0] != "br" {
		t.Errorf("país: %v", rc)
	}
}

func TestAutocompleteBodySemAt(t *testing.T) {
	for _, at := range []string{"", "lixo", "1,2,3", "a,b"} {
		b, err := autocompleteBody("Graal", at, "")
		if err != nil {
			t.Fatal(err)
		}
		m := decode(t, b)
		if _, has := m["origin"]; has {
			t.Errorf("at=%q não devia gerar origin", at)
		}
		if _, has := m["locationBias"]; has {
			t.Errorf("at=%q não devia gerar locationBias", at)
		}
		if _, has := m["sessionToken"]; has {
			t.Errorf("sessão vazia não devia ir no corpo")
		}
	}
}

func TestDetailsMaskFicaEssentials(t *testing.T) {
	// displayName é Pro (US$ 17/1k). Se alguém adicionar, este teste avisa.
	for _, f := range []string{"displayName", "rating", "photos", "*"} {
		if strings.Contains(placesDetailsMask, f) {
			t.Errorf("field mask do Details pede campo caro: %s", f)
		}
	}
}
