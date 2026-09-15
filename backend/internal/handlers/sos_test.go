package handlers

import (
	"strings"
	"testing"
)

func TestValidateSos(t *testing.T) {
	ok := sosCreateIn{Lat: -23.2, Lng: -45.8, Tipo: "pneu", Texto: "estepe furado"}
	if err := validateSos(ok); err != nil {
		t.Fatalf("válido reprovou: %v", err)
	}
	casos := map[string]sosCreateIn{
		"posicao": {Lat: 0, Lng: 0, Tipo: "pneu"},
		"tipo":    {Lat: -23.2, Lng: -45.8, Tipo: "guincho"},
		"texto":   {Lat: -23.2, Lng: -45.8, Tipo: "outro", Texto: strings.Repeat("a", sosTextoMax+1)},
	}
	for quer, in := range casos {
		err := validateSos(in)
		if err == nil || err.Error() != quer {
			t.Errorf("%+v: erro = %v, quer %q", in, err, quer)
		}
	}
	// 120 runas com acento passa (limite é em caracteres, não bytes)
	if err := validateSos(sosCreateIn{Lat: -23.2, Lng: -45.8, Tipo: "outro",
		Texto: strings.Repeat("ã", sosTextoMax)}); err != nil {
		t.Errorf("120 runas acentuadas reprovou: %v", err)
	}
}
