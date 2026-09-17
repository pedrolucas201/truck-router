package handlers

import (
	"fmt"
	"math"
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
		// Caminhão e cor passaram a vir do app (perfil ATIVO) em vez de
		// `profiles`: o teto era da regra do Firestore e agora só existe aqui.
		"caminhao": {Lat: -23.2, Lng: -45.8, Tipo: "pneu",
			Caminhao: strings.Repeat("a", sosCaminhaoMax+1)},
		"cor": {Lat: -23.2, Lng: -45.8, Tipo: "pneu",
			Cor: strings.Repeat("a", sosCorMax+1)},
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
	// Caminhão vazio é válido: identidade é opcional e a ficha lida com vazio.
	// Se isto virar obrigatório, quem não preencheu não consegue pedir ajuda.
	if err := validateSos(sosCreateIn{Lat: -23.2, Lng: -45.8, Tipo: "pneu",
		Caminhao: "", Cor: ""}); err != nil {
		t.Errorf("caminhão vazio reprovou: %v", err)
	}
}

// Falha se o raio, a exclusão do dono ou o dedupe por token quebrarem.
func TestSosDestinatarios(t *testing.T) {
	// S.O.S. em São José dos Campos; presenças: Jacareí (~14 km), São Paulo
	// (~80 km), o próprio dono a 0 m, token repetido (reinstalação), sem token.
	ps := []presenca{
		{UID: "jacarei", Token: "t1", Lat: -23.305, Lng: -45.966},
		{UID: "saopaulo", Token: "t2", Lat: -23.55, Lng: -46.63},
		{UID: "dono", Token: "t3", Lat: -23.19, Lng: -45.88},
		{UID: "jacarei-velho", Token: "t1", Lat: -23.30, Lng: -45.96},
		{UID: "sem-token", Token: "", Lat: -23.19, Lng: -45.88},
	}
	got := sosDestinatarios(ps, -23.19, -45.88, sosRaioM, "dono")
	if len(got) != 1 || got[0].UID != "jacarei" {
		t.Fatalf("quer só jacarei, veio %+v", got)
	}
	if got[0].DistM < 10_000 || got[0].DistM > 20_000 {
		t.Errorf("distância SJC-Jacareí fora da faixa: %.0f m", got[0].DistM)
	}
	if want := fmt.Sprintf("%d km", int(math.Round(got[0].DistM/1000))); kmTexto(got[0].DistM) != want {
		t.Errorf("kmTexto = %q, quer %q", kmTexto(got[0].DistM), want)
	}
	if kmTexto(400) != "menos de 1 km" {
		t.Errorf("kmTexto(400) = %q", kmTexto(400))
	}
}
